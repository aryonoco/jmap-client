# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Email/query → Email/get chained via the
## RFC 8620 §3.7 result reference (``#ids`` JSON Pointer). Stalwart is
## empty after a fresh ``stalwart-up``, so the test seeds one Email via
## ``Email/set create`` (Path C of the plan: use the library to test
## the library; no SMTP path needed) before exercising the chain.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.
##
## Three sequential requests:
##  1. ``resolveInboxId`` (mlive) — Mailbox/get for Alice's inbox.
##  2. ``seedSimpleEmail`` (mlive) — Email/set create for one text/plain
##     message. Pattern A (BlueprintBodyPart) is exercised inside the
##     helper.
##  3. Email/query → Email/get — the chain under test. The query returns
##     all emails for Alice (no filter); the get fetches them by
##     reference to the query's ``ids`` (JSON Pointer ``/ids``).

import std/json
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mconfig
import ./mlive

block temailQueryGetChainLive:
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

    # --- Step 1: resolve inbox id (mlive helper) -------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")

    # --- Step 2: seed one email (mlive helper) ---------------------------
    discard seedSimpleEmail(
        client, mailAccountId, inbox, "phase-1 step-6 seed", "seedMail"
      )
      .expect("seedSimpleEmail")

    # --- Step 3: Email/query → Email/get via #ids back-reference ---------
    let (b3a, queryHandle) = addEmailQuery(initRequestBuilder(), mailAccountId)
    let (b3b, getHandle) = addEmailGet(
      b3a,
      mailAccountId,
      ids = Opt.some(queryHandle.idsRef()),
      properties = Opt.some(@["id", "subject", "from", "receivedAt"]),
    )
    let resp3 = client.send(b3b).expect("send Email/query+get")
    let queryResp = resp3.get(queryHandle).expect("Email/query extract")
    doAssert queryResp.ids.len >= 1, "Email/query must return the seeded message"
    let getResp = resp3.get(getHandle).expect("Email/get extract")
    doAssert getResp.list.len == queryResp.ids.len,
      "Email/get list count must match Email/query ids count"
    var sawSeed = false
    for node in getResp.list:
      doAssert not node{"id"}.isNil, "every Email/get entry must have an id"
      doAssert not node{"subject"}.isNil, "every Email/get entry must have a subject"
      if node{"subject"}.getStr("") == "phase-1 step-6 seed":
        sawSeed = true
    doAssert sawSeed, "Email/get list must include the seeded subject"
    client.close()
