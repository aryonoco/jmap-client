# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/get`` extended
## HeaderForm response
## (``tests/testdata/captured/email-get-header-forms-extended-stalwart.json``).
## Verifies that ``Email.fromJson`` correctly parses the four
## ``HeaderForm`` arms not exercised by Phase D22 — ``hfMessageIds``,
## ``hfText``, ``hfGroupedAddresses``, ``hfRaw`` — plus the ``:all``
## multi-instance flag carrying both Resent-To instances.

{.push raises: [].}

import std/tables

import jmap_client
import ./mloader

block tcapturedEmailGetHeaderFormsExtended:
  forEachCapturedServer("email-get-header-forms-extended", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "Email/get"

    let getResp =
      GetResponse[Email].fromJson(inv.arguments).expect("GetResponse[Email].fromJson")
    doAssert getResp.list.len == 1, "captured Email/get must carry one record"
    let email = Email.fromJson(getResp.list[0]).expect("Email.fromJson")

    let messageIdsKey = parseHeaderPropertyName("header:Message-ID:asMessageIds").expect(
        "parseHeaderPropertyName messageIds"
      )
    doAssert messageIdsKey in email.requestedHeaders,
      "header:Message-ID:asMessageIds must be present"
    doAssert email.requestedHeaders.getOrDefault(messageIdsKey).form == hfMessageIds,
      "Message-ID HeaderValue must carry hfMessageIds form"

    let commentsTextKey = parseHeaderPropertyName("header:Comments:asText").expect(
        "parseHeaderPropertyName commentsText"
      )
    doAssert commentsTextKey in email.requestedHeaders,
      "header:Comments:asText must be present"
    doAssert email.requestedHeaders.getOrDefault(commentsTextKey).form == hfText,
      "Comments asText HeaderValue must carry hfText form"

    let commentsRawKey = parseHeaderPropertyName("header:Comments:asRaw").expect(
        "parseHeaderPropertyName commentsRaw"
      )
    doAssert commentsRawKey in email.requestedHeaders,
      "header:Comments:asRaw must be present (the wire emits header:Comments — " &
        "asRaw is the default form)"
    doAssert email.requestedHeaders.getOrDefault(commentsRawKey).form == hfRaw,
      "Comments asRaw HeaderValue must carry hfRaw form"

    let toGroupedKey = parseHeaderPropertyName("header:To:asGroupedAddresses").expect(
        "parseHeaderPropertyName toGrouped"
      )
    doAssert toGroupedKey in email.requestedHeaders,
      "header:To:asGroupedAddresses must be present"
    doAssert email.requestedHeaders.getOrDefault(toGroupedKey).form == hfGroupedAddresses,
      "To HeaderValue must carry hfGroupedAddresses form"

    let resentAllKey = parseHeaderPropertyName("header:Resent-To:asAddresses:all")
      .expect("parseHeaderPropertyName resentAll")
    doAssert resentAllKey in email.requestedHeadersAll,
      "header:Resent-To:asAddresses:all must be present in requestedHeadersAll"
    let resentAllHvs = email.requestedHeadersAll.getOrDefault(resentAllKey)
    doAssert resentAllHvs.len >= 1,
      "the :all flag must surface at least one Resent-To instance"
    for hv in resentAllHvs:
      doAssert hv.form == hfAddresses, "every :all instance must carry hfAddresses form"
