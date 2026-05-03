# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for combined ``Mailbox/changes`` +
## ``Thread/changes`` + ``Email/changes`` in one Request envelope.
## Phase H Step 47 — proves the dispatch layer demuxes three
## heterogeneous typed handles in a single response. The Email arm is
## already wire-tested by Phase B Step 11 (``temail_changes_live``);
## its presence here is purely to exercise the combined-Request demux
## across three distinct ``ResponseHandle[T]`` shapes
## (``MailboxChangesResponse``,
## ``ChangesResponse[jmap_client.Thread]``, ``ChangesResponse[Email]``).
##
## All three invocations target the mail accountId — Identity carries
## the submission capability and would force a cross-accountId
## confound, so it stays out of this test. Identity/changes is
## covered standalone in Phase H Step 46.
##
## Stalwart's threading pipeline is asynchronous, so the entire
## combined send + extract + assert is wrapped in a 5×200 ms re-fetch
## loop. Each iteration rebuilds the request and re-issues; the
## baseline states never advance between mutations and the changes
## call, so iterations are idempotent.
##
## Sequence:
##  1. Resolve inbox + resolve-or-create the step-47 child mailbox
##     (so the mailbox exists at baseline; the destroy is then the
##     only mutation in the Mailbox baseline window — see Step 43
##     for why the simpler "baseline-first then create-then-destroy"
##     ordering doesn't work against Stalwart 0.15.5).
##  2. Capture three baselines (Mailbox, Thread, Email) via
##     ``captureBaselineState[T]`` (mlive H0).
##  3. Mutate: destroy the step-47 mailbox; seed one simple email
##     into the inbox.
##  4. Combined Request inside re-fetch loop: ``Mailbox/changes`` +
##     ``Thread/changes`` + ``Email/changes``, all since their
##     respective baselines. Exit loop when
##     ``threadCr.created.len + threadCr.updated.len >= 1``.
##  5. Assert per-arm ``oldState`` echoes baseline; the destroyed
##     mailbox id surfaces in ``mailboxCr.destroyed``; the seeded
##     email id surfaces in ``emailCr.created``; every arm reports
##     ``hasMoreChanges == false``.
##
## Capture: ``combined-changes-mailbox-thread-email-stalwart`` after
## the converged combined send. Listed in
## ``tests/testament_skip.txt`` so ``just test`` skips it; run via
## ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins
## testament's megatest cleanly under ``just test-full`` when env
## vars are absent.

import std/os
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tcombinedChangesLive:
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

    # --- Resolve inbox + ensure the step-47 mailbox exists --------------
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let tempMailboxId = resolveOrCreateMailbox(
        client, mailAccountId, "phase-h step-47 child"
      )
      .expect("resolveOrCreateMailbox child")

    # --- Capture three baselines (post-create) --------------------------
    let baselineMailboxState = captureBaselineState[Mailbox](client, mailAccountId)
      .expect("captureBaselineState[Mailbox]")
    let baselineThreadState = captureBaselineState[jmap_client.Thread](
        client, mailAccountId
      )
      .expect("captureBaselineState[Thread]")
    let baselineEmailState = captureBaselineState[Email](client, mailAccountId).expect(
        "captureBaselineState[Email]"
      )

    # --- Mutate: destroy the step-47 mailbox + seed an email ------------
    let (bDestroy, destroyHandle) = addMailboxSet(
      initRequestBuilder(), mailAccountId, destroy = directIds(@[tempMailboxId])
    )
    let respDestroy =
      client.send(bDestroy).expect("send Mailbox/set destroy step-47 child")
    let destroyResp =
      respDestroy.get(destroyHandle).expect("Mailbox/set destroy step-47 extract")
    var sawDestroyOk = false
    destroyResp.destroyResults.withValue(tempMailboxId, outcome):
      doAssert outcome.isOk,
        "Mailbox/set destroy of empty step-47 mailbox must succeed: " &
          outcome.error.rawType
      sawDestroyOk = true
    do:
      doAssert false, "Mailbox/set must report a destroy outcome for tempMailboxId"
    doAssert sawDestroyOk

    let seededEmailId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-h step-47 seed", "step47seed"
      )
      .expect("seedSimpleEmail")

    # --- Combined Request inside re-fetch loop --------------------------
    var converged = false
    var capturedMailboxCr: MailboxChangesResponse
    var capturedThreadCr: ChangesResponse[jmap_client.Thread]
    var capturedEmailCr: ChangesResponse[Email]
    for attempt in 0 ..< 5:
      let (b1, mailboxH) = addMailboxChanges(
        initRequestBuilder(), mailAccountId, sinceState = baselineMailboxState
      )
      let (b2, threadH) = addChanges[jmap_client.Thread](
        b1, mailAccountId, sinceState = baselineThreadState
      )
      let (b3, emailH) =
        addChanges[Email](b2, mailAccountId, sinceState = baselineEmailState)
      let resp = client.send(b3).expect("send combined */changes")
      let mailboxCr = resp.get(mailboxH).expect("Mailbox/changes extract")
      let threadCr = resp.get(threadH).expect("Thread/changes extract")
      let emailCr = resp.get(emailH).expect("Email/changes extract")
      if threadCr.created.len + threadCr.updated.len >= 1:
        captureIfRequested(client, "combined-changes-mailbox-thread-email-stalwart")
          .expect("captureIfRequested")
        capturedMailboxCr = mailboxCr
        capturedThreadCr = threadCr
        capturedEmailCr = emailCr
        converged = true
        break
      sleep(200)
    doAssert converged,
      "combined */changes did not converge within 1 s — extend re-fetch budget " &
        "or investigate Stalwart 0.15.5 threading pipeline"
    doAssert string(capturedMailboxCr.oldState) == string(baselineMailboxState),
      "Mailbox/changes oldState must echo baseline"
    doAssert string(capturedThreadCr.oldState) == string(baselineThreadState),
      "Thread/changes oldState must echo baseline"
    doAssert string(capturedEmailCr.oldState) == string(baselineEmailState),
      "Email/changes oldState must echo baseline"
    doAssert tempMailboxId in capturedMailboxCr.destroyed,
      "destroyed mailbox id must surface in Mailbox/changes destroyed"
    doAssert seededEmailId in capturedEmailCr.created,
      "seeded email id must surface in Email/changes created"
    doAssert capturedMailboxCr.hasMoreChanges == false,
      "Mailbox/changes hasMoreChanges must be false"
    doAssert capturedThreadCr.hasMoreChanges == false,
      "Thread/changes hasMoreChanges must be false"
    doAssert capturedEmailCr.hasMoreChanges == false,
      "Email/changes hasMoreChanges must be false"
    client.close()
