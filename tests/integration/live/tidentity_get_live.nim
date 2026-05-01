# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
#
## Live integration test for Identity/set + Identity/get (RFC 8621 §6)
## against Stalwart. Stalwart does not auto-provision an identity at
## principal-creation time, so the test creates one via Identity/set
## before reading it back via Identity/get in the same request.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.
##
## Re-runs against the same Stalwart instance simply pile up additional
## identities (Stalwart permits multiple identities per address); the
## Identity/get assertion is ``>= 1`` and stays true. Use
## ``just stalwart-reset`` for a clean slate.
##
## If Steps 3 and 4 pass and this one fails, the bug is in the
## submission-URI wiring, the ``IdentityCreate`` toJson serialiser, or
## the ``Identity`` parser — clean isolation by design.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mconfig

block tidentityGetLive:
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
    var submissionAccountId: AccountId
    session.primaryAccounts.withValue("urn:ietf:params:jmap:submission", v):
      submissionAccountId = v
    do:
      doAssert false, "session must advertise a primary submission account"

    let create = parseIdentityCreate(email = "alice@example.com", name = "Alice").expect(
        "parseIdentityCreate"
      )
    let cid = parseCreationId("seedAlice").expect("parseCreationId")
    var createTbl = initTable[CreationId, IdentityCreate]()
    createTbl[cid] = create
    let (b1, setHandle) = addIdentitySet(
      initRequestBuilder(), submissionAccountId, create = Opt.some(createTbl)
    )
    let (b2, getHandle) = addIdentityGet(b1, submissionAccountId)
    let resp = client.send(b2).expect("send")

    let setResp = resp.get(setHandle).expect("Identity/set extract")
    doAssert setResp.createResults.len == 1, "set must report one create result"
    let createResult = setResp.createResults[cid]
    doAssert createResult.isOk, "Identity/set must succeed for seeded address"

    let gr = resp.get(getHandle).expect("Identity/get extract")
    doAssert gr.list.len >= 1, "alice must own at least one identity after set"
    var sawAliceEmail = false
    for node in gr.list:
      let ident = Identity.fromJson(node).expect("parse Identity")
      doAssert ident.email.len > 0, "every identity must have a non-empty email"
      doAssert ident.id.len > 0, "every identity must carry a server-assigned id"
      if ident.email == "alice@example.com":
        sawAliceEmail = true
    doAssert sawAliceEmail, "alice's seeded address must appear among her identities"
    client.close()
