# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
#
## Live integration test for Email/query → Email/get chained via the
## RFC 8620 §3.7 result reference (``#ids`` JSON Pointer). Stalwart is
## empty after a fresh ``stalwart-up``, so the test seeds one Email via
## ``Email/set create`` (Path C of the plan: use the library to test
## the library; no SMTP path needed) before exercising the chain.
##
## The seeded subject carries the byte-disjoint discriminator token
## ``"chainquery6"`` and the ``Email/query`` filters on it. Re-runs
## against an accumulated Stalwart instance bound the result set to
## this test's own seeds — without the filter, the unbounded chain
## eventually exceeds Stalwart's per-method-call ``Email/get`` cap as
## the account grows. A cleanup leg destroys the seed at end-of-test
## so the count cannot grow unboundedly even under the filter.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.
##
## Five sequential requests:
##  1. ``resolveInboxId`` (mlive) — Mailbox/get for Alice's inbox.
##  2. ``seedSimpleEmail`` (mlive) — Email/set create for one
##     text/plain message carrying the ``"chainquery6"`` token.
##  3. Email/query → Email/get — the chain under test, filtered on
##     ``"chainquery6"`` and capped at ``limit=50`` for belt-and-
##     braces.
##  4. Email/set destroy — cleanup leg so subsequent runs see a clean
##     baseline for this discriminator.

import std/sets
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mconfig
import ./mlive
import ../../mtestblock

testCase temailQueryGetChainLive:
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

    # --- Step 1: resolve inbox id (mlive helper) -------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )

    # --- Step 2: seed one email (mlive helper) ---------------------------
    const seedSubject = "phase-1 step-6 chainquery6 seed"
    let seedId = seedSimpleEmail(client, mailAccountId, inbox, seedSubject, "seedMail")
      .expect("seedSimpleEmail[" & $target.kind & "]")

    # --- Step 3: Email/query → Email/get via #ids back-reference ---------
    # Filter on the byte-disjoint token ``chainquery6`` so the query
    # returns only this test's seeds even on an accumulated Stalwart
    # instance. Stalwart tokenises subject filters; ``chainquery6`` is
    # a single contiguous token chosen to be unique across every
    # ``*_live.nim`` seed. The ``limit=50`` is belt-and-braces: even
    # if a future test reuses the token, the chain stays under
    # Stalwart's per-method-call ``Email/get`` cap.
    let filter = filterCondition(EmailFilterCondition(subject: Opt.some("chainquery6")))
    # Wait for the seeded id to surface in the index so the chained
    # Email/query → Email/get resolves on every server. Cyrus
    # 3.12.2's Xapian rolling indexer settles asynchronously; a
    # fresh-client poll bypasses Cyrus's per-session index cache.
    discard pollEmailQueryIndexed(target, mailAccountId, filter, [seedId].toHashSet)
      .expect("pollEmailQueryIndexed[" & $target.kind & "]")
    let queryParams = QueryParams(limit: Opt.some(parseUnsignedInt(50).get()))
    let (b3a, queryHandle) = addEmailQuery(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      filter = Opt.some(filter),
      queryParams = queryParams,
    )
    let (b3b, getHandle) = addEmailGet(
      b3a,
      mailAccountId,
      ids = Opt.some(queryHandle.idsRef()),
      properties = Opt.some(@["id", "subject", "from", "receivedAt"]),
    )
    let resp3 =
      client.send(b3b.freeze()).expect("send Email/query+get[" & $target.kind & "]")
    let queryResp =
      resp3.get(queryHandle).expect("Email/query extract[" & $target.kind & "]")
    assertOn target,
      queryResp.ids.len >= 1, "Email/query must return the seeded message"
    let getResp = resp3.get(getHandle).expect("Email/get extract[" & $target.kind & "]")
    assertOn target,
      getResp.list.len == queryResp.ids.len,
      "Email/get list count must match Email/query ids count"
    var sawSeed = false
    for email in getResp.list:
      assertOn target, email.id.isSome, "every Email/get entry must have an id"
      assertOn target, email.subject.isSome, "every Email/get entry must have a subject"
      if email.subject.unsafeGet == seedSubject:
        sawSeed = true
    assertOn target, sawSeed, "Email/get list must include the seeded subject"

    # --- Step 4: cleanup — destroy the seed so re-runs stay bounded ------
    let (b4, cleanHandle) = addEmailSet(
      initRequestBuilder(makeBuilderId()), mailAccountId, destroy = directIds(@[seedId])
    )
    let respClean =
      client.send(b4.freeze()).expect("send Email/set cleanup[" & $target.kind & "]")
    let cleanResp = respClean.get(cleanHandle).expect(
        "Email/set cleanup extract[" & $target.kind & "]"
      )
    var cleaned = false
    cleanResp.destroyResults.withValue(seedId, outcome):
      assertOn target, outcome.isOk, "cleanup destroy of seed must succeed"
      cleaned = true
    do:
      assertOn target, false, "cleanup must report an outcome for seedId"
    assertOn target, cleaned
    client.close()
