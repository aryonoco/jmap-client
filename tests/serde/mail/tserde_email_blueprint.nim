# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for ``EmailBlueprint.toJson`` (scenarios 51–73a per design
## docs/design/10-mail-e-design.md §6.2.1–§6.2.3). Scenarios 60, 71, 74
## retired (design pre-audit consolidation). Wire-format conformance
## scenarios (75–84) live in ``tserde_email_blueprint_wire.nim`` per §6.5.1.

import std/json
import std/sequtils
import std/strutils
import std/tables

import jmap_client/internal/mail/body
import jmap_client/internal/mail/email_blueprint
import jmap_client/internal/mail/headers
import jmap_client/internal/mail/keyword
import jmap_client/internal/mail/serde_email_blueprint
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation

import ../../massertions
import ../../mfixtures
import ../../mtestblock

# =========== A. Top-level shape (scenarios 51–53, 58–59, 58a) ===========

testCase minimalBlueprintOnlyMailboxIds: # scenario 51
  # A default blueprint must emit only ``mailboxIds`` — every other
  # convenience field is ``Opt.none`` or empty at default and thus
  # omitted (R4-2, R4-3).
  let bp = makeEmailBlueprint()
  let obj = bp.toJson()
  doAssert obj.kind == JObject
  doAssert obj{"mailboxIds"} != nil
  assertJsonKeyAbsent obj, "keywords"
  assertJsonKeyAbsent obj, "receivedAt"
  assertJsonKeyAbsent obj, "from"
  assertJsonKeyAbsent obj, "to"
  assertJsonKeyAbsent obj, "cc"
  assertJsonKeyAbsent obj, "bcc"
  assertJsonKeyAbsent obj, "replyTo"
  assertJsonKeyAbsent obj, "sender"
  assertJsonKeyAbsent obj, "subject"
  assertJsonKeyAbsent obj, "sentAt"
  assertJsonKeyAbsent obj, "messageId"
  assertJsonKeyAbsent obj, "inReplyTo"
  assertJsonKeyAbsent obj, "references"
  assertJsonKeyAbsent obj, "bodyValues"

testCase keywordsEmitsFlagTable: # scenario 52
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      keywords = initKeywordSet(@[parseKeyword("$seen").get()]),
    )
    .get()
  let obj = bp.toJson()
  let kw = obj{"keywords"}
  doAssert kw != nil
  doAssert kw.kind == JObject
  assertJsonFieldEq kw, "$seen", %true

testCase emptyKeywordsOmitsKey: # scenario 53
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), keywords = initKeywordSet(@[])
    )
    .get()
  assertJsonKeyAbsent bp.toJson(), "keywords"

testCase receivedAtEmitsIsoString: # scenario 58
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      receivedAt = Opt.some(parseUtcDate("2026-04-12T12:00:00Z").get()),
    )
    .get()
  assertJsonStringEquals bp.toJson(), "receivedAt", "2026-04-12T12:00:00Z"

testCase receivedAtEndsWithLiteralZ: # scenario 58a
  # Same input as 58 — separately pin the trailing ``Z`` via ``endsWith``
  # so a future timezone-offset regression fires here without waiting for
  # the byte-exact comparison to surface the discrepancy.
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      receivedAt = Opt.some(parseUtcDate("2026-04-12T12:00:00Z").get()),
    )
    .get()
  let field = bp.toJson(){"receivedAt"}
  doAssert field != nil and field.kind == JString
  doAssert field.getStr().endsWith("Z")

testCase receivedAtNoneOmitsKey: # scenario 59
  let bp = makeEmailBlueprint()
  assertJsonKeyAbsent bp.toJson(), "receivedAt"

# ====== B. Convenience fields: addresses (55–57, 61, 62a–62e, 65a–65c) ======

testCase fromAddrEmitsAddressArray: # scenario 55
  let alice = makeEmailAddress("alice@example.com", "Alice")
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), fromAddr = Opt.some(@[alice])
    )
    .get()
  let arr = bp.toJson(){"from"}
  doAssert arr != nil and arr.kind == JArray
  assertLen arr.getElems(), 1
  assertJsonFieldEq arr[0], "email", %"alice@example.com"
  assertJsonFieldEq arr[0], "name", %"Alice"

testCase senderEmitsOneElementArray: # scenario 56
  # RFC 5322 §3.6.2 Sender is singular in the domain but wire-wrapped to
  # a 1-element JArray per R4-1.
  let alice = makeEmailAddress("alice@example.com", "Alice")
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), sender = Opt.some(alice)
    )
    .get()
  let arr = bp.toJson(){"sender"}
  doAssert arr != nil and arr.kind == JArray
  assertLen arr.getElems(), 1
  assertJsonFieldEq arr.getElems()[0], "email", %"alice@example.com"

testCase senderNoneOmitsKey: # scenario 57
  assertJsonKeyAbsent makeEmailBlueprint().toJson(), "sender"

testCase fromEmitsArrayOfOne: # scenario 61
  # Single-element convenience invariant — one-address lists still wrap.
  let alice = makeEmailAddress()
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), fromAddr = Opt.some(@[alice])
    )
    .get()
  let arr = bp.toJson(){"from"}
  doAssert arr != nil and arr.kind == JArray
  assertLen arr.getElems(), 1

testCase toEmitsArrayOfTwo: # scenario 62a
  let a = makeEmailAddress("a@x")
  let b = makeEmailAddress("b@x")
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), to = Opt.some(@[a, b])
    )
    .get()
  assertLen bp.toJson(){"to"}.getElems(), 2

testCase ccEmitsArrayOfTwo: # scenario 62b
  let a = makeEmailAddress("a@x")
  let b = makeEmailAddress("b@x")
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), cc = Opt.some(@[a, b])
    )
    .get()
  assertLen bp.toJson(){"cc"}.getElems(), 2

testCase bccEmitsArrayOfTwo: # scenario 62c
  let a = makeEmailAddress("a@x")
  let b = makeEmailAddress("b@x")
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), bcc = Opt.some(@[a, b])
    )
    .get()
  assertLen bp.toJson(){"bcc"}.getElems(), 2

testCase replyToEmitsArrayOfTwo: # scenario 62d
  let a = makeEmailAddress("a@x")
  let b = makeEmailAddress("b@x")
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), replyTo = Opt.some(@[a, b])
    )
    .get()
  assertLen bp.toJson(){"replyTo"}.getElems(), 2

testCase senderEmitsSingletonArray: # scenario 62e
  # Duplicates 56 by design (§6.2.2 audit row) — the 1-element wrapping
  # invariant deserves both a "shape" and a "length" pin.
  let alice = makeEmailAddress()
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), sender = Opt.some(alice)
    )
    .get()
  let arr = bp.toJson(){"sender"}
  doAssert arr.kind == JArray
  assertLen arr.getElems(), 1

# ============= C. Convenience fields: scalars (63, 64) =============

testCase subjectEmitsJString: # scenario 63
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), subject = Opt.some("hello")
    )
    .get()
  assertJsonStringEquals bp.toJson(), "subject", "hello"

testCase sentAtEmitsIsoString: # scenario 64
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      sentAt = Opt.some(parseDate("2026-04-12T08:00:00Z").get()),
    )
    .get()
  let field = bp.toJson(){"sentAt"}
  doAssert field != nil and field.kind == JString

testCase messageIdEmitsStringArray: # scenario 65a
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), messageId = Opt.some(@["<id1@host>"])
    )
    .get()
  let arr = bp.toJson(){"messageId"}
  doAssert arr != nil and arr.kind == JArray
  assertLen arr.getElems(), 1
  doAssert arr[0].getStr() == "<id1@host>"

testCase inReplyToEmitsStringArray: # scenario 65b
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), inReplyTo = Opt.some(@["<ref0@host>"])
    )
    .get()
  let arr = bp.toJson(){"inReplyTo"}
  doAssert arr != nil and arr.kind == JArray
  assertLen arr.getElems(), 1

testCase referencesEmitsStringArray: # scenario 65c
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      references = Opt.some(@["<ref0@host>", "<ref1@host>"]),
    )
    .get()
  let arr = bp.toJson(){"references"}
  doAssert arr != nil and arr.kind == JArray
  assertLen arr.getElems(), 2

# ============= D. extraHeaders wire composition (66, 66a) =============

testCase extraHeaderSingleValueRawNoAllSuffix: # scenario 66
  # Cardinality 1 forbids ``:all``; form ``hfRaw`` forbids ``:asRaw`` by
  # the composeHeaderKey rule (matches headers.nim ``toPropertyString``).
  let name = parseBlueprintEmailHeaderName("x-custom").get()
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  extra[name] = makeBhmvRawSingle("raw value")
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), extraHeaders = extra
    )
    .get()
  let obj = bp.toJson()
  let field = obj{"header:x-custom"}
  doAssert field != nil and field.kind == JString
  assertEq field.getStr(), "raw value"
  assertJsonKeyAbsent obj, "header:x-custom:asRaw"
  assertJsonKeyAbsent obj, "header:x-custom:all"

testCase extraHeaderMultiValueRawAllSuffix: # scenario 66a
  let name = parseBlueprintEmailHeaderName("x-custom").get()
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  extra[name] = makeBhmvRaw(@["v1", "v2"])
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), extraHeaders = extra
    )
    .get()
  let obj = bp.toJson()
  let arr = obj{"header:x-custom:all"}
  doAssert arr != nil and arr.kind == JArray
  assertLen arr.getElems(), 2

# ============= E. Body variant emission (67–70) =============

testCase ebkStructuredOmitsFlatKeys: # scenario 67
  let root = makeBlueprintBodyPartMultipart(subParts = @[makeBlueprintBodyPartInline()])
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(root)
    )
    .get()
  let obj = bp.toJson()
  doAssert obj{"bodyStructure"} != nil
  assertJsonKeyAbsent obj, "textBody"
  assertJsonKeyAbsent obj, "htmlBody"
  assertJsonKeyAbsent obj, "attachments"

testCase ebkFlatTextBodyOnly: # scenario 68
  let textLeaf = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("1").get(),
    contentType = "text/plain",
    value = BlueprintBodyValue(value: "text"),
  )
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      body = flatBody(textBody = Opt.some(textLeaf)),
    )
    .get()
  let obj = bp.toJson()
  let tb = obj{"textBody"}
  doAssert tb != nil and tb.kind == JArray
  assertLen tb.getElems(), 1
  assertJsonKeyAbsent obj, "htmlBody"
  assertJsonKeyAbsent obj, "attachments"

testCase ebkFlatTextAndHtml: # scenario 69
  let textLeaf = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("1").get(),
    contentType = "text/plain",
    value = BlueprintBodyValue(value: "text"),
  )
  let htmlLeaf = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("2").get(),
    contentType = "text/html",
    value = BlueprintBodyValue(value: "<p>html</p>"),
  )
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      body = flatBody(textBody = Opt.some(textLeaf), htmlBody = Opt.some(htmlLeaf)),
    )
    .get()
  let obj = bp.toJson()
  assertLen obj{"textBody"}.getElems(), 1
  assertLen obj{"htmlBody"}.getElems(), 1
  assertJsonKeyAbsent obj, "attachments"

testCase ebkFlatAttachmentsMixed: # scenario 70
  let pdf = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("1").get(),
    contentType = "application/pdf",
    value = BlueprintBodyValue(value: "pdfbytes"),
  )
  let png = makeBlueprintBodyPartBlobRef(
    blobId = makeBlobId("blobA"), contentType = "image/png"
  )
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      body = flatBody(attachments = @[pdf, png]),
    )
    .get()
  let obj = bp.toJson()
  let arr = obj{"attachments"}
  doAssert arr != nil and arr.kind == JArray
  assertLen arr.getElems(), 2
  doAssert arr[0]{"partId"} != nil
  doAssert arr[1]{"blobId"} != nil

# ============= F. bodyValues harvest (72, 72a, 72b, 73, 73a) =============

testCase bodyValuesHarvestSingleLeaf: # scenario 72
  let leaf = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("1").get(),
    contentType = "text/plain",
    value = BlueprintBodyValue(value: "hi"),
  )
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      body = flatBody(textBody = Opt.some(leaf)),
    )
    .get()
  let obj = bp.toJson()
  let bv = obj{"bodyValues"}
  doAssert bv != nil and bv.kind == JObject
  assertJsonFieldEq bv{"1"}, "value", %"hi"

testCase bodyValuesLastWinsOnDuplicatePartId: # scenario 72a
  # Documented gap E30: ``bodyValues`` accessor resolves duplicate partIds
  # via ``Table`` last-wins. We pin cardinality (exactly one key) without
  # asserting which value wins, since that is an insertion-order-sensitive
  # Table side-effect we deliberately do not freeze.
  let first = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("1").get(),
    contentType = "text/plain",
    value = BlueprintBodyValue(value: "first"),
  )
  let last = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("1").get(),
    contentType = "text/plain",
    value = BlueprintBodyValue(value: "last"),
  )
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      body = flatBody(attachments = @[first, last]),
    )
    .get()
  let obj = bp.toJson()
  let bv = obj{"bodyValues"}
  doAssert bv != nil and bv.kind == JObject
  assertLen toSeq(bv.keys), 1

testCase bodyValuesOrderSensitiveByteDiff: # scenario 72b
  # Two blueprints with leaves in swapped order emit byte-different JSON
  # because ``attachments`` array preserves insertion order. We compare
  # string-stringified outputs rather than structural equality so the test
  # catches any regression that stabilises attachment order spuriously.
  let leafA = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("1").get(),
    contentType = "text/plain",
    value = BlueprintBodyValue(value: "alpha"),
  )
  let leafB = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("2").get(),
    contentType = "text/plain",
    value = BlueprintBodyValue(value: "beta"),
  )
  let bp1 = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      body = flatBody(attachments = @[leafA, leafB]),
    )
    .get()
  let bp2 = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      body = flatBody(attachments = @[leafB, leafA]),
    )
    .get()
  doAssert $bp1.toJson() != $bp2.toJson()

testCase bodyValuesHarvestMultipleLeaves: # scenario 73
  let leafA = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("1").get(),
    contentType = "text/plain",
    value = BlueprintBodyValue(value: "alpha"),
  )
  let leafB = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("2").get(),
    contentType = "application/pdf",
    value = BlueprintBodyValue(value: "pdf"),
  )
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      body = flatBody(textBody = Opt.some(leafA), attachments = @[leafB]),
    )
    .get()
  let obj = bp.toJson()
  assertLen toSeq(obj{"bodyValues"}.keys), 2

testCase bodyValuesHarvestDepth5Tree: # scenario 73a
  # Depth-5 multipart spine with inline leaves at odd depths. The walker
  # recurses ``subParts`` until it reaches a leaf and then picks up the
  # ``BlueprintBodyValue`` via ``collectInlineValues``.
  let leaf5 = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("5").get(), value = BlueprintBodyValue(value: "at 5")
  )
  let leaf3 = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("3").get(), value = BlueprintBodyValue(value: "at 3")
  )
  let leaf1 = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("1").get(), value = BlueprintBodyValue(value: "at 1")
  )
  let depth5 = makeBlueprintBodyPartMultipart(subParts = @[leaf5])
  let depth4 = makeBlueprintBodyPartMultipart(subParts = @[depth5])
  let depth3 = makeBlueprintBodyPartMultipart(subParts = @[leaf3, depth4])
  let depth2 = makeBlueprintBodyPartMultipart(subParts = @[depth3])
  let depth1 = makeBlueprintBodyPartMultipart(subParts = @[leaf1, depth2])
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(depth1)
    )
    .get()
  let obj = bp.toJson()
  assertLen toSeq(obj{"bodyValues"}.keys), 3
