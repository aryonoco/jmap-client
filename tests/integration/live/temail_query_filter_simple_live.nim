# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Email/query (RFC 8621 §4.4) with a single
## EmailFilterCondition leaf against Stalwart. First Phase C step —
## establishes wire compatibility for the Filter[C] framework's
## ``fkCondition`` arm before later steps exercise the operator-tree
## arm and the sort framework.
##
## Sequence:
##  1. Resolve inbox via mlive.
##  2. Seed three emails with distinct subjects via
##     ``seedEmailsWithSubjects`` — only one carries the discriminator
##     token ``"aardvark"``; the others use ``"bravo"`` / ``"charlie"``.
##     Filter on the discriminator alone — Stalwart's subject filter
##     tokenises the input, so a multi-word filter with the shared
##     ``"phase-c-13"`` prefix would match every seed (catalogued
##     divergence #1: *Subject vs text filter coverage*).
##  3. ``Email/query`` with ``filter = filterCondition(EmailFilterCondition(
##     subject: Opt.some("aardvark")))``.
##  4. Assert the seeded match is in the result and the seeded
##     non-matches are absent. Delta-based: the live suite shares a
##     Stalwart instance, so absolute counts are not assertable
##     (mirrors ``temail_query_changes_live``'s baselineCount idiom).
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

block temailQueryFilterSimpleLive:
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
        @["phase-c-13 aardvark", "phase-c-13 bravo", "phase-c-13 charlie"],
      )
      .expect("seedEmailsWithSubjects")
    doAssert ids.len == 3, "seedEmailsWithSubjects must return three ids"
    let matchId = ids[0]
    let bravoId = ids[1]
    let charlieId = ids[2]

    # --- Email/query with single-condition filter ------------------------
    let filter = filterCondition(EmailFilterCondition(subject: Opt.some("aardvark")))
    let (b, queryHandle) =
      addEmailQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(filter))
    let resp = client.send(b).expect("send Email/query")
    let queryResp = resp.get(queryHandle).expect("Email/query extract")
    let hits = queryResp.ids.toHashSet
    doAssert matchId in hits,
      "Email/query subject==\"aardvark\" must include the seeded aardvark id"
    doAssert bravoId notin hits,
      "Email/query subject==\"aardvark\" must NOT include the seeded bravo id"
    doAssert charlieId notin hits,
      "Email/query subject==\"aardvark\" must NOT include the seeded charlie id"
    client.close()
