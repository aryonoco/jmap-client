# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phase H capstone (Step 48). One semantic event — destroying a
## populated mailbox with ``onDestroyRemoveEmails: true`` — produces
## coherent state-delta projections across three entity surfaces. The
## test seeds a child mailbox with six emails (three
## ``seedThreadedEmails`` batches × two emails, each batch carrying a
## distinct ``rootMessageId``), captures three baselines, observes
## whatever ``threadId`` membership Stalwart reports for the seeded
## emails AT cascade time, cascades, then asserts:
##
##  * **Mailbox/changes**: the cascaded mailbox surfaces in
##    ``mailboxCr.destroyed``.
##  * **Email/changes**: every seeded email id appears in the union
##    ``created ∪ updated ∪ destroyed`` of ``emailCr``.
##  * **Thread/changes**: every ``threadId`` Stalwart reported for the
##    seeded emails — *whatever count that is* — appears in the union
##    ``created ∪ updated ∪ destroyed`` of ``threadCr``. Per-thread
##    COUNT is server-discretionary (RFC 8621 §3 "the exact algorithm
##    for determining whether two Emails belong to the same Thread is
##    not mandated in this spec"); per-thread COVERAGE is
##    deterministic (RFC 8620 §5.2 "an id MUST only appear once
##    across the three lists" invariant on the threads that *do*
##    exist).
##  * Per-arm ``hasMoreChanges == false``.
##
## **Why the test does not assert "6 emails → 3 threads".**
## RFC 8621 §3 makes thread merging discretionary — the spec defines
## what a Thread is and what fields it carries, but does not require
## any specific pair of emails to be merged. Stalwart 0.15.5 merges
## threads in Inbox synchronously (Phase C Step 18 verifies this in
## ~1 s) but does not merge threads for emails seeded into a non-
## Inbox child mailbox within any practical observation window
## (>30 s observed, never converges). The capstone's contract is
## *cascade coherence across three entity surfaces*, not threading
## correctness — Phase C Step 18 is the test that exercises threading
## correctness in a setting where the spec-discretionary behaviour
## happens to converge.
##
## **Mutation ordering** follows Step 43's pattern: ensure the
## cascade mailbox + emails exist BEFORE capturing baselines. ThreadId
## collection happens IMMEDIATELY before cascade (no wait between
## collection and cascade) so the observed ids reflect Stalwart's
## thread-membership state at cascade time — eliminating the race
## window where threading could merge between observation and cascade
## and invalidate the observation.
##
## **Re-fetch loop** wraps only the post-cascade combined three-
## changes Request (5×200 ms). Thread/changes state advancement may
## lag the cascade Set call; loop exits when both
## ``observedThreadIds <= allThreadDelta`` and
## ``seededEmailSet <= allEmailDelta``.
##
## Capture: ``cascade-changes-mailbox-email-thread-coherence-stalwart``
## after convergence. Listed in ``tests/testament_skip.txt`` so
## ``just test`` skips it; run via ``just test-integration`` after
## ``just stalwart-up``. Body is guarded on
## ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are
## absent.

import std/os
import std/sets
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tcascadeChangesCoherenceLive:
  forEachLiveTarget(target):
    # James 3.9 compatibility: skipped on James.
    # Reason: exercises Thread/changes convergence after Email/set; James 3.9's Thread/changes is documented as partially implemented (`doc/specs/spec/mail/thread.mdown`: "Naive implementation") and does not advance Thread state when emails are created — `oldState == newState` and `created/updated/destroyed` stay empty. Re-fetch loop times out. Stalwart's threading pipeline is async and exercises the full RFC 8621 §3.2 contract, so the wire shape is preserved via the captured `-stalwart` fixture.
    # Replay coverage for the Stalwart wire shape is preserved via
    # captured ``-stalwart`` fixtures.
    if target.kind == ltkJames:
      continue
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # --- Resolve cascade mailbox + seed three threads (six emails) ------
    let cascadeId = resolveOrCreateMailbox(
        client, mailAccountId, "phase-h step-48 cascade"
      )
      .expect("resolveOrCreateMailbox cascade[" & $target.kind & "]")
    var seededEmailIds: seq[Id] = @[]
    for n in 1 .. 3:
      let subjects =
        @["phase-h step-48 t" & $n & " root", "phase-h step-48 t" & $n & " reply"]
      let rootMessageId = "<phase-h-step-48-t" & $n & "-root@example.com>"
      let ids = seedThreadedEmails(
          client, mailAccountId, cascadeId, subjects, rootMessageId = rootMessageId
        )
        .expect("seedThreadedEmails t" & $n)
      assertOn target,
        ids.len == 2, "seedThreadedEmails t" & $n & " must return two ids"
      seededEmailIds.add(ids[0])
      seededEmailIds.add(ids[1])
    assertOn target,
      seededEmailIds.len == 6,
      "six seeded email ids expected (three threads × two emails)"

    # --- Capture three baselines (post-seed) ----------------------------
    let baselineMailboxState = captureBaselineState[Mailbox](client, mailAccountId)
      .expect("captureBaselineState[Mailbox][" & $target.kind & "]")
    let baselineThreadState = captureBaselineState[jmap_client.Thread](
        client, mailAccountId
      )
      .expect("captureBaselineState[Thread][" & $target.kind & "]")
    let baselineEmailState = captureBaselineState[Email](client, mailAccountId).expect(
        "captureBaselineState[Email]"
      )

    # --- Observe Stalwart's thread membership for the seeded emails ----
    # Single no-wait pass: ask Stalwart for whatever ``threadId`` it
    # currently associates with each seeded email. Whatever count
    # comes back IS Stalwart's thread-membership state at this moment;
    # the per-thread coverage assertion below ratifies that state
    # against the post-cascade Thread/changes delta. RFC 8621 §3
    # makes the count discretionary, so we make no claim about it.
    # The collection sits immediately before the cascade so the
    # observation is the freshest possible snapshot — there is no
    # wait between collection and cascade in which Stalwart could
    # merge threads and invalidate ``observedThreadIds``.
    var observedThreadIds = initHashSet[Id]()
    for sid in seededEmailIds:
      let (b, getHandle) = addEmailGet(
        initRequestBuilder(),
        mailAccountId,
        ids = directIds(@[sid]),
        properties = Opt.some(@["id", "threadId"]),
      )
      let resp =
        client.send(b).expect("send Email/get threadId resolve[" & $target.kind & "]")
      let getResp =
        resp.get(getHandle).expect("Email/get threadId extract[" & $target.kind & "]")
      assertOn target,
        getResp.list.len == 1,
        "Email/get must return exactly one record for the seeded id (got " &
          $getResp.list.len & ")"
      let email = Email.fromJson(getResp.list[0]).expect(
          "parse Email threadId[" & $target.kind & "]"
        )
      assertOn target,
        email.threadId.isSome,
        "every seeded email must carry a threadId; Email/set sets it synchronously"
      observedThreadIds.incl(email.threadId.unsafeGet)
    assertOn target,
      observedThreadIds.len >= 1,
      "at least one threadId must be observed across six seeded emails"

    # --- Cascade destroy ------------------------------------------------
    let (bCascade, cascadeHandle) = addMailboxSet(
      initRequestBuilder(),
      mailAccountId,
      destroy = directIds(@[cascadeId]),
      onDestroyRemoveEmails = true,
    )
    let respCascade = client.send(bCascade).expect(
        "send Mailbox/set cascade destroy[" & $target.kind & "]"
      )
    let cascadeResp = respCascade.get(cascadeHandle).expect(
        "Mailbox/set cascade destroy extract[" & $target.kind & "]"
      )
    var cascadeOk = false
    cascadeResp.destroyResults.withValue(cascadeId, outcome):
      assertOn target,
        outcome.isOk,
        "Mailbox/set destroy with cascade must succeed: " & outcome.error.rawType
      cascadeOk = true
    do:
      assertOn target, false, "Mailbox/set must report a destroy outcome for cascadeId"
    assertOn target, cascadeOk

    # --- Combined three-changes Request inside re-fetch loop ------------
    let seededEmailSet = seededEmailIds.toHashSet
    var converged = false
    var capturedMailboxCr: MailboxChangesResponse
    var capturedEmailCr: ChangesResponse[Email]
    var capturedThreadCr: ChangesResponse[jmap_client.Thread]
    for attempt in 0 ..< 5:
      let (b1, mailboxH) = addMailboxChanges(
        initRequestBuilder(), mailAccountId, sinceState = baselineMailboxState
      )
      let (b2, emailH) =
        addChanges[Email](b1, mailAccountId, sinceState = baselineEmailState)
      let (b3, threadH) = addChanges[jmap_client.Thread](
        b2, mailAccountId, sinceState = baselineThreadState
      )
      let resp = client.send(b3).expect("send cascade */changes[" & $target.kind & "]")
      let mailboxCr =
        resp.get(mailboxH).expect("Mailbox/changes extract[" & $target.kind & "]")
      let emailCr =
        resp.get(emailH).expect("Email/changes extract[" & $target.kind & "]")
      let threadCr =
        resp.get(threadH).expect("Thread/changes extract[" & $target.kind & "]")
      let allEmailDelta =
        emailCr.created.toHashSet + emailCr.updated.toHashSet +
        emailCr.destroyed.toHashSet
      let allThreadDelta =
        threadCr.created.toHashSet + threadCr.updated.toHashSet +
        threadCr.destroyed.toHashSet
      let emailCovered = seededEmailSet <= allEmailDelta
      let threadCovered = observedThreadIds <= allThreadDelta
      if emailCovered and threadCovered:
        captureIfRequested(
          client, "cascade-changes-mailbox-email-thread-coherence-stalwart"
        )
          .expect("captureIfRequested[" & $target.kind & "]")
        capturedMailboxCr = mailboxCr
        capturedEmailCr = emailCr
        capturedThreadCr = threadCr
        converged = true
        break
      sleep(200)
    assertOn target,
      converged,
      "cascade */changes did not converge within 1 s — extend re-fetch budget " &
        "or investigate Stalwart 0.15.5 threading pipeline"

    # --- Coherence assertions ------------------------------------------
    assertOn target,
      cascadeId in capturedMailboxCr.destroyed,
      "cascade mailbox id must surface in Mailbox/changes destroyed"
    assertOn target,
      capturedMailboxCr.hasMoreChanges == false,
      "Mailbox/changes hasMoreChanges must be false"
    let allEmailDelta =
      capturedEmailCr.created.toHashSet + capturedEmailCr.updated.toHashSet +
      capturedEmailCr.destroyed.toHashSet
    for sid in seededEmailIds:
      assertOn target,
        sid in allEmailDelta,
        "seeded email " & string(sid) & " must appear in Email/changes delta"
    assertOn target,
      capturedEmailCr.hasMoreChanges == false,
      "Email/changes hasMoreChanges must be false"
    let allThreadDelta =
      capturedThreadCr.created.toHashSet + capturedThreadCr.updated.toHashSet +
      capturedThreadCr.destroyed.toHashSet
    for tid in observedThreadIds:
      assertOn target,
        tid in allThreadDelta,
        "observed thread " & string(tid) & " must appear in Thread/changes delta"
    assertOn target,
      capturedThreadCr.hasMoreChanges == false,
      "Thread/changes hasMoreChanges must be false"
    client.close()
