# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for header sub-types (scenarios 8–9, 11a–11f, 30–52, 52a–52c).

import std/json

import jmap_client/mail/headers
import jmap_client/mail/serde_headers
import jmap_client/mail/addresses
import jmap_client/validation
import jmap_client/primitives

import ../../massertions

# ============= A. EmailHeader toJson (scenario 8) =============

block emailHeaderToJson: # scenario 8
  let eh = parseEmailHeader("From", "joe@example.com").get()
  let node = eh.toJson()
  assertJsonFieldEq node, "name", %"From"
  assertJsonFieldEq node, "value", %"joe@example.com"

# ============= B. EmailHeader round-trip (scenario 9) =============

block emailHeaderRoundTrip: # scenario 9
  let original = parseEmailHeader("From", "joe@example.com").get()
  let roundTripped = EmailHeader.fromJson(original.toJson()).get()
  assertEq roundTripped.name, original.name
  assertEq roundTripped.value, original.value

# ============= C. EmailHeader fromJson edge cases (scenarios 11a–11f) =============

block fromJsonNonObject: # scenario 11a
  assertErr EmailHeader.fromJson(%*[1, 2, 3])

block fromJsonAbsentName: # scenario 11b
  assertErr EmailHeader.fromJson(%*{"value": "test"})

block fromJsonNullName: # scenario 11c
  assertErr EmailHeader.fromJson(%*{"name": nil, "value": "test"})

block fromJsonWrongKindName: # scenario 11d
  assertErr EmailHeader.fromJson(%*{"name": 42, "value": "test"})

block fromJsonAbsentValue: # scenario 11e
  assertErr EmailHeader.fromJson(%*{"name": "From"})

block fromJsonNullValue: # scenario 11f
  assertErr EmailHeader.fromJson(%*{"name": "From", "value": nil})

# ============= D. parseHeaderValue — all forms (scenarios 30–39) =============

block parseHfRaw: # scenario 30
  let res = parseHeaderValue(hfRaw, %"raw header content")
  assertOk res
  assertEq res.get().rawValue, "raw header content"

block parseHfText: # scenario 31
  let res = parseHeaderValue(hfText, %"text header content")
  assertOk res
  assertEq res.get().textValue, "text header content"

block parseHfAddresses: # scenario 32
  let node = %*[{"name": "Joe", "email": "joe@example.com"}]
  let res = parseHeaderValue(hfAddresses, node)
  assertOk res
  assertLen res.get().addresses, 1
  assertEq res.get().addresses[0].email, "joe@example.com"

block parseHfGroupedAddresses: # scenario 33
  let node =
    %*[{"name": "Team", "addresses": [{"name": "Joe", "email": "joe@example.com"}]}]
  let res = parseHeaderValue(hfGroupedAddresses, node)
  assertOk res
  assertLen res.get().groups, 1
  assertSomeEq res.get().groups[0].name, "Team"

block parseHfMessageIds: # scenario 34
  let node = %*["<msg1@example.com>", "<msg2@example.com>"]
  let res = parseHeaderValue(hfMessageIds, node)
  assertOk res
  assertSome res.get().messageIds
  assertLen res.get().messageIds.get(), 2

block parseHfMessageIdsNull: # scenario 35
  let res = parseHeaderValue(hfMessageIds, newJNull())
  assertOk res
  assertNone res.get().messageIds

block parseHfDate: # scenario 36
  let res = parseHeaderValue(hfDate, %"2023-01-15T12:00:00Z")
  assertOk res
  assertSome res.get().date

block parseHfDateNull: # scenario 37
  let res = parseHeaderValue(hfDate, newJNull())
  assertOk res
  assertNone res.get().date

block parseHfUrls: # scenario 38
  let node = %*["https://example.com/unsub", "https://example.com/help"]
  let res = parseHeaderValue(hfUrls, node)
  assertOk res
  assertSome res.get().urls
  assertLen res.get().urls.get(), 2

block parseHfUrlsNull: # scenario 39
  let res = parseHeaderValue(hfUrls, newJNull())
  assertOk res
  assertNone res.get().urls

# ============= E. Wrong JSON kinds (scenarios 40–41, 51–52) =============

block wrongKindHfRaw: # scenario 40
  assertErr parseHeaderValue(hfRaw, %42)

block wrongKindHfAddresses: # scenario 41
  assertErr parseHeaderValue(hfAddresses, %"not an array")

block wrongKindRemainingForms: # scenario 51
  assertErr parseHeaderValue(hfText, %42)
  assertErr parseHeaderValue(hfGroupedAddresses, %"not an array")
  assertErr parseHeaderValue(hfMessageIds, %*{"not": "array"})
  assertErr parseHeaderValue(hfDate, %*[1, 2])
  assertErr parseHeaderValue(hfUrls, %*{"not": "array"})

block nullForNonNullableForm: # scenario 52
  assertErr parseHeaderValue(hfAddresses, newJNull())

# ============= F. HeaderValue toJson (scenario 42) =============

block headerValueToJsonAllForms: # scenario 42
  # hfRaw
  let rawVal = HeaderValue(form: hfRaw, rawValue: "raw content")
  assertEq rawVal.toJson(), %"raw content"

  # hfText
  let textVal = HeaderValue(form: hfText, textValue: "text content")
  assertEq textVal.toJson(), %"text content"

  # hfAddresses
  let ea = parseEmailAddress("joe@example.com", Opt.some("Joe")).get()
  let addrVal = HeaderValue(form: hfAddresses, addresses: @[ea])
  let addrJson = addrVal.toJson()
  doAssert addrJson.kind == JArray
  assertLen addrJson.getElems(), 1

  # hfGroupedAddresses
  let group = EmailAddressGroup(name: Opt.some("Team"), addresses: @[ea])
  let groupVal = HeaderValue(form: hfGroupedAddresses, groups: @[group])
  let groupJson = groupVal.toJson()
  doAssert groupJson.kind == JArray
  assertLen groupJson.getElems(), 1

  # hfMessageIds — Some
  let msgVal =
    HeaderValue(form: hfMessageIds, messageIds: Opt.some(@["<msg@example.com>"]))
  let msgJson = msgVal.toJson()
  doAssert msgJson.kind == JArray
  assertLen msgJson.getElems(), 1

  # hfDate — Some
  let d = parseDate("2023-01-15T12:00:00Z").get()
  let dateVal = HeaderValue(form: hfDate, date: Opt.some(d))
  let dateJson = dateVal.toJson()
  doAssert dateJson.kind == JString

  # hfUrls — Some
  let urlVal = HeaderValue(form: hfUrls, urls: Opt.some(@["https://example.com"]))
  let urlJson = urlVal.toJson()
  doAssert urlJson.kind == JArray
  assertLen urlJson.getElems(), 1

# ============= G. Round-trips (scenarios 43–44) =============

block headerValueRoundTrip: # scenario 43
  # hfRaw
  let rawOrig = HeaderValue(form: hfRaw, rawValue: "test")
  let rawRT = parseHeaderValue(hfRaw, rawOrig.toJson()).get()
  assertEq rawRT.rawValue, "test"

  # hfText
  let textOrig = HeaderValue(form: hfText, textValue: "test text")
  let textRT = parseHeaderValue(hfText, textOrig.toJson()).get()
  assertEq textRT.textValue, "test text"

  # hfAddresses
  let ea = parseEmailAddress("joe@example.com", Opt.some("Joe")).get()
  let addrOrig = HeaderValue(form: hfAddresses, addresses: @[ea])
  let addrRT = parseHeaderValue(hfAddresses, addrOrig.toJson()).get()
  assertLen addrRT.addresses, 1
  assertEq addrRT.addresses[0].email, "joe@example.com"

  # hfGroupedAddresses
  let group = EmailAddressGroup(name: Opt.some("Team"), addresses: @[ea])
  let groupOrig = HeaderValue(form: hfGroupedAddresses, groups: @[group])
  let groupRT = parseHeaderValue(hfGroupedAddresses, groupOrig.toJson()).get()
  assertLen groupRT.groups, 1

  # hfMessageIds — Some
  let msgOrig = HeaderValue(form: hfMessageIds, messageIds: Opt.some(@["<msg@ex.com>"]))
  let msgRT = parseHeaderValue(hfMessageIds, msgOrig.toJson()).get()
  assertSomeEq msgRT.messageIds, @["<msg@ex.com>"]

  # hfMessageIds — None
  let msgNone = HeaderValue(form: hfMessageIds, messageIds: Opt.none(seq[string]))
  let msgNoneRT = parseHeaderValue(hfMessageIds, msgNone.toJson()).get()
  assertNone msgNoneRT.messageIds

  # hfDate — Some
  let d = parseDate("2023-01-15T12:00:00Z").get()
  let dateOrig = HeaderValue(form: hfDate, date: Opt.some(d))
  let dateRT = parseHeaderValue(hfDate, dateOrig.toJson()).get()
  assertSomeEq dateRT.date, d

  # hfUrls — Some
  let urlOrig = HeaderValue(form: hfUrls, urls: Opt.some(@["https://example.com"]))
  let urlRT = parseHeaderValue(hfUrls, urlOrig.toJson()).get()
  assertSomeEq urlRT.urls, @["https://example.com"]

  # hfUrls — None
  let urlNone = HeaderValue(form: hfUrls, urls: Opt.none(seq[string]))
  let urlNoneRT = parseHeaderValue(hfUrls, urlNone.toJson()).get()
  assertNone urlNoneRT.urls

block headerValueDateNoneToJson: # scenario 44
  let dateNone = HeaderValue(form: hfDate, date: Opt.none(Date))
  let node = dateNone.toJson()
  doAssert node.kind == JNull

# ============= H. Empty arrays (scenarios 45–48) =============

block emptyAddressesArray: # scenario 45
  let res = parseHeaderValue(hfAddresses, %*[])
  assertOk res
  assertLen res.get().addresses, 0

block emptyGroupsArray: # scenario 46
  let res = parseHeaderValue(hfGroupedAddresses, %*[])
  assertOk res
  assertLen res.get().groups, 0

block emptyMessageIdsArray: # scenario 47
  let res = parseHeaderValue(hfMessageIds, %*[])
  assertOk res
  assertSomeEq res.get().messageIds, newSeq[string]()

block emptyUrlsArray: # scenario 48
  let res = parseHeaderValue(hfUrls, %*[])
  assertOk res
  assertSomeEq res.get().urls, newSeq[string]()

# ============= I. Malformed elements (scenarios 49–50) =============

block malformedAddressElement: # scenario 49
  let node = %*[{"name": "Joe"}] # missing email field
  assertErr parseHeaderValue(hfAddresses, node)

block malformedDateString: # scenario 50
  assertErr parseHeaderValue(hfDate, %"not-a-date")

# ============= J. Edge cases (scenarios 52a–52c) =============

block emptyRawString: # scenario 52a
  let res = parseHeaderValue(hfRaw, %"")
  assertOk res
  assertEq res.get().rawValue, ""

block mixedKindArray: # scenario 52b
  let node = %*[42, "not-an-object"]
  assertErr parseHeaderValue(hfAddresses, node)

block nonStringInMessageIdArray: # scenario 52c
  let node = %*["valid", 42]
  assertErr parseHeaderValue(hfMessageIds, node)
