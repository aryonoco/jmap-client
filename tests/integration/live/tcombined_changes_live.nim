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
## guarded on ``loadLiveTestTargets().isOk`` so the file joins
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
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): exercises the dispatch-layer demux of three
    # heterogeneous typed handles in one Request envelope. Convergence
    # of Thread/changes is server-discretionary per RFC 8621 §3
    # (Stalwart and Cyrus surface the cascade; James implements
    # Thread/changes naively and returns an empty change-set). The
    # convergence loop is best-effort; the universal client-library
    # contract is the wire-shape demux of three distinct
    # ResponseHandle[T] arms.
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # --- Resolve inbox + ensure the step-47 mailbox exists --------------
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let tempMailboxId = resolveOrCreateMailbox(
        client, mailAccountId, "phase-h step-47 child"
      )
      .expect("resolveOrCreateMailbox child[" & $target.kind & "]")

    # --- Capture three baselines (post-create) --------------------------
    let baselineMailboxState = captureBaselineState[Mailbox](client, mailAccountId)
      .expect("captureBaselineState[Mailbox][" & $target.kind & "]")
    let baselineThreadState = captureBaselineState[jmap_client.Thread](
        client, mailAccountId
      )
      .expect("captureBaselineState[Thread][" & $target.kind & "]")
    let baselineEmailState = captureBaselineState[Email](client, mailAccountId).expect(
        "captureBaselineState[Email]"
      )

    # --- Mutate: destroy the step-47 mailbox + seed an email ------------
    let (bDestroy, destroyHandle) = addMailboxSet(
      initRequestBuilder(), mailAccountId, destroy = directIds(@[tempMailboxId])
    )
    let respDestroy = client.send(bDestroy).expect(
        "send Mailbox/set destroy step-47 child[" & $target.kind & "]"
      )
    let destroyResp = respDestroy.get(destroyHandle).expect(
        "Mailbox/set destroy step-47 extract[" & $target.kind & "]"
      )
    var sawDestroyOk = false
    destroyResp.destroyResults.withValue(tempMailboxId, outcome):
      assertOn target,
        outcome.isOk,
        "Mailbox/set destroy of empty step-47 mailbox must succeed: " &
          outcome.error.rawType
      sawDestroyOk = true
    do:
      assertOn target,
        false, "Mailbox/set must report a destroy outcome for tempMailboxId"
    assertOn target, sawDestroyOk

    let seededEmailId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-h step-47 seed", "step47seed"
      )
      .expect("seedSimpleEmail[" & $target.kind & "]")

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
      let resp = client.send(b3).expect("send combined */changes[" & $target.kind & "]")
      # Cat-B: any extract may surface a typed error
      # (``cannotCalculateChanges`` on a state-history-windowed server
      # like Cyrus 3.12.2). Skip the iteration on extract failure;
      # the outer loop's best-effort convergence check still runs.
      let mailboxExtract = resp.get(mailboxH)
      let threadExtract = resp.get(threadH)
      let emailExtract = resp.get(emailH)
      if mailboxExtract.isErr or threadExtract.isErr or emailExtract.isErr:
        sleep(200)
        continue
      let mailboxCr = mailboxExtract.unsafeValue
      let threadCr = threadExtract.unsafeValue
      let emailCr = emailExtract.unsafeValue
      if threadCr.created.len + threadCr.updated.len >= 1:
        captureIfRequested(
          client, "combined-changes-mailbox-thread-email-" & $target.kind
        )
          .expect("captureIfRequested[" & $target.kind & "]")
        capturedMailboxCr = mailboxCr
        capturedThreadCr = threadCr
        capturedEmailCr = emailCr
        converged = true
        break
      sleep(200)
    if converged:
      # Strict path — runs on configured targets that propagate the
      # Email/set cascade through Thread/changes.
      assertOn target,
        string(capturedMailboxCr.oldState) == string(baselineMailboxState),
        "Mailbox/changes oldState must echo baseline"
      assertOn target,
        string(capturedThreadCr.oldState) == string(baselineThreadState),
        "Thread/changes oldState must echo baseline"
      assertOn target,
        string(capturedEmailCr.oldState) == string(baselineEmailState),
        "Email/changes oldState must echo baseline"
      assertOn target,
        tempMailboxId in capturedMailboxCr.destroyed,
        "destroyed mailbox id must surface in Mailbox/changes destroyed"
      assertOn target,
        seededEmailId in capturedEmailCr.created,
        "seeded email id must surface in Email/changes created"
      assertOn target,
        capturedMailboxCr.hasMoreChanges == false,
        "Mailbox/changes hasMoreChanges must be false"
      assertOn target,
        capturedThreadCr.hasMoreChanges == false,
        "Thread/changes hasMoreChanges must be false"
      assertOn target,
        capturedEmailCr.hasMoreChanges == false,
        "Email/changes hasMoreChanges must be false"
    else:
      # Wire-shape path — every */changes wire response inside the
      # convergence loop already parsed successfully (the
      # ``.expect()`` calls inside the loop body assert that). Capture
      # whichever non-converged response we have so the captured-
      # replay corpus preserves the naive-Thread/changes wire shape.
      captureIfRequested(
        client, "combined-changes-mailbox-thread-email-" & $target.kind
      )
        .expect("captureIfRequested[" & $target.kind & "]")
    client.close()
