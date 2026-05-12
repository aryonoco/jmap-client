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

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailGetHeaderFormsLive:
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

    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let mailboxIds = parseNonEmptyMailboxIdSet(@[inbox]).expect(
        "parseNonEmptyMailboxIdSet[" & $target.kind & "]"
      )
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
    let listPostName = parseBlueprintEmailHeaderName("List-Post").expect(
        "List-Post header name[" & $target.kind & "]"
      )
    var extraHeaders = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
    extraHeaders[listPostName] = urlsSingle(@["mailto:list@example.com"])
    let sentAt =
      parseDate("2026-05-01T12:00:00Z").expect("parseDate[" & $target.kind & "]")
    let blueprint = parseEmailBlueprint(
      mailboxIds = mailboxIds,
      body = flatBody(textBody = Opt.some(textPart)),
      fromAddr = Opt.some(@[aliceAddr]),
      to = Opt.some(@[aliceAddr]),
      subject = Opt.some("phase-d step-22 header forms"),
      sentAt = Opt.some(sentAt),
      extraHeaders = extraHeaders,
    )
    assertOn target, blueprint.isOk, "parseEmailBlueprint must succeed"
    let blueprintOk = blueprint.unsafeValue
    let cid =
      parseCreationId("seedHeaders").expect("parseCreationId[" & $target.kind & "]")
    var createTbl = initTable[CreationId, EmailBlueprint]()
    createTbl[cid] = blueprintOk
    let (bSeed, seedHandle) = addEmailSet(
      initRequestBuilder(makeBuilderId()), mailAccountId, create = Opt.some(createTbl)
    )
    let seedResp =
      client.send(bSeed.freeze()).expect("send Email/set seed[" & $target.kind & "]")
    let seedSet =
      seedResp.get(seedHandle).expect("Email/set seed extract[" & $target.kind & "]")
    var seededId: Id
    var found = false
    seedSet.createResults.withValue(cid, outcome):
      assertOn target,
        outcome.isOk,
        "Email/set must succeed: " &
          (if outcome.isErr: outcome.unsafeError.rawType else: "(ok)")
      seededId = outcome.unsafeValue.id
      found = true
    do:
      assertOn target, false, "Email/set returned no result for creationId"
    assertOn target, found

    let (b, getHandle) = addEmailGet(
      initRequestBuilder(makeBuilderId()),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(
        @[
          "id", "header:List-Post:asURLs", "header:Date:asDate",
          "header:From:asAddresses",
        ]
      ),
    )
    let resp = client.send(b.freeze()).expect(
        "send Email/get header forms[" & $target.kind & "]"
      )
    captureIfRequested(client, "email-header-forms-" & $target.kind).expect(
      "captureIfRequested"
    )
    let getResp =
      resp.get(getHandle).expect("Email/get header forms extract[" & $target.kind & "]")
    assertOn target, getResp.list.len == 1, "Email/get must return the seeded message"

    let email = getResp.list[0]

    let listPostKey = parseHeaderPropertyName("header:List-Post:asURLs").expect(
        "listPostKey[" & $target.kind & "]"
      )
    let listPostHv = email.requestedHeaders.getOrDefault(listPostKey)
    assertOn target,
      listPostKey in email.requestedHeaders, "header:List-Post:asURLs must be present"
    assertOn target,
      listPostHv.form == hfUrls, "List-Post HeaderValue must carry hfUrls form"
    assertOn target,
      listPostHv.urls.isSome,
      "List-Post hfUrls payload must parse — server returned non-null"
    assertOn target,
      listPostHv.urls.unsafeGet.len == 1,
      "expected one URL in List-Post (got " & $listPostHv.urls.unsafeGet.len & ")"

    let dateKey = parseHeaderPropertyName("header:Date:asDate").expect(
        "dateKey[" & $target.kind & "]"
      )
    assertOn target,
      dateKey in email.requestedHeaders, "header:Date:asDate must be present"
    let dateHv = email.requestedHeaders.getOrDefault(dateKey)
    assertOn target, dateHv.form == hfDate, "Date HeaderValue must carry hfDate form"
    assertOn target,
      dateHv.date.isSome, "Date hfDate payload must parse — server returned non-null"

    let fromKey = parseHeaderPropertyName("header:From:asAddresses").expect(
        "fromKey[" & $target.kind & "]"
      )
    assertOn target,
      fromKey in email.requestedHeaders, "header:From:asAddresses must be present"
    let fromHv = email.requestedHeaders.getOrDefault(fromKey)
    assertOn target,
      fromHv.form == hfAddresses, "From HeaderValue must carry hfAddresses form"
    assertOn target,
      fromHv.addresses.len == 1,
      "expected one From address (got " & $fromHv.addresses.len & ")"
    assertOn target,
      fromHv.addresses[0].email == "alice@example.com",
      "From address must be alice@example.com (got " & fromHv.addresses[0].email & ")"
    client.close()
