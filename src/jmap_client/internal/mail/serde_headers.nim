# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for header sub-types (RFC 8621 section 4.1.2).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json

import ../serialisation/serde
import ../types
import ./headers
import ./addresses
import ./serde_addresses

# =============================================================================
# EmailHeader
# =============================================================================

func toJson*(eh: EmailHeader): JsonNode =
  ## Serialise EmailHeader to JSON object with ``name`` and ``value``.
  var node = newJObject()
  node["name"] = %eh.name
  node["value"] = %eh.value
  return node

func fromJson*(
    T: typedesc[EmailHeader], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[EmailHeader, SerdeViolation] =
  ## Deserialise JSON object to EmailHeader. Rejects absent, null, or
  ## non-string ``name`` and ``value``.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let nameNode = ?fieldJString(node, "name", path)
  let name = nameNode.getStr("")
  let valueNode = ?fieldJString(node, "value", path)
  let value = valueNode.getStr("")
  return wrapInner(parseEmailHeader(name, value), path)

# =============================================================================
# HeaderValue — parseHeaderValue
# =============================================================================

func parseNullableStringArray(
    node: JsonNode, path: JsonPath
): Result[Opt[seq[string]], SerdeViolation] =
  ## Shared parser for nullable string array forms (hfMessageIds, hfUrls).
  ## JNull → Opt.none. JArray of JString → Opt.some(seq).
  if node.isNil or node.kind == JNull:
    return ok(Opt.none(seq[string]))
  ?expectKind(node, JArray, path)
  var strs: seq[string] = @[]
  for i, elem in node.getElems(@[]):
    ?expectKind(elem, JString, path / i)
    strs.add(elem.getStr(""))
  return ok(Opt.some(strs))

func parseHeaderValue*(
    form: HeaderForm, node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[HeaderValue, SerdeViolation] =
  ## Parses a JSON value into the correct ``HeaderValue`` variant based on
  ## the given form. Nullable forms (messageIds, date, urls) accept JNull
  ## as ``Opt.none``.
  case form
  of hfRaw:
    ?expectKind(node, JString, path)
    return ok(HeaderValue(form: hfRaw, rawValue: node.getStr("")))
  of hfText:
    ?expectKind(node, JString, path)
    return ok(HeaderValue(form: hfText, textValue: node.getStr("")))
  of hfAddresses:
    ?expectKind(node, JArray, path)
    var addrs: seq[EmailAddress] = @[]
    for i, elem in node.getElems(@[]):
      let ea = ?EmailAddress.fromJson(elem, path / i)
      addrs.add(ea)
    return ok(HeaderValue(form: hfAddresses, addresses: addrs))
  of hfGroupedAddresses:
    ?expectKind(node, JArray, path)
    var groups: seq[EmailAddressGroup] = @[]
    for i, elem in node.getElems(@[]):
      let g = ?EmailAddressGroup.fromJson(elem, path / i)
      groups.add(g)
    return ok(HeaderValue(form: hfGroupedAddresses, groups: groups))
  of hfMessageIds:
    let ids = ?parseNullableStringArray(node, path)
    return ok(HeaderValue(form: hfMessageIds, messageIds: ids))
  of hfDate:
    if node.isNil or node.kind == JNull:
      return ok(HeaderValue(form: hfDate, date: Opt.none(Date)))
    let d = ?Date.fromJson(node, path)
    return ok(HeaderValue(form: hfDate, date: Opt.some(d)))
  of hfUrls:
    let urls = ?parseNullableStringArray(node, path)
    return ok(HeaderValue(form: hfUrls, urls: urls))

# =============================================================================
# HeaderValue — toJson
# =============================================================================

func toJson*(v: HeaderValue): JsonNode =
  ## Serialise HeaderValue to JSON. ``Opt.none`` on nullable variants
  ## produces ``null``.
  case v.form
  of hfRaw:
    return %v.rawValue
  of hfText:
    return %v.textValue
  of hfAddresses:
    var arr = newJArray()
    for ea in v.addresses:
      arr.add(ea.toJson())
    return arr
  of hfGroupedAddresses:
    var arr = newJArray()
    for g in v.groups:
      arr.add(g.toJson())
    return arr
  of hfMessageIds:
    for ids in v.messageIds:
      var arr = newJArray()
      for id in ids:
        arr.add(%id)
      return arr
    return newJNull()
  of hfDate:
    for d in v.date:
      return d.toJson()
    return newJNull()
  of hfUrls:
    for urls in v.urls:
      var arr = newJArray()
      for u in urls:
        arr.add(%u)
      return arr
    return newJNull()

# =============================================================================
# BlueprintEmailHeaderName (Design §4.3.3)
# =============================================================================
# Distinct-string wire projection: ``toJson`` emits the wrapped lowercase
# name; ``fromJson`` routes through the strict smart constructor. The
# wire-key composition (``"header:<name>:as<Form>[:all]"``) is performed
# at the consumer aggregate (``EmailBlueprint.toJson``), not here.

defineDistinctStringToJson(BlueprintEmailHeaderName)
defineDistinctStringFromJson(BlueprintEmailHeaderName, parseBlueprintEmailHeaderName)

# =============================================================================
# BlueprintBodyHeaderName (Design §4.4.3)
# =============================================================================

defineDistinctStringToJson(BlueprintBodyHeaderName)
defineDistinctStringFromJson(BlueprintBodyHeaderName, parseBlueprintBodyHeaderName)

# =============================================================================
# BlueprintHeaderMultiValue wire composition (Design §4.5.3)
# =============================================================================
# ``BlueprintHeaderMultiValue`` has no standalone wire identity: the wire-key
# (``"header:<name>[:as<Form>][:all]"``) is composed at the consumer
# aggregate, with the value serialised via ``blueprintMultiValueToJson``.
# ``multiLen`` is the cardinality probe callers use to set the ``:all``
# suffix. The seven ``neXxxToJson`` helpers stay private — they are the
# dispatcher's implementation detail.

func multiLen*(m: BlueprintHeaderMultiValue): int =
  ## Length of the underlying ``NonEmptySeq`` for any variant. The case
  ## object wraps seven differently-named fields, so no borrowed ``len``
  ## exists on ``BlueprintHeaderMultiValue`` directly.
  case m.form
  of hfRaw: m.rawValues.len
  of hfText: m.textValues.len
  of hfAddresses: m.addressLists.len
  of hfGroupedAddresses: m.groupLists.len
  of hfMessageIds: m.messageIdLists.len
  of hfDate: m.dateValues.len
  of hfUrls: m.urlLists.len

func composeHeaderKey*[T: BlueprintEmailHeaderName or BlueprintBodyHeaderName](
    name: T, form: HeaderForm, isAll: bool
): string =
  ## Compose ``"header:<name>[:as<Form>][:all]"``. Form suffix omitted for
  ## ``hfRaw`` (matches ``headers.nim`` ``toPropertyString`` convention).
  ## ``:all`` is appended iff ``multiLen > 1`` (decided by the caller).
  ## Generic over both header-name newtypes because the wire rule is one
  ## fact — the two types share the newtype for context safety, not for
  ## wire-shape divergence.
  result = "header:" & $name
  if form != hfRaw:
    result &= ":" & $form
  if isAll:
    result &= ":all"

func neStringToJson(ne: NonEmptySeq[string]): JsonNode =
  ## Cardinality 1 → JString; otherwise JArray of JString. Used for
  ## ``hfRaw`` and ``hfText`` variants.
  if ne.len == 1:
    return %ne.head
  result = newJArray()
  for v in ne:
    result.add(%v)

func neAddrListsToJson(ne: NonEmptySeq[seq[EmailAddress]]): JsonNode =
  ## Cardinality 1 → JArray of address objects; otherwise JArray of JArrays.
  if ne.len == 1:
    result = newJArray()
    for ea in ne.head:
      result.add(ea.toJson())
    return
  result = newJArray()
  for lst in ne:
    var inner = newJArray()
    for ea in lst:
      inner.add(ea.toJson())
    result.add(inner)

func neGroupListsToJson(ne: NonEmptySeq[seq[EmailAddressGroup]]): JsonNode =
  ## Cardinality 1 → JArray of group objects; otherwise JArray of JArrays.
  if ne.len == 1:
    result = newJArray()
    for g in ne.head:
      result.add(g.toJson())
    return
  result = newJArray()
  for lst in ne:
    var inner = newJArray()
    for g in lst:
      inner.add(g.toJson())
    result.add(inner)

func neStringSeqToJson(ne: NonEmptySeq[seq[string]]): JsonNode =
  ## Cardinality 1 → flat JArray of JString; otherwise JArray of JArrays.
  ## Used for ``hfMessageIds`` and ``hfUrls`` variants.
  if ne.len == 1:
    result = newJArray()
    for s in ne.head:
      result.add(%s)
    return
  result = newJArray()
  for lst in ne:
    var inner = newJArray()
    for s in lst:
      inner.add(%s)
    result.add(inner)

func neDateToJson(ne: NonEmptySeq[Date]): JsonNode =
  ## Cardinality 1 → JString (RFC 3339); otherwise JArray of JString.
  if ne.len == 1:
    return ne.head.toJson()
  result = newJArray()
  for d in ne:
    result.add(d.toJson())

func blueprintMultiValueToJson*(m: BlueprintHeaderMultiValue): JsonNode =
  ## Variant dispatcher for ``BlueprintHeaderMultiValue`` serialisation.
  ## Public because consumer aggregates (``EmailBlueprint.toJson``,
  ## ``BlueprintBodyPart.toJson``) compose the wire-key and pair it with
  ## the output of this dispatcher. The value has no standalone wire
  ## identity (Design §4.5.3).
  case m.form
  of hfRaw:
    neStringToJson(m.rawValues)
  of hfText:
    neStringToJson(m.textValues)
  of hfAddresses:
    neAddrListsToJson(m.addressLists)
  of hfGroupedAddresses:
    neGroupListsToJson(m.groupLists)
  of hfMessageIds:
    neStringSeqToJson(m.messageIdLists)
  of hfDate:
    neDateToJson(m.dateValues)
  of hfUrls:
    neStringSeqToJson(m.urlLists)
