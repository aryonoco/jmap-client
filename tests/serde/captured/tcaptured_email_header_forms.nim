# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/get`` response
## with typed-header properties (RFC 8621 §4.1.2 / §4.2,
## ``tests/testdata/captured/email-header-forms-stalwart.json``).
## Three dynamic header keys parse through ``parseHeaderValue`` to
## the expected ``HeaderForm`` discriminator with populated payload.

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedEmailHeaderForms:
  forEachCapturedServer("email-header-forms", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "Email/get"

    let getResp =
      GetResponse[Email].fromJson(inv.arguments).expect("GetResponse[Email].fromJson")
    doAssert getResp.list.len == 1
    let email = getResp.list[0]

    let listPostKey =
      parseHeaderPropertyName("header:List-Post:asURLs").expect("listPostKey")
    doAssert listPostKey in email.requestedHeaders,
      "header:List-Post:asURLs must be present"
    let listPostHV = email.requestedHeaders.getOrDefault(listPostKey)
    doAssert listPostHV.form == hfUrls
    doAssert listPostHV.urls.isSome and listPostHV.urls.unsafeGet.len >= 1,
      "List-Post must carry at least one URL in the captured fixture"

    let dateKey = parseHeaderPropertyName("header:Date:asDate").expect("dateKey")
    doAssert dateKey in email.requestedHeaders, "header:Date:asDate must be present"
    let dateHV = email.requestedHeaders.getOrDefault(dateKey)
    doAssert dateHV.form == hfDate
    doAssert dateHV.date.isSome,
      "Date must parse to a populated date in the captured fixture"

    let fromKey = parseHeaderPropertyName("header:From:asAddresses").expect("fromKey")
    doAssert fromKey in email.requestedHeaders,
      "header:From:asAddresses must be present"
    let fromHV = email.requestedHeaders.getOrDefault(fromKey)
    doAssert fromHV.form == hfAddresses
    doAssert fromHV.addresses.len >= 1,
      "From must carry at least one address in the captured fixture"
