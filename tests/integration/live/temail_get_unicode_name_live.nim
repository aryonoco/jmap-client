# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for UTF-8 display name round-trip in the
## From header against Stalwart. Phase D Step 23 — verifies that a
## ``parseEmailAddress`` smart constructor produces an
## ``EmailAddress`` whose ``name`` survives Stalwart's MIME pipeline
## byte-for-byte on the read path.
##
## Per ``addresses.nim:24-32`` the parser is byte-passthrough: the
## display name is *not* RFC 2047-decoded inside this client; that
## responsibility sits with the server.  Stalwart 0.15.5 emits the
## decoded UTF-8 octets directly in the JSON wire.  The test pins
## that contract — if Stalwart ever stopped decoding, or this client
## started decoding, the assertion would surface the divergence.
##
## Asserts:
##   1. ``Email/get`` returns the seeded message.
##   2. The ``from`` array carries one entry with the injected
##      UTF-8 display name (``"héllo wörld"``) byte-for-byte.
##
## No capture site — the assertion is on octet-level equality, which
## the structural fixtures in Steps 19–22 / 24 already cover for
## addresses generally.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mconfig
import ./mlive

block temailGetUnicodeNameLive:
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

    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    const unicodeName = "héllo wörld"
    let aliceAddr = parseEmailAddress("alice@example.com", Opt.some(unicodeName)).expect(
        "parseEmailAddress utf-8 name"
      )
    let mailboxIds =
      parseNonEmptyMailboxIdSet(@[inbox]).expect("parseNonEmptyMailboxIdSet")
    let textPart = makeLeafPart(
      LeafPartSpec(
        partId: buildPartId("1"),
        contentType: "text/plain",
        body: "phase-d step-23 unicode display name.",
        name: Opt.none(string),
        disposition: Opt.none(ContentDisposition),
        cid: Opt.none(string),
      )
    )
    let blueprint = parseEmailBlueprint(
      mailboxIds = mailboxIds,
      body = flatBody(textBody = Opt.some(textPart)),
      fromAddr = Opt.some(@[aliceAddr]),
      to = Opt.some(@[aliceAddr]),
      subject = Opt.some("phase-d step-23 unicode name"),
    )
    doAssert blueprint.isOk, "parseEmailBlueprint must succeed"
    let cid = parseCreationId("seedUnicode").expect("parseCreationId")
    var createTbl = initTable[CreationId, EmailBlueprint]()
    createTbl[cid] = blueprint.unsafeValue
    let (bSeed, seedHandle) =
      addEmailSet(initRequestBuilder(), mailAccountId, create = Opt.some(createTbl))
    let seedResp = client.send(bSeed).expect("send Email/set seed")
    let seedSet = seedResp.get(seedHandle).expect("Email/set seed extract")
    var seededId: Id
    var found = false
    seedSet.createResults.withValue(cid, outcome):
      doAssert outcome.isOk,
        "Email/set must succeed: " &
          (if outcome.isErr: outcome.unsafeError.rawType else: "(ok)")
      seededId = outcome.unsafeValue.id
      found = true
    do:
      doAssert false, "Email/set returned no result for creationId"
    doAssert found

    let (b, getHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "from"]),
    )
    let resp = client.send(b).expect("send Email/get unicode name")
    let getResp = resp.get(getHandle).expect("Email/get unicode name extract")
    doAssert getResp.list.len == 1, "Email/get must return the seeded message"

    let email = Email.fromJson(getResp.list[0]).expect("Email.fromJson")
    doAssert email.fromAddr.isSome and email.fromAddr.unsafeGet.len == 1,
      "from must be a one-element list"
    let fromAddr = email.fromAddr.unsafeGet[0]
    doAssert fromAddr.email == "alice@example.com",
      "from[0].email must be alice@example.com (got " & fromAddr.email & ")"
    doAssert fromAddr.name.isSome,
      "from[0].name must be present — Stalwart preserves display names"
    doAssert fromAddr.name.unsafeGet == unicodeName,
      "from[0].name must round-trip the UTF-8 octets verbatim (got " &
        fromAddr.name.unsafeGet & ")"
    client.close()
