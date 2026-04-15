# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for Email, ParsedEmail, and EmailComparator
## (§12.2–12.5, scenarios 3–45).
## Uses ``unsafeError`` instead of ``.error`` for Result[Email, ...] and
## Result[ParsedEmail, ...] because ``$Email`` triggers side effects
## through Table fields' ``collectionToString``.

{.push raises: [].}

import std/json
import std/tables
import std/strutils

import jmap_client/mail/email
import jmap_client/mail/headers
import jmap_client/mail/body
import jmap_client/mail/keyword
import jmap_client/mail/addresses
import jmap_client/mail/serde_email
import jmap_client/serde
import jmap_client/validation

import ../../massertions
import ../../mfixtures

# ============= A. Email fromJson (scenarios 3–17) =============

block fromJsonNonObject: # scenario 3
  for input in [newJArray(), newJString("x"), newJNull()]:
    let res = emailFromJson(input)
    doAssert res.isErr, "expected Err for non-JObject input"
    doAssert res.unsafeError.kind == svkWrongKind, "error must be svkWrongKind"
    doAssert res.unsafeError.expectedKind == JObject, "error must expect JObject"

block fromJsonGoldenPath: # scenario 4
  let j = makeEmailJson()
  let res = emailFromJson(j)
  assertOk res
  let parsed = res.get()
  # Round-trip: parse → serialize → parse produces identical result.
  # Cannot compare directly with makeEmail() because parseCharsetField
  # applies C20 defaults (text/* → us-ascii) that the fixture omits.
  let rt = emailFromJson(parsed.toJson())
  assertOk rt
  doAssert emailEq(rt.get(), parsed), "golden path round-trip mismatch"

block fromJsonAbsentKeywords: # scenario 5
  var j = makeEmailJson()
  j.delete("keywords")
  let res = emailFromJson(j)
  assertOk res
  assertEq res.get().keywords.len, 0

block fromJsonConvenienceHeaders: # scenario 6
  var j = makeEmailJson()
  # Set "from" to a valid address array, set "subject" to null
  j["from"] = %*[{"name": "Alice", "email": "alice@example.com"}]
  j["subject"] = newJNull()
  let res = emailFromJson(j)
  assertOk res
  let e = res.get()
  assertSome e.fromAddr
  assertEq e.fromAddr.get().len, 1
  assertNone e.subject

block fromJsonFromKey: # scenario 7
  var j = makeEmailJson()
  j["from"] = %*[{"name": nil, "email": "bob@test.com"}]
  let res = emailFromJson(j)
  assertOk res
  assertSome res.get().fromAddr
  assertEq res.get().fromAddr.get()[0].email, "bob@test.com"

block fromJsonDynamicHeader: # scenario 8
  var j = makeEmailJson()
  j["header:Subject:asText"] = %"Hello World"
  let res = emailFromJson(j)
  assertOk res
  let e = res.get()
  assertEq e.requestedHeaders.len, 1
  for key, val in e.requestedHeaders:
    assertEq key.name, "subject"
    assertEq key.form, hfText
    doAssert not key.isAll, "must not be :all"

block fromJsonDynamicHeaderAll: # scenario 9
  var j = makeEmailJson()
  j["header:From:asAddresses:all"] = %*[%*[{"name": nil, "email": "a@b"}]]
  let res = emailFromJson(j)
  assertOk res
  let e = res.get()
  assertEq e.requestedHeadersAll.len, 1
  for key, vals in e.requestedHeadersAll:
    assertEq key.name, "from"
    assertEq key.form, hfAddresses
    doAssert key.isAll, "must be :all"

block fromJsonBothDynamicHeaders: # scenario 10
  var j = makeEmailJson()
  j["header:Subject:asText"] = %"test"
  j["header:From:asAddresses:all"] = %*[%*[{"name": nil, "email": "a@b"}]]
  let res = emailFromJson(j)
  assertOk res
  let e = res.get()
  assertEq e.requestedHeaders.len, 1
  assertEq e.requestedHeadersAll.len, 1

block fromJsonUnknownKeyIgnored: # scenario 11
  var j = makeEmailJson()
  j["unknownField"] = %42
  j["anotherUnknown"] = %"ignored"
  let res = emailFromJson(j)
  assertOk res

block fromJsonBodyValuesPartId: # scenario 12
  var j = makeEmailJson()
  j["bodyValues"] =
    %*{"1": {"value": "hello", "isEncodingProblem": false, "isTruncated": false}}
  let res = emailFromJson(j)
  assertOk res
  let e = res.get()
  assertEq e.bodyValues.len, 1
  let pid = parsePartIdFromServer("1").get()
  doAssert pid in e.bodyValues, "PartId '1' must be in bodyValues"
  assertEq e.bodyValues[pid].value, "hello"

block fromJsonMissingMetadata: # scenario 13
  const metadataKeys = ["id", "blobId", "threadId", "mailboxIds", "size", "receivedAt"]
  for key in metadataKeys:
    var j = makeEmailJson()
    j.delete(key)
    assertErr emailFromJson(j)

block fromJsonConvHeaderWrongType: # scenario 14
  var j = makeEmailJson()
  j["from"] = %42
  assertErr emailFromJson(j)

block fromJsonMalformedDynamicHeader: # scenario 15
  # Empty name after header: prefix
  var j1 = makeEmailJson()
  j1["header:"] = %"test"
  assertErr emailFromJson(j1)

  # Unknown form suffix
  var j2 = makeEmailJson()
  j2["header:From:asUnknown"] = %"test"
  assertErr emailFromJson(j2)

  # Too many segments
  var j3 = makeEmailJson()
  j3["header:From:asText:all:extra"] = %"test"
  assertErr emailFromJson(j3)

block fromJsonMailboxIdsNull: # scenario 16
  var j = makeEmailJson()
  j["mailboxIds"] = newJNull()
  assertErr emailFromJson(j)

block fromJsonKeywordsWrongType: # scenario 17
  var j = makeEmailJson()
  j["keywords"] = %*[1, 2, 3]
  assertErr emailFromJson(j)

# ============= B. Email toJson (scenarios 18–23) =============

block toJsonOptNoneNull: # scenario 18
  let node = makeEmail().toJson()
  # All convenience headers are Opt.none in makeEmail(), so they emit as null
  const headerKeys = [
    "messageId", "inReplyTo", "references", "sender", "from", "to", "cc", "bcc",
    "replyTo", "subject", "sentAt",
  ]
  for key in headerKeys:
    doAssert node{key} != nil, key & " must be present"
    doAssert node{key}.kind == JNull, key & " must be null when Opt.none"

block toJsonFromAddrKey: # scenario 19
  var e = makeEmail()
  let ea = EmailAddress(name: Opt.none(string), email: "test@example.com")
  e.fromAddr = Opt.some(@[ea])
  let node = e.toJson()
  doAssert node{"from"} != nil, "\"from\" key must be present"
  doAssert node{"from"}.kind == JArray
  doAssert node{"fromAddr"}.isNil, "\"fromAddr\" key must not appear"

block toJsonRequestedHeaders: # scenario 20
  var e = makeEmail()
  let hpk = parseHeaderPropertyName("header:Subject:asText").get()
  let hv = HeaderValue(form: hfText, textValue: "Test Subject")
  e.requestedHeaders[hpk] = hv
  let node = e.toJson()
  doAssert node{"header:subject:asText"} != nil,
    "dynamic header key must appear as top-level key"

block toJsonRequestedHeadersAll: # scenario 21
  var e = makeEmail()
  let hpk = parseHeaderPropertyName("header:From:asAddresses:all").get()
  let hv = HeaderValue(
    form: hfAddresses, addresses: @[EmailAddress(name: Opt.none(string), email: "a@b")]
  )
  e.requestedHeadersAll[hpk] = @[hv]
  let node = e.toJson()
  doAssert node{"header:from:asAddresses:all"} != nil,
    "dynamic :all header key must appear"
  doAssert node{"header:from:asAddresses:all"}.kind == JArray

block toJsonNoDynamicHeaders: # scenario 22
  let node = makeEmail().toJson()
  for key, _ in node.pairs:
    doAssert not key.startsWith("header:"),
      "no header: prefixed keys when tables are empty"

block toJsonEmptyCollections: # scenario 23
  let node = makeEmail().toJson()
  # Empty seq emits as []
  doAssert node{"textBody"} != nil and node{"textBody"}.kind == JArray
  assertLen node{"textBody"}.getElems(@[]), 0
  # Empty Table emits as {}
  doAssert node{"bodyValues"} != nil and node{"bodyValues"}.kind == JObject
  assertLen node{"bodyValues"}, 0

# ============= C. ParsedEmail (scenarios 24–33) =============

block parsedEmailThreadIdNull: # scenario 24
  var j = makeParsedEmailJson()
  j["threadId"] = newJNull()
  let res = parsedEmailFromJson(j)
  assertOk res
  assertNone res.get().threadId

block parsedEmailThreadIdPresent: # scenario 25
  var j = makeParsedEmailJson()
  j["threadId"] = %"t1"
  let res = parsedEmailFromJson(j)
  assertOk res
  assertSome res.get().threadId

block parsedEmailAbsentMetadata: # scenario 26
  let j = makeParsedEmailJson()
  # makeParsedEmailJson() has no metadata keys — should parse fine
  let res = parsedEmailFromJson(j)
  assertOk res

block parsedEmailFromKey: # scenario 27
  var j = makeParsedEmailJson()
  j["from"] = %*[{"name": nil, "email": "alice@test.com"}]
  let res = parsedEmailFromJson(j)
  assertOk res
  assertSome res.get().fromAddr
  assertEq res.get().fromAddr.get()[0].email, "alice@test.com"

block parsedEmailDynamicHeaders: # scenario 28
  var j = makeParsedEmailJson()
  j["header:Subject:asText"] = %"subj"
  j["header:From:asAddresses:all"] = %*[%*[{"name": nil, "email": "a@b"}]]
  let res = parsedEmailFromJson(j)
  assertOk res
  let pe = res.get()
  assertEq pe.requestedHeaders.len, 1
  assertEq pe.requestedHeadersAll.len, 1

block parsedEmailThreadIdWrongType: # scenario 29
  var j = makeParsedEmailJson()
  j["threadId"] = %42
  assertErr parsedEmailFromJson(j)

block parsedEmailExtraMetadataIgnored: # scenario 30
  var j = makeParsedEmailJson()
  j["id"] = %"extra-id"
  j["blobId"] = %"extra-blob"
  j["mailboxIds"] = %*{"mbx1": true}
  j["keywords"] = %*{"$seen": true}
  j["size"] = %100
  j["receivedAt"] = %"2025-01-15T09:00:00Z"
  let res = parsedEmailFromJson(j)
  assertOk res

block parsedEmailToJsonNoMetadata: # scenario 31
  let node = makeParsedEmail().toJson()
  const absentKeys = ["id", "blobId", "mailboxIds", "keywords", "size", "receivedAt"]
  for key in absentKeys:
    doAssert node{key}.isNil, key & " must not appear in ParsedEmail.toJson"
  # threadId DOES appear (as null for Opt.none)
  doAssert node{"threadId"} != nil, "threadId must be present"

block parsedEmailToJsonFromKey: # scenario 32
  var pe = makeParsedEmail()
  let ea = EmailAddress(name: Opt.none(string), email: "test@test.com")
  pe.fromAddr = Opt.some(@[ea])
  let node = pe.toJson()
  doAssert node{"from"} != nil, "\"from\" key must be present"
  doAssert node{"fromAddr"}.isNil, "\"fromAddr\" key must not appear"

block parsedEmailRoundTrip: # scenario 33
  let j = makeParsedEmail().toJson()
  let first = parsedEmailFromJson(j)
  assertOk first
  # Round-trip: parse → serialize → parse produces identical result.
  # Cannot compare with original fixture because parseCharsetField
  # applies C20 defaults (text/* → us-ascii).
  let rt = parsedEmailFromJson(first.get().toJson())
  assertOk rt
  doAssert parsedEmailEq(rt.get(), first.get()), "round-trip mismatch"

# ============= D. EmailComparator (scenarios 34–45) =============

block comparatorToJsonPlain: # scenario 34
  let c = plainComparator(pspReceivedAt)
  let node = c.toJson()
  assertJsonFieldEq node, "property", %"receivedAt"

block comparatorToJsonKeyword: # scenario 35
  let c = keywordComparator(kspHasKeyword, kwFlagged)
  let node = c.toJson()
  assertJsonFieldEq node, "property", %"hasKeyword"
  assertJsonFieldEq node, "keyword", %"$flagged"

block comparatorToJsonOmitsOptionals: # scenario 36
  let c = plainComparator(pspSize)
  let node = c.toJson()
  doAssert node{"isAscending"}.isNil, "isAscending must be omitted when Opt.none"
  doAssert node{"collation"}.isNil, "collation must be omitted when Opt.none"

block comparatorToJsonAllKeys: # scenario 37
  let c = keywordComparator(
    kspHasKeyword, kwSeen, Opt.some(false), Opt.some("i;unicode-casemap")
  )
  let node = c.toJson()
  assertLen node, 4
  assertJsonFieldEq node, "property", %"hasKeyword"
  assertJsonFieldEq node, "keyword", %"$seen"
  assertJsonFieldEq node, "isAscending", %false
  assertJsonFieldEq node, "collation", %"i;unicode-casemap"

block comparatorFromJsonPlain: # scenario 38
  let res = emailComparatorFromJson(%*{"property": "receivedAt"})
  assertOk res
  let c = res.get()
  assertEq c.kind, eckPlain
  assertEq c.property, pspReceivedAt

block comparatorFromJsonHasKeyword: # scenario 39
  let res = emailComparatorFromJson(%*{"property": "hasKeyword", "keyword": "$seen"})
  assertOk res
  let c = res.get()
  assertEq c.kind, eckKeyword
  assertEq c.keywordProperty, kspHasKeyword

block comparatorFromJsonAllInThread: # scenario 40
  let res = emailComparatorFromJson(
    %*{"property": "allInThreadHaveKeyword", "keyword": "$seen"}
  )
  assertOk res
  assertEq res.get().kind, eckKeyword
  assertEq res.get().keywordProperty, kspAllInThreadHaveKeyword

block comparatorFromJsonSomeInThread: # scenario 41
  let res = emailComparatorFromJson(
    %*{"property": "someInThreadHaveKeyword", "keyword": "$seen"}
  )
  assertOk res
  assertEq res.get().kind, eckKeyword
  assertEq res.get().keywordProperty, kspSomeInThreadHaveKeyword

block comparatorFromJsonKeywordMissing: # scenario 42
  assertErr emailComparatorFromJson(%*{"property": "hasKeyword"})

block comparatorFromJsonUnknownProp: # scenario 43
  assertErr emailComparatorFromJson(%*{"property": "unknownSort"})

block comparatorFromJsonIsAscending: # scenario 44
  let res = emailComparatorFromJson(%*{"property": "size", "isAscending": false})
  assertOk res
  assertSomeEq res.get().isAscending, false

block comparatorFromJsonCollation: # scenario 45
  let res =
    emailComparatorFromJson(%*{"property": "size", "collation": "i;unicode-casemap"})
  assertOk res
  assertSomeEq res.get().collation, "i;unicode-casemap"

# ============= F. emitInto tests =============

block emitIntoDefault:
  ## emitInto with default(EmailBodyFetchOptions) adds no keys.
  var node = newJObject()
  default(EmailBodyFetchOptions).emitInto(node)
  doAssert node.len == 0

block emitIntoText:
  ## emitInto with bvsText emits fetchTextBodyValues: true.
  var node = newJObject()
  let opts = EmailBodyFetchOptions(fetchBodyValues: bvsText)
  opts.emitInto(node)
  doAssert node{"fetchTextBodyValues"}.getBool(false) == true
  doAssert node{"fetchHTMLBodyValues"}.isNil
  doAssert node{"fetchAllBodyValues"}.isNil

block emitIntoHtml:
  ## emitInto with bvsHtml emits fetchHTMLBodyValues: true.
  var node = newJObject()
  let opts = EmailBodyFetchOptions(fetchBodyValues: bvsHtml)
  opts.emitInto(node)
  doAssert node{"fetchHTMLBodyValues"}.getBool(false) == true
  doAssert node{"fetchTextBodyValues"}.isNil

block emitIntoTextAndHtml:
  ## emitInto with bvsTextAndHtml emits both fetch booleans.
  var node = newJObject()
  let opts = EmailBodyFetchOptions(fetchBodyValues: bvsTextAndHtml)
  opts.emitInto(node)
  doAssert node{"fetchTextBodyValues"}.getBool(false) == true
  doAssert node{"fetchHTMLBodyValues"}.getBool(false) == true

block emitIntoAll:
  ## emitInto with bvsAll emits fetchAllBodyValues: true.
  var node = newJObject()
  let opts = EmailBodyFetchOptions(fetchBodyValues: bvsAll)
  opts.emitInto(node)
  doAssert node{"fetchAllBodyValues"}.getBool(false) == true

block emitIntoParityWithToJson:
  ## emitInto on fresh node produces same result as toJson.
  let opts = EmailBodyFetchOptions(fetchBodyValues: bvsText)
  var emitNode = newJObject()
  opts.emitInto(emitNode)
  let toJsonNode = opts.toJson()
  doAssert $emitNode == $toJsonNode

block emitIntoPreservesExistingKeys:
  ## emitInto adds keys to an existing node without clobbering.
  var node = %*{"accountId": "a1", "ids": []}
  let opts = EmailBodyFetchOptions(fetchBodyValues: bvsText)
  opts.emitInto(node)
  doAssert node{"accountId"}.getStr("") == "a1"
  doAssert node{"ids"}.kind == JArray
  doAssert node{"fetchTextBodyValues"}.getBool(false) == true
