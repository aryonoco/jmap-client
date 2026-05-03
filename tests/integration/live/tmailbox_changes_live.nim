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
## ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tmailboxChangesLive:
  let cfgRes = loadLiveTestConfig()
  if cfgRes.isOk:
    let cfg = cfgRes.get()
    var client = initJmapClient(
        sessionUrl = cfg.sessionUrl,
        bearerToken = cfg.aliceToken,
        authScheme = cfg.authScheme,
      )
      .expect("initJmapClient")
    let session = client.fetchSession().expect("fetchSession")
    var mailAccountId: AccountId
    session.primaryAccounts.withValue("urn:ietf:params:jmap:mail", v):
      mailAccountId = v
    do:
      doAssert false, "session must advertise a primary mail account"

    # --- Resolve-or-create child mailbox (mutation seed) ----------------
    let tempId = resolveOrCreateMailbox(client, mailAccountId, "phase-h step-43 child")
      .expect("resolveOrCreateMailbox child")

    # --- Baseline state via empty Mailbox/get (post-create) -------------
    # Captured AFTER resolve-or-create so the destroy is the only
    # mutation between baseline and the changes call. This makes the
    # destroyed id's appearance in ``cr.destroyed`` deterministic for
    # any RFC-conformant server, sidestepping Stalwart 0.15.5's silence
    # on the §5.2 create-then-destroy SHOULD clause.
    let baselineState = captureBaselineState[Mailbox](client, mailAccountId).expect(
        "captureBaselineState[Mailbox]"
      )

    let (bDestroy, destroyHandle) =
      addMailboxSet(initRequestBuilder(), mailAccountId, destroy = directIds(@[tempId]))
    let respDestroy = client.send(bDestroy).expect("send Mailbox/set destroy")
    let destroyResp =
      respDestroy.get(destroyHandle).expect("Mailbox/set destroy extract")
    var sawDestroyOk = false
    destroyResp.destroyResults.withValue(tempId, outcome):
      doAssert outcome.isOk,
        "Mailbox/set destroy of empty mailbox must succeed: " & outcome.error.rawType
      sawDestroyOk = true
    do:
      doAssert false, "Mailbox/set must report a destroy outcome for tempId"
    doAssert sawDestroyOk

    # --- Happy path: Mailbox/changes since baseline ---------------------
    let (bHappy, happyHandle) =
      addMailboxChanges(initRequestBuilder(), mailAccountId, sinceState = baselineState)
    let respHappy = client.send(bHappy).expect("send Mailbox/changes happy")
    let cr = respHappy.get(happyHandle).expect("Mailbox/changes happy extract")
    doAssert string(cr.oldState) == string(baselineState),
      "oldState must echo the supplied baseline"
    doAssert tempId in cr.destroyed,
      "create-then-destroy id must surface in destroyed (RFC 8620 §5.2 SHOULD)"
    doAssert cr.hasMoreChanges == false, "no further changes pending"
    # cr.updatedProperties is reachable as Opt[seq[string]] — the
    # MailboxChangesResponse RFC 8621 §2.2 extension. Reading it here
    # is the compile-time guarantee under test; runtime presence is
    # server-discretional.
    discard cr.updatedProperties

    # --- Sad path: bogus sinceState -------------------------------------
    let bogusState = JmapState("phase-h-43-bogus-state")
    let (bSad, sadHandle) =
      addMailboxChanges(initRequestBuilder(), mailAccountId, sinceState = bogusState)
    let respSad = client.send(bSad).expect("send Mailbox/changes bogus")
    captureIfRequested(client, "mailbox-changes-bogus-state-stalwart").expect(
      "captureIfRequested"
    )
    let sadExtract = respSad.get(sadHandle)
    doAssert sadExtract.isErr, "bogus sinceState must surface as a method-level error"
    let methodErr = sadExtract.error
    doAssert methodErr.errorType in {metCannotCalculateChanges, metInvalidArguments},
      "method error must project as cannotCalculateChanges or invalidArguments " &
        "(got rawType=" & methodErr.rawType & ")"
    client.close()
