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

import jmap_client/internal/mail/body
import jmap_client/internal/mail/serde_body
import jmap_client/internal/mail/headers
import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives
import jmap_client/internal/types/identifiers

import ../../massertions
import ../../mtestblock

# ============= A. EmailBodyPart.fromJson basic (scenarios 77–82) =============

testCase fromJsonLeafPart: # scenario 77
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
  assertEq part.partId, parsePartIdFromServer("1").get()
  assertEq part.blobId, parseBlobId("abc123").get()
  assertSomeEq part.charset, "utf-8"

testCase fromJsonMultipart: # scenario 78
  let node = %*{
    "type": "multipart/mixed",
    "subParts": [{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 100}],
  }
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  assertEq res.get().isMultipart, true
  assertLen res.get().subParts, 1

testCase fromJsonMultipartAbsentSubParts: # scenario 79
  let node = %*{"type": "multipart/mixed"}
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  assertLen res.get().subParts, 0

testCase fromJsonLeafAbsentPartId: # scenario 80
  assertErr EmailBodyPart.fromJson(%*{"type": "text/plain", "blobId": "abc", "size": 1})

testCase fromJsonLeafAbsentBlobId: # scenario 81
  assertErr EmailBodyPart.fromJson(%*{"type": "text/plain", "partId": "1", "size": 1})

testCase isMultipartFromContentType: # scenario 82
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

testCase sizeRequiredOnLeaf: # scenario 83
  assertErr EmailBodyPart.fromJson(
    %*{"type": "text/plain", "partId": "1", "blobId": "abc"}
  )

testCase sizeDefaultOnMultipart: # scenario 84
  let res = EmailBodyPart.fromJson(%*{"type": "multipart/mixed"})
  assertOk res
  assertEq res.get().size, parseUnsignedInt(0).get()

# ============= C. Charset defaults (scenarios 85–90) =============

testCase charsetAbsentTextPlain: # scenario 85
  let node = %*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 1}
  assertSomeEq EmailBodyPart.fromJson(node).get().charset, "us-ascii"

testCase charsetPresentTextPlain: # scenario 86
  let node = %*{
    "type": "text/plain", "partId": "1", "blobId": "abc", "size": 1, "charset": "utf-8"
  }
  assertSomeEq EmailBodyPart.fromJson(node).get().charset, "utf-8"

testCase charsetNullTextHtml: # scenario 87
  let node =
    %*{"type": "text/html", "partId": "1", "blobId": "abc", "size": 1, "charset": nil}
  assertSomeEq EmailBodyPart.fromJson(node).get().charset, "us-ascii"

testCase charsetAbsentImagePng: # scenario 88
  let node = %*{"type": "image/png", "partId": "1", "blobId": "abc", "size": 1}
  assertNone EmailBodyPart.fromJson(node).get().charset

testCase charsetAbsentMultipart: # scenario 89
  let node = %*{"type": "multipart/mixed"}
  assertNone EmailBodyPart.fromJson(node).get().charset

testCase charsetPresentImagePng: # scenario 90
  let node = %*{
    "type": "image/png", "partId": "1", "blobId": "abc", "size": 1, "charset": "binary"
  }
  assertSomeEq EmailBodyPart.fromJson(node).get().charset, "binary"

# ============= D. Headers (scenarios 91–92) =============

testCase headersAbsent: # scenario 91
  let node = %*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 1}
  assertLen EmailBodyPart.fromJson(node).get().headers, 0

testCase headersPresent: # scenario 92
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

testCase depthLimit129: # scenario 93
  # 128 multipart wrappers + 1 leaf = 129 parse calls → err
  var node = %*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 1}
  for i in 0 ..< 128:
    node = %*{"type": "multipart/mixed", "subParts": [node]}
  assertErr EmailBodyPart.fromJson(node)

testCase depthLimitExact128: # scenario 104
  # 127 multipart wrappers + 1 leaf = 128 parse calls → ok
  var node = %*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 1}
  for i in 0 ..< 127:
    node = %*{"type": "multipart/mixed", "subParts": [node]}
  assertOk EmailBodyPart.fromJson(node)

# ============= F. Round-trips (scenarios 94–95) =============

testCase roundTripLeaf: # scenario 94
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
  assertSomeEq rt.disposition, dispositionInline
  assertSomeEq rt.name, "file.txt"
  assertSomeEq rt.cid, "cid123"
  assertSome rt.language
  assertSomeEq rt.location, "https://example.com"

testCase roundTripMultipart: # scenario 95
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
  assertEq rt.subParts[0].partId, parsePartIdFromServer("1").get()
  assertEq rt.subParts[1].partId, parsePartIdFromServer("2").get()

# ============= G. toJson depth (scenarios 96, 108) =============

testCase toJsonDepthStress: # scenario 96
  # Build a deeply nested structure and verify toJson doesn't crash
  var part = EmailBodyPart(
    headers: @[],
    name: Opt.none(string),
    contentType: "text/plain",
    charset: Opt.none(string),
    disposition: Opt.none(ContentDisposition),
    cid: Opt.none(string),
    language: Opt.none(seq[string]),
    location: Opt.none(string),
    size: parseUnsignedInt(0).get(),
    isMultipart: false,
    partId: parsePartIdFromServer("1").get(),
    blobId: parseBlobId("abc").get(),
  )
  for i in 0 ..< 200:
    part = EmailBodyPart(
      headers: @[],
      name: Opt.none(string),
      contentType: "multipart/mixed",
      charset: Opt.none(string),
      disposition: Opt.none(ContentDisposition),
      cid: Opt.none(string),
      language: Opt.none(seq[string]),
      location: Opt.none(string),
      size: parseUnsignedInt(0).get(),
      isMultipart: true,
      subParts: @[part],
    )
  let node = part.toJson()
  doAssert node.kind == JObject

testCase toJsonDepthExact128: # scenario 108
  var part = EmailBodyPart(
    headers: @[],
    name: Opt.none(string),
    contentType: "text/plain",
    charset: Opt.none(string),
    disposition: Opt.none(ContentDisposition),
    cid: Opt.none(string),
    language: Opt.none(seq[string]),
    location: Opt.none(string),
    size: parseUnsignedInt(0).get(),
    isMultipart: false,
    partId: parsePartIdFromServer("1").get(),
    blobId: parseBlobId("abc").get(),
  )
  for i in 0 ..< 127:
    part = EmailBodyPart(
      headers: @[],
      name: Opt.none(string),
      contentType: "multipart/mixed",
      charset: Opt.none(string),
      disposition: Opt.none(ContentDisposition),
      cid: Opt.none(string),
      language: Opt.none(seq[string]),
      location: Opt.none(string),
      size: parseUnsignedInt(0).get(),
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

testCase absentContentType: # scenario 97
  assertErr EmailBodyPart.fromJson(%*{"partId": "1", "blobId": "abc", "size": 1})

testCase nonObjectInput: # scenario 97a
  assertErr EmailBodyPart.fromJson(%*[1, 2, 3])
  assertErr EmailBodyPart.fromJson(newJNull())
  assertErr EmailBodyPart.fromJson(%"string")

testCase typeWrongKind: # scenario 97b
  assertErr EmailBodyPart.fromJson(
    %*{"type": 42, "partId": "1", "blobId": "abc", "size": 1}
  )

testCase uppercaseMultipart: # scenario 98
  let node = %*{
    "type": "MULTIPART/MIXED",
    "subParts": [{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 1}],
  }
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  assertEq res.get().isMultipart, true

testCase charsetDefaultUppercaseText: # scenario 98a
  let node = %*{"type": "TEXT/PLAIN", "partId": "1", "blobId": "abc", "size": 1}
  assertSomeEq EmailBodyPart.fromJson(node).get().charset, "us-ascii"

testCase multipartSlashOnly: # scenario 99
  let res = EmailBodyPart.fromJson(%*{"type": "multipart/"})
  assertOk res
  assertEq res.get().isMultipart, true

testCase textSlashCharsetDefault: # scenario 99a
  let node = %*{"type": "text/", "partId": "1", "blobId": "abc", "size": 1}
  assertSomeEq EmailBodyPart.fromJson(node).get().charset, "us-ascii"

testCase textplainNoSlash: # scenario 99b
  # "textplain" does not start with "multipart/" → leaf
  assertErr EmailBodyPart.fromJson(%*{"type": "textplain"})
  # Requires partId/blobId since it's a leaf

testCase multipartNoTrailingSlash: # scenario 99c
  # "multipart" does not start with "multipart/" → not multipart
  assertErr EmailBodyPart.fromJson(%*{"type": "multipart"})

testCase emptyContentType: # scenario 99d
  # Empty string: not multipart, not text/* → leaf
  assertErr EmailBodyPart.fromJson(%*{"type": ""})
  # Requires partId/blobId since it's a leaf

testCase duplicateTypeKey: # scenario 108c
  # std/json last-wins: second "type" value overrides first
  const raw = """{"type": "text/plain", "type": "multipart/mixed"}"""
  let node = parseJson(raw)
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  assertEq res.get().isMultipart, true
  assertLen res.get().subParts, 0

# ============= I. Field validation edge cases (scenarios 100–107) =============

testCase leafWithSubPartsIgnored: # scenario 100
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

testCase multipartWithPartIdBlobIdIgnored: # scenario 101
  let node = %*{
    "type": "multipart/mixed",
    "partId": "1",
    "blobId": "abc",
    "subParts": [{"type": "text/plain", "partId": "2", "blobId": "def", "size": 1}],
  }
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  assertEq res.get().isMultipart, true

testCase nullInHeadersArray: # scenario 102
  let node = %*{
    "type": "text/plain", "partId": "1", "blobId": "abc", "size": 1, "headers": [nil]
  }
  assertErr EmailBodyPart.fromJson(node)

testCase nonStringInLanguageArray: # scenario 102a
  let node = %*{
    "type": "text/plain", "partId": "1", "blobId": "abc", "size": 1, "language": [42]
  }
  assertErr EmailBodyPart.fromJson(node)

testCase nullInSubPartsArray: # scenario 103
  let node = %*{"type": "multipart/mixed", "subParts": [nil]}
  assertErr EmailBodyPart.fromJson(node)

testCase emptyCharsetString: # scenario 105
  let node =
    %*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 1, "charset": ""}
  assertSomeEq EmailBodyPart.fromJson(node).get().charset, ""

testCase sizeNegative: # scenario 106
  let node = %*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": -1}
  assertErr EmailBodyPart.fromJson(node)

testCase sizeExceeding: # scenario 107
  let node =
    %*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 9007199254740992}
  assertErr EmailBodyPart.fromJson(node)

# ============= J. EmailBodyValue serde (scenarios 109–118, 115a, 118a–118b) =============

testCase bodyValueAllFields: # scenario 109
  let node = %*{"value": "Hello", "isEncodingProblem": false, "isTruncated": false}
  let res = EmailBodyValue.fromJson(node)
  assertOk res
  let bv = res.get()
  assertEq bv.value, "Hello"
  assertEq bv.isEncodingProblem, false
  assertEq bv.isTruncated, false

testCase bodyValueEncodingProblem: # scenario 110
  let node = %*{"value": "Hello", "isEncodingProblem": true}
  assertEq EmailBodyValue.fromJson(node).get().isEncodingProblem, true

testCase bodyValueTruncated: # scenario 111
  let node = %*{"value": "Hello", "isTruncated": true}
  assertEq EmailBodyValue.fromJson(node).get().isTruncated, true

testCase bodyValueBothFlags: # scenario 112
  let node = %*{"value": "Hello", "isEncodingProblem": true, "isTruncated": true}
  let bv = EmailBodyValue.fromJson(node).get()
  assertEq bv.isEncodingProblem, true
  assertEq bv.isTruncated, true

testCase bodyValueFlagsDefault: # scenario 113
  let node = %*{"value": "Hello"}
  let bv = EmailBodyValue.fromJson(node).get()
  assertEq bv.isEncodingProblem, false
  assertEq bv.isTruncated, false

testCase bodyValueRoundTrip: # scenario 114
  let original =
    EmailBodyValue(value: "Hello", isEncodingProblem: true, isTruncated: false)
  let rt = EmailBodyValue.fromJson(original.toJson()).get()
  assertEq rt.value, original.value
  assertEq rt.isEncodingProblem, original.isEncodingProblem
  assertEq rt.isTruncated, original.isTruncated

testCase bodyValueAbsentValue: # scenario 115
  assertErr EmailBodyValue.fromJson(%*{"isEncodingProblem": false})

testCase bodyValueNonObject: # scenario 115a
  assertErr EmailBodyValue.fromJson(%*[1, 2])
  assertErr EmailBodyValue.fromJson(newJNull())

testCase bodyValueNullValue: # scenario 116
  assertErr EmailBodyValue.fromJson(%*{"value": nil})

testCase bodyValueWrongKindValue: # scenario 117
  assertErr EmailBodyValue.fromJson(%*{"value": 42})

testCase bodyValueWrongKindFlags: # scenario 118
  assertErr EmailBodyValue.fromJson(%*{"value": "Hi", "isEncodingProblem": "true"})
  assertErr EmailBodyValue.fromJson(%*{"value": "Hi", "isTruncated": "true"})

testCase bodyValueEmptyValue: # scenario 118a
  let bv = EmailBodyValue.fromJson(%*{"value": ""}).get()
  assertEq bv.value, ""

testCase bodyValueNullFlag: # scenario 118b
  # null for bool flag treated as absent → default false
  let node = %*{"value": "Hi", "isEncodingProblem": nil}
  let bv = EmailBodyValue.fromJson(node).get()
  assertEq bv.isEncodingProblem, false

# ============= K. BlueprintBodyPart.toJson (scenarios 119–131, 125, 127a, 130a–130b) =============

testCase bpInlineLeaf: # scenario 119
  let bp = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsInline,
      partId: parsePartIdFromServer("1").get(),
      value: BlueprintBodyValue(value: ""),
    ),
  )
  let node = bp.toJson()
  assertJsonFieldEq node, "type", %"text/plain"
  assertJsonFieldEq node, "partId", %"1"
  # blobId, charset, size must be absent
  doAssert node{"blobId"} == nil, "blobId should be absent on inline leaf"
  doAssert node{"charset"} == nil, "charset should be absent on inline leaf"
  doAssert node{"size"} == nil, "size should be absent on inline leaf"

testCase bpBlobRefLeaf: # scenario 120
  let bp = BlueprintBodyPart(
    contentType: "image/png",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsBlobRef,
      blobId: parseBlobId("abc123").get(),
      size: Opt.some(parseUnsignedInt(5678).get()),
      charset: Opt.some("utf-8"),
    ),
  )
  let node = bp.toJson()
  assertJsonFieldEq node, "type", %"image/png"
  assertJsonFieldEq node, "blobId", %"abc123"

testCase bpBlobRefBothPresent: # scenario 121
  let bp = BlueprintBodyPart(
    contentType: "image/png",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsBlobRef,
      blobId: parseBlobId("abc").get(),
      size: Opt.some(parseUnsignedInt(100).get()),
      charset: Opt.some("binary"),
    ),
  )
  let node = bp.toJson()
  doAssert node{"charset"} != nil
  doAssert node{"size"} != nil

testCase bpBlobRefBothAbsent: # scenario 122
  let bp = BlueprintBodyPart(
    contentType: "image/png",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsBlobRef,
      blobId: parseBlobId("abc").get(),
      size: Opt.none(UnsignedInt),
      charset: Opt.none(string),
    ),
  )
  let node = bp.toJson()
  doAssert node{"charset"} == nil, "charset should be absent"
  doAssert node{"size"} == nil, "size should be absent"

testCase bpMultipart: # scenario 123
  let child = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsInline,
      partId: parsePartIdFromServer("1").get(),
      value: BlueprintBodyValue(value: ""),
    ),
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

testCase bpDepthLimit: # scenario 124
  var bp = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsInline,
      partId: parsePartIdFromServer("1").get(),
      value: BlueprintBodyValue(value: ""),
    ),
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

testCase bpNoFromJson: # scenario 125
  assertNotCompiles(BlueprintBodyPart.fromJson(%*{}))

testCase bpInlineKeyAbsence: # scenario 126
  let bp = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsInline,
      partId: parsePartIdFromServer("1").get(),
      value: BlueprintBodyValue(value: ""),
    ),
  )
  let node = bp.toJson()
  # Keys must be absent (not null, not present)
  doAssert "blobId" notin node
  doAssert "charset" notin node
  doAssert "size" notin node

testCase bpExtraHeaders: # scenario 127
  let name = parseBlueprintBodyHeaderName("x-custom").get()
  var headers = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  headers[name] = textSingle("custom value")
  let bp = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: headers,
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsInline,
      partId: parsePartIdFromServer("1").get(),
      value: BlueprintBodyValue(value: ""),
    ),
  )
  let node = bp.toJson()
  doAssert node{"header:x-custom:asText"} != nil
  assertEq node{"header:x-custom:asText"}, %"custom value"

testCase bpExtraHeadersHfRaw: # scenario 127a
  # hfRaw form suffix is omitted by composeHeaderKey.
  let name = parseBlueprintBodyHeaderName("x-custom").get()
  var headers = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  headers[name] = rawSingle("raw value")
  let bp = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: headers,
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsInline,
      partId: parsePartIdFromServer("1").get(),
      value: BlueprintBodyValue(value: ""),
    ),
  )
  let node = bp.toJson()
  # Key should be "header:x-custom" (no ":asRaw" — hfRaw suppressed).
  doAssert node{"header:x-custom"} != nil
  assertEq node{"header:x-custom"}, %"raw value"

testCase bpEmptyExtraHeaders: # scenario 128
  let bp = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsInline,
      partId: parsePartIdFromServer("1").get(),
      value: BlueprintBodyValue(value: ""),
    ),
  )
  let node = bp.toJson()
  # Only standard keys should be present
  for key, _ in node.pairs:
    doAssert key.startsWith("header:") == false, "no header properties expected"

testCase bpMultipartEmptySubParts: # scenario 129
  let bp = BlueprintBodyPart(
    contentType: "multipart/mixed",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: true,
    subParts: @[],
  )
  let node = bp.toJson()
  doAssert node{"subParts"} != nil
  assertLen node{"subParts"}.getElems(@[]), 0

testCase bpNestedMultipart: # scenario 130
  let leaf = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsInline,
      partId: parsePartIdFromServer("1").get(),
      value: BlueprintBodyValue(value: ""),
    ),
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

testCase bpMixedChildren: # scenario 130a
  let inline = BlueprintBodyPart(
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsInline,
      partId: parsePartIdFromServer("1").get(),
      value: BlueprintBodyValue(value: ""),
    ),
  )
  let blobRef = BlueprintBodyPart(
    contentType: "image/png",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsBlobRef,
      blobId: parseBlobId("abc").get(),
      size: Opt.none(UnsignedInt),
      charset: Opt.none(string),
    ),
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

testCase bpBlobRefBothOptAbsent: # scenario 131
  let bp = BlueprintBodyPart(
    contentType: "image/png",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsBlobRef,
      blobId: parseBlobId("abc").get(),
      size: Opt.none(UnsignedInt),
      charset: Opt.none(string),
    ),
  )
  let node = bp.toJson()
  doAssert "charset" notin node
  doAssert "size" notin node

# ============= L. Adversarial (scenarios A1–A6) =============

testCase adversarialNulInHeaderName: # scenario A1
  # NUL byte in header name portion — NUL is not 0x3A (colon), so it does
  # not trigger delimiter splits. The name includes raw bytes.
  let res = parseHeaderPropertyName("header:From\x00Evil:asAddresses")
  # NUL is a control char < 0x20 — but parseHeaderPropertyName is lenient
  # (Decision C42: structural parser does not validate printable-ASCII).
  # The colon splits produce ["From\x00Evil", "asAddresses"] since NUL ≠ ':'.
  assertOk res

testCase adversarialOverlongUtf8Colon: # scenario A2
  # Overlong encoding of ':' (0x3A) as \xC0\xBA — NOT literal 0x3A bytes.
  # Byte-level split on ':' (0x3A) does not trigger on these bytes.
  let res = parseHeaderPropertyName("header:From\xC0\xBA:asAddresses")
  # Split produces ["From\xC0\xBA", "asAddresses"] — name contains raw bytes.
  assertOk res

testCase adversarialNulInContentType: # scenario A3
  let node = %*{
    "type": "text/plain\x00multipart/mixed", "partId": "1", "blobId": "abc", "size": 1
  }
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  # startsWith("multipart/") on full byte sequence → false (NUL ≠ '/')
  assertEq res.get().isMultipart, false

testCase adversarial10kChildren: # scenario A4
  var children = newJArray()
  for i in 0 ..< 10_000:
    children.add(%*{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 1})
  let node = %*{"type": "multipart/mixed", "subParts": children}
  let res = EmailBodyPart.fromJson(node)
  assertOk res
  assertLen res.get().subParts, 10_000

testCase adversarialFloatSize: # scenario A6
  const raw = """{"type": "text/plain", "partId": "1", "blobId": "abc", "size": 3.14}"""
  let node = parseJson(raw)
  assertErr EmailBodyPart.fromJson(node)
