# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for SearchSnippet/get (RFC 8621 §5.1) in
## standalone form (literal email ids) against Stalwart. First
## Phase C step exercising ``addSearchSnippetGet`` and the
## ``SearchSnippet.fromJson`` parser end-to-end. Splits cleanly
## from Step 17's chain test so a failure pinpoints either the
## standalone-builder/parser layer or the chain plumbing — never
## both at once.
##
## Sequence:
##  1. Resolve inbox via mlive.
##  2. Seed two emails via ``seedEmailsWithSubjects`` carrying a
##     unique discriminator ``"stepsixteen"`` plus distinct token
##     suffixes (``aardvarkSixteen`` / ``bravoSixteen``). Capture
##     both ids as ``id1``, ``id2``.
##  3. Build ``addSearchSnippetGet(b, mailAccountId, filter =
##     filterCondition(EmailFilterCondition(subject:
##     Opt.some("stepsixteen"))), firstEmailId = id1,
##     restEmailIds = @[id2])``.
##  4. Send. Assert Stalwart returns snippets for both seeded ids
##     and that each snippet has at least one of subject/preview
##     populated. The ``<mark>`` highlight format is intentionally
##     not asserted (catalogued divergence #3).
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/sets
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mconfig
import ./mlive

block tsearchSnippetGetStandaloneLive:
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
    let mailAccountId = resolveMailAccountId(session).expect("resolveMailAccountId")

    # --- Resolve inbox + seed corpus ------------------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let ids = seedEmailsWithSubjects(
        client,
        mailAccountId,
        inbox,
        @[
          "phase-c-16 stepsixteen aardvarkSixteen",
          "phase-c-16 stepsixteen bravoSixteen",
        ],
      )
      .expect("seedEmailsWithSubjects")
    doAssert ids.len == 2, "seedEmailsWithSubjects must return two ids"
    let id1 = ids[0]
    let id2 = ids[1]
    let corpus = ids.toHashSet

    # --- SearchSnippet/get with literal email ids -----------------------
    let filter = filterCondition(EmailFilterCondition(subject: Opt.some("stepsixteen")))
    let (b, snippetHandle) = addSearchSnippetGet(
      initRequestBuilder(),
      mailAccountId,
      filter = filter,
      firstEmailId = id1,
      restEmailIds = @[id2],
    )
    let resp = client.send(b).expect("send SearchSnippet/get")
    let snippetResp = resp.get(snippetHandle).expect("SearchSnippet/get extract")
    doAssert snippetResp.list.len == 2,
      "SearchSnippet/get must return one snippet per requested id (got " &
        $snippetResp.list.len & ")"
    var seenIds = initHashSet[Id]()
    for snippet in snippetResp.list:
      doAssert snippet.emailId in corpus,
        "every snippet's emailId must be one of the seeded ids; got " &
          string(snippet.emailId)
      seenIds.incl(snippet.emailId)
      let subjectPresent = snippet.subject.isSome and snippet.subject.get().len > 0
      let previewPresent = snippet.preview.isSome and snippet.preview.get().len > 0
      doAssert subjectPresent or previewPresent,
        "every snippet must populate at least one of subject/preview; got emailId=" &
          string(snippet.emailId)
    doAssert id1 in seenIds, "snippet list must include the first seeded emailId"
    doAssert id2 in seenIds, "snippet list must include the second seeded emailId"
    client.close()
