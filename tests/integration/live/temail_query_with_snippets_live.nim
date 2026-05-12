# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Email/query → SearchSnippet/get chained
## via the H1 ``ChainedHandles[A, B]`` generic (RFC 8620 §3.7
## back-reference + RFC 8621 §4.10/§5.1). First Phase C step
## exercising ``addEmailQueryWithSnippets`` (mail_methods.nim) and
## ``getBoth`` (dispatch.nim). Splits cleanly from Step 16 — that
## test proved the standalone snippet-builder/parser; this test
## isolates the chain plumbing.
##
## Sequence:
##  1. Resolve inbox via mlive.
##  2. Seed two emails sharing a phase-c-17 prefix and a per-test
##     discriminator ``"stepseventeen"`` plus distinct ordering
##     suffixes. Capture both ids as the seeded corpus.
##  3. Build ``addEmailQueryWithSnippets(b, mailAccountId, filter =
##     filterCondition(EmailFilterCondition(subject:
##     Opt.some("stepseventeen"))))``.
##  4. Send. Extract via ``resp.getBoth(chainHandles)`` —
##     ``ChainedHandles[QueryResponse[Email], SearchSnippetGetResponse]``.
##  5. Assert ``pair.first`` (Email/query) ids include both seeded
##     ids; assert ``pair.second`` (SearchSnippet/get) list contains
##     a snippet for each seeded id, and every snippet's
##     ``emailId`` appears in ``pair.first.ids``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/sets

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailQueryWithSnippetsLive:
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

    # --- Resolve inbox + seed corpus ------------------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let ids = seedEmailsWithSubjects(
        client,
        mailAccountId,
        inbox,
        @[
          "phase-c-17 stepseventeen alphaSeventeen",
          "phase-c-17 stepseventeen bravoSeventeen",
        ],
      )
      .expect("seedEmailsWithSubjects[" & $target.kind & "]")
    assertOn target, ids.len == 2, "seedEmailsWithSubjects must return two ids"
    let id1 = ids[0]
    let id2 = ids[1]
    let corpus = ids.toHashSet

    # --- Wait for the index to settle so both seeds are observable.
    # Cyrus 3.12.2's Xapian rolling indexer lags Email/set by ~300 ms;
    # Stalwart and James index synchronously and return on the first
    # poll iteration.
    let preFilter =
      filterCondition(EmailFilterCondition(subject: Opt.some("stepseventeen")))
    discard pollEmailQueryIndexed(target, mailAccountId, preFilter, corpus).expect(
        "pollEmailQueryIndexed[" & $target.kind & "]"
      )

    # --- Email/query → SearchSnippet/get chained via ChainedHandles -----
    let filter =
      filterCondition(EmailFilterCondition(subject: Opt.some("stepseventeen")))
    let (b, chainHandles) = addEmailQueryWithSnippets(
      initRequestBuilder(makeBuilderId()), mailAccountId, filter = filter
    )
    let resp = client.send(b.freeze()).expect(
        "send Email/query+SearchSnippet/get[" & $target.kind & "]"
      )
    captureIfRequested(client, "email-query-with-snippets-" & $target.kind).expect(
      "captureIfRequested"
    )
    let pair = resp.getBoth(chainHandles).expect("getBoth[" & $target.kind & "]")

    let queryHits = pair.first.ids.toHashSet
    assertOn target, id1 in queryHits, "Email/query result must include first seeded id"
    assertOn target,
      id2 in queryHits, "Email/query result must include second seeded id"

    let queryHitSet = queryHits
    var snippetIds = initHashSet[Id]()
    for snippet in pair.second.list:
      assertOn target,
        snippet.emailId in queryHitSet,
        "every snippet's emailId must appear in the chained Email/query result; got " &
          string(snippet.emailId)
      if snippet.emailId in corpus:
        snippetIds.incl(snippet.emailId)
    assertOn target,
      id1 in snippetIds, "snippet list must include the first seeded emailId"
    assertOn target,
      id2 in snippetIds, "snippet list must include the second seeded emailId"
    client.close()
