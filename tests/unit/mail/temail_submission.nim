# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for the phantom-typed ``EmailSubmission[S: static UndoStatus]``
## entity, the existential wrapper ``AnyEmailSubmission`` (Pattern A
## sealed — see ``12-mail-G2-design.md`` §8 item 4), and the typed
## transition arrow ``cancelUpdate`` (G1 §4.2, §4.4; G2 §8.3, §8.5).
## The load-bearing check is ``phantomArrowStaticRejectsFinalAndCanceled``:
## a compile-time ``static:`` proof that ``cancelUpdate`` refuses
## ``EmailSubmission[usFinal]`` and ``EmailSubmission[usCanceled]``. A
## regression silently demotes the RFC 8621 §7 "only pending may be
## cancelled" invariant to an unchecked runtime path — ``cancelUpdate``
## has no runtime guard.

{.push raises: [].}

import jmap_client/internal/mail/email_submission
import jmap_client/internal/mail/submission_status
import jmap_client/internal/types/validation

import ../../massertions
import ../../mfixtures
import ../../mtestblock

testCase toAnyPendingBranchPreserved:
  # ``toAny(EmailSubmission[usPending])`` must set ``state == usPending``
  # and populate only the ``usPending`` branch — ``asPending`` returns
  # ``Opt.some`` with the input value; ``asFinal`` and ``asCanceled``
  # return ``Opt.none``. Covers §8.5 matrix rows 1 (value) and 4
  # (right-branch access).
  let s = makeEmailSubmission[usPending](id = makeId("es-pending"))
  let a = toAny(s)
  doAssert a.state == usPending
  let p = a.asPending()
  doAssert p.isSome
  assertEq p.get(), s
  doAssert a.asFinal().isNone
  doAssert a.asCanceled().isNone

testCase toAnyFinalBranchPreserved:
  # Symmetric to ``toAnyPendingBranchPreserved`` for the ``usFinal``
  # phantom instantiation.
  let s = makeEmailSubmission[usFinal](id = makeId("es-final"))
  let a = toAny(s)
  doAssert a.state == usFinal
  let f = a.asFinal()
  doAssert f.isSome
  assertEq f.get(), s
  doAssert a.asPending().isNone
  doAssert a.asCanceled().isNone

testCase toAnyCanceledBranchPreserved:
  # Symmetric to ``toAnyPendingBranchPreserved`` for the ``usCanceled``
  # phantom instantiation.
  let s = makeEmailSubmission[usCanceled](id = makeId("es-canceled"))
  let a = toAny(s)
  doAssert a.state == usCanceled
  let c = a.asCanceled()
  doAssert c.isSome
  assertEq c.get(), s
  doAssert a.asPending().isNone
  doAssert a.asFinal().isNone

testCase cancelUpdateProducesSetUndoStatusToCanceled:
  # Value-level shape: cancelUpdate returns the nullary
  # ``esuSetUndoStatusToCanceled`` variant. Delegation equivalence
  # (cancelUpdate == setUndoStatusToCanceled) is documented in the
  # source comment block (email_submission.nim cancelUpdate) — pin it
  # here via the discriminator. ``EmailSubmissionUpdate`` is a single-
  # variant nullary case object with no custom ``==``; the
  # discriminator is the sole source of truth for variant identity.
  # Type-level enforcement (only usPending accepted) is in block
  # ``phantomArrowStaticRejectsFinalAndCanceled`` below.
  let s = makeEmailSubmission[usPending]()
  let u = cancelUpdate(s)
  doAssert u.kind == esuSetUndoStatusToCanceled
  doAssert u.kind == setUndoStatusToCanceled().kind

testCase phantomArrowStaticRejectsFinalAndCanceled:
  # THE LOAD-BEARING CHECK for the phantom-typed transition arrow.
  # ``cancelUpdate`` is declared as ``cancelUpdate(s: EmailSubmission[
  # usPending])``. The two wrong-state instantiations MUST fail at
  # compile time via overload resolution — there is no runtime guard
  # inside ``cancelUpdate`` (the parameter is ``discard``ed; only its
  # phantom type matters). A regression where any of these negative
  # probes starts compiling would silently demote the RFC 8621 §7
  # "only pending may be cancelled" invariant from type-level to
  # runtime-level — and there is no runtime check.
  static:
    doAssert compiles(cancelUpdate(default(EmailSubmission[usPending])))
    doAssert not compiles(cancelUpdate(default(EmailSubmission[usFinal])))
    doAssert not compiles(cancelUpdate(default(EmailSubmission[usCanceled])))

testCase existentialBranchAccessorContract:
  # §8.5 matrix row 5 (post-sealing): wrong-branch access on
  # AnyEmailSubmission is UNREPRESENTABLE. Pattern A sealing renames
  # the branch fields to module-private ``rawPending`` / ``rawFinal`` /
  # ``rawCanceled`` and introduces the ``asPending`` / ``asFinal`` /
  # ``asCanceled`` accessor family. This block pins three contracts:
  # (1) accessor visibility, (2) compile-time refusal of raw-name
  # and public-duplicate brace construction, (3) ``Opt[T]`` projection
  # shape per state.
  #
  # Relates to the pre-sealing "raises FieldDefect" contract — now
  # unreachable from external code, which matters because under
  # ``--panics:on`` (config.nims:23) ``FieldDefect`` is fatal and
  # cannot be caught.

  # (1) Accessor visibility — all three accessors are UFCS-callable.
  let a = toAny(makeEmailSubmission[usPending](id = makeId("es-p")))
  doAssert compiles(a.asPending())
  doAssert compiles(a.asFinal())
  doAssert compiles(a.asCanceled())

  # (2) Sealing — raw field names are module-private; brace
  # construction with them from outside the module fails to compile.
  # Mirrors EmailSubmissionBlueprint sealingContract in
  # temail_submission_blueprint.nim.
  # The ``{.used.}`` pragma silences XDeclaredButNotUsed hints — the
  # ``compiles()`` probes inside ``assertNotCompiles`` do not count
  # as uses under Nim's reference-tracking heuristics for every
  # variable equally.
  let sp {.used.} = makeEmailSubmission[usPending]()
  let sf {.used.} = makeEmailSubmission[usFinal]()
  let sc {.used.} = makeEmailSubmission[usCanceled]()
  assertNotCompiles AnyEmailSubmission(state: usPending, rawPending: sp)
  assertNotCompiles AnyEmailSubmission(state: usFinal, rawFinal: sf)
  assertNotCompiles AnyEmailSubmission(state: usCanceled, rawCanceled: sc)
  # No public duplicates — the old exported names must not exist.
  assertNotCompiles AnyEmailSubmission(state: usPending, pending: sp)
  assertNotCompiles AnyEmailSubmission(state: usFinal, final: sf)
  assertNotCompiles AnyEmailSubmission(state: usCanceled, canceled: sc)

  # (3) Opt projection shape — each constructed state yields
  # ``Opt.some`` on its matching accessor and ``Opt.none`` on the
  # other two. Three states × three accessors = 9 probes.
  doAssert a.asPending().isSome
  doAssert a.asFinal().isNone
  doAssert a.asCanceled().isNone
  let f = toAny(makeEmailSubmission[usFinal](id = makeId("es-f")))
  doAssert f.asFinal().isSome
  doAssert f.asPending().isNone
  doAssert f.asCanceled().isNone
  let c = toAny(makeEmailSubmission[usCanceled](id = makeId("es-c")))
  doAssert c.asCanceled().isSome
  doAssert c.asPending().isNone
  doAssert c.asFinal().isNone
