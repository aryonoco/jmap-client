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

import jmap_client/internal/mail/email
import jmap_client/internal/mail/headers
import jmap_client/internal/mail/body
import jmap_client/internal/mail/keyword
import jmap_client/internal/mail/addresses
import jmap_client/internal/mail/serde_email
import jmap_client/internal/types/collation
import jmap_client/internal/serialisation/serde
import jmap_client/internal/types/validation

import ../../massertions
import ../../mfixtures
import ../../mtestblock

# ============= A. Email fromJson (scenarios 3–17) =============

testCase fromJsonNonObject: # scenario 3
  for input in [newJArray(), newJString("x"), newJNull()]:
    let res = emailFromJson(input)
    doAssert res.isErr, "expected Err for non-JObject input"
    doAssert res.unsafeError.kind == svkWrongKind, "error must be svkWrongKind"
    doAssert res.unsafeError.expectedKind == JObject, "error must expect JObject"

testCase fromJsonGoldenPath: # scenario 4
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

testCase fromJsonAbsentKeywords: # scenario 5
  ## Absent ``keywords`` parses to ``Opt.none(KeywordSet)``.
  var j = makeEmailJson()
  j.delete("keywords")
  let res = emailFromJson(j)
  assertOk res
  assertNone res.get().keywords

testCase fromJsonConvenienceHeaders: # scenario 6
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

testCase fromJsonFromKey: # scenario 7
  var j = makeEmailJson()
  j["from"] = %*[{"name": nil, "email": "bob@test.com"}]
  let res = emailFromJson(j)
  assertOk res
  assertSome res.get().fromAddr
  assertEq res.get().fromAddr.get()[0].email, "bob@test.com"

testCase fromJsonDynamicHeader: # scenario 8
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

testCase fromJsonDynamicHeaderAll: # scenario 9
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

testCase fromJsonBothDynamicHeaders: # scenario 10
  var j = makeEmailJson()
  j["header:Subject:asText"] = %"test"
  j["header:From:asAddresses:all"] = %*[%*[{"name": nil, "email": "a@b"}]]
  let res = emailFromJson(j)
  assertOk res
  let e = res.get()
  assertEq e.requestedHeaders.len, 1
  assertEq e.requestedHeadersAll.len, 1

testCase fromJsonUnknownKeyIgnored: # scenario 11
  var j = makeEmailJson()
  j["unknownField"] = %42
  j["anotherUnknown"] = %"ignored"
  let res = emailFromJson(j)
  assertOk res

testCase fromJsonBodyValuesPartId: # scenario 12
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

testCase fromJsonMissingMetadata: # scenario 13
  ## Property-filtered ``Email/get`` may omit any metadata field; absence
  ## must parse to ``Opt.none``, not error.
  const metadataKeys = ["id", "blobId", "threadId", "mailboxIds", "size", "receivedAt"]
  for key in metadataKeys:
    var j = makeEmailJson()
    j.delete(key)
    let res = emailFromJson(j)
    assertOk res
    let e = res.get()
    case key
    of "id":
      assertNone e.id
    of "blobId":
      assertNone e.blobId
    of "threadId":
      assertNone e.threadId
    of "mailboxIds":
      assertNone e.mailboxIds
    of "size":
      assertNone e.size
    of "receivedAt":
      assertNone e.receivedAt
    else:
      discard

testCase fromJsonConvHeaderWrongType: # scenario 14
  var j = makeEmailJson()
  j["from"] = %42
  assertErr emailFromJson(j)

testCase fromJsonMalformedDynamicHeader: # scenario 15
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

testCase fromJsonMailboxIdsNull: # scenario 16
  ## ``mailboxIds: null`` parses to ``Opt.none(MailboxIdSet)``.
  var j = makeEmailJson()
  j["mailboxIds"] = newJNull()
  let res = emailFromJson(j)
  assertOk res
  assertNone res.get().mailboxIds

testCase fromJsonKeywordsWrongType: # scenario 17
  ## Wrong-kind keywords (JArray when JObject expected) still errs —
  ## the Opt parser short-circuits only on absence/null, not wrong kind.
  var j = makeEmailJson()
  j["keywords"] = %*[1, 2, 3]
  assertErr emailFromJson(j)

testCase fromJsonStep38PartialShape: # scenario 17a — sparse property-filter shape
  ## Mirrors Step 38: ``properties = ["id", "subject", "from", "mailboxIds"]``.
  let j = %*{
    "id": "e1",
    "subject": "phase-g step-38 marker",
    "from": [{"name": "Alice", "email": "alice@example.com"}],
    "mailboxIds": {"mbx1": true},
  }
  let res = emailFromJson(j)
  assertOk res
  let e = res.get()
  assertSome e.id
  assertSome e.subject
  assertSome e.fromAddr
  assertSome e.mailboxIds
  assertNone e.blobId
  assertNone e.threadId
  assertNone e.size
  assertNone e.receivedAt
  assertNone e.bodyStructure

testCase fromJsonBodyOnlyPartialShape: # scenario 17b — body-only sparse shape
  ## Mirrors Phase D Step 19: ``properties = ["id", "textBody", "bodyValues"]``.
  let j = %*{
    "id": "e2",
    "textBody": [{"partId": "1", "type": "text/plain", "size": 12, "blobId": "b1"}],
    "bodyValues": {
      "1": {"value": "hello world\n", "isEncodingProblem": false, "isTruncated": false}
    },
  }
  let res = emailFromJson(j)
  assertOk res
  let e = res.get()
  assertSome e.id
  assertEq e.textBody.len, 1
  assertEq e.bodyValues.len, 1
  assertNone e.bodyStructure

testCase fromJsonAttachmentsOnlyPartialShape: # scenario 17c — attachments-only shape
  ## Mirrors Phase D Step 21: ``properties = ["id", "attachments"]``.
  let j = %*{
    "id": "e3",
    "attachments": [
      {
        "partId": "2",
        "type": "application/octet-stream",
        "size": 32,
        "blobId": "b2",
        "disposition": "attachment",
        "name": "sentinel.dat",
      }
    ],
  }
  let res = emailFromJson(j)
  assertOk res
  let e = res.get()
  assertSome e.id
  assertEq e.attachments.len, 1
  assertNone e.bodyStructure
  assertNone e.mailboxIds

# ============= B. Email toJson (scenarios 18–23) =============

testCase toJsonOptNoneNull: # scenario 18
  let node = makeEmail().toJson()
  # All convenience headers are Opt.none in makeEmail(), so they emit as null
  const headerKeys = [
    "messageId", "inReplyTo", "references", "sender", "from", "to", "cc", "bcc",
    "replyTo", "subject", "sentAt",
  ]
  for key in headerKeys:
    doAssert node{key} != nil, key & " must be present"
    doAssert node{key}.kind == JNull, key & " must be null when Opt.none"

testCase toJsonFromAddrKey: # scenario 19
  var e = makeEmail()
  let ea = EmailAddress(name: Opt.none(string), email: "test@example.com")
  e.fromAddr = Opt.some(@[ea])
  let node = e.toJson()
  doAssert node{"from"} != nil, "\"from\" key must be present"
  doAssert node{"from"}.kind == JArray
  doAssert node{"fromAddr"}.isNil, "\"fromAddr\" key must not appear"

testCase toJsonRequestedHeaders: # scenario 20
  var e = makeEmail()
  let hpk = parseHeaderPropertyName("header:Subject:asText").get()
  let hv = HeaderValue(form: hfText, textValue: "Test Subject")
  e.requestedHeaders[hpk] = hv
  let node = e.toJson()
  doAssert node{"header:subject:asText"} != nil,
    "dynamic header key must appear as top-level key"

testCase toJsonRequestedHeadersAll: # scenario 21
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

testCase toJsonNoDynamicHeaders: # scenario 22
  let node = makeEmail().toJson()
  for key, _ in node.pairs:
    doAssert not key.startsWith("header:"),
      "no header: prefixed keys when tables are empty"

testCase toJsonEmptyCollections: # scenario 23
  let node = makeEmail().toJson()
  # Empty seq emits as []
  doAssert node{"textBody"} != nil and node{"textBody"}.kind == JArray
  assertLen node{"textBody"}.getElems(@[]), 0
  # Empty Table emits as {}
  doAssert node{"bodyValues"} != nil and node{"bodyValues"}.kind == JObject
  assertLen node{"bodyValues"}, 0

# ============= C. ParsedEmail (scenarios 24–33) =============

testCase parsedEmailThreadIdNull: # scenario 24
  var j = makeParsedEmailJson()
  j["threadId"] = newJNull()
  let res = parsedEmailFromJson(j)
  assertOk res
  assertNone res.get().threadId

testCase parsedEmailThreadIdPresent: # scenario 25
  var j = makeParsedEmailJson()
  j["threadId"] = %"t1"
  let res = parsedEmailFromJson(j)
  assertOk res
  assertSome res.get().threadId

testCase parsedEmailAbsentMetadata: # scenario 26
  let j = makeParsedEmailJson()
  # makeParsedEmailJson() has no metadata keys — should parse fine
  let res = parsedEmailFromJson(j)
  assertOk res

testCase parsedEmailFromKey: # scenario 27
  var j = makeParsedEmailJson()
  j["from"] = %*[{"name": nil, "email": "alice@test.com"}]
  let res = parsedEmailFromJson(j)
  assertOk res
  assertSome res.get().fromAddr
  assertEq res.get().fromAddr.get()[0].email, "alice@test.com"

testCase parsedEmailDynamicHeaders: # scenario 28
  var j = makeParsedEmailJson()
  j["header:Subject:asText"] = %"subj"
  j["header:From:asAddresses:all"] = %*[%*[{"name": nil, "email": "a@b"}]]
  let res = parsedEmailFromJson(j)
  assertOk res
  let pe = res.get()
  assertEq pe.requestedHeaders.len, 1
  assertEq pe.requestedHeadersAll.len, 1

testCase parsedEmailThreadIdWrongType: # scenario 29
  var j = makeParsedEmailJson()
  j["threadId"] = %42
  assertErr parsedEmailFromJson(j)

testCase parsedEmailExtraMetadataIgnored: # scenario 30
  var j = makeParsedEmailJson()
  j["id"] = %"extra-id"
  j["blobId"] = %"extra-blob"
  j["mailboxIds"] = %*{"mbx1": true}
  j["keywords"] = %*{"$seen": true}
  j["size"] = %100
  j["receivedAt"] = %"2025-01-15T09:00:00Z"
  let res = parsedEmailFromJson(j)
  assertOk res

testCase parsedEmailToJsonNoMetadata: # scenario 31
  let node = makeParsedEmail().toJson()
  const absentKeys = ["id", "blobId", "mailboxIds", "keywords", "size", "receivedAt"]
  for key in absentKeys:
    doAssert node{key}.isNil, key & " must not appear in ParsedEmail.toJson"
  # threadId DOES appear (as null for Opt.none)
  doAssert node{"threadId"} != nil, "threadId must be present"

testCase parsedEmailToJsonFromKey: # scenario 32
  var pe = makeParsedEmail()
  let ea = EmailAddress(name: Opt.none(string), email: "test@test.com")
  pe.fromAddr = Opt.some(@[ea])
  let node = pe.toJson()
  doAssert node{"from"} != nil, "\"from\" key must be present"
  doAssert node{"fromAddr"}.isNil, "\"fromAddr\" key must not appear"

testCase parsedEmailRoundTrip: # scenario 33
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

testCase comparatorToJsonPlain: # scenario 34
  let c = plainComparator(pspReceivedAt)
  let node = c.toJson()
  assertJsonFieldEq node, "property", %"receivedAt"

testCase comparatorToJsonKeyword: # scenario 35
  let c = keywordComparator(kspHasKeyword, kwFlagged)
  let node = c.toJson()
  assertJsonFieldEq node, "property", %"hasKeyword"
  assertJsonFieldEq node, "keyword", %"$flagged"

testCase comparatorToJsonOmitsOptionals: # scenario 36
  let c = plainComparator(pspSize)
  let node = c.toJson()
  doAssert node{"isAscending"}.isNil, "isAscending must be omitted when Opt.none"
  doAssert node{"collation"}.isNil, "collation must be omitted when Opt.none"

testCase comparatorToJsonAllKeys: # scenario 37
  let c = keywordComparator(
    kspHasKeyword, kwSeen, Opt.some(false), Opt.some(CollationUnicodeCasemap)
  )
  let node = c.toJson()
  assertLen node, 4
  assertJsonFieldEq node, "property", %"hasKeyword"
  assertJsonFieldEq node, "keyword", %"$seen"
  assertJsonFieldEq node, "isAscending", %false
  assertJsonFieldEq node, "collation", %"i;unicode-casemap"

testCase comparatorFromJsonPlain: # scenario 38
  let res = emailComparatorFromJson(%*{"property": "receivedAt"})
  assertOk res
  let c = res.get()
  assertEq c.kind, eckPlain
  assertEq c.property, pspReceivedAt

testCase comparatorFromJsonHasKeyword: # scenario 39
  let res = emailComparatorFromJson(%*{"property": "hasKeyword", "keyword": "$seen"})
  assertOk res
  let c = res.get()
  assertEq c.kind, eckKeyword
  assertEq c.keywordProperty, kspHasKeyword

testCase comparatorFromJsonAllInThread: # scenario 40
  let res = emailComparatorFromJson(
    %*{"property": "allInThreadHaveKeyword", "keyword": "$seen"}
  )
  assertOk res
  assertEq res.get().kind, eckKeyword
  assertEq res.get().keywordProperty, kspAllInThreadHaveKeyword

testCase comparatorFromJsonSomeInThread: # scenario 41
  let res = emailComparatorFromJson(
    %*{"property": "someInThreadHaveKeyword", "keyword": "$seen"}
  )
  assertOk res
  assertEq res.get().kind, eckKeyword
  assertEq res.get().keywordProperty, kspSomeInThreadHaveKeyword

testCase comparatorFromJsonKeywordMissing: # scenario 42
  assertErr emailComparatorFromJson(%*{"property": "hasKeyword"})

testCase comparatorFromJsonUnknownProp: # scenario 43
  assertErr emailComparatorFromJson(%*{"property": "unknownSort"})

testCase comparatorFromJsonIsAscending: # scenario 44
  let res = emailComparatorFromJson(%*{"property": "size", "isAscending": false})
  assertOk res
  assertSomeEq res.get().isAscending, false

testCase comparatorFromJsonCollation: # scenario 45
  let res =
    emailComparatorFromJson(%*{"property": "size", "collation": "i;unicode-casemap"})
  assertOk res
  assertSomeEq res.get().collation, CollationUnicodeCasemap

# ============= F. EmailBodyFetchOptions.toJson tests =============

testCase toJsonDefault:
  ## toJson on default(EmailBodyFetchOptions) produces an empty JObject.
  doAssert default(EmailBodyFetchOptions).toJson().len == 0

testCase toJsonText:
  ## toJson with bvsText emits a single fetchTextBodyValues=true key.
  let opts = EmailBodyFetchOptions(fetchBodyValues: bvsText)
  let node = opts.toJson()
  doAssert node.len == 1
  doAssert node{"fetchTextBodyValues"}.getBool(false) == true

testCase toJsonHtml:
  ## toJson with bvsHtml emits a single fetchHTMLBodyValues=true key.
  let opts = EmailBodyFetchOptions(fetchBodyValues: bvsHtml)
  let node = opts.toJson()
  doAssert node.len == 1
  doAssert node{"fetchHTMLBodyValues"}.getBool(false) == true

testCase toJsonTextAndHtml:
  ## toJson with bvsTextAndHtml emits both fetchTextBodyValues and
  ## fetchHTMLBodyValues in text-then-HTML insertion order.
  let opts = EmailBodyFetchOptions(fetchBodyValues: bvsTextAndHtml)
  let node = opts.toJson()
  doAssert node.len == 2
  doAssert node{"fetchTextBodyValues"}.getBool(false) == true
  doAssert node{"fetchHTMLBodyValues"}.getBool(false) == true

testCase toJsonAll:
  ## toJson with bvsAll emits a single fetchAllBodyValues=true key.
  let opts = EmailBodyFetchOptions(fetchBodyValues: bvsAll)
  let node = opts.toJson()
  doAssert node.len == 1
  doAssert node{"fetchAllBodyValues"}.getBool(false) == true
