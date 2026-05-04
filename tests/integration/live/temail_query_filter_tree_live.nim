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
##  2. Seed five emails sharing a phase-c-14 subject prefix and a
##     single discriminator token apiece (``alpha-1`` / ``alpha-2`` /
##     ``bravo-1`` / ``bravo-2`` / ``charlie-1``). Discriminator words
##     are unique single tokens, sidestepping the divergence #1
##     tokenised-subject behaviour observed at Step 13.
##  3. AND test — alpha AND 1: expects ``alpha-1`` only.
##  4. OR test — alpha OR bravo: expects four emails.
##  5. NOT test — phase-c-14 AND NOT alpha: expects three emails
##     (bravo-1, bravo-2, charlie-1). The wrapper-AND scopes the
##     negation to phase-c-14-prefixed emails, avoiding negation
##     against the inbox-wide corpus.
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

block temailQueryFilterTreeLive:
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
          "phase-c-14 alpha-1", "phase-c-14 alpha-2", "phase-c-14 bravo-1",
          "phase-c-14 bravo-2", "phase-c-14 charlie-1",
        ],
      )
      .expect("seedEmailsWithSubjects")
    doAssert ids.len == 5, "seedEmailsWithSubjects must return five ids"
    let corpus = ids.toHashSet

    # --- AND test: alpha AND 1 ------------------------------------------
    let andFilter = filterOperator(
      foAnd,
      @[
        filterCondition(EmailFilterCondition(subject: Opt.some("alpha"))),
        filterCondition(EmailFilterCondition(subject: Opt.some("1"))),
      ],
    )
    let (ba, andHandle) =
      addEmailQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(andFilter))
    let respA = client.send(ba).expect("send Email/query AND")
    let andResp = respA.get(andHandle).expect("Email/query AND extract")
    let andHits = andResp.ids.toHashSet * corpus
    doAssert andHits.len == 1,
      "AND(alpha, 1) must return exactly one phase-c-14 id (got " & $andHits.len & ")"
    doAssert ids[0] in andHits,
      "AND(alpha, 1) must return the alpha-1 id; got ids=" & $andHits

    # --- OR test: alpha OR bravo ----------------------------------------
    let orFilter = filterOperator(
      foOr,
      @[
        filterCondition(EmailFilterCondition(subject: Opt.some("alpha"))),
        filterCondition(EmailFilterCondition(subject: Opt.some("bravo"))),
      ],
    )
    let (bo, orHandle) =
      addEmailQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(orFilter))
    let respO = client.send(bo).expect("send Email/query OR")
    let orResp = respO.get(orHandle).expect("Email/query OR extract")
    let orHits = orResp.ids.toHashSet * corpus
    doAssert orHits.len == 4,
      "OR(alpha, bravo) must return four phase-c-14 ids (got " & $orHits.len & ")"
    for i in 0 ..< 4:
      doAssert ids[i] in orHits,
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
    let (bn, notHandle) =
      addEmailQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(notFilter))
    let respN = client.send(bn).expect("send Email/query NOT")
    let notResp = respN.get(notHandle).expect("Email/query NOT extract")
    let notHits = notResp.ids.toHashSet * corpus
    doAssert notHits.len == 3,
      "AND(phase-c-14, NOT alpha) must return three phase-c-14 ids (got " & $notHits.len &
        ")"
    for i in 2 ..< 5:
      doAssert ids[i] in notHits,
        "AND(phase-c-14, NOT alpha) must return bravo-1/bravo-2/charlie-1; missing index " &
          $i
    client.close()
