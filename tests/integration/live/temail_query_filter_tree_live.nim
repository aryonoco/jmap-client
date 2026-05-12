# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Email/query (RFC 8621 §4.4) with a
## recursive ``Filter[C]`` operator tree (FilterOperator AND/OR/NOT)
## against Stalwart. Builds on Step 13 — that test proved the
## ``fkCondition`` leaf shape; this test proves the ``fkOperator``
## arm and exercises all three operators in a single block.
##
## Sequence:
##  1. Resolve inbox via mlive.
##  2. Seed five emails sharing a phase-c-14 subject prefix and one
##     whitespace-separated discriminator token apiece
##     (``alpha uno`` / ``alpha dos`` / ``bravo uno`` / ``bravo dos``
##     / ``charlie uno``). Discriminators are split by whitespace
##     because both Stalwart's and James's Lucene-based subject
##     tokenisers split on whitespace — but James 3.9 keeps
##     hyphenated words (``alpha-uno``) as single tokens, which would
##     break the AND test below.
##  3. AND test — alpha AND uno: expects ``alpha uno`` only.
##  4. OR test — alpha OR bravo: expects four emails.
##  5. NOT test — phase-c-14 AND NOT alpha: expects three emails
##     (bravo uno, bravo dos, charlie uno). The wrapper-AND scopes the
##     negation to phase-c-14-prefixed emails, avoiding negation
##     against the inbox-wide corpus.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/sets

import results
import jmap_client
import jmap_client/client
import ./mconfig
import ./mlive

block temailQueryFilterTreeLive:
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
          "phase-c-14 alpha uno", "phase-c-14 alpha dos", "phase-c-14 bravo uno",
          "phase-c-14 bravo dos", "phase-c-14 charlie uno",
        ],
      )
      .expect("seedEmailsWithSubjects[" & $target.kind & "]")
    assertOn target, ids.len == 5, "seedEmailsWithSubjects must return five ids"
    let corpus = ids.toHashSet

    # --- AND test: alpha AND uno ----------------------------------------
    let andFilter = filterOperator(
      foAnd,
      @[
        filterCondition(EmailFilterCondition(subject: Opt.some("alpha"))),
        filterCondition(EmailFilterCondition(subject: Opt.some("uno"))),
      ],
    )
    let (ba, andHandle) = addEmailQuery(
      initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(andFilter)
    )
    let respA =
      client.send(ba.freeze()).expect("send Email/query AND[" & $target.kind & "]")
    let andResp =
      respA.get(andHandle).expect("Email/query AND extract[" & $target.kind & "]")
    let andHits = andResp.ids.toHashSet * corpus
    assertOn target,
      andHits.len == 1,
      "AND(alpha, uno) must return exactly one phase-c-14 id (got " & $andHits.len & ")"
    assertOn target,
      ids[0] in andHits,
      "AND(alpha, uno) must return the alpha-uno id; got ids=" & $andHits

    # --- OR test: alpha OR bravo ----------------------------------------
    let orFilter = filterOperator(
      foOr,
      @[
        filterCondition(EmailFilterCondition(subject: Opt.some("alpha"))),
        filterCondition(EmailFilterCondition(subject: Opt.some("bravo"))),
      ],
    )
    let (bo, orHandle) = addEmailQuery(
      initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(orFilter)
    )
    let respO =
      client.send(bo.freeze()).expect("send Email/query OR[" & $target.kind & "]")
    let orResp =
      respO.get(orHandle).expect("Email/query OR extract[" & $target.kind & "]")
    let orHits = orResp.ids.toHashSet * corpus
    assertOn target,
      orHits.len == 4,
      "OR(alpha, bravo) must return four phase-c-14 ids (got " & $orHits.len & ")"
    for i in 0 ..< 4:
      assertOn target,
        ids[i] in orHits,
        "OR(alpha, bravo) must return alpha-1/alpha-2/bravo-1/bravo-2; missing index " &
          $i

    # --- NOT test: phase-c-14 AND NOT alpha -----------------------------
    let notFilter = filterOperator(
      foAnd,
      @[
        filterCondition(EmailFilterCondition(subject: Opt.some("phase-c-14"))),
        filterOperator(
          foNot, @[filterCondition(EmailFilterCondition(subject: Opt.some("alpha")))]
        ),
      ],
    )
    let (bn, notHandle) = addEmailQuery(
      initRequestBuilder(makeBuilderId()), mailAccountId, filter = Opt.some(notFilter)
    )
    let respN =
      client.send(bn.freeze()).expect("send Email/query NOT[" & $target.kind & "]")
    let notResp =
      respN.get(notHandle).expect("Email/query NOT extract[" & $target.kind & "]")
    let notHits = notResp.ids.toHashSet * corpus
    assertOn target,
      notHits.len == 3,
      "AND(phase-c-14, NOT alpha) must return three phase-c-14 ids (got " & $notHits.len &
        ")"
    for i in 2 ..< 5:
      assertOn target,
        ids[i] in notHits,
        "AND(phase-c-14, NOT alpha) must return bravo-1/bravo-2/charlie-1; missing index " &
          $i
    client.close()
