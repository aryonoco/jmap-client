# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for header sub-types (RFC 8621 section 4.1.2).

{.push raises: [], noSideEffect.}

import std/json

import ../serde
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
    T: typedesc[EmailHeader], node: JsonNode
): Result[EmailHeader, ValidationError] =
  ## Deserialise JSON object to EmailHeader. Rejects absent, null, or
  ## non-string ``name`` and ``value``.
  ?checkJsonKind(node, JObject, $T)
  let nameNode = node{"name"}
  ?checkJsonKind(nameNode, JString, $T, "missing or invalid name")
  let name = nameNode.getStr("")
  let valueNode = node{"value"}
  ?checkJsonKind(valueNode, JString, $T, "missing or invalid value")
  let value = valueNode.getStr("")
  return parseEmailHeader(name, value)

# =============================================================================
# HeaderValue — parseHeaderValue
# =============================================================================

func parseNullableStringArray(
    node: JsonNode, formName: string, elemDesc: string
): Result[Opt[seq[string]], ValidationError] =
  ## Shared parser for nullable string array forms (hfMessageIds, hfUrls).
  ## JNull → Opt.none. JArray of JString → Opt.some(seq).
  if node.isNil or node.kind == JNull:
    return ok(Opt.none(seq[string]))
  ?checkJsonKind(node, JArray, "HeaderValue", formName & " requires JArray or null")
  var strs: seq[string] = @[]
  for elem in node.getElems(@[]):
    ?checkJsonKind(elem, JString, "HeaderValue", elemDesc)
    strs.add(elem.getStr(""))
  return ok(Opt.some(strs))

func parseHeaderValue*(
    form: HeaderForm, node: JsonNode
): Result[HeaderValue, ValidationError] =
  ## Parses a JSON value into the correct ``HeaderValue`` variant based on
  ## the given form. Nullable forms (messageIds, date, urls) accept JNull
  ## as ``Opt.none``.
  case form
  of hfRaw:
    ?checkJsonKind(node, JString, "HeaderValue", "hfRaw requires JString")
    return ok(HeaderValue(form: hfRaw, rawValue: node.getStr("")))
  of hfText:
    ?checkJsonKind(node, JString, "HeaderValue", "hfText requires JString")
    return ok(HeaderValue(form: hfText, textValue: node.getStr("")))
  of hfAddresses:
    ?checkJsonKind(node, JArray, "HeaderValue", "hfAddresses requires JArray")
    var addrs: seq[EmailAddress] = @[]
    for elem in node.getElems(@[]):
      let ea = ?EmailAddress.fromJson(elem)
      addrs.add(ea)
    return ok(HeaderValue(form: hfAddresses, addresses: addrs))
  of hfGroupedAddresses:
    ?checkJsonKind(node, JArray, "HeaderValue", "hfGroupedAddresses requires JArray")
    var groups: seq[EmailAddressGroup] = @[]
    for elem in node.getElems(@[]):
      let g = ?EmailAddressGroup.fromJson(elem)
      groups.add(g)
    return ok(HeaderValue(form: hfGroupedAddresses, groups: groups))
  of hfMessageIds:
    let ids = ?parseNullableStringArray(
      node, "hfMessageIds", "message-id element must be string"
    )
    return ok(HeaderValue(form: hfMessageIds, messageIds: ids))
  of hfDate:
    if node.isNil or node.kind == JNull:
      return ok(HeaderValue(form: hfDate, date: Opt.none(Date)))
    let d = ?Date.fromJson(node)
    return ok(HeaderValue(form: hfDate, date: Opt.some(d)))
  of hfUrls:
    let urls = ?parseNullableStringArray(node, "hfUrls", "URL element must be string")
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
