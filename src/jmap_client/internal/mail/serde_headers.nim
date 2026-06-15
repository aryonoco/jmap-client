# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for header sub-types (RFC 8621 section 4.1.2).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json

import ../serialisation/serde
import ../serialisation/serde_diagnostics
import ../serialisation/serde_helpers
import ../serialisation/serde_primitives
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

func noneHeaderValue(form: HeaderForm): HeaderValue =
  ## The ``Opt.none`` variant for each form — the wire shape of a requested
  ## single-instance header the message lacks (RFC 8621 §4.1.3, ``null``).
  case form
  of hfRaw:
    HeaderValue(form: hfRaw, rawValue: Opt.none(string))
  of hfText:
    HeaderValue(form: hfText, textValue: Opt.none(string))
  of hfAddresses:
    HeaderValue(form: hfAddresses, addresses: Opt.none(seq[EmailAddress]))
  of hfGroupedAddresses:
    HeaderValue(form: hfGroupedAddresses, groups: Opt.none(seq[EmailAddressGroup]))
  of hfMessageIds:
    HeaderValue(form: hfMessageIds, messageIds: Opt.none(seq[string]))
  of hfDate:
    HeaderValue(form: hfDate, date: Opt.none(Date))
  of hfUrls:
    HeaderValue(form: hfUrls, urls: Opt.none(seq[string]))

func parseAddressArray(
    node: JsonNode, path: JsonPath
): Result[seq[EmailAddress], SerdeViolation] =
  ## Parse a present JSON array of address objects (RFC 8621 §4.1.2.3). The
  ## caller's top-level null guard guarantees ``node`` is non-null.
  ?expectKind(node, JArray, path)
  var addrs: seq[EmailAddress] = @[]
  for i, elem in node.getElems(@[]):
    addrs.add(?EmailAddress.fromJson(elem, path / i))
  return ok(addrs)

func parseGroupArray(
    node: JsonNode, path: JsonPath
): Result[seq[EmailAddressGroup], SerdeViolation] =
  ## Parse a present JSON array of grouped-address objects (RFC 8621
  ## §4.1.2.4). The caller's top-level null guard guarantees ``node`` is
  ## non-null.
  ?expectKind(node, JArray, path)
  var groups: seq[EmailAddressGroup] = @[]
  for i, elem in node.getElems(@[]):
    groups.add(?EmailAddressGroup.fromJson(elem, path / i))
  return ok(groups)

func parseHeaderValue*(
    form: HeaderForm, node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[HeaderValue, SerdeViolation] =
  ## Parses a JSON value into the correct ``HeaderValue`` variant based on
  ## the given form. Every form accepts JNull as ``Opt.none``: RFC 8621
  ## §4.1.3 returns ``null`` for a requested single-instance header the
  ## message lacks. The single null guard below covers all seven forms, so
  ## each ``case`` arm handles only the present-value shape.
  if node.isNil or node.kind == JNull:
    return ok(noneHeaderValue(form))
  case form
  of hfRaw:
    ?expectKind(node, JString, path)
    return ok(HeaderValue(form: hfRaw, rawValue: Opt.some(node.getStr(""))))
  of hfText:
    ?expectKind(node, JString, path)
    return ok(HeaderValue(form: hfText, textValue: Opt.some(node.getStr(""))))
  of hfAddresses:
    let addrs = ?parseAddressArray(node, path)
    return ok(HeaderValue(form: hfAddresses, addresses: Opt.some(addrs)))
  of hfGroupedAddresses:
    let groups = ?parseGroupArray(node, path)
    return ok(HeaderValue(form: hfGroupedAddresses, groups: Opt.some(groups)))
  of hfMessageIds:
    let ids = ?parseNullableStringArray(node, path)
    return ok(HeaderValue(form: hfMessageIds, messageIds: ids))
  of hfDate:
    let d = ?Date.fromJson(node, path)
    return ok(HeaderValue(form: hfDate, date: Opt.some(d)))
  of hfUrls:
    let urls = ?parseNullableStringArray(node, path)
    return ok(HeaderValue(form: hfUrls, urls: urls))

# =============================================================================
# HeaderValue — toJson
# =============================================================================

func optSeqToJsonArray[T](opt: Opt[seq[T]]): JsonNode =
  ## Emit a JSON array — each element rendered via its ``toJson`` — when the
  ## option holds a value, or ``null`` when absent (RFC 8621 §4.1.3 wire
  ## shape for a requested single-instance header the message lacks).
  result = newJNull()
  for items in opt:
    var arr = newJArray()
    for item in items:
      arr.add(item.toJson())
    result = arr

func optStringSeqToJsonArray(opt: Opt[seq[string]]): JsonNode =
  ## Emit a JSON array of strings when the option holds a value, or ``null``
  ## when absent (RFC 8621 §4.1.3 absent single-instance wire shape).
  result = newJNull()
  for items in opt:
    var arr = newJArray()
    for s in items:
      arr.add(%s)
    result = arr

func toJson*(v: HeaderValue): JsonNode =
  ## Serialise HeaderValue to JSON. ``Opt.none`` on any variant produces
  ## ``null`` — RFC 8621 §4.1.3 wire shape for an absent single instance.
  case v.form
  of hfRaw:
    optStringToJsonOrNull(v.rawValue)
  of hfText:
    optStringToJsonOrNull(v.textValue)
  of hfAddresses:
    optSeqToJsonArray(v.addresses)
  of hfGroupedAddresses:
    optSeqToJsonArray(v.groups)
  of hfMessageIds:
    optStringSeqToJsonArray(v.messageIds)
  of hfDate:
    optToJsonOrNull(v.date)
  of hfUrls:
    optStringSeqToJsonArray(v.urls)

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
