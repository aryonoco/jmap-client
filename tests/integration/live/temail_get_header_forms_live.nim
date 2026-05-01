# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Email/get with typed header-form
## properties (RFC 8621 §4.1.2 / §4.2) against Stalwart. Phase D
## Step 22 — exercises three of the seven ``HeaderForm`` variants:
## ``hfUrls`` (List-Post), ``hfDate`` (Date), and ``hfAddresses``
## (From).
##
## ``List-Post`` is injected as a top-level ``extraHeaders`` entry on
## the seeded email; its allowed forms are ``{hfUrls, hfRaw}`` per
## ``allowedHeaderFormsTable``.  ``Date`` is set via ``sentAt`` rather
## than ``extraHeaders`` because the latter would collide with
## Stalwart's auto-generated Date header.  ``From`` flows through the
## existing ``fromAddr`` parameter — every seeded email has it.
##
## Asserts:
##   1. The response carries the three dynamic header keys
##      ``"header:List-Post:asURLs"``, ``"header:Date:asDate"``,
##      ``"header:From:asAddresses"``.
##   2. Each parses through ``parseHeaderValue(<form>, node)`` to a
##      ``HeaderValue`` whose ``form`` discriminator matches the
##      requested form (``hfUrls``, ``hfDate``, ``hfAddresses``).
##   3. The variant payload is populated:
##        - ``urls.isSome and urls.unsafeGet.len == 1``
##        - ``date.isSome``
##        - ``addresses.len == 1`` (alice's seeded From address)
##
## Captures: ``email-header-forms-stalwart`` after the ``Email/get``
## so the typed-header wire shape is recorded.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``.

import std/json
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailGetHeaderFormsLive:
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
    let mailboxIds =
      parseNonEmptyMailboxIdSet(@[inbox]).expect("parseNonEmptyMailboxIdSet")
    let aliceAddr = buildAliceAddr()
    let textPart = makeLeafPart(
      LeafPartSpec(
        partId: buildPartId("1"),
        contentType: "text/plain",
        body: "phase-d step-22 typed header forms.",
        name: Opt.none(string),
        disposition: Opt.none(ContentDisposition),
        cid: Opt.none(string),
      )
    )
    let listPostName =
      parseBlueprintEmailHeaderName("List-Post").expect("List-Post header name")
    var extraHeaders = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
    extraHeaders[listPostName] = urlsSingle(@["mailto:list@example.com"])
    let sentAt = parseDate("2026-05-01T12:00:00Z").expect("parseDate")
    let blueprint = parseEmailBlueprint(
      mailboxIds = mailboxIds,
      body = flatBody(textBody = Opt.some(textPart)),
      fromAddr = Opt.some(@[aliceAddr]),
      to = Opt.some(@[aliceAddr]),
      subject = Opt.some("phase-d step-22 header forms"),
      sentAt = Opt.some(sentAt),
      extraHeaders = extraHeaders,
    )
    doAssert blueprint.isOk, "parseEmailBlueprint must succeed"
    let blueprintOk = blueprint.unsafeValue
    let cid = parseCreationId("seedHeaders").expect("parseCreationId")
    var createTbl = initTable[CreationId, EmailBlueprint]()
    createTbl[cid] = blueprintOk
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
      properties = Opt.some(
        @[
          "id", "header:List-Post:asURLs", "header:Date:asDate",
          "header:From:asAddresses",
        ]
      ),
    )
    let resp = client.send(b).expect("send Email/get header forms")
    captureIfRequested(client, "email-header-forms-stalwart").expect(
      "captureIfRequested"
    )
    let getResp = resp.get(getHandle).expect("Email/get header forms extract")
    doAssert getResp.list.len == 1, "Email/get must return the seeded message"

    let entity = getResp.list[0]

    let listPostNode = entity{"header:List-Post:asURLs"}
    doAssert not listPostNode.isNil, "header:List-Post:asURLs must be present"
    let listPostHV =
      parseHeaderValue(hfUrls, listPostNode).expect("parseHeaderValue List-Post")
    doAssert listPostHV.form == hfUrls, "List-Post HeaderValue must carry hfUrls form"
    doAssert listPostHV.urls.isSome,
      "List-Post hfUrls payload must parse — server returned non-null"
    doAssert listPostHV.urls.unsafeGet.len == 1,
      "expected one URL in List-Post (got " & $listPostHV.urls.unsafeGet.len & ")"

    let dateNode = entity{"header:Date:asDate"}
    doAssert not dateNode.isNil, "header:Date:asDate must be present"
    let dateHV = parseHeaderValue(hfDate, dateNode).expect("parseHeaderValue Date")
    doAssert dateHV.form == hfDate, "Date HeaderValue must carry hfDate form"
    doAssert dateHV.date.isSome,
      "Date hfDate payload must parse — server returned non-null"

    let fromNode = entity{"header:From:asAddresses"}
    doAssert not fromNode.isNil, "header:From:asAddresses must be present"
    let fromHV = parseHeaderValue(hfAddresses, fromNode).expect("parseHeaderValue From")
    doAssert fromHV.form == hfAddresses, "From HeaderValue must carry hfAddresses form"
    doAssert fromHV.addresses.len == 1,
      "expected one From address (got " & $fromHV.addresses.len & ")"
    doAssert fromHV.addresses[0].email == "alice@example.com",
      "From address must be alice@example.com (got " & fromHV.addresses[0].email & ")"
    client.close()
