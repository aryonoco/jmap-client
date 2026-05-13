# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Mailbox/changes (RFC 8621 §2.2) against
## Stalwart. Phase H Step 43 — first wire test of ``addMailboxChanges``
## and the §2.2-extended ``MailboxChangesResponse`` (carries the
## Mailbox-specific ``updatedProperties`` field on top of the seven
## standard ``ChangesResponse[Mailbox]`` fields).
##
## Mutation chosen for determinism: ensure a child mailbox exists,
## capture baseline ``state``, then destroy. Between baseline and the
## changes call the only mutation is the destroy, so the destroyed id
## surfaces in ``cr.destroyed`` for any RFC-conformant server (RFC
## 8620 §5.2 invariant "An id MUST only appear once across the three
## lists"). The simpler alternative — capture baseline, then create-
## then-destroy — would require Stalwart to honour the §5.2 SHOULD
## clause (server SHOULD collapse a create-then-destroy into just
## ``destroyed``); Stalwart 0.15.5 does not, hence the ordering chosen
## here.
##
## Two paths:
##  1. **Happy path** — resolve-or-create child mailbox; capture
##     baseline via ``captureBaselineState[Mailbox]`` (mlive H0);
##     destroy it; ``Mailbox/changes`` since baseline. Assert the
##     destroyed id surfaces in ``cr.destroyed``, ``cr.oldState``
##     echoes the baseline, and ``hasMoreChanges`` is false.
##     ``cr.updatedProperties`` is reachable as ``Opt[seq[string]]``
##     — the typed extension field.
##  2. **Sad path** — issue ``Mailbox/changes`` with a synthetic
##     bogus ``sinceState``. RFC 8620 §5.5 permits the server to
##     project the failure as either ``cannotCalculateChanges`` or
##     ``invalidArguments``; the test accepts both via set-membership
##     (Phase B Step 11 precedent at ``temail_changes_live.nim:96-98``).
##
## Capture: ``mailbox-changes-bogus-state-stalwart`` after the sad-
## path send. Listed in ``tests/testament_skip.txt`` so ``just test``
## skips it; run via ``just test-integration`` after
## ``just stalwart-up``. Body is guarded on
## ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tmailboxChangesLive:
  forEachLiveTarget(target):
    let (client, recorder) = initRecordingClient(target)
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # --- Resolve-or-create child mailbox (mutation seed) ----------------
    let tempId = resolveOrCreateMailbox(client, mailAccountId, "phase-h step-43 child")
      .expect("resolveOrCreateMailbox child[" & $target.kind & "]")

    # --- Baseline state via empty Mailbox/get (post-create) -------------
    # Captured AFTER resolve-or-create so the destroy is the only
    # mutation between baseline and the changes call. This makes the
    # destroyed id's appearance in ``cr.destroyed`` deterministic for
    # any RFC-conformant server, sidestepping Stalwart 0.15.5's silence
    # on the §5.2 create-then-destroy SHOULD clause.
    let baselineState = captureBaselineState[Mailbox](client, mailAccountId).expect(
        "captureBaselineState[Mailbox]"
      )

    let (bDestroy, destroyHandle) = addMailboxSet(
      initRequestBuilder(makeBuilderId()), mailAccountId, destroy = directIds(@[tempId])
    )
    let respDestroy = client.send(bDestroy.freeze()).expect(
        "send Mailbox/set destroy[" & $target.kind & "]"
      )
    let destroyResp = respDestroy.get(destroyHandle).expect(
        "Mailbox/set destroy extract[" & $target.kind & "]"
      )
    var sawDestroyOk = false
    destroyResp.destroyResults.withValue(tempId, outcome):
      assertOn target,
        outcome.isOk,
        "Mailbox/set destroy of empty mailbox must succeed: " & outcome.error.rawType
      sawDestroyOk = true
    do:
      assertOn target, false, "Mailbox/set must report a destroy outcome for tempId"
    assertOn target, sawDestroyOk

    # --- Happy path: Mailbox/changes since baseline ---------------------
    let (bHappy, happyHandle) = addMailboxChanges(
      initRequestBuilder(makeBuilderId()), mailAccountId, sinceState = baselineState
    )
    let respHappy = client.send(bHappy.freeze()).expect(
        "send Mailbox/changes happy[" & $target.kind & "]"
      )
    let cr = respHappy.get(happyHandle).expect(
        "Mailbox/changes happy extract[" & $target.kind & "]"
      )
    assertOn target,
      $cr.oldState == $baselineState, "oldState must echo the supplied baseline"
    assertOn target,
      tempId in cr.destroyed,
      "create-then-destroy id must surface in destroyed (RFC 8620 §5.2 SHOULD)"
    assertOn target, cr.hasMoreChanges == false, "no further changes pending"
    # cr.updatedProperties is reachable as Opt[seq[string]] — the
    # MailboxChangesResponse RFC 8621 §2.2 extension. Reading it here
    # is the compile-time guarantee under test; runtime presence is
    # server-discretional.
    discard cr.updatedProperties

    # --- Sad path: bogus sinceState -------------------------------------
    let bogusState = parseJmapState("phase-h-43-bogus-state").get()
    let (bSad, sadHandle) = addMailboxChanges(
      initRequestBuilder(makeBuilderId()), mailAccountId, sinceState = bogusState
    )
    let respSad = client.send(bSad.freeze()).expect(
        "send Mailbox/changes bogus[" & $target.kind & "]"
      )
    captureIfRequested(
      recorder.lastResponseBody, "mailbox-changes-bogus-state-" & $target.kind
    )
      .expect("captureIfRequested")
    let sadExtract = respSad.get(sadHandle)
    assertOn target,
      sadExtract.isErr, "bogus sinceState must surface as a method-level error"
    let getErr = sadExtract.error
    doAssert getErr.kind == gekMethod, "expected gekMethod"
    let methodErr = getErr.methodErr
    assertOn target,
      methodErr.errorType in {metCannotCalculateChanges, metInvalidArguments},
      "method error must project as cannotCalculateChanges or invalidArguments " &
        "(got rawType=" & methodErr.rawType & ")"
