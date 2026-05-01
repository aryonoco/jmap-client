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
##  1. Mailbox/get — resolve Alice's inbox id (needed for the seed's
##     ``mailboxIds`` invariant: every Email belongs to ≥1 Mailbox).
##  2. Email/set create — seed one Email; uses ``EmailBlueprint`` smart
##     constructor + ``BlueprintBodyPart`` direct construction (Pattern A
##     unsealed at the leaf).
##  3. Email/query → Email/get — the chain. The query returns all
##     emails for Alice (no filter); the get fetches them by reference
##     to the query's ``ids`` (JSON Pointer ``/ids``).

import std/json
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mconfig

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

    # --- Step 1: resolve inbox id ----------------------------------------
    let (b1, mbHandle) = addGet[Mailbox](initRequestBuilder(), mailAccountId)
    let resp1 = client.send(b1).expect("send Mailbox/get")
    let mbResp = resp1.get(mbHandle).expect("Mailbox/get extract")
    var inboxId = Opt.none(Id)
    for node in mbResp.list:
      let mb = Mailbox.fromJson(node).expect("parse Mailbox")
      for role in mb.role:
        if role == roleInbox:
          inboxId = Opt.some(mb.id)
    doAssert inboxId.isSome, "alice's account must have an Inbox role mailbox"
    let inbox = inboxId.get()

    # --- Step 2: seed one email via Email/set create ---------------------
    let mailboxIds = parseNonEmptyMailboxIdSet(@[inbox]).expect("mailboxIds")
    let aliceAddr = parseEmailAddress("alice@example.com", Opt.some("Alice")).expect(
      "parseEmailAddress"
    )
    let textPart = BlueprintBodyPart(
      isMultipart: false,
      leaf: BlueprintLeafPart(
        source: bpsInline,
        partId: parsePartIdFromServer("1").expect("partId"),
        value: BlueprintBodyValue(value: "Hello from phase 1 step 6."),
      ),
      contentType: "text/plain",
      extraHeaders:
        initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
      name: Opt.none(string),
      disposition: Opt.none(ContentDisposition),
      cid: Opt.none(string),
      language: Opt.none(seq[string]),
      location: Opt.none(string),
    )
    let blueprint = parseEmailBlueprint(
      mailboxIds = mailboxIds,
      body = flatBody(textBody = Opt.some(textPart)),
      fromAddr = Opt.some(@[aliceAddr]),
      to = Opt.some(@[aliceAddr]),
      subject = Opt.some("phase-1 step-6 seed"),
    )
    .expect("parseEmailBlueprint")
    let cid = parseCreationId("seedMail").expect("parseCreationId")
    var createTbl = initTable[CreationId, EmailBlueprint]()
    createTbl[cid] = blueprint
    let (b2, setHandle) = addEmailSet(
      initRequestBuilder(), mailAccountId, create = Opt.some(createTbl)
    )
    let resp2 = client.send(b2).expect("send Email/set")
    let setResp = resp2.get(setHandle).expect("Email/set extract")
    doAssert setResp.createResults.len == 1,
      "set must report exactly one create result"
    doAssert setResp.createResults[cid].isOk,
      "Email/set must succeed for the seeded message"

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
    doAssert queryResp.ids.len >= 1,
      "Email/query must return the seeded message"
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
