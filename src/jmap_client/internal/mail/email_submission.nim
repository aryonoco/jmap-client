# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## RFC 8621 §7 EmailSubmission entity read model with GADT-style phantom
## indexing on ``UndoStatus``. The phantom parameter lifts
## the RFC's "only pending submissions may be canceled" invariant
## into the type system. ``AnyEmailSubmission`` is the
## existential wrapper — serde produces it once at the wire boundary;
## consumers pattern-match on ``.state`` to recover the phantom-indexed
## branch.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/tables

import ../types/primitives
import ../types/identifiers
import ../types/validation
import ../types/framework
import ../types/field_echo
import ../protocol/methods
import ../protocol/dispatch
import ./submission_envelope
import ./submission_status
import ./email
import ./email_update

type EmailSubmission*[S: static UndoStatus] {.ruleOff: "objects".} = object
  ## Entity read model indexed on the RFC 8621 §7 ``undoStatus``. Each
  ## ``S`` produces a distinct concrete type — ``EmailSubmission[usPending]``
  ## vs ``EmailSubmission[usFinal]`` — `cancelUpdate`` can
  ## constrain on ``EmailSubmission[usPending]`` only.
  id*: Id
  identityId*: Id
  emailId*: Id
  threadId*: Id
  envelope*: Opt[Envelope]
  sendAt*: UTCDate
  deliveryStatus*: Opt[DeliveryStatusMap]
  dsnBlobIds*: seq[BlobId]
  mdnBlobIds*: seq[BlobId]

type AnyEmailSubmission* {.ruleOff: "objects".} = object
  ## Existential wrapper discriminated on ``UndoStatus``. Branch fields
  ## are module-private with a ``raw`` prefix; construction is gated by
  ## the ``toAny`` overload family (one per phantom instantiation), and
  ## read access is via the ``asPending`` / ``asFinal`` / ``asCanceled``
  ## accessors below, each returning ``Opt[EmailSubmission[S]]``. The
  ## discriminator ``state`` remains exported because callers case on
  ## it before projecting through an accessor. Pattern A sealing
  ## mirrors ``EmailSubmissionBlueprint`` — wrong-branch reads cannot
  ## be written. Under ``--panics:on`` the alternative (a runtime
  ## ``FieldDefect``) would be fatal and uncatchable.
  case state*: UndoStatus
  of usPending:
    rawPending: EmailSubmission[usPending]
  of usFinal:
    rawFinal: EmailSubmission[usFinal]
  of usCanceled:
    rawCanceled: EmailSubmission[usCanceled]

func toAny*(s: EmailSubmission[usPending]): AnyEmailSubmission =
  ## Lifts a pending submission into the existential wrapper.
  AnyEmailSubmission(state: usPending, rawPending: s)

func toAny*(s: EmailSubmission[usFinal]): AnyEmailSubmission =
  ## Lifts a final submission into the existential wrapper.
  AnyEmailSubmission(state: usFinal, rawFinal: s)

func toAny*(s: EmailSubmission[usCanceled]): AnyEmailSubmission =
  ## Lifts a canceled submission into the existential wrapper.
  AnyEmailSubmission(state: usCanceled, rawCanceled: s)

func `==`*(a, b: AnyEmailSubmission): bool =
  ## Arm-dispatched structural equality. Auto-derived ``==`` on a case
  ## object uses a parallel ``fields`` iterator that rejects the
  ## discriminated shape. Delegates each branch to the non-case
  ## ``EmailSubmission[S].==``.
  ##
  ## Nested case on both operands — strict doesn't carry ``a.state ==
  ## b.state`` across outer branches.
  case a.state
  of usPending:
    case b.state
    of usPending:
      a.rawPending == b.rawPending
    of usFinal, usCanceled:
      false
  of usFinal:
    case b.state
    of usFinal:
      a.rawFinal == b.rawFinal
    of usPending, usCanceled:
      false
  of usCanceled:
    case b.state
    of usCanceled:
      a.rawCanceled == b.rawCanceled
    of usPending, usFinal:
      false

func asPending*(s: AnyEmailSubmission): Opt[EmailSubmission[usPending]] =
  ## Safe projection onto the ``usPending`` branch. ``Opt.some`` iff
  ## ``s.state == usPending``; ``Opt.none`` otherwise. The return-type
  ## phantom is fixed — an ``Opt[EmailSubmission[usPending]]`` can
  ## never carry a ``usFinal`` or ``usCanceled`` payload.
  case s.state
  of usPending:
    Opt.some(s.rawPending)
  of usFinal, usCanceled:
    Opt.none(EmailSubmission[usPending])

func asFinal*(s: AnyEmailSubmission): Opt[EmailSubmission[usFinal]] =
  ## Safe projection onto the ``usFinal`` branch.
  case s.state
  of usFinal:
    Opt.some(s.rawFinal)
  of usPending, usCanceled:
    Opt.none(EmailSubmission[usFinal])

func asCanceled*(s: AnyEmailSubmission): Opt[EmailSubmission[usCanceled]] =
  ## Safe projection onto the ``usCanceled`` branch.
  case s.state
  of usCanceled:
    Opt.some(s.rawCanceled)
  of usPending, usFinal:
    Opt.none(EmailSubmission[usCanceled])

# -----------------------------------------------------------------------------
# EmailSubmissionBlueprint — creation model (RFC 8621 §7.5)
#
# Shape: Pattern A sealing (raw* private fields + same-name UFCS accessors)
# combined with Result[T, seq[ValidationError]] error rail.
# -----------------------------------------------------------------------------

type EmailSubmissionBlueprint* {.ruleOff: "objects".} = object
  ## Creation model for ``EmailSubmission/set`` create operations. Carries
  ## the three client-settable fields per RFC 8621 §7.5: ``identityId``,
  ## ``emailId``, and an optional ``envelope``.
  ##
  ## Fields are module-private with a ``raw`` prefix; construction is gated
  ## by ``parseEmailSubmissionBlueprint`` and read access is via same-name
  ## UFCS accessors below.
  ##
  ## When ``envelope`` is ``Opt.none``, the server synthesises the envelope
  ## from the referenced Email's headers per RFC §7.5 ¶4.
  rawIdentityId: Id
  rawEmailId: Id
  rawEnvelope: Opt[Envelope]

func parseEmailSubmissionBlueprint*(
    identityId: Id, emailId: Id, envelope: Opt[Envelope] = Opt.none(Envelope)
): Result[EmailSubmissionBlueprint, seq[ValidationError]] =
  ## Accumulating-error smart constructor. Returns ``Result[T, seq[...]]``.
  ##
  ok(
    EmailSubmissionBlueprint(
      rawIdentityId: identityId, rawEmailId: emailId, rawEnvelope: envelope
    )
  )

func identityId*(bp: EmailSubmissionBlueprint): Id =
  ## UFCS accessor — ``bp.identityId`` reads as a field access.
  bp.rawIdentityId

func emailId*(bp: EmailSubmissionBlueprint): Id =
  ## UFCS accessor — ``bp.emailId`` reads as a field access.
  bp.rawEmailId

func envelope*(bp: EmailSubmissionBlueprint): Opt[Envelope] =
  ## UFCS accessor — ``bp.envelope`` reads as a field access.
  bp.rawEnvelope

# -----------------------------------------------------------------------------
# EmailSubmissionUpdate — update algebra (RFC 8621 §7.5 ¶3)
#
# Typed patch operations for EmailSubmission/set update. The RFC permits
# exactly one mutation post-create: ``undoStatus`` pending → canceled.
# -----------------------------------------------------------------------------

type EmailSubmissionUpdateVariantKind* = enum
  ## Discriminator for ``EmailSubmissionUpdate``. Single variant today —
  ## the sealed-sum shape exists for forwards compatibility
  esuSetUndoStatusToCanceled

type EmailSubmissionUpdate* {.ruleOff: "objects".} = object
  ## Typed EmailSubmission patch operation (RFC 8621 §7.5 ¶3). One
  ## variant today — pending → canceled — matching the RFC's single
  ## permitted mutation. Nullary variant (``discard``) is deliberate: the
  ## discriminator alone carries the semantics.
  case kind*: EmailSubmissionUpdateVariantKind
  of esuSetUndoStatusToCanceled:
    discard

func setUndoStatusToCanceled*(): EmailSubmissionUpdate =
  ## Protocol-primitive constructor for the RFC 8621 §7.5 ¶3
  ## ``undoStatus: "canceled"`` wire patch. Total — the RFC imposes no
  ## client-checkable preconditions on the patch value itself; the
  ## "pending only" invariant is enforced at the submission site via
  ## ``cancelUpdate``'s phantom-typed parameter.
  EmailSubmissionUpdate(kind: esuSetUndoStatusToCanceled)

func cancelUpdate*(s: EmailSubmission[usPending]): EmailSubmissionUpdate =
  ## Cancel a pending submission — thin ergonomic wrapper that carries
  ## the RFC 8621 §7 invariant "only pending may be canceled" in the
  ## type. ``cancelUpdate(EmailSubmission[usFinal])`` and
  ## ``cancelUpdate(EmailSubmission[usCanceled])`` are compile errors.
  ## The ``s`` parameter is unused at runtime — the phantom binds
  ## at the call site to carry the compile-time guarantee.
  discard s
  setUndoStatusToCanceled()

# -----------------------------------------------------------------------------
# NonEmptyEmailSubmissionUpdates — non-empty, dup-free batch for /set update
# -----------------------------------------------------------------------------

type NonEmptyEmailSubmissionUpdates* = distinct Table[Id, EmailSubmissionUpdate]
  ## Non-empty, duplicate-free batch of per-submission update operations
  ## keyed by existing EmailSubmission ``Id``. Construction gated by
  ## ``parseNonEmptyEmailSubmissionUpdates``; the raw distinct
  ## constructor is module-private surface, matching
  ## ``NonEmptyEmailImportMap`` (email.nim) and ``DeliveryStatusMap``
  ## (submission_status.nim) — serde (Step 12) unwrap-casts to iterate.
  ##
  ## Creation-reference keys (``#ref``-style forward references to
  ## sibling create operations) are a Builder-layer concern routed
  ## through ``IdOrCreationRef`` — this L1 type stays focused on
  ## resolved ``Id`` keys.

func len*(a: NonEmptyEmailSubmissionUpdates): int {.borrow.}
  ## Number of update entries — borrowed from the underlying ``Table``.

func parseNonEmptyEmailSubmissionUpdates*(
    items: openArray[(Id, EmailSubmissionUpdate)]
): Result[NonEmptyEmailSubmissionUpdates, seq[ValidationError]] =
  ## Accumulating smart constructor.
  ## Rejects:
  ##   * empty input — the ``/set`` builder's ``update:`` field has
  ##     exactly one "no updates" representation: omit the entry via
  ##     ``Opt.none``.
  ##   * duplicate ``Id`` keys — silent last-wins shadowing at Table
  ##     construction would swallow caller data; ``openArray`` (not
  ##     ``Table``) preserves duplicates for inspection.
  ## All violations surface in a single Err pass; each repeated id is
  ## reported exactly once regardless of occurrence count.
  let errs = validateUniqueByIt(
    items,
    it[0],
    typeName = "NonEmptyEmailSubmissionUpdates",
    emptyMsg = "must contain at least one entry",
    dupMsg = "duplicate submission id",
  )
  if errs.len > 0:
    return err(errs)
  var t = initTable[Id, EmailSubmissionUpdate](items.len)
  for (id, update) in items:
    t[id] = update
  ok(NonEmptyEmailSubmissionUpdates(t))

# -----------------------------------------------------------------------------
# NonEmptyIdSeq — non-empty seq[Id] for EmailSubmissionFilterCondition list
# fields. Dedicated distinct (rather than an alias for NonEmptySeq[Id]) for
# symmetry with NonEmptyRcptList in submission_envelope.nim.
# -----------------------------------------------------------------------------

type NonEmptyIdSeq* = distinct seq[Id]
  ## Non-empty seq of ``Id`` for filter list fields. Construction gated by
  ## ``parseNonEmptyIdSeq``; the raw distinct constructor is module-private
  ## surface, consistent with ``NonEmptyRcptList``.

func `==`*(a, b: NonEmptyIdSeq): bool {.borrow.}
  ## Element-wise equality delegated to the underlying ``seq[Id]``.

func `$`*(a: NonEmptyIdSeq): string {.borrow.}
  ## Textual form delegated to the underlying ``seq[Id]`` (diagnostic only).

func len*(a: NonEmptyIdSeq): int {.borrow.}
  ## Element count; invariant ``>= 1`` by construction.

func `[]`*(a: NonEmptyIdSeq, i: Idx): lent Id =
  ## Indexed read-only access via sealed non-negative ``Idx``; the
  ## underlying ``seq[Id]`` retains ownership.
  seq[Id](a)[i.toInt]

func head*(a: NonEmptyIdSeq): lent Id =
  ## First element — guaranteed present by the non-empty invariant.
  ## Semantic accessor that reads cleaner than ``a[idx(0)]``.
  seq[Id](a)[0]

iterator items*(a: NonEmptyIdSeq): Id =
  ## Iteration over the underlying ``seq[Id]``.
  for x in seq[Id](a):
    yield x

func parseNonEmptyIdSeq*(items: openArray[Id]): Result[NonEmptyIdSeq, ValidationError] =
  ## Strict: rejects empty input. Duplicate ids permitted (RFC 8621 §7.3
  ## filter list semantics accept any combination). Matches
  ## ``parseNonEmptySeq`` (primitives.nim) — single ``ValidationError``,
  ## non-empty check only.
  if items.len == 0:
    return err(validationError("NonEmptyIdSeq", "must not be empty", ""))
  ok(NonEmptyIdSeq(@items))

# -----------------------------------------------------------------------------
# EmailSubmissionFilterCondition — /query filter condition (RFC 8621 §7.3)
#
# Plain record, no smart constructor. Each typed field already validates at
# construction (NonEmptyIdSeq / UndoStatus / UTCDate); any combination of
# Opt.none fields is a meaningful "no constraint". toJson-only: server
# never echoes filter conditions back.
# -----------------------------------------------------------------------------

type EmailSubmissionFilterCondition* {.ruleOff: "objects".} = object
  ## Typed filter condition for ``EmailSubmission/query`` (RFC 8621 §7.3).
  ## List fields use ``Opt[NonEmptyIdSeq]`` — an empty list matches nothing
  ## on the server side and is almost certainly a caller bug, so it is
  ## structurally unrepresentable.
  identityIds*: Opt[NonEmptyIdSeq]
  emailIds*: Opt[NonEmptyIdSeq]
  threadIds*: Opt[NonEmptyIdSeq]
  undoStatus*: Opt[UndoStatus]
  before*: Opt[UTCDate]
  after*: Opt[UTCDate]

# -----------------------------------------------------------------------------
# EmailSubmissionSortProperty — /query sort property enum (RFC 8621 §7.3)
#
# Wire token "sentAt" ≠ entity field name "sendAt" — the RFC's inconsistency,
# preserved verbatim. esspOther catch-all mirrors dsOther / dpOther in
# submission_status.nim for forward compatibility with vendor extensions.
# -----------------------------------------------------------------------------

type EmailSubmissionSortProperty* = enum
  ## Sort properties for ``EmailSubmission/query`` (RFC 8621 §7.3).
  ## ``esspOther`` is the catch-all for vendor-extension sort tokens — the
  ## raw wire string survives on ``EmailSubmissionComparator.rawProperty``.
  esspEmailId = "emailId"
  esspThreadId = "threadId"
  esspSentAt = "sentAt"
  esspOther

# -----------------------------------------------------------------------------
# EmailSubmissionComparator — /query sort criterion (RFC 8621 §7.3)
#
# Plain record with a property enum + rawProperty round-trip string. Mirrors
# ParsedDeliveredState / ParsedDisplayedState (submission_status.nim): both
# fields public; the smart constructor below resolves the wire token once
# and stores rawProperty as the round-trip carrier.
# -----------------------------------------------------------------------------

type EmailSubmissionComparator* {.ruleOff: "objects".} = object
  ## ``/query`` sort criterion for EmailSubmission. ``isAscending`` defaults
  ## to ``true`` per RFC 8620 §5.5; ``collation`` absent means "the server
  ## default" (RFC 4790 collation registry). ``rawProperty`` carries the
  ## wire token verbatim — for ``esspOther`` it is the only authoritative
  ## value; for known properties it equals the string backing of
  ## ``property``.
  property*: EmailSubmissionSortProperty
  rawProperty*: string
  isAscending*: bool
  collation*: Opt[CollationAlgorithm]

func parseEmailSubmissionComparator*(
    rawProperty: string,
    isAscending: bool = true,
    collation: Opt[CollationAlgorithm] = Opt.none(CollationAlgorithm),
): Result[EmailSubmissionComparator, ValidationError] =
  ## Smart constructor. Resolves the wire token to a known
  ## ``EmailSubmissionSortProperty`` variant, falling back to ``esspOther``
  ## with the raw token preserved. Rejects empty ``rawProperty``.
  if rawProperty.len == 0:
    return err(
      validationError(
        "EmailSubmissionComparator", "property must not be empty", rawProperty
      )
    )
  let property =
    case rawProperty
    of "emailId": esspEmailId
    of "threadId": esspThreadId
    of "sentAt": esspSentAt
    else: esspOther
  ok(
    EmailSubmissionComparator(
      property: property,
      rawProperty: rawProperty,
      isAscending: isAscending,
      collation: collation,
    )
  )

# -----------------------------------------------------------------------------
# EmailSubmissionCreatedItem — minimum RFC-mandated server-set subset
# returned in the created map for each successful /set create. Parallels
# EmailCreatedItem (email.nim) — plain record of the server-authoritative
# fields the client couldn't have known at submit time.
# -----------------------------------------------------------------------------

type EmailSubmissionCreatedItem* {.ruleOff: "objects".} = object
  ## RFC 8621 §7.5 ¶2 server-set subset returned in the
  ## ``EmailSubmission/set`` ``created`` map: ``id`` (always
  ## server-assigned), ``threadId`` (derived from the referenced Email),
  ## ``sendAt`` (server stamp), ``undoStatus`` (server-set live state).
  ##
  ## All four optional fields are ``Opt[T]`` because servers diverge on
  ## what they include in the create acknowledgement:
  ##
  ## - **Stalwart 0.15.5** emits only ``{"id": "<id>"}`` — strict-RFC
  ##   §7.5 ¶2 minimum.
  ## - **Cyrus 3.12.2** emits ``{"id", "undoStatus", "sendAt"}`` —
  ##   `imap/jmap_mail_submission.c` returns the full server-set state
  ##   inline because Cyrus's submission lifecycle is fire-and-forget:
  ##   the server may have already finalised and discarded the record
  ##   by the time the client could call ``/get``, so the create
  ##   response must carry the live state to be useful.
  ## - **James 3.9** TBD — defers to live ``/get``.
  ##
  ## Capturing ``undoStatus`` from the create response lets callers
  ## avoid a futile poll on Cyrus and gives them the live state on
  ## any server that includes it. Postel's-law accommodation per
  ## ``.claude/rules/nim-conventions.md`` §"Serde Conventions": be
  ## lenient on receive. Mirrors the ``IdentityCreatedItem`` /
  ## ``MailboxCreatedItem`` design.
  id*: Id
  threadId*: Opt[Id]
  sendAt*: Opt[UTCDate]
  undoStatus*: Opt[UndoStatus]

# =============================================================================
# PartialEmailSubmission
# =============================================================================

type PartialEmailSubmission* {.ruleOff: "objects".} = object
  ## RFC 8621 §7 partial EmailSubmission. Non-generic — the
  ## ``EmailSubmission[S: static UndoStatus]`` phantom cannot promise a
  ## lifecycle state on a partial echo. ``undoStatus`` is
  ## ``Opt[UndoStatus]`` (typed closed enum from ``submission_status.nim``);
  ## a present wire token outside the closed set surfaces as a
  ## SerdeViolation per A4 D4.
  id*: Opt[Id]
  identityId*: Opt[Id]
  emailId*: Opt[Id]
  threadId*: Opt[Id]
  envelope*: FieldEcho[Envelope]
    ## Wire admits null (server synthesises from message per RFC 8621 §7.5).
  sendAt*: Opt[UTCDate]
  undoStatus*: Opt[UndoStatus]
  deliveryStatus*: FieldEcho[DeliveryStatusMap]
    ## Wire admits null (no delivery info yet per RFC 8621 §7).
  dsnBlobIds*: Opt[seq[BlobId]]
  mdnBlobIds*: Opt[seq[BlobId]]

# -----------------------------------------------------------------------------
# EmailSubmissionSetResponse — /set response alias (RFC 8621 §7.5)
#
# Typed instantiation of the generic SetResponse[T, U] (methods.nim). ``T``
# drives ``createResults`` typed payload via ``T.fromJson`` resolved at
# instantiation through ``mixin``; ``U`` drives ``updateResults`` typed
# payload via ``U.fromJson`` (A4 D1/D2).
# -----------------------------------------------------------------------------

type EmailSubmissionSetResponse* =
  SetResponse[EmailSubmissionCreatedItem, PartialEmailSubmission]
  ## Typed alias for the EmailSubmission/set response (RFC 8621 §7.5).
  ## ``createResults`` carries ``EmailSubmissionCreatedItem`` payloads via
  ## ``mergeCreateResults[EmailSubmissionCreatedItem]`` (methods.nim);
  ## ``updateResults`` carries ``PartialEmailSubmission`` payloads via
  ## ``mergeUpdateResults[PartialEmailSubmission]`` (A4); ``destroyResults``
  ## follows the standard merged ``Result``-table shape.

# -----------------------------------------------------------------------------
# IdOrCreationRef — creation-reference key for onSuccess* maps (RFC 8620 §5.3)
#
# Distinct from ``Referencable[T]`` (RFC 8620 §3.7): creation references are
# string-shaped wire keys (``"#"`` + ``creationId``) that resolve against
# sibling creates in the same ``/set`` call; result references are
# JSON-object-shaped values substituting a previous call's output.
# Different wire shape, different semantics — separate types (G35/G36).
# -----------------------------------------------------------------------------

type IdOrCreationRefKind* = enum
  ## Discriminator for ``IdOrCreationRef``. ``icrDirect`` references an
  ## EmailSubmission already persisted on the server; ``icrCreation``
  ## references one being created in the same ``/set`` call — the wire
  ## form prepends ``"#"`` to the creation id per RFC 8620 §5.3.
  icrDirect
  icrCreation

type IdOrCreationRef* {.ruleOff: "objects".} = object
  ## Either an existing EmailSubmission ``Id`` or a ``CreationId``-shaped
  ## forward reference to a submission being created in the same ``/set``
  ## call. Used as the map key in ``onSuccessUpdateEmail`` and as the list
  ## element in ``onSuccessDestroyEmail`` on the compound builder
  ## ``addEmailSubmissionAndEmailSet`` (RFC 8621 §7.5 ¶3).
  ##
  ## Wire format (resolved by L2 serde): ``icrDirect`` serialises as the
  ## underlying ``Id`` string; ``icrCreation`` serialises as ``"#"``
  ## concatenated with the underlying ``CreationId`` string.
  case kind*: IdOrCreationRefKind
  of icrDirect:
    id*: Id
  of icrCreation:
    creationId*: CreationId

func `==`*(a, b: IdOrCreationRef): bool =
  ## Arm-dispatched structural equality. Auto-derived ``==`` on a case
  ## object fails with *parallel 'fields' iterator does not work for
  ## 'case' objects*; the arm-dispatch pattern mirrors
  ## ``SubmissionParamKey.==``. Cross-arm values compare unequal even on
  ## coincident payload strings — an ``icrDirect`` with ``Id("abc")``
  ## and an ``icrCreation`` with ``CreationId("abc")`` are not the same
  ## key.
  ##
  ## Nested case on both operands for strictCaseObjects.
  case a.kind
  of icrDirect:
    case b.kind
    of icrDirect:
      a.id == b.id
    of icrCreation:
      false
  of icrCreation:
    case b.kind
    of icrDirect:
      false
    of icrCreation:
      a.creationId == b.creationId

func hash*(k: IdOrCreationRef): Hash =
  ## Arm-dispatched hash honouring the ``a == b ⇒ hash(a) == hash(b)``
  ## contract. Mixes the discriminator ordinal into the payload hash so
  ## ``directRef(Id("abc"))`` and ``creationRef(CreationId("abc"))`` land
  ## in different buckets — ``Id.hash`` and ``CreationId.hash`` both
  ## delegate to ``string.hash``, so without the ordinal mix-in
  ## coincident payload strings would collide across arms and
  ## ``Table[IdOrCreationRef, _]`` lookups in the compound builder would
  ## silently break. Follows ``SubmissionParamKey.hash``.
  case k.kind
  of icrDirect:
    var h: Hash = 0
    h = h !& hash(icrDirect.ord)
    h = h !& hash(k.id)
    !$h
  of icrCreation:
    var h: Hash = 0
    h = h !& hash(icrCreation.ord)
    h = h !& hash(k.creationId)
    !$h

func directRef*(id: Id): IdOrCreationRef =
  ## Smart constructor for an existing-``Id`` reference. Total — the
  ## ``Id`` has already been validated upstream (``parseId`` or
  ## ``parseIdFromServer``); no further constraint applies.
  IdOrCreationRef(kind: icrDirect, id: id)

func creationRef*(cid: CreationId): IdOrCreationRef =
  ## Smart constructor for a forward-reference to a sibling create
  ## operation. The ``"#"`` prefix is a wire concern — added at
  ## ``toJson`` time, not stored on the ``CreationId``.
  IdOrCreationRef(kind: icrCreation, creationId: cid)

# =============================================================================
# NonEmptyOnSuccessUpdateEmail / NonEmptyOnSuccessDestroyEmail
# (RFC 8621 §7.5 ¶3 — compound EmailSubmission/set + implicit Email/set)
# =============================================================================

type NonEmptyOnSuccessUpdateEmail* = distinct Table[IdOrCreationRef, EmailUpdateSet]
  ## Non-empty, duplicate-free map of per-email update patches triggered
  ## by a successful ``EmailSubmission/set`` (RFC 8621 §7.5 ¶3). Keys may
  ## be resolved Email ids or creation-references to sibling
  ## EmailSubmission creates; ``IdOrCreationRef`` ``==`` and ``hash`` are
  ## arm-dispatched, so ``directRef(Id("x"))`` and
  ## ``creationRef(CreationId("x"))`` hash into distinct buckets even
  ## when their payload strings coincide. Construction gated by
  ## ``parseNonEmptyOnSuccessUpdateEmail``.

type NonEmptyOnSuccessDestroyEmail* = distinct seq[IdOrCreationRef]
  ## Non-empty, duplicate-free sequence of Email references triggered
  ## for destroy on a successful ``EmailSubmission/set`` (RFC 8621 §7.5
  ## ¶3). Construction gated by ``parseNonEmptyOnSuccessDestroyEmail``.

func parseNonEmptyOnSuccessUpdateEmail*(
    items: openArray[(IdOrCreationRef, EmailUpdateSet)]
): Result[NonEmptyOnSuccessUpdateEmail, seq[ValidationError]] =
  ## Accumulating smart constructor. Rejects empty input (``Opt.none`` is
  ## the single "no extras" representation) and duplicate
  ## ``IdOrCreationRef`` keys (silent last-wins at Table construction
  ## would swallow caller data).
  let errs = validateUniqueByIt(
    items,
    it[0],
    typeName = "NonEmptyOnSuccessUpdateEmail",
    emptyMsg = "must contain at least one entry",
    dupMsg = "duplicate id or creation reference",
  )
  if errs.len > 0:
    return err(errs)
  var t = initTable[IdOrCreationRef, EmailUpdateSet](items.len)
  for (k, v) in items:
    t[k] = v
  ok(NonEmptyOnSuccessUpdateEmail(t))

func parseNonEmptyOnSuccessDestroyEmail*(
    items: openArray[IdOrCreationRef]
): Result[NonEmptyOnSuccessDestroyEmail, seq[ValidationError]] =
  ## Accumulating smart constructor. Rejects empty input and duplicate
  ## ``IdOrCreationRef`` elements.
  let errs = validateUniqueByIt(
    items,
    it,
    typeName = "NonEmptyOnSuccessDestroyEmail",
    emptyMsg = "must contain at least one entry",
    dupMsg = "duplicate id or creation reference",
  )
  if errs.len > 0:
    return err(errs)
  ok(NonEmptyOnSuccessDestroyEmail(@items))

# -----------------------------------------------------------------------------
# EmailSubmissionHandles / EmailSubmissionResults (RFC 8621 §7.5, RFC 8620 §5.4)
#
# Compound handle pair for ``addEmailSubmissionAndEmailSet``. Aliases of the
# generic ``CompoundHandles[A, B]`` / ``CompoundResults[A, B]`` from
# ``dispatch.nim``; the generic ``getBoth[A, B]`` extractor at
# ``dispatch.nim:254-264`` dispatches by phantom-instantiation, with
# ``mixin fromJson`` deferring serde lookup until call-site instantiation
# (where ``SetResponse[EmailCreatedItem].fromJson`` and
# ``EmailSubmissionSetResponse.fromJson`` are in scope).
# -----------------------------------------------------------------------------

type EmailSubmissionHandles* = CompoundHandles[
  EmailSubmissionSetResponse, SetResponse[EmailCreatedItem, PartialEmail]
]
  ## Domain-named specialisation of ``CompoundHandles[A, B]`` for
  ## ``addEmailSubmissionAndEmailSet`` (EmailSubmission/set + implicit
  ## Email/set per RFC 8620 §5.4 + RFC 8621 §7.5 ¶3). Fields ``primary``
  ## / ``implicit`` inherit from the generic at ``dispatch.nim``. The
  ## implicit handle's ``SetResponse`` carries typed ``PartialEmail``
  ## echoes for the implicit Email/set (A4 D2).

type EmailSubmissionResults* = CompoundResults[
  EmailSubmissionSetResponse, SetResponse[EmailCreatedItem, PartialEmail]
]
  ## Paired extraction target for ``getBoth(EmailSubmissionHandles)`` —
  ## the generic overload in ``dispatch.nim`` handles the dispatch.
