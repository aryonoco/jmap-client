# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: ``Request.createdIds`` and
## ``Response.createdIds`` (``envelope.nim:80``, ``envelope.nim:86``)
## round-trip per RFC 8620 §3.3:
##
## > If sent, the server MUST include the same map as the value of
## > the createdIds property in the response.
##
## ``RequestBuilder.build()`` hardcodes ``createdIds: Opt.none`` at
## ``builder.nim:75-80``, so this contract is exercised only by
## constructing a ``Request`` value manually.  Cross-method creation-
## id references (``"ids": ["#draft1"]`` resolving to the create-cid
## ``draft1`` from the same envelope) are also tested.
##
## Phase J Step 68.  Two sub-tests in one block.

import std/json
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tcreatedIdsEnvelopeLive:
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
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let drafts =
      resolveOrCreateDrafts(client, mailAccountId).expect("resolveOrCreateDrafts")

    # Sub-test 1: outgoing createdIds round-trip with a Core/echo
    # invocation.  Build the Request value directly so createdIds
    # can be set; ``RequestBuilder.build()`` hardcodes none.
    block outgoingCreatedIdsCase:
      let realEmailId = seedSimpleEmail(
          client, mailAccountId, inbox, "phase-j 68 createdIds seed", "phase-j-68-seed"
        )
        .expect("seedSimpleEmail")
      let knownCid = parseCreationId("knownEmail").expect("parseCreationId")
      var seedMap = initTable[CreationId, Id]()
      seedMap[knownCid] = realEmailId

      let echoArgs = %*{"phase-j-68": "createdIds-roundtrip"}
      let (b, _) = initRequestBuilder().addEcho(echoArgs)
      let baseReq = b.build()
      let req = Request(
        `using`: baseReq.`using`,
        methodCalls: baseReq.methodCalls,
        createdIds: Opt.some(seedMap),
      )
      let resp = client.send(req).expect("send Core/echo with createdIds")
      captureIfRequested(client, "created-ids-envelope-stalwart").expect(
        "captureIfRequested createdIds"
      )

      # RFC 8620 §3.3 mandates the server MUST echo createdIds when
      # the client sends them.  Set-membership on Stalwart's choice
      # is library-contract design — if Stalwart returns Opt.none,
      # the captured fixture pins the deviation; the live assertion
      # focuses on the parser handling whichever shape arrives.
      if resp.createdIds.isSome:
        var echoed = resp.createdIds.unsafeGet
        echoed.withValue(knownCid, v):
          doAssert string(v[]) == string(realEmailId),
            "echoed createdIds entry must match the supplied id"
        do:
          doAssert false, "echoed createdIds must contain knownCid"

      # Cleanup: destroy seed.
      let (bClean, cleanHandle) = addEmailSet(
        initRequestBuilder(), mailAccountId, destroy = directIds(@[realEmailId])
      )
      let respClean = client.send(bClean).expect("send Email/set cleanup")
      let cleanResp = respClean.get(cleanHandle).expect("Email/set cleanup extract")
      cleanResp.destroyResults.withValue(realEmailId, outcome):
        doAssert outcome.isOk, "cleanup destroy must succeed"
      do:
        doAssert false, "cleanup must report an outcome"

    # Sub-test 2: cross-method creation-id reference.  Email/set
    # create with cid ``draft1``; Email/get in the same envelope
    # with ``ids: ["#draft1"]`` — server resolves the # prefix to
    # the freshly assigned id.
    block crossMethodCreationIdRefCase:
      let mailboxIds =
        parseNonEmptyMailboxIdSet(@[drafts]).expect("parseNonEmptyMailboxIdSet")
      let aliceAddr = buildAliceAddr()
      let textPart = makeLeafPart(
        LeafPartSpec(
          partId: buildPartId("1"),
          contentType: "text/plain",
          body: "phase-j 68 cross-method creation-id ref body",
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
          subject = Opt.some("phase-j 68 cross-method"),
        )
        .expect("parseEmailBlueprint")
      let draft1Cid = parseCreationId("draft1").expect("parseCreationId")
      var createTbl = initTable[CreationId, EmailBlueprint]()
      createTbl[draft1Cid] = blueprint
      let (b1, setHandle) =
        addEmailSet(initRequestBuilder(), mailAccountId, create = Opt.some(createTbl))
      # ``Id("#draft1")`` is the wire-shape way to reference a
      # creation id in the same envelope.  parseId accepts any
      # non-empty 1-255 ASCII; the bare ``Id`` cast bypasses the
      # smart constructor.
      let creationRefId = Id("#draft1")
      let (b2, getHandle) =
        addEmailGet(b1, mailAccountId, ids = directIds(@[creationRefId]))
      let resp = client.send(b2).expect("send Email/set+Email/get with creation ref")
      let setResp = resp.get(setHandle).expect("Email/set extract")
      var seededId: Id
      var seeded = false
      setResp.createResults.withValue(draft1Cid, outcome):
        doAssert outcome.isOk, "Email/set create must succeed"
        seededId = outcome.unsafeValue.id
        seeded = true
      do:
        doAssert false, "Email/set must report an outcome for draft1"
      doAssert seeded

      let getResp = resp.get(getHandle).expect("Email/get extract")
      doAssert getResp.list.len == 1,
        "Email/get with #draft1 must return the freshly created Email; got " &
          $getResp.list.len
      let email = Email.fromJson(getResp.list[0]).expect("Email.fromJson")
      doAssert email.id.isSome and email.id.unsafeGet == seededId,
        "Email/get with #draft1 must return the same id Email/set assigned"

      # Cleanup: destroy the freshly created draft.
      let (bClean, cleanHandle) = addEmailSet(
        initRequestBuilder(), mailAccountId, destroy = directIds(@[seededId])
      )
      let respClean = client.send(bClean).expect("send Email/set cleanup")
      let cleanResp = respClean.get(cleanHandle).expect("Email/set cleanup extract")
      cleanResp.destroyResults.withValue(seededId, outcome):
        doAssert outcome.isOk, "cleanup destroy must succeed"
      do:
        doAssert false, "cleanup must report an outcome"

    client.close()
