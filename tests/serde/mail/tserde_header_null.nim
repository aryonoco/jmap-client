# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Regression tests for RFC 8621 §4.1.3: when a single-instance header
## property (``header:{name}:as{Form}``) is requested but the message lacks
## that header, the server returns the property as JSON ``null``. All four
## single-instance forms (asRaw, asText, asAddresses, asGroupedAddresses)
## must parse that ``null`` to ``Opt.none`` — consistent with the already
## nullable forms — rather than rejecting it.

import std/json
import std/tables

import results

import jmap_client/internal/mail/headers
import jmap_client/internal/mail/serde_headers
import jmap_client/internal/mail/addresses
import jmap_client/internal/mail/email
import jmap_client/internal/mail/serde_email

import ../../massertions
import ../../mtestblock

# === parseHeaderValue: null -> Opt.none for the four single-instance forms ===

testCase parseNullText:
  let res = parseHeaderValue(hfText, newJNull())
  assertOk res
  assertNone res.get().textValue

testCase parseNullRaw:
  let res = parseHeaderValue(hfRaw, newJNull())
  assertOk res
  assertNone res.get().rawValue

testCase parseNullAddresses:
  let res = parseHeaderValue(hfAddresses, newJNull())
  assertOk res
  assertNone res.get().addresses

testCase parseNullGroupedAddresses:
  let res = parseHeaderValue(hfGroupedAddresses, newJNull())
  assertOk res
  assertNone res.get().groups

# === present values still parse to Opt.some ===

testCase parsePresentText:
  let res = parseHeaderValue(hfText, %"hello")
  assertOk res
  assertSomeEq res.get().textValue, "hello"

testCase parsePresentRaw:
  let res = parseHeaderValue(hfRaw, %"raw bytes")
  assertOk res
  assertSomeEq res.get().rawValue, "raw bytes"

testCase parsePresentAddresses:
  let node = %*[{"name": "Joe", "email": "joe@example.com"}]
  let res = parseHeaderValue(hfAddresses, node)
  assertOk res
  assertSome res.get().addresses
  assertLen res.get().addresses.get(), 1
  assertEq res.get().addresses.get()[0].email, "joe@example.com"

testCase parsePresentGroupedAddresses:
  let node =
    %*[{"name": "Team", "addresses": [{"name": "Joe", "email": "joe@example.com"}]}]
  let res = parseHeaderValue(hfGroupedAddresses, node)
  assertOk res
  assertSome res.get().groups
  assertLen res.get().groups.get(), 1

# === toJson: none -> null, some -> value (round-trip stable) ===

testCase toJsonNoneEmitsNull:
  let textNone = HeaderValue(form: hfText, textValue: Opt.none(string))
  doAssert textNone.toJson().kind == JNull
  let rawNone = HeaderValue(form: hfRaw, rawValue: Opt.none(string))
  doAssert rawNone.toJson().kind == JNull
  let addrNone = HeaderValue(form: hfAddresses, addresses: Opt.none(seq[EmailAddress]))
  doAssert addrNone.toJson().kind == JNull
  let groupNone =
    HeaderValue(form: hfGroupedAddresses, groups: Opt.none(seq[EmailAddressGroup]))
  doAssert groupNone.toJson().kind == JNull

testCase toJsonSomeEmitsValueRoundTrip:
  let textSome = HeaderValue(form: hfText, textValue: Opt.some("subject"))
  assertEq textSome.toJson(), %"subject"
  assertSomeEq parseHeaderValue(hfText, textSome.toJson()).get().textValue, "subject"

  let rawSome = HeaderValue(form: hfRaw, rawValue: Opt.some("raw"))
  assertEq rawSome.toJson(), %"raw"
  assertSomeEq parseHeaderValue(hfRaw, rawSome.toJson()).get().rawValue, "raw"

  let ea = parseEmailAddress("joe@example.com", Opt.some("Joe")).get()
  let addrSome = HeaderValue(form: hfAddresses, addresses: Opt.some(@[ea]))
  doAssert addrSome.toJson().kind == JArray
  let addrRt = parseHeaderValue(hfAddresses, addrSome.toJson()).get()
  assertSome addrRt.addresses
  assertLen addrRt.addresses.get(), 1

testCase toJsonNullRoundTripStable:
  let textNone = HeaderValue(form: hfText, textValue: Opt.none(string))
  let textRt = parseHeaderValue(hfText, textNone.toJson()).get()
  assertNone textRt.textValue
  let addrNone = HeaderValue(form: hfAddresses, addresses: Opt.none(seq[EmailAddress]))
  let addrRt = parseHeaderValue(hfAddresses, addrNone.toJson()).get()
  assertNone addrRt.addresses

# === full Email receive round-trip with null single-instance headers ===

testCase emailReceiveNullSingleInstanceHeaders:
  let j = %*{"id": "M1", "header:Subject:asText": nil, "header:To:asAddresses": nil}
  let res = Email.fromJson(j)
  assertOk res
  let e = res.get()
  assertSome e.requestedHeaders
  let tbl = e.requestedHeaders.get()

  let subjKey = parseHeaderPropertyName("header:Subject:asText").get()
  doAssert subjKey in tbl, "header:Subject:asText entry must be present"
  assertNone tbl[subjKey].textValue

  let toKey = parseHeaderPropertyName("header:To:asAddresses").get()
  doAssert toKey in tbl, "header:To:asAddresses entry must be present"
  assertNone tbl[toKey].addresses
