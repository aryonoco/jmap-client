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
##  4. Assert the returned ids contain exactly the seeded match.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

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
    var mailAccountId: AccountId
    session.primaryAccounts.withValue("urn:ietf:params:jmap:mail", v):
      mailAccountId = v
    do:
      doAssert false, "session must advertise a primary mail account"

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

    # --- Email/query with single-condition filter ------------------------
    let filter = filterCondition(EmailFilterCondition(subject: Opt.some("aardvark")))
    let (b, queryHandle) =
      addEmailQuery(initRequestBuilder(), mailAccountId, filter = Opt.some(filter))
    let resp = client.send(b).expect("send Email/query")
    let queryResp = resp.get(queryHandle).expect("Email/query extract")
    doAssert queryResp.ids.len == 1,
      "Email/query with subject==\"aardvark\" must return exactly one id (got " &
        $queryResp.ids.len & ")"
    doAssert queryResp.ids[0] == matchId,
      "Email/query must return the seeded aardvark id; got " & string(queryResp.ids[0]) &
        " expected " & string(matchId)
    client.close()
