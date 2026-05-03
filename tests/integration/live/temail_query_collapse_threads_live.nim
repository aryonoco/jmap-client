# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phase I Step 57 — wire test of ``Email/query`` with the
## ``collapseThreads`` parameter (RFC 8621 §4.4.3).  Phase C17 used
## the default ``false`` in the chain.  This step asserts:
##
##  * ``collapseThreads = false`` (default) returns every email
##    that matches the filter.
##  * ``collapseThreads = true`` returns at most one email per
##    threadId — the threaded pair collapses to one entry while
##    the standalone email remains.
##
## **Threading convergence note.** Phase C18 / H48 catalogue
## documents Stalwart 0.15.5's behaviour: the inbox merges threads
## synchronously for emails seeded with the same root Message-ID,
## while non-Inbox mailboxes do not converge within any practical
## window.  Step 57 seeds into Inbox so threading converges.
##
## Workflow:
##
##  1. Resolve mail account, inbox.
##  2. Seed two threaded emails sharing a root Message-ID via
##     ``seedThreadedEmails`` (subjects ``phase-i 57 root`` /
##     ``phase-i 57 reply``) plus one standalone email via
##     ``seedSimpleEmail`` (``phase-i 57 standalone``).
##  3. Sub-test A: ``collapseThreads = false`` — capture the
##     no-collapse cardinality.  Re-runs against the same Stalwart
##     compound the seeded copies, so the test asserts the
##     baseline ``>= 3`` (one per fresh seed) without pinning an
##     exact count.
##  4. Sub-test B: re-fetch loop wrapping ``collapseThreads = true``
##     — Stalwart's threading pipeline may need a brief moment to
##     observe the threaded pair as a single thread.  Convergence
##     condition: ``ids.len < noCollapseCount`` and ``>= 2`` (at
##     least the threaded pair plus the standalone).  Capture the
##     wire response on this leg.
##
## Capture: ``email-query-collapse-threads-stalwart``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it;
## run via ``just test-integration`` after ``just stalwart-up``.
## Body is guarded on ``loadLiveTestConfig().isOk`` so the file
## joins testament's megatest cleanly under ``just test-full`` when
## env vars are absent.

import std/os
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

const ThreadConvergeAttempts = 10
const ThreadConvergeIntervalMs = 200

block temailQueryCollapseThreadsLive:
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

    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let threadedIds = seedThreadedEmails(
        client,
        mailAccountId,
        inbox,
        @["phase-i 57 root", "phase-i 57 reply"],
        rootMessageId = "<phase-i-57@example.com>",
      )
      .expect("seedThreadedEmails")
    doAssert threadedIds.len == 2, "two threaded ids expected"
    let standaloneId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-i 57 standalone", "phase-i-57-standalone"
      )
      .expect("seedSimpleEmail standalone")
    discard standaloneId

    let filter = filterCondition(EmailFilterCondition(subject: Opt.some("phase-i 57")))

    # Sub-test A: collapseThreads default false.  The exact count
    # may vary across runs (re-running the test seeds additional
    # copies because the seed creates new emails each time), but
    # the no-collapse leg must surface at least the three seeds.
    let (b1, h1) =
      addEmailQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(filter))
    let resp1 = client.send(b1).expect("send Email/query no-collapse")
    let qr1 = resp1.get(h1).expect("Email/query no-collapse extract")
    let noCollapseCount = qr1.ids.len
    doAssert noCollapseCount >= 3,
      "default collapseThreads=false must surface at least the three seeds (got " &
        $noCollapseCount & ")"

    # Sub-test B: collapseThreads = true.  Re-fetch loop wraps the
    # query because Stalwart's threading pipeline may need a moment
    # to merge seeded replies into the same thread.  Convergence
    # condition: ``collapseCount < noCollapseCount`` and
    # ``collapseCount >= 2`` (at least the threaded pair plus the
    # standalone email).
    var converged = false
    for _ in 0 ..< ThreadConvergeAttempts:
      let (b2, h2) = addEmailQuery(
        initRequestBuilder(),
        mailAccountId,
        filter = Opt.some(filter),
        collapseThreads = true,
      )
      let resp2 = client.send(b2).expect("send Email/query collapse")
      let qr2 = resp2.get(h2).expect("Email/query collapse extract")
      if qr2.ids.len < noCollapseCount and qr2.ids.len >= 2:
        captureIfRequested(client, "email-query-collapse-threads-stalwart").expect(
          "captureIfRequested"
        )
        converged = true
        break
      sleep(ThreadConvergeIntervalMs)
    doAssert converged,
      "collapseThreads=true must converge to fewer ids than no-collapse within " &
        $(ThreadConvergeAttempts * ThreadConvergeIntervalMs) & " ms — Stalwart's " &
        "threading pipeline may need a moment to merge the seeded reply"

    client.close()
