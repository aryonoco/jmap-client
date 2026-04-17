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

import std/tables

import ../primitives
import ../identifiers
import ../validation
import ../framework
import ../methods
import ./submission_envelope
import ./submission_status

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
  ## Existential wrapper discriminated on ``UndoStatus``. Serde
  ## dispatches once on the wire ``undoStatus`` field and constructs the
  ## corresponding phantom-typed branch via the ``toAny`` overloads.
  case state*: UndoStatus
  of usPending:
    pending*: EmailSubmission[usPending]
  of usFinal:
    final*: EmailSubmission[usFinal]
  of usCanceled:
    canceled*: EmailSubmission[usCanceled]

func toAny*(s: EmailSubmission[usPending]): AnyEmailSubmission =
  ## Lifts a pending submission into the existential wrapper.
  AnyEmailSubmission(state: usPending, pending: s)

func toAny*(s: EmailSubmission[usFinal]): AnyEmailSubmission =
  ## Lifts a final submission into the existential wrapper.
  AnyEmailSubmission(state: usFinal, final: s)

func toAny*(s: EmailSubmission[usCanceled]): AnyEmailSubmission =
  ## Lifts a canceled submission into the existential wrapper.
  AnyEmailSubmission(state: usCanceled, canceled: s)

func `==`*(a, b: AnyEmailSubmission): bool =
  ## Arm-dispatched structural equality. Auto-derived ``==`` on a case
  ## object uses a parallel ``fields`` iterator that rejects the
  ## discriminated shape. Delegates each branch to the non-case
  ## ``EmailSubmission[S].==``.
  if a.state != b.state:
    return false
  case a.state
  of usPending:
    a.pending == b.pending
  of usFinal:
    a.final == b.final
  of usCanceled:
    a.canceled == b.canceled

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

func `[]`*(a: NonEmptyIdSeq, i: Natural): lent Id =
  ## Indexed read-only access; the underlying ``seq[Id]`` retains ownership.
  seq[Id](a)[i]

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
  ## ``sendAt`` (server stamp). ``undoStatus`` deliberately omitted —
  ## delay-send-disabled servers may flip it to ``final`` or ``canceled``
  ## immediately, so callers must read live state via ``/get`` rather than
  ## trust a stale value carried on the create response.
  id*: Id
  threadId*: Id
  sendAt*: UTCDate

# -----------------------------------------------------------------------------
# EmailSubmissionSetResponse — /set response alias (RFC 8621 §7.5)
#
# Typed instantiation of the generic SetResponse[T] (methods.nim). After
# Phase A's promotion, T drives createResults' typed payload via T.fromJson
# resolved at instantiation through ``mixin``.
# -----------------------------------------------------------------------------

type EmailSubmissionSetResponse* = SetResponse[EmailSubmissionCreatedItem]
  ## Typed alias for the EmailSubmission/set response (RFC 8621 §7.5).
  ## ``createResults`` carries ``EmailSubmissionCreatedItem`` payloads via
  ## ``mergeCreateResults[EmailSubmissionCreatedItem]`` (methods.nim);
  ## ``updateResults`` and ``destroyResults`` follow the standard merged
  ## ``Result``-table shape. The
  ## per-entity ``fromJson`` for
  ## ``EmailSubmissionCreatedItem`` lands in the L2 serde module — until
  ## then this alias is callable as a typed handle but cannot be parsed.
