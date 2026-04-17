# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## RFC 8621 §4.6 wire-format conformance tests for ``EmailBlueprint.toJson``
## (scenarios 75–84 per design §6.2.4). Split from
## ``tserde_email_blueprint.nim`` per §6.5.1 to stay under the per-file
## line ceiling.

import std/json
import std/strutils
import std/tables

import jmap_client/mail/addresses
import jmap_client/mail/body
import jmap_client/mail/email_blueprint
import jmap_client/mail/headers
import jmap_client/mail/serde_email_blueprint
import jmap_client/primitives
import jmap_client/validation

import ../../massertions
import ../../mfixtures

# ============= A. RFC §4.6 top-level prohibitions (75–77) =============

block noContentStarTopLevelKeys: # scenario 75
  # The creation-model vocabulary forbids ``Content-*`` at the top level
  # via ``BlueprintEmailHeaderName``'s parser; we additionally pin that
  # no such key accidentally leaks through ``toJson`` for a maximally
  # populated blueprint. ``JsonNode.keys`` iterates the underlying
  # ``OrderedTable`` in insertion order.
  let obj = makeFullEmailBlueprint().toJson()
  for key in obj.keys:
    doAssert not key.startsWith("Content-"), "unexpected Content-* key: " & key

block bodyPartNoHeadersArrayKey: # scenario 76
  # RFC §4.6 creation input forbids a ``headers`` array on body parts —
  # only discrete ``"header:<name>:as<Form>"`` keys. Walk the structured
  # body to confirm.
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
  let tb = bp.toJson(){"textBody"}
  doAssert tb != nil
  doAssert tb[0]{"headers"} == nil

block ebkStructuredPresenceAndExclusions: # scenario 77
  # ``bodyStructure`` must coexist with no flat-list keys on the same
  # aggregate — the XOR is a type invariant, and the serialiser respects
  # it at the wire boundary too.
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

# ============= B. Leaf discriminant wire shape (78–79) =============

block inlineLeafHasPartIdNoBlobIdChartsetSize: # scenario 78
  # Inline leaves carry ``partId`` on the wire and omit ``blobId`` /
  # ``charset`` / ``size`` — the latter three belong to ``bpsBlobRef``.
  let leaf = makeBlueprintBodyPartInline(
    partId = parsePartIdFromServer("7").get(),
    contentType = "text/plain",
    value = BlueprintBodyValue(value: "hi"),
  )
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(),
      body = flatBody(textBody = Opt.some(leaf)),
    )
    .get()
  let tb0 = bp.toJson(){"textBody"}[0]
  doAssert tb0{"partId"} != nil
  doAssert tb0{"blobId"} == nil
  doAssert tb0{"charset"} == nil
  doAssert tb0{"size"} == nil

block blobRefLeafHasBlobIdNoPartId: # scenario 79
  # Dual to 78 — blob-ref leaves expose ``blobId`` and elide ``partId``.
  let leaf =
    makeBlueprintBodyPartBlobRef(blobId = makeBlobId("B"), contentType = "image/png")
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), body = flatBody(attachments = @[leaf])
    )
    .get()
  let att0 = bp.toJson(){"attachments"}[0]
  doAssert att0{"blobId"} != nil
  doAssert att0{"partId"} == nil

# ============= C. Header-key lowercase normalisation (81) =============

block headerKeysLowercaseRegardlessOfInput: # scenario 81
  # ``parseBlueprintEmailHeaderName`` lower-cases the backing string at
  # construction; the serialiser reads the distinct string as-is. Slice
  # the wire key between ``"header:"`` and the next ``:`` to extract the
  # name segment and confirm it is ASCII-lowercase.
  let name = parseBlueprintEmailHeaderName("X-Upper").get()
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  extra[name] = makeBhmvRawSingle("v")
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), extraHeaders = extra
    )
    .get()
  let obj = bp.toJson()
  var sawHeader = false
  for key in obj.keys:
    if key.startsWith("header:"):
      sawHeader = true
      let nameStart = "header:".len
      let afterName = key.find(':', nameStart)
      let nameEnd = if afterName == -1: key.len else: afterName
      let headerName = key[nameStart ..< nameEnd]
      doAssert headerName == headerName.toLowerAscii(),
        "header name not lowercase: " & headerName
  doAssert sawHeader, "no header:* key emitted"

# ============= D. Form-specific wire shape (82–84) =============

block asAddressesAllEmitsNestedArrays: # scenario 82
  # Cardinality > 1 for ``hfAddresses`` forces the ``:all`` suffix and
  # the value is a JArray of JArrays — the outer axis is cardinality,
  # the inner axis is the address list per occurrence.
  let name = parseBlueprintEmailHeaderName("x-two-addr").get()
  let a = makeEmailAddress("a@x", "A")
  let b = makeEmailAddress("b@x", "B")
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  extra[name] = makeBhmvAddresses(@[@[a], @[b]])
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), extraHeaders = extra
    )
    .get()
  let obj = bp.toJson()
  let arr = obj{"header:x-two-addr:asAddresses:all"}
  doAssert arr != nil and arr.kind == JArray
  assertLen arr.getElems(), 2
  doAssert arr[0].kind == JArray and arr[1].kind == JArray

block asGroupedAddressesWireShape: # scenario 83
  let name = parseBlueprintEmailHeaderName("x-groups").get()
  let alice = makeEmailAddress("alice@x", "Alice")
  let grp = EmailAddressGroup(name: Opt.some("team"), addresses: @[alice])
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  extra[name] = makeBhmvGroupedAddressesSingle(@[grp])
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), extraHeaders = extra
    )
    .get()
  let obj = bp.toJson()
  let arr = obj{"header:x-groups:asGroupedAddresses"}
  doAssert arr != nil and arr.kind == JArray
  assertLen arr.getElems(), 1
  let g0 = arr[0]
  doAssert g0{"name"} != nil
  doAssert g0{"addresses"} != nil

block asUrlsWireShape: # scenario 84a
  let name = parseBlueprintEmailHeaderName("x-url").get()
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  extra[name] = makeBhmvUrlsSingle(@["https://a", "https://b"])
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), extraHeaders = extra
    )
    .get()
  let obj = bp.toJson()
  let arr = obj{"header:x-url:asURLs"}
  doAssert arr != nil and arr.kind == JArray
  assertLen arr.getElems(), 2
  doAssert arr[0].kind == JString

block asMessageIdsWireShape: # scenario 84b
  let name = parseBlueprintEmailHeaderName("x-mid").get()
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  extra[name] = makeBhmvMessageIdsSingle(@["<id1@host>", "<id2@host>"])
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), extraHeaders = extra
    )
    .get()
  let obj = bp.toJson()
  let arr = obj{"header:x-mid:asMessageIds"}
  doAssert arr != nil and arr.kind == JArray
  assertLen arr.getElems(), 2
  doAssert arr[0].kind == JString

block asDateWireShape: # scenario 84c
  # Cardinality = 1 for ``hfDate`` — the dispatcher emits a JString (the
  # RFC 3339 text), NOT a JArray. The ``assertJsonStringEquals`` helper
  # pins both kind and byte content.
  let name = parseBlueprintEmailHeaderName("x-ts").get()
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  extra[name] = makeBhmvDateSingle(parseDate("2026-04-12T00:00:00Z").get())
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), extraHeaders = extra
    )
    .get()
  assertJsonStringEquals bp.toJson(), "header:x-ts:asDate", "2026-04-12T00:00:00Z"
