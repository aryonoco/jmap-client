# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## RFC 8621 §7 EmailSubmission entity read model with GADT-style phantom
## indexing on ``UndoStatus`` (G1 design §4). The phantom parameter lifts
## the RFC's "only pending submissions may be canceled" invariant from
## runtime guard into the type system. ``AnyEmailSubmission`` is the
## existential wrapper — serde produces it once at the wire boundary;
## consumers pattern-match on ``.state`` to recover the phantom-indexed
## branch.

{.push raises: [], noSideEffect.}

import std/tables

import ../primitives
import ../identifiers
import ../validation
import ./submission_envelope
import ./submission_status

type EmailSubmission*[S: static UndoStatus] {.ruleOff: "objects".} = object
  ## Entity read model indexed on the RFC 8621 §7 ``undoStatus``. Each
  ## ``S`` produces a distinct concrete type — ``EmailSubmission[usPending]``
  ## vs ``EmailSubmission[usFinal]`` — so Step 7's ``cancelUpdate`` can
  ## constrain on ``EmailSubmission[usPending]`` only. Adding a
  ## hypothetical fourth ``UndoStatus`` variant forces compile errors at
  ## every ``AnyEmailSubmission`` case site and every ``toAny`` overload.
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
  ## Existential wrapper discriminated on ``UndoStatus``. Serde (Step 12)
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
  ## ``EmailSubmission[S].==`` which auto-derives cleanly once
  ## ``ReversePath.==`` is in place.
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
# EmailSubmissionBlueprint — creation model (RFC 8621 §7.5; design §5, G13–G15)
#
# Shape: Pattern A sealing (raw* private fields + same-name UFCS accessors)
# combined with Result[T, seq[ValidationError]] error rail.
# -----------------------------------------------------------------------------

type EmailSubmissionBlueprint* {.ruleOff: "objects".} = object
  ## Creation model for ``EmailSubmission/set`` create operations. Carries
  ## the three client-settable fields per RFC 8621 §7.5: ``identityId``,
  ## ``emailId``, and an optional ``envelope``. Named "Blueprint" to match
  ## ``EmailBlueprint`` (F1) — signals construction-with-rules (G13).
  ##
  ## Fields are module-private with a ``raw`` prefix; construction is gated
  ## by ``parseEmailSubmissionBlueprint`` and read access is via same-name
  ## UFCS accessors below. Direct brace construction outside this module is
  ## a compile error — Pattern A sealing ensures the smart constructor is
  ## the sole construction path, so any future client-checkable rule lands
  ## inside the constructor body with zero call-site churn.
  ##
  ## When ``envelope`` is ``Opt.none``, the server synthesises the envelope
  ## from the referenced Email's headers per RFC §7.5 ¶4 (G14).
  rawIdentityId: Id
  rawEmailId: Id
  rawEnvelope: Opt[Envelope]

func parseEmailSubmissionBlueprint*(
    identityId: Id, emailId: Id, envelope: Opt[Envelope] = Opt.none(Envelope)
): Result[EmailSubmissionBlueprint, seq[ValidationError]] =
  ## Accumulating-error smart constructor. Returns ``Result[T, seq[...]]``
  ## for API-shape parity with sibling creation constructors
  ## (``parseEmailBlueprint``, ``initEmailUpdateSet``,
  ## ``parseNonEmptyRcptList``) per G15.
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
# EmailSubmissionUpdate — update algebra (RFC 8621 §7.5 ¶3; design §6, G16)
#
# Typed patch operations for EmailSubmission/set update. The RFC permits
# exactly one mutation post-create: ``undoStatus`` pending → canceled. The
# sealed-sum shape (one variant today) mirrors F1 ``EmailUpdate`` so future
# variants force compile errors at every ``case`` site.
# -----------------------------------------------------------------------------

type EmailSubmissionUpdateVariantKind* = enum
  ## Discriminator for ``EmailSubmissionUpdate``. Single variant today —
  ## the sealed-sum shape exists for forwards compatibility (G16): adding
  ## a second variant later would force compile errors at every ``case``
  ## site.
  esuSetUndoStatusToCanceled

type EmailSubmissionUpdate* {.ruleOff: "objects".} = object
  ## Typed EmailSubmission patch operation (RFC 8621 §7.5 ¶3). One
  ## variant today — pending → canceled — matching the RFC's single
  ## permitted mutation. Sealed-sum shape preserves F1 ``EmailUpdate``
  ## parity (G16). Nullary variant (``discard``) is deliberate: the
  ## discriminator alone carries the semantics, mirroring how
  ## ``euSetKeywords`` in F1 carries data only when data is meaningful.
  case kind*: EmailSubmissionUpdateVariantKind
  of esuSetUndoStatusToCanceled:
    discard

func setUndoStatusToCanceled*(): EmailSubmissionUpdate =
  ## Protocol-primitive constructor for the RFC 8621 §7.5 ¶3
  ## ``undoStatus: "canceled"`` wire patch. Total — the RFC imposes no
  ## client-checkable preconditions on the patch value itself; the
  ## "pending only" invariant is enforced at the submission site via
  ## ``cancelUpdate``'s phantom-typed parameter, not here.
  EmailSubmissionUpdate(kind: esuSetUndoStatusToCanceled)

func cancelUpdate*(s: EmailSubmission[usPending]): EmailSubmissionUpdate =
  ## Cancel a pending submission — thin ergonomic wrapper that carries
  ## the RFC 8621 §7 invariant "only pending may be canceled" in the
  ## type. ``cancelUpdate(EmailSubmission[usFinal])`` and
  ## ``cancelUpdate(EmailSubmission[usCanceled])`` are compile errors
  ## (G4). The ``s`` parameter is unused at runtime — the phantom binds
  ## at the call site purely to carry the compile-time guarantee.
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
  ## Accumulating smart constructor mirroring ``initNonEmptyEmailImportMap``
  ## (email.nim) and ``parseEmailSubmissionBlueprint`` above. Rejects:
  ##   * empty input — the ``/set`` builder's ``update:`` field has
  ##     exactly one "no updates" representation: omit the entry via
  ##     ``Opt.none``. Allowing an empty Table would create a second
  ##     encoding and break one-source-of-truth.
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
