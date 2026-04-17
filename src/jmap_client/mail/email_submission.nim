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
