# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for the RFC 8621 §4.10 first-login workflow:
## Email/query → Email/get(threadId) → Thread/get → Email/get(display)
## chained via ``addEmailQueryWithThreads`` and the H1 purpose-built
## ``EmailQueryThreadChain`` four-handle record. Capstone of Phase C —
## proves the arity-4 type-lift surface end-to-end.
##
## Stalwart's threading pipeline is asynchronous (mirrors Step 8's
## tthread_get_live precedent). The Email/set call records a
## ``threadId`` synchronously, but the Thread record may take a few
## hundred milliseconds to materialise with both seeded ids. The test
## issues the four-call chain inside a bounded re-fetch loop (5
## attempts × 200 ms) and exits the loop as soon as the displayH
## projection carries both seeded ids. Re-fetch budget is documented
## in catalogued divergence #4.
##
## Sequence:
##  1. Resolve inbox via mlive.
##  2. Seed two threaded emails via ``seedThreadedEmails`` — root
##     email gets ``messageId = @[rootMessageId]``; reply email gets
##     ``inReplyTo = @[rootMessageId]`` and ``references =
##     @[rootMessageId]``. Both share the ``"phase-c-18"`` subject
##     prefix (covers the subject-based threading fallback per
##     catalogued divergence #5).
##  3. Build ``addEmailQueryWithThreads(b, mailAccountId, filter =
##     filterCondition(EmailFilterCondition(subject:
##     Opt.some("stepeighteen"))))``.
##  4. Send + extract via ``resp.getAll(threadHandles)``. Retry up to
##     5 times with 200 ms backoff until the display projection
##     carries both seeded ids.
##  5. Assert both seeded ids appear in the threads' emailIds set
##     and in the display projection.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/json
import std/os
import std/sets

import results
import jmap_client
import jmap_client/client
import ./mconfig
import ./mlive

type ChainProjection = object
  ## Distilled view of an ``EmailQueryThreadResults`` extraction —
  ## the two id sets the test asserts on, lifted out of the main
  ## block so the per-attempt parsing does not balloon the block's
  ## cyclomatic complexity past the analyser's threshold.
  displayIds*: HashSet[Id]
  threadEmailIds*: HashSet[Id]

proc projectChainResults(all: EmailQueryThreadResults): ChainProjection =
  ## Project the four-handle thread-chain result into the two id sets
  ## the test cares about: ids from the display Email/get list and
  ## the union of emailIds across the threads' Thread/get list.
  ## Skips entries whose ``id`` is missing or unparseable, and
  ## Thread records that fail to parse — the convergence loop then
  ## decides whether the projection is complete.
  var displayIds = initHashSet[Id]()
  for email in all.display.list:
    for id in email.id:
      displayIds.incl(id)
  var threadEmailIds = initHashSet[Id]()
  for thr in all.threads.list:
    for eid in thr.emailIds:
      threadEmailIds.incl(eid)
  ChainProjection(displayIds: displayIds, threadEmailIds: threadEmailIds)

block temailQueryThreadChainLive:
  forEachLiveTarget(target):
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # --- Resolve inbox + seed threaded corpus ---------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let ids = seedThreadedEmails(
        client,
        mailAccountId,
        inbox,
        @["phase-c-18 stepeighteen root", "phase-c-18 stepeighteen reply"],
        rootMessageId = "<phase-c-18-root@example.com>",
      )
      .expect("seedThreadedEmails[" & $target.kind & "]")
    assertOn target, ids.len == 2, "seedThreadedEmails must return two ids"
    let corpus = ids.toHashSet

    # --- Email/query → Email/get → Thread/get → Email/get -----------------
    # Bounded re-fetch loop. Stalwart's threading pipeline is async
    # (catalogued divergence #4); the synchronous threadId is set at
    # Email/set time, but the Thread record's emailIds list may lag.
    # Cyrus 3.12.2's Xapian rolling indexer also lags Email/set for
    # the writing client's HTTP session (the seeds only become
    # visible to a fresh connection); pre-poll with a fresh client to
    # let the index settle, then close+reopen the test client so the
    # subsequent chained request sees the indexed seeds.
    let filter =
      filterCondition(EmailFilterCondition(subject: Opt.some("stepeighteen")))
    discard pollEmailQueryIndexed(target, mailAccountId, filter, corpus).expect(
        "pollEmailQueryIndexed[" & $target.kind & "]"
      )
    reconnectClient(target, client)
    var projection = ChainProjection()
    var converged = false
    for attempt in 0 ..< 5:
      let (b, threadHandles) =
        addEmailQueryWithThreads(initRequestBuilder(), mailAccountId, filter = filter)
      let resp =
        client.send(b).expect("send Email/query+threads chain[" & $target.kind & "]")
      let all = resp.getAll(threadHandles).expect("getAll[" & $target.kind & "]")
      projection = projectChainResults(all)
      if (corpus <= projection.displayIds) and (corpus <= projection.threadEmailIds):
        converged = true
        break
      sleep(200)

    assertOn target,
      converged,
      "Stalwart threading + display projection did not converge within 1 s — extend " &
        "re-fetch budget or investigate Stalwart 0.15.5 threading pipeline. displayIds=" &
        $projection.displayIds & " threadEmailIds=" & $projection.threadEmailIds
    assertOn target,
      (corpus * projection.displayIds).len == 2,
      "display projection must carry both seeded ids (got intersection " &
        $(corpus * projection.displayIds) & ")"
    assertOn target,
      (corpus * projection.threadEmailIds).len == 2,
      "Thread.emailIds across the chained Thread/get must include both seeded ids " &
        "(got intersection " & $(corpus * projection.threadEmailIds) & ")"
    client.close()
