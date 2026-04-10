# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Adversarial serde tests for Email, ParsedEmail, EmailComparator,
## EmailFilterCondition, and response types (section 12.11, scenarios 91-123).
## Uses ``unsafeError`` for ``Result[Email, ...]`` and
## ``Result[ParsedEmail, ...]`` because ``$Email`` triggers side effects
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
import jmap_client/mail/snippet
import jmap_client/mail/mail_filters
import jmap_client/mail/mail_methods
import jmap_client/mail/serde_email
import jmap_client/mail/serde_snippet
import jmap_client/mail/serde_mail_filters
import jmap_client/validation
import jmap_client/primitives

import ../../massertions
import ../../mfixtures

# =============================================================================
# A. Two-Phase Boundary (scenarios 91–92)
# =============================================================================

block twoPhaseFromCoexist: # scenario 91
  ## Phase 1 routes "from" to fromAddr; Phase 2 routes "header:From:asAddresses"
  ## to requestedHeaders. Both coexist.
  var j = makeEmailJson()
  j["from"] = %*[{"name": "Alice", "email": "alice@test.com"}]
  j["header:From:asAddresses"] = %*[{"name": nil, "email": "bob@test.com"}]
  let res = emailFromJson(j)
  assertOk res
  let e = res.get()
  assertSome e.fromAddr
  assertEq e.fromAddr.get()[0].email, "alice@test.com"
  assertEq e.requestedHeaders.len, 1

block twoPhaseStress100Headers: # scenario 92
  ## 100 dynamic header keys all routed via Phase 2 iteration.
  var j = makeEmailJson()
  for i in 0 ..< 100:
    j["header:X-Custom-" & $i & ":asText"] = %("value" & $i)
  let res = emailFromJson(j)
  assertOk res
  assertEq res.get().requestedHeaders.len, 100

# =============================================================================
# B. Dynamic Header Injection (scenarios 93–96)
# =============================================================================

block headerEmptyName: # scenario 93
  ## "header:" with empty name after prefix -> err.
  var j = makeEmailJson()
  j["header:"] = %"test"
  let res = emailFromJson(j)
  doAssert res.isErr, "expected Err for empty header name"
  doAssert res.unsafeError.message.contains("empty header name"),
    "error must mention empty header name"

block headerTooManySegments: # scenario 94
  ## 5 colon-separated segments -> err.
  var j = makeEmailJson()
  j["header:From:asAddresses:all:extra"] = %"test"
  let res = emailFromJson(j)
  doAssert res.isErr, "expected Err for too many segments"
  doAssert res.unsafeError.message.contains("too many segments"),
    "error must mention too many segments"

block headerInvalidForm: # scenario 95
  ## Unknown form suffix -> err.
  var j = makeEmailJson()
  j["header:From:asUnknown"] = %"test"
  let res = emailFromJson(j)
  doAssert res.isErr, "expected Err for unknown form"
  doAssert res.unsafeError.message.contains("unknown header form suffix"),
    "error must mention unknown header form suffix"

block headerKeyWithoutColon: # scenario 96
  ## Key "header" (no colon) does not start with "header:" — ignored.
  var j = makeEmailJson()
  j["header"] = %"test"
  let res = emailFromJson(j)
  assertOk res

# =============================================================================
# C. EmailComparator Discriminant (scenarios 97–103)
# =============================================================================

block comparatorUnderscoreProperty: # scenario 97
  ## Underscore variant "received_At" does not match "receivedAt".
  assertErr emailComparatorFromJson(%*{"property": "received_At"})

block comparatorWrongCase: # scenario 98
  ## All-caps "RECEIVERAT" does not match "receivedAt".
  assertErr emailComparatorFromJson(%*{"property": "RECEIVERAT"})

block comparatorLeadingSpace: # scenario 99
  ## Leading space " receivedAt" does not match "receivedAt".
  assertErr emailComparatorFromJson(%*{"property": " receivedAt"})

block comparatorEmptyKeyword: # scenario 100
  ## Empty keyword string fails server-assigned token validation.
  let res = emailComparatorFromJson(%*{"property": "hasKeyword", "keyword": ""})
  assertErrContains res, "length must be 1-255"

block comparatorPlainSpuriousKeyword: # scenario 101
  ## Keyword field ignored when property is a plain sort property.
  let res = emailComparatorFromJson(%*{"property": "receivedAt", "keyword": "$seen"})
  assertOk res
  assertEq res.get().kind, eckPlain
  assertEq res.get().property, pspReceivedAt

block comparatorMissingProperty: # scenario 102
  ## No property key at all -> err.
  assertErr emailComparatorFromJson(%*{"isAscending": true})

block comparatorPropertyNull: # scenario 103
  ## property: null (JNull != JString) -> err.
  assertErr emailComparatorFromJson(%*{"property": nil})

# =============================================================================
# D. EmailHeaderFilter (scenarios 104–106)
# =============================================================================

block headerFilterColonInName: # scenario 104
  ## Colon within header name is accepted (only empty rejected).
  let res = parseEmailHeaderFilter("Sub:ject")
  assertOk res
  assertEq res.get().name, "Sub:ject"

block headerFilterNulByte: # scenario 105
  ## NUL byte in header name is accepted (only empty rejected).
  let res = parseEmailHeaderFilter("Sub\x00ject")
  assertOk res
  assertEq res.get().name, "Sub\x00ject"

block filterHeaderEmptyValue: # scenario 106
  ## Empty value string emits 2-element array ["Name", ""], distinct from
  ## 1-element ["Name"] (value absent).
  let withValue = parseEmailHeaderFilter("Subject", Opt.some("")).get()
  let withoutValue = parseEmailHeaderFilter("Subject").get()
  let jWith = withValue.toJson()
  let jWithout = withoutValue.toJson()
  assertEq jWith.len, 2
  assertEq jWith[1].getStr("x"), ""
  assertEq jWithout.len, 1

# =============================================================================
# E. Table[PartId, EmailBodyValue] (scenarios 107–108)
# =============================================================================

block bodyValuesDuplicatePartId: # scenario 107
  ## Duplicate key "1" in bodyValues JSON — last-wins (std/json OrderedTable).
  var j = makeEmailJson()
  let bv = parseJson(
    """{"1": {"value": "first", "isEncodingProblem": false, "isTruncated": false}, "1": {"value": "second", "isEncodingProblem": false, "isTruncated": false}}"""
  )
  j["bodyValues"] = bv
  let res = emailFromJson(j)
  assertOk res
  let pid = parsePartIdFromServer("1").get()
  assertEq res.get().bodyValues[pid].value, "second"

block bodyValuesEmptyPartId: # scenario 108
  ## Empty string as PartId key -> err (parsePartIdFromServer rejects).
  var j = makeEmailJson()
  j["bodyValues"] =
    %*{"": {"value": "test", "isEncodingProblem": false, "isTruncated": false}}
  let res = emailFromJson(j)
  doAssert res.isErr, "expected Err for empty PartId"
  doAssert res.unsafeError.message.contains("must not be empty"),
    "error must mention empty PartId"

# =============================================================================
# F. EmailFilterCondition Structural (scenarios 109–110)
# =============================================================================

block filterContradictorySize: # scenario 109
  ## minSize=0 and maxSize=0 both emitted — no semantic validation.
  var fc = makeEmailFilterCondition()
  fc.minSize = Opt.some(parseUnsignedInt(0).get())
  fc.maxSize = Opt.some(parseUnsignedInt(0).get())
  let node = fc.toJson()
  doAssert node{"minSize"} != nil, "minSize must be present"
  doAssert node{"maxSize"} != nil, "maxSize must be present"
  assertJsonFieldEq node, "minSize", %0
  assertJsonFieldEq node, "maxSize", %0

block filterHeaderColonPreserved: # scenario 110
  ## Colon within header name preserved verbatim in serialised JSON array.
  let ehf = parseEmailHeaderFilter("Content:Type").get()
  var fc = makeEmailFilterCondition()
  fc.header = Opt.some(ehf)
  let node = fc.toJson()
  doAssert node{"header"} != nil, "header must be present"
  assertEq node["header"][0].getStr(""), "Content:Type"

# =============================================================================
# G. Response Types (scenarios 111–114)
# =============================================================================

block snippetGetResponseListNull: # scenario 111
  ## list: null — implementation is lenient (ok with empty list), not err.
  let j = %*{"accountId": "acct1", "list": nil, "notFound": []}
  let res = searchSnippetGetResponseFromJson(j)
  assertOk res
  assertLen res.get().list, 0

block snippetXssInSubject: # scenario 112
  ## HTML in subject preserved verbatim — no sanitisation at serde layer.
  let j = %*{"emailId": "e1", "subject": "<script>alert(1)</script>", "preview": nil}
  let res = searchSnippetFromJson(j)
  assertOk res
  assertSomeEq res.get().subject, "<script>alert(1)</script>"

block snippetExtraFieldIgnored: # scenario 113
  ## Extra unknown field preserved under Postel's law.
  let j = %*{"emailId": "e1", "subject": nil, "preview": nil, "unknownField": 42}
  let res = searchSnippetFromJson(j)
  assertOk res

block emailAllWrongTypes: # scenario 114
  ## All required metadata fields set to wrong JSON types — err on first failure.
  let j = %*{
    "id": 42,
    "blobId": 42,
    "threadId": 42,
    "mailboxIds": "not-object",
    "keywords": "not-object",
    "size": "not-int",
    "receivedAt": 42,
    "bodyStructure": "not-object",
    "bodyValues": "not-object",
    "textBody": "not-array",
    "htmlBody": "not-array",
    "attachments": "not-array",
    "hasAttachment": "not-bool",
    "preview": 42,
    "headers": "not-array",
    "messageId": 42,
    "inReplyTo": 42,
    "references": 42,
    "sender": 42,
    "from": 42,
    "to": 42,
    "cc": 42,
    "bcc": 42,
    "replyTo": 42,
    "subject": 42,
    "sentAt": 42,
  }
  let res = emailFromJson(j)
  doAssert res.isErr, "expected Err for all wrong types"

# =============================================================================
# H. Recursive/Resource (scenarios 115–117)
# =============================================================================

block deepNestedBody50: # scenario 115
  ## 50-level nested multipart body — within MaxBodyPartDepth=128.
  var j = makeEmailJson()
  var body =
    %*{"type": "text/plain", "partId": "1", "blobId": "b1", "size": 0, "headers": []}
  for i in 0 ..< 50:
    body = %*{"type": "multipart/mixed", "subParts": [body], "size": 0, "headers": []}
  j["bodyStructure"] = body
  let res = emailFromJson(j)
  assertOk res

block cyrillicHomoglyphHeader: # scenario 116
  ## U+04BB (Cyrillic SHHA, UTF-8: \xD2\xBB) looks like 'h' but fails
  ## byte-level startsWith("header:"). Only the real key is routed.
  var j = makeEmailJson()
  j["\xD2\xBBeader:Subject:asText"] = %"fake"
  j["header:Subject:asText"] = %"real"
  let res = emailFromJson(j)
  assertOk res
  assertEq res.get().requestedHeaders.len, 1

block maxUnsignedIntSize: # scenario 117
  ## size = 2^53-1 (max safe JSON integer) — parses successfully.
  var j = makeEmailJson()
  j["size"] = newJInt(9007199254740991'i64)
  let res = emailFromJson(j)
  assertOk res
  assertEq int64(res.get().size), 9007199254740991'i64

# =============================================================================
# I. Cross-Field Semantic (scenarios 118–123)
# =============================================================================

block sameHeaderDifferentForms: # scenario 118
  ## Same header name with different forms — both routed as separate entries
  ## because form is part of HeaderPropertyKey identity.
  var j = makeEmailJson()
  j["header:From:asText"] = %"Alice <alice@test.com>"
  j["header:From:asAddresses"] = %*[{"name": "Alice", "email": "alice@test.com"}]
  let res = emailFromJson(j)
  assertOk res
  assertEq res.get().requestedHeaders.len, 2

block bodyValueAllFlagsTrue: # scenario 119
  ## isTruncated=true and isEncodingProblem=true are not mutually exclusive.
  var j = makeEmailJson()
  j["bodyValues"] =
    %*{"1": {"value": "", "isEncodingProblem": true, "isTruncated": true}}
  let res = emailFromJson(j)
  assertOk res
  let pid = parsePartIdFromServer("1").get()
  let bv = res.get().bodyValues[pid]
  doAssert bv.isTruncated, "isTruncated must be true"
  doAssert bv.isEncodingProblem, "isEncodingProblem must be true"

block keywordDraftNonDraftMailbox: # scenario 120
  ## $draft keyword with non-Draft mailbox — no cross-field validation.
  var j = makeEmailJson()
  j["keywords"] = %*{"$draft": true}
  j["mailboxIds"] = %*{"inbox1": true}
  let res = emailFromJson(j)
  assertOk res
  doAssert kwDraft in res.get().keywords, "$draft must be in keywords"

block hasAttachmentFalseWithAttachments: # scenario 121
  ## hasAttachment=false with non-empty attachments — contradiction preserved.
  var j = makeEmailJson()
  j["hasAttachment"] = %false
  j["attachments"] = %*[
    {"type": "image/png", "partId": "att1", "blobId": "b2", "size": 1024, "headers": []}
  ]
  let res = emailFromJson(j)
  assertOk res
  let e = res.get()
  doAssert not e.hasAttachment, "hasAttachment must be false"
  assertGe e.attachments.len, 1

block filterBeforeAfterContradiction: # scenario 122
  ## before < after (impossible range) — both emitted, no temporal validation.
  var fc = makeEmailFilterCondition()
  let early = parseUtcDate("2020-01-01T00:00:00Z").get()
  let late = parseUtcDate("2025-12-31T23:59:59Z").get()
  fc.before = Opt.some(early)
  fc.after = Opt.some(late)
  let node = fc.toJson()
  doAssert node{"before"} != nil, "before must be present"
  doAssert node{"after"} != nil, "after must be present"

block snippetDanglingEmailId: # scenario 123
  ## Snippet with emailId not in any result set — no referential integrity check.
  let j = %*{"emailId": "nonExistentEmailId999", "subject": "orphan", "preview": nil}
  let res = searchSnippetFromJson(j)
  assertOk res
  assertEq string(res.get().emailId), "nonExistentEmailId999"
