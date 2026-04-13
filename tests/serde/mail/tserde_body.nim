# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for body sub-types (scenarios 77–131, 97a–99d, 102a, 108c,
## 115a, 118a–118b, 127a, 130a, A1–A4, A6). Scenarios 130b (form
## mismatch) and A5 (CTE in extraHeaders) retired with Part E §5.2:
## both are structurally unreachable; CTE-rejection moved to
## theaders_blueprint.nim.

import std/json
import std/strutils
import std/tables

import jmap_client/mail/body
import jmap_client/mail/serde_body
import jmap_client/mail/headers
import jmap_client/validation
import jmap_client/primitives

import ../../massertions

# ============= A. EmailBodyPart.fromJson basic (scenarios 77–82) =============

block fromJsonLeafPart: # scenario 77
  let node = %*{
    "type": "text/plain",
    "partId": "1",
    "blobId": "abc123",
    "size": 100,
    "charset": "utf-8",
  }
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  let part = res.get()
  assertEq part.isMultipart, false
  assertEq part.contentType, "text/plain"
  assertEq part.partId, PartId("1")
  assertEq part.blobId, Id("abc123")
  assertSomeEq part.charset, "utf-8"

block fromJsonMultipart: # scenario 78
  let node = %*{
    "type": "multipart/mixed",
    "subParts": [{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 100}],
  }
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  assertEq res.get().isMultipart, true
  assertLen res.get().subParts, 1

block fromJsonMultipartAbsentSubParts: # scenario 79
  let node = %*{"type": "multipart/mixed"}
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  assertLen res.get().subParts, 0

block fromJsonLeafAbsentPartId: # scenario 80
  assertErr EmailBodyPart.fromJson(%*{"type": "text/plain", "blobId": "abc", "size": 1})

block fromJsonLeafAbsentBlobId: # scenario 81
  assertErr EmailBodyPart.fromJson(%*{"type": "text/plain", "partId": "1", "size": 1})

block isMultipartFromContentType: # scenario 82
  # text/plain with subParts key present is still a leaf
  let node = %*{
    "type": "text/plain",
    "partId": "1",
    "blobId": "abc",
    "size": 100,
    "subParts": [{"type": "text/html", "partId": "2", "blobId": "def", "size": 50}],
  }
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  assertEq res.get().isMultipart, false

# ============= B. Size handling (scenarios 83–84) =============

block sizeRequiredOnLeaf: # scenario 83
  assertErr EmailBodyPart.fromJson(
    %*{"type": "text/plain", "partId": "1", "blobId": "abc"}
  )

block sizeDefaultOnMultipart: # scenario 84
  let res = EmailBodyPart.fromJson(%*{"type": "multipart/mixed"})
  assertOk res
  assertEq res.get().size, UnsignedInt(0)

# ============= C. Charset defaults (scenarios 85–90) =============

block charsetAbsentTextPlain: # scenario 85
  let node = %*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 1}
  assertSomeEq EmailBodyPart.fromJson(node).get().charset, "us-ascii"

block charsetPresentTextPlain: # scenario 86
  let node = %*{
    "type": "text/plain", "partId": "1", "blobId": "abc", "size": 1, "charset": "utf-8"
  }
  assertSomeEq EmailBodyPart.fromJson(node).get().charset, "utf-8"

block charsetNullTextHtml: # scenario 87
  let node =
    %*{"type": "text/html", "partId": "1", "blobId": "abc", "size": 1, "charset": nil}
  assertSomeEq EmailBodyPart.fromJson(node).get().charset, "us-ascii"

block charsetAbsentImagePng: # scenario 88
  let node = %*{"type": "image/png", "partId": "1", "blobId": "abc", "size": 1}
  assertNone EmailBodyPart.fromJson(node).get().charset

block charsetAbsentMultipart: # scenario 89
  let node = %*{"type": "multipart/mixed"}
  assertNone EmailBodyPart.fromJson(node).get().charset

block charsetPresentImagePng: # scenario 90
  let node = %*{
    "type": "image/png", "partId": "1", "blobId": "abc", "size": 1, "charset": "binary"
  }
  assertSomeEq EmailBodyPart.fromJson(node).get().charset, "binary"

# ============= D. Headers (scenarios 91–92) =============

block headersAbsent: # scenario 91
  let node = %*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 1}
  assertLen EmailBodyPart.fromJson(node).get().headers, 0

block headersPresent: # scenario 92
  let node = %*{
    "type": "text/plain",
    "partId": "1",
    "blobId": "abc",
    "size": 1,
    "headers": [{"name": "Content-Type", "value": "text/plain; charset=utf-8"}],
  }
  let part = EmailBodyPart.fromJson(node).get()
  assertLen part.headers, 1
  assertEq part.headers[0].name, "Content-Type"

# ============= E. Depth limit (scenarios 93, 104) =============

block depthLimit129: # scenario 93
  # 128 multipart wrappers + 1 leaf = 129 parse calls → err
  var node = %*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 1}
  for i in 0 ..< 128:
    node = %*{"type": "multipart/mixed", "subParts": [node]}
  assertErr EmailBodyPart.fromJson(node)

block depthLimitExact128: # scenario 104
  # 127 multipart wrappers + 1 leaf = 128 parse calls → ok
  var node = %*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 1}
  for i in 0 ..< 127:
    node = %*{"type": "multipart/mixed", "subParts": [node]}
  assertOk EmailBodyPart.fromJson(node)

# ============= F. Round-trips (scenarios 94–95) =============

block roundTripLeaf: # scenario 94
  let node = %*{
    "type": "text/plain",
    "partId": "1",
    "blobId": "abc",
    "size": 1234,
    "charset": "utf-8",
    "disposition": "inline",
    "name": "file.txt",
    "cid": "cid123",
    "language": ["en", "fr"],
    "location": "https://example.com",
    "headers": [{"name": "X-Custom", "value": "val"}],
  }
  let part = EmailBodyPart.fromJson(node).get()
  let rt = EmailBodyPart.fromJson(part.toJson()).get()
  assertEq rt.contentType, part.contentType
  assertEq rt.partId, part.partId
  assertEq rt.blobId, part.blobId
  assertEq rt.size, part.size
  assertEq rt.isMultipart, false
  assertLen rt.headers, 1
  assertEq rt.headers[0].name, "X-Custom"
  # Opt fields
  assertSomeEq rt.charset, "utf-8"
  assertSomeEq rt.disposition, "inline"
  assertSomeEq rt.name, "file.txt"
  assertSomeEq rt.cid, "cid123"
  assertSome rt.language
  assertSomeEq rt.location, "https://example.com"

block roundTripMultipart: # scenario 95
  let node = %*{
    "type": "multipart/mixed",
    "size": 5000,
    "subParts": [
      {"type": "text/plain", "partId": "1", "blobId": "a", "size": 100},
      {"type": "image/png", "partId": "2", "blobId": "b", "size": 4900},
    ],
  }
  let part = EmailBodyPart.fromJson(node).get()
  let rt = EmailBodyPart.fromJson(part.toJson()).get()
  assertEq rt.isMultipart, true
  assertLen rt.subParts, 2
  assertEq rt.subParts[0].partId, PartId("1")
  assertEq rt.subParts[1].partId, PartId("2")

# ============= G. toJson depth (scenarios 96, 108) =============

block toJsonDepthStress: # scenario 96
  # Build a deeply nested structure and verify toJson doesn't crash
  var part = EmailBodyPart(
    headers: @[],
    name: Opt.none(string),
    contentType: "text/plain",
    charset: Opt.none(string),
    disposition: Opt.none(string),
    cid: Opt.none(string),
    language: Opt.none(seq[string]),
    location: Opt.none(string),
    size: UnsignedInt(0),
    isMultipart: false,
    partId: PartId("1"),
    blobId: Id("abc"),
  )
  for i in 0 ..< 200:
    part = EmailBodyPart(
      headers: @[],
      name: Opt.none(string),
      contentType: "multipart/mixed",
      charset: Opt.none(string),
      disposition: Opt.none(string),
      cid: Opt.none(string),
      language: Opt.none(seq[string]),
      location: Opt.none(string),
      size: UnsignedInt(0),
      isMultipart: true,
      subParts: @[part],
    )
  let node = part.toJson()
  doAssert node.kind == JObject

block toJsonDepthExact128: # scenario 108
  var part = EmailBodyPart(
    headers: @[],
    name: Opt.none(string),
    contentType: "text/plain",
    charset: Opt.none(string),
    disposition: Opt.none(string),
    cid: Opt.none(string),
    language: Opt.none(seq[string]),
    location: Opt.none(string),
    size: UnsignedInt(0),
    isMultipart: false,
    partId: PartId("1"),
    blobId: Id("abc"),
  )
  for i in 0 ..< 127:
    part = EmailBodyPart(
      headers: @[],
      name: Opt.none(string),
      contentType: "multipart/mixed",
      charset: Opt.none(string),
      disposition: Opt.none(string),
      cid: Opt.none(string),
      language: Opt.none(seq[string]),
      location: Opt.none(string),
      size: UnsignedInt(0),
      isMultipart: true,
      subParts: @[part],
    )
  let node = part.toJson()
  # Verify the leaf is fully serialised (has partId)
  var cursor = node
  for i in 0 ..< 127:
    cursor = cursor{"subParts"}{0}
  doAssert cursor{"partId"} != nil

# ============= H. ContentType edge cases (scenarios 97, 97a–97b, 98–99, 99a–99d, 108c) =============

block absentContentType: # scenario 97
  assertErr EmailBodyPart.fromJson(%*{"partId": "1", "blobId": "abc", "size": 1})

block nonObjectInput: # scenario 97a
  assertErr EmailBodyPart.fromJson(%*[1, 2, 3])
  assertErr EmailBodyPart.fromJson(newJNull())
  assertErr EmailBodyPart.fromJson(%"string")

block typeWrongKind: # scenario 97b
  assertErr EmailBodyPart.fromJson(
    %*{"type": 42, "partId": "1", "blobId": "abc", "size": 1}
  )

block uppercaseMultipart: # scenario 98
  let node = %*{
    "type": "MULTIPART/MIXED",
    "subParts": [{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 1}],
  }
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  assertEq res.get().isMultipart, true

block charsetDefaultUppercaseText: # scenario 98a
  let node = %*{"type": "TEXT/PLAIN", "partId": "1", "blobId": "abc", "size": 1}
  assertSomeEq EmailBodyPart.fromJson(node).get().charset, "us-ascii"

block multipartSlashOnly: # scenario 99
  let res = EmailBodyPart.fromJson(%*{"type": "multipart/"})
  assertOk res
  assertEq res.get().isMultipart, true

block textSlashCharsetDefault: # scenario 99a
  let node = %*{"type": "text/", "partId": "1", "blobId": "abc", "size": 1}
  assertSomeEq EmailBodyPart.fromJson(node).get().charset, "us-ascii"

block textplainNoSlash: # scenario 99b
  # "textplain" does not start with "multipart/" → leaf
  assertErr EmailBodyPart.fromJson(%*{"type": "textplain"})
  # Requires partId/blobId since it's a leaf

block multipartNoTrailingSlash: # scenario 99c
  # "multipart" does not start with "multipart/" → not multipart
  assertErr EmailBodyPart.fromJson(%*{"type": "multipart"})

block emptyContentType: # scenario 99d
  # Empty string: not multipart, not text/* → leaf
  assertErr EmailBodyPart.fromJson(%*{"type": ""})
  # Requires partId/blobId since it's a leaf

block duplicateTypeKey: # scenario 108c
  # std/json last-wins: second "type" value overrides first
  const raw = """{"type": "text/plain", "type": "multipart/mixed"}"""
  let node = parseJson(raw)
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  assertEq res.get().isMultipart, true
  assertLen res.get().subParts, 0

# ============= I. Field validation edge cases (scenarios 100–107) =============

block leafWithSubPartsIgnored: # scenario 100
  let node = %*{
    "type": "text/plain",
    "partId": "1",
    "blobId": "abc",
    "size": 1,
    "subParts": [{"type": "text/html", "partId": "2", "blobId": "def", "size": 1}],
  }
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  assertEq res.get().isMultipart, false

block multipartWithPartIdBlobIdIgnored: # scenario 101
  let node = %*{
    "type": "multipart/mixed",
    "partId": "1",
    "blobId": "abc",
    "subParts": [{"type": "text/plain", "partId": "2", "blobId": "def", "size": 1}],
  }
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  assertEq res.get().isMultipart, true

block nullInHeadersArray: # scenario 102
  let node = %*{
    "type": "text/plain", "partId": "1", "blobId": "abc", "size": 1, "headers": [nil]
  }
  assertErr EmailBodyPart.fromJson(node)

block nonStringInLanguageArray: # scenario 102a
  let node = %*{
    "type": "text/plain", "partId": "1", "blobId": "abc", "size": 1, "language": [42]
  }
  assertErr EmailBodyPart.fromJson(node)

block nullInSubPartsArray: # scenario 103
  let node = %*{"type": "multipart/mixed", "subParts": [nil]}
  assertErr EmailBodyPart.fromJson(node)

block emptyCharsetString: # scenario 105
  let node =
    %*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 1, "charset": ""}
  assertSomeEq EmailBodyPart.fromJson(node).get().charset, ""

block sizeNegative: # scenario 106
  let node = %*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": -1}
  assertErr EmailBodyPart.fromJson(node)

block sizeExceeding: # scenario 107
  let node =
    %*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 9007199254740992}
  assertErr EmailBodyPart.fromJson(node)

# ============= J. EmailBodyValue serde (scenarios 109–118, 115a, 118a–118b) =============

block bodyValueAllFields: # scenario 109
  let node = %*{"value": "Hello", "isEncodingProblem": false, "isTruncated": false}
  let res = EmailBodyValue.fromJson(node)
  assertOk res
  let bv = res.get()
  assertEq bv.value, "Hello"
  assertEq bv.isEncodingProblem, false
  assertEq bv.isTruncated, false

block bodyValueEncodingProblem: # scenario 110
  let node = %*{"value": "Hello", "isEncodingProblem": true}
  assertEq EmailBodyValue.fromJson(node).get().isEncodingProblem, true

block bodyValueTruncated: # scenario 111
  let node = %*{"value": "Hello", "isTruncated": true}
  assertEq EmailBodyValue.fromJson(node).get().isTruncated, true

block bodyValueBothFlags: # scenario 112
  let node = %*{"value": "Hello", "isEncodingProblem": true, "isTruncated": true}
  let bv = EmailBodyValue.fromJson(node).get()
  assertEq bv.isEncodingProblem, true
  assertEq bv.isTruncated, true

block bodyValueFlagsDefault: # scenario 113
  let node = %*{"value": "Hello"}
  let bv = EmailBodyValue.fromJson(node).get()
  assertEq bv.isEncodingProblem, false
  assertEq bv.isTruncated, false

block bodyValueRoundTrip: # scenario 114
  let original =
    EmailBodyValue(value: "Hello", isEncodingProblem: true, isTruncated: false)
  let rt = EmailBodyValue.fromJson(original.toJson()).get()
  assertEq rt.value, original.value
  assertEq rt.isEncodingProblem, original.isEncodingProblem
  assertEq rt.isTruncated, original.isTruncated

block bodyValueAbsentValue: # scenario 115
  assertErr EmailBodyValue.fromJson(%*{"isEncodingProblem": false})

block bodyValueNonObject: # scenario 115a
  assertErr EmailBodyValue.fromJson(%*[1, 2])
  assertErr EmailBodyValue.fromJson(newJNull())

block bodyValueNullValue: # scenario 116
  assertErr EmailBodyValue.fromJson(%*{"value": nil})

block bodyValueWrongKindValue: # scenario 117
  assertErr EmailBodyValue.fromJson(%*{"value": 42})

block bodyValueWrongKindFlags: # scenario 118
  assertErr EmailBodyValue.fromJson(%*{"value": "Hi", "isEncodingProblem": "true"})
  assertErr EmailBodyValue.fromJson(%*{"value": "Hi", "isTruncated": "true"})

block bodyValueEmptyValue: # scenario 118a
  let bv = EmailBodyValue.fromJson(%*{"value": ""}).get()
  assertEq bv.value, ""

block bodyValueNullFlag: # scenario 118b
  # null for bool flag treated as absent → default false
  let node = %*{"value": "Hi", "isEncodingProblem": nil}
  let bv = EmailBodyValue.fromJson(node).get()
  assertEq bv.isEncodingProblem, false

# ============= K. BlueprintBodyPart.toJson (scenarios 119–131, 125, 127a, 130a–130b) =============

block bpInlineLeaf: # scenario 119
  let bp = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    source: bpsInline,
    partId: PartId("1"),
    value: BlueprintBodyValue(value: ""),
  )
  let node = bp.toJson()
  assertJsonFieldEq node, "type", %"text/plain"
  assertJsonFieldEq node, "partId", %"1"
  # blobId, charset, size must be absent
  doAssert node{"blobId"} == nil, "blobId should be absent on inline leaf"
  doAssert node{"charset"} == nil, "charset should be absent on inline leaf"
  doAssert node{"size"} == nil, "size should be absent on inline leaf"

block bpBlobRefLeaf: # scenario 120
  let bp = BlueprintBodyPart(
    contentType: "image/png",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    source: bpsBlobRef,
    blobId: Id("abc123"),
    size: Opt.some(UnsignedInt(5678)),
    charset: Opt.some("utf-8"),
  )
  let node = bp.toJson()
  assertJsonFieldEq node, "type", %"image/png"
  assertJsonFieldEq node, "blobId", %"abc123"

block bpBlobRefBothPresent: # scenario 121
  let bp = BlueprintBodyPart(
    contentType: "image/png",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    source: bpsBlobRef,
    blobId: Id("abc"),
    size: Opt.some(UnsignedInt(100)),
    charset: Opt.some("binary"),
  )
  let node = bp.toJson()
  doAssert node{"charset"} != nil
  doAssert node{"size"} != nil

block bpBlobRefBothAbsent: # scenario 122
  let bp = BlueprintBodyPart(
    contentType: "image/png",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    source: bpsBlobRef,
    blobId: Id("abc"),
    size: Opt.none(UnsignedInt),
    charset: Opt.none(string),
  )
  let node = bp.toJson()
  doAssert node{"charset"} == nil, "charset should be absent"
  doAssert node{"size"} == nil, "size should be absent"

block bpMultipart: # scenario 123
  let child = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    source: bpsInline,
    partId: PartId("1"),
    value: BlueprintBodyValue(value: ""),
  )
  let bp = BlueprintBodyPart(
    contentType: "multipart/mixed",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: true,
    subParts: @[child],
  )
  let node = bp.toJson()
  assertJsonFieldEq node, "type", %"multipart/mixed"
  doAssert node{"subParts"} != nil
  doAssert node{"subParts"}.kind == JArray
  assertLen node{"subParts"}.getElems(@[]), 1

block bpDepthLimit: # scenario 124
  var bp = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    source: bpsInline,
    partId: PartId("1"),
    value: BlueprintBodyValue(value: ""),
  )
  for i in 0 ..< 200:
    bp = BlueprintBodyPart(
      contentType: "multipart/mixed",
      extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
      isMultipart: true,
      subParts: @[bp],
    )
  let node = bp.toJson()
  doAssert node.kind == JObject

block bpNoFromJson: # scenario 125
  assertNotCompiles(BlueprintBodyPart.fromJson(%*{}))

block bpInlineKeyAbsence: # scenario 126
  let bp = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    source: bpsInline,
    partId: PartId("1"),
    value: BlueprintBodyValue(value: ""),
  )
  let node = bp.toJson()
  # Keys must be absent (not null, not present)
  doAssert "blobId" notin node
  doAssert "charset" notin node
  doAssert "size" notin node

block bpExtraHeaders: # scenario 127
  let name = parseBlueprintBodyHeaderName("x-custom").get()
  var headers = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  headers[name] = textSingle("custom value")
  let bp = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: headers,
    isMultipart: false,
    source: bpsInline,
    partId: PartId("1"),
    value: BlueprintBodyValue(value: ""),
  )
  let node = bp.toJson()
  doAssert node{"header:x-custom:asText"} != nil
  assertEq node{"header:x-custom:asText"}, %"custom value"

block bpExtraHeadersHfRaw: # scenario 127a
  # hfRaw form suffix is omitted by composeBodyHeaderKey.
  let name = parseBlueprintBodyHeaderName("x-custom").get()
  var headers = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  headers[name] = rawSingle("raw value")
  let bp = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: headers,
    isMultipart: false,
    source: bpsInline,
    partId: PartId("1"),
    value: BlueprintBodyValue(value: ""),
  )
  let node = bp.toJson()
  # Key should be "header:x-custom" (no ":asRaw" — hfRaw suppressed).
  doAssert node{"header:x-custom"} != nil
  assertEq node{"header:x-custom"}, %"raw value"

block bpEmptyExtraHeaders: # scenario 128
  let bp = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    source: bpsInline,
    partId: PartId("1"),
    value: BlueprintBodyValue(value: ""),
  )
  let node = bp.toJson()
  # Only standard keys should be present
  for key, _ in node.pairs:
    doAssert key.startsWith("header:") == false, "no header properties expected"

block bpMultipartEmptySubParts: # scenario 129
  let bp = BlueprintBodyPart(
    contentType: "multipart/mixed",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: true,
    subParts: @[],
  )
  let node = bp.toJson()
  doAssert node{"subParts"} != nil
  assertLen node{"subParts"}.getElems(@[]), 0

block bpNestedMultipart: # scenario 130
  let leaf = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    source: bpsInline,
    partId: PartId("1"),
    value: BlueprintBodyValue(value: ""),
  )
  let inner = BlueprintBodyPart(
    contentType: "multipart/alternative",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: true,
    subParts: @[leaf],
  )
  let outer = BlueprintBodyPart(
    contentType: "multipart/mixed",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: true,
    subParts: @[inner],
  )
  let node = outer.toJson()
  let innerNode = node{"subParts"}{0}
  doAssert innerNode != nil
  assertJsonFieldEq innerNode, "type", %"multipart/alternative"
  let leafNode = innerNode{"subParts"}{0}
  doAssert leafNode != nil
  assertJsonFieldEq leafNode, "type", %"text/plain"

block bpMixedChildren: # scenario 130a
  let inline = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    source: bpsInline,
    partId: PartId("1"),
    value: BlueprintBodyValue(value: ""),
  )
  let blobRef = BlueprintBodyPart(
    contentType: "image/png",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    source: bpsBlobRef,
    blobId: Id("abc"),
    size: Opt.none(UnsignedInt),
    charset: Opt.none(string),
  )
  let mp = BlueprintBodyPart(
    contentType: "multipart/mixed",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: true,
    subParts: @[inline, blobRef],
  )
  let node = mp.toJson()
  assertLen node{"subParts"}.getElems(@[]), 2
  # First child: inline with partId
  doAssert node{"subParts"}{0}{"partId"} != nil
  # Second child: blob-ref with blobId
  doAssert node{"subParts"}{1}{"blobId"} != nil

block bpBlobRefBothOptAbsent: # scenario 131
  let bp = BlueprintBodyPart(
    contentType: "image/png",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    source: bpsBlobRef,
    blobId: Id("abc"),
    size: Opt.none(UnsignedInt),
    charset: Opt.none(string),
  )
  let node = bp.toJson()
  doAssert "charset" notin node
  doAssert "size" notin node

# ============= L. Adversarial (scenarios A1–A6) =============

block adversarialNulInHeaderName: # scenario A1
  # NUL byte in header name portion — NUL is not 0x3A (colon), so it does
  # not trigger delimiter splits. The name includes raw bytes.
  let res = parseHeaderPropertyName("header:From\x00Evil:asAddresses")
  # NUL is a control char < 0x20 — but parseHeaderPropertyName is lenient
  # (Decision C42: structural parser does not validate printable-ASCII).
  # The colon splits produce ["From\x00Evil", "asAddresses"] since NUL ≠ ':'.
  assertOk res

block adversarialOverlongUtf8Colon: # scenario A2
  # Overlong encoding of ':' (0x3A) as \xC0\xBA — NOT literal 0x3A bytes.
  # Byte-level split on ':' (0x3A) does not trigger on these bytes.
  let res = parseHeaderPropertyName("header:From\xC0\xBA:asAddresses")
  # Split produces ["From\xC0\xBA", "asAddresses"] — name contains raw bytes.
  assertOk res

block adversarialNulInContentType: # scenario A3
  let node = %*{
    "type": "text/plain\x00multipart/mixed", "partId": "1", "blobId": "abc", "size": 1
  }
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  # startsWith("multipart/") on full byte sequence → false (NUL ≠ '/')
  assertEq res.get().isMultipart, false

block adversarial10kChildren: # scenario A4
  var children = newJArray()
  for i in 0 ..< 10_000:
    children.add(%*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 1})
  let node = %*{"type": "multipart/mixed", "subParts": children}
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  assertLen res.get().subParts, 10_000

block adversarialFloatSize: # scenario A6
  const raw = """{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 3.14}"""
  let node = parseJson(raw)
  assertErr EmailBodyPart.fromJson(node)
