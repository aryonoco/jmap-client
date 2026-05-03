# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phase I Step 53 — wire test for the four ``HeaderForm`` arms not
## exercised by Phase D22.  Phase D22 covered ``hfUrls`` /
## ``hfDate`` / ``hfAddresses``; this step adds:
##
##  * ``hfMessageIds`` via the ``Message-ID`` header,
##  * ``hfText`` via the ``Comments`` header,
##  * ``hfGroupedAddresses`` via a ``To`` header parsed in grouped
##    form,
##  * ``hfRaw`` via the ``Comments`` header in raw form,
##  * the ``:all`` multi-instance flag via two ``Resent-To``
##    instances.
##
## Workflow:
##
##  1. Seed an email via ``seedEmailWithHeaders`` carrying a
##     dedicated ``Comments`` extra header.  The ``Message-ID`` and
##     ``Resent-To`` headers ride through the ``messageId``
##     convenience field and a multi-value ``addressesMulti``
##     ``Resent-To`` extra header respectively, so each test arm has
##     a deterministic source.
##  2. ``Email/get`` requesting the corresponding ``header:Name:asForm``
##     keys plus the ``:all`` variant for ``Resent-To``.  Capture
##     the wire response.
##  3. Pattern-match each header value via the appropriate parser
##     and assert the discriminator + payload shape.
##
## Capture: ``email-get-header-forms-extended-stalwart``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it;
## run via ``just test-integration`` after ``just stalwart-up``.
## Body is guarded on ``loadLiveTestConfig().isOk`` so the file
## joins testament's megatest cleanly under ``just test-full`` when
## env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailGetHeaderFormsExtendedLive:
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
    let aliceAddr = buildAliceAddr()
    let commentsName = parseBlueprintEmailHeaderName("Comments").expect(
        "parseBlueprintEmailHeaderName Comments"
      )
    let resentToName = parseBlueprintEmailHeaderName("Resent-To").expect(
        "parseBlueprintEmailHeaderName Resent-To"
      )
    let resent1 =
      parseEmailAddress("resent1@example.com", Opt.none(string)).expect("resent1")
    let resent2 =
      parseEmailAddress("resent2@example.com", Opt.none(string)).expect("resent2")
    let resentMulti =
      addressesMulti(@[@[resent1], @[resent2]]).expect("addressesMulti Resent-To")
    let extraHeaders = @[
      (commentsName, textSingle("phase-i step-53 free text")),
      (resentToName, resentMulti),
    ]
    let seededId = seedEmailWithHeaders(
        client, mailAccountId, inbox, aliceAddr, aliceAddr, "phase-i 53 header forms",
        "phase-i step-53 body", extraHeaders, "phase-i-53-seed",
      )
      .expect("seedEmailWithHeaders")

    let (b, getHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(
        @[
          "id", "header:Message-ID:asMessageIds", "header:Comments:asText",
          "header:Comments:asRaw", "header:To:asGroupedAddresses",
          "header:Resent-To:asAddresses:all",
        ]
      ),
    )
    let resp = client.send(b).expect("send Email/get extended header forms")
    captureIfRequested(client, "email-get-header-forms-extended-stalwart").expect(
      "captureIfRequested"
    )
    let getResp = resp.get(getHandle).expect("Email/get extended header forms extract")
    doAssert getResp.list.len == 1, "Email/get must return the seeded message"
    let email = Email.fromJson(getResp.list[0]).expect("Email.fromJson")

    let messageIdsKey = parseHeaderPropertyName("header:Message-ID:asMessageIds").expect(
        "parseHeaderPropertyName messageIds"
      )
    let messageIdsHv = email.requestedHeaders.getOrDefault(messageIdsKey)
    doAssert messageIdsKey in email.requestedHeaders,
      "header:Message-ID:asMessageIds must be present"
    doAssert messageIdsHv.form == hfMessageIds,
      "Message-ID HeaderValue must carry hfMessageIds form"

    let commentsTextKey = parseHeaderPropertyName("header:Comments:asText").expect(
        "parseHeaderPropertyName commentsText"
      )
    doAssert commentsTextKey in email.requestedHeaders,
      "header:Comments:asText must be present"
    let commentsTextHv = email.requestedHeaders.getOrDefault(commentsTextKey)
    doAssert commentsTextHv.form == hfText,
      "Comments HeaderValue must carry hfText form"
    doAssert commentsTextHv.textValue.len > 0,
      "asText payload must be a non-empty string"

    let commentsRawKey = parseHeaderPropertyName("header:Comments:asRaw").expect(
        "parseHeaderPropertyName commentsRaw"
      )
    doAssert commentsRawKey in email.requestedHeaders,
      "header:Comments:asRaw must be present"
    let commentsRawHv = email.requestedHeaders.getOrDefault(commentsRawKey)
    doAssert commentsRawHv.form == hfRaw,
      "Comments asRaw HeaderValue must carry hfRaw form"
    doAssert commentsRawHv.rawValue.len > 0,
      "asRaw payload must be a non-empty byte-passthrough string"

    let toGroupedKey = parseHeaderPropertyName("header:To:asGroupedAddresses").expect(
        "parseHeaderPropertyName toGrouped"
      )
    doAssert toGroupedKey in email.requestedHeaders,
      "header:To:asGroupedAddresses must be present"
    let toGroupedHv = email.requestedHeaders.getOrDefault(toGroupedKey)
    doAssert toGroupedHv.form == hfGroupedAddresses,
      "To HeaderValue must carry hfGroupedAddresses form"
    doAssert toGroupedHv.groups.len >= 1,
      "asGroupedAddresses must produce at least one group entry"

    let resentAllKey = parseHeaderPropertyName("header:Resent-To:asAddresses:all")
      .expect("parseHeaderPropertyName resentAll")
    let resentAllHvs = email.requestedHeadersAll.getOrDefault(resentAllKey)
    doAssert resentAllKey in email.requestedHeadersAll,
      "header:Resent-To:asAddresses:all must be present in requestedHeadersAll"
    doAssert resentAllHvs.len >= 1,
      "the :all flag must surface at least one Resent-To instance"
    for hv in resentAllHvs:
      doAssert hv.form == hfAddresses, "every :all instance must carry hfAddresses form"

    client.close()
