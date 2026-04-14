# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for body sub-types (RFC 8621 sections 4.1.4, 4.6).

{.push raises: [], noSideEffect.}

import std/json
import std/strutils
import std/tables

import ../serde
import ../types
import ./body
import ./headers
import ./serde_headers

# =============================================================================
# PartId
# =============================================================================

defineDistinctStringToJson(PartId)
defineDistinctStringFromJson(PartId, parsePartIdFromServer)

# =============================================================================
# EmailBodyPart — fromJson
# =============================================================================

const MaxBodyPartDepth = 128
  ## Maximum nesting depth for EmailBodyPart/BlueprintBodyPart serialisation.
  ## Defence-in-depth guard against stack overflow. Matches MaxFilterDepth
  ## in serde_framework.nim.

func parseOptString(node: JsonNode, key: string): Opt[string] =
  ## Extracts an optional string field: absent, null, or wrong kind → none.
  let f = optJsonField(node, key, JString)
  if f.isSome:
    return Opt.some(f.get().getStr(""))
  return Opt.none(string)

func parseCharsetField(node: JsonNode, ctLower: string): Opt[string] =
  ## Parse charset with text/* default (Decision C20).
  let f = optJsonField(node, "charset", JString)
  if f.isSome:
    return Opt.some(f.get().getStr(""))
  if ctLower.startsWith("text/"):
    return Opt.some("us-ascii")
  return Opt.none(string)

func parseLanguageField(
    node: JsonNode, typeName: string
): Result[Opt[seq[string]], ValidationError] =
  ## Parse optional language tag array.
  let langNode = node{"language"}
  if langNode.isNil or langNode.kind == JNull or langNode.kind != JArray:
    return ok(Opt.none(seq[string]))
  var langs: seq[string] = @[]
  for elem in langNode.getElems(@[]):
    ?checkJsonKind(elem, JString, typeName, "language element must be string")
    langs.add(elem.getStr(""))
  return ok(Opt.some(langs))

func parseSizeField(
    node: JsonNode, isMultipart: bool
): Result[UnsignedInt, ValidationError] =
  ## Parse size: required on leaf, default 0 on multipart (Decision C16).
  let sizeNode = node{"size"}
  if isMultipart and (sizeNode.isNil or sizeNode.kind != JInt):
    return ok(UnsignedInt(0))
  return UnsignedInt.fromJson(sizeNode)

func parseHeadersField(node: JsonNode): Result[seq[EmailHeader], ValidationError] =
  ## Parse optional headers array: absent or non-array yields empty seq.
  var headers: seq[EmailHeader] = @[]
  let headersNode = node{"headers"}
  if not headersNode.isNil and headersNode.kind == JArray:
    for elem in headersNode.getElems(@[]):
      headers.add(?EmailHeader.fromJson(elem))
  return ok(headers)

func fromJsonImpl(node: JsonNode, depth: int): Result[EmailBodyPart, ValidationError] =
  ## Recursive depth-limited deserialisation of EmailBodyPart.
  const typeName = "EmailBodyPart"
  ?checkJsonKind(node, JObject, typeName)
  if depth <= 0:
    return err(parseError(typeName, "maximum nesting depth exceeded"))

  # contentType from "type" wire key (Decision C19)
  let typeNode = node{"type"}
  ?checkJsonKind(typeNode, JString, typeName, "missing or invalid type")
  let contentType = typeNode.getStr("")
  let ctLower = contentType.toLowerAscii()
  let isMultipart = ctLower.startsWith("multipart/")

  # --- Shared fields ---
  let headers = ?parseHeadersField(node)
  let name = parseOptString(node, "name")
  let disposition = parseOptString(node, "disposition")
  let cid = parseOptString(node, "cid")
  let location = parseOptString(node, "location")
  let charset = parseCharsetField(node, ctLower)
  let language = ?parseLanguageField(node, typeName)
  let size = ?parseSizeField(node, isMultipart)

  # --- Branch-specific fields ---
  if isMultipart:
    var subParts: seq[EmailBodyPart] = @[]
    let subPartsNode = node{"subParts"}
    if not subPartsNode.isNil and subPartsNode.kind == JArray:
      for elem in subPartsNode.getElems(@[]):
        subParts.add(?fromJsonImpl(elem, depth - 1))
    return ok(
      EmailBodyPart(
        headers: headers,
        name: name,
        contentType: contentType,
        charset: charset,
        disposition: disposition,
        cid: cid,
        language: language,
        location: location,
        size: size,
        isMultipart: true,
        subParts: subParts,
      )
    )

  let partId = ?PartId.fromJson(node{"partId"})
  let blobId = ?Id.fromJson(node{"blobId"})
  return ok(
    EmailBodyPart(
      headers: headers,
      name: name,
      contentType: contentType,
      charset: charset,
      disposition: disposition,
      cid: cid,
      language: language,
      location: location,
      size: size,
      isMultipart: false,
      partId: partId,
      blobId: blobId,
    )
  )

func fromJson*(
    T: typedesc[EmailBodyPart], node: JsonNode
): Result[EmailBodyPart, ValidationError] =
  ## Deserialise JSON to EmailBodyPart. Recursive with depth limit.
  ## ``isMultipart`` is derived from ``contentType`` (case-insensitive).
  discard $T
  return fromJsonImpl(node, MaxBodyPartDepth)

# =============================================================================
# EmailBodyPart — toJson
# =============================================================================

func emitLanguageOrNull(node: var JsonNode, opt: Opt[seq[string]]) =
  ## Emit optional language array as value when present, null when absent.
  if opt.isSome:
    var arr = newJArray()
    for lang in opt.get():
      arr.add(%lang)
    node["language"] = arr
  else:
    node["language"] = newJNull()

func toJsonImpl(part: EmailBodyPart, depth: int): JsonNode =
  ## Recursive depth-limited serialisation of EmailBodyPart.
  var node = newJObject()
  node["type"] = %part.contentType
  if depth <= 0:
    return node

  # Shared fields — headers always emitted
  var headersArr = newJArray()
  for eh in part.headers:
    headersArr.add(eh.toJson())
  node["headers"] = headersArr

  # Optional strings: Opt.none → null
  emitOptStringOrNull(node, "name", part.name)
  emitOptStringOrNull(node, "charset", part.charset)
  emitOptStringOrNull(node, "disposition", part.disposition)
  emitOptStringOrNull(node, "cid", part.cid)
  emitLanguageOrNull(node, part.language)
  emitOptStringOrNull(node, "location", part.location)
  node["size"] = part.size.toJson()

  # Branch-specific
  if part.isMultipart:
    var subPartsArr = newJArray()
    for child in part.subParts:
      subPartsArr.add(toJsonImpl(child, depth - 1))
    node["subParts"] = subPartsArr
  else:
    node["partId"] = part.partId.toJson()
    node["blobId"] = part.blobId.toJson()

  return node

func toJson*(part: EmailBodyPart): JsonNode =
  ## Serialise EmailBodyPart to JSON. Recursive with depth limit for totality.
  return toJsonImpl(part, MaxBodyPartDepth)

# =============================================================================
# EmailBodyValue
# =============================================================================

func fromJson*(
    T: typedesc[EmailBodyValue], node: JsonNode
): Result[EmailBodyValue, ValidationError] =
  ## Deserialise JSON to EmailBodyValue.
  const typeName = "EmailBodyValue"
  ?checkJsonKind(node, JObject, typeName)
  let valueNode = node{"value"}
  ?checkJsonKind(valueNode, JString, typeName, "missing or invalid value")
  let value = valueNode.getStr("")

  # Bool flags: absent/null → default false; present non-bool → err
  let epNode = node{"isEncodingProblem"}
  if not epNode.isNil and epNode.kind != JNull and epNode.kind != JBool:
    return err(parseError(typeName, "isEncodingProblem must be boolean"))
  let isEncodingProblem = epNode.getBool(false)

  let trNode = node{"isTruncated"}
  if not trNode.isNil and trNode.kind != JNull and trNode.kind != JBool:
    return err(parseError(typeName, "isTruncated must be boolean"))
  let isTruncated = trNode.getBool(false)

  return ok(
    EmailBodyValue(
      value: value, isEncodingProblem: isEncodingProblem, isTruncated: isTruncated
    )
  )

func toJson*(bv: EmailBodyValue): JsonNode =
  ## Serialise EmailBodyValue to JSON. Always emits all three fields.
  var node = newJObject()
  node["value"] = %bv.value
  node["isEncodingProblem"] = %bv.isEncodingProblem
  node["isTruncated"] = %bv.isTruncated
  return node

# =============================================================================
# BlueprintBodyValue — toJson only (creation type, R1-3)
# =============================================================================

func toJson*(v: BlueprintBodyValue): JsonNode =
  ## Serialise BlueprintBodyValue to ``{"value": "..."}`` (Design §4.1.3).
  ## No ``fromJson`` — creation types are unidirectional.
  return %*{"value": v.value}

# =============================================================================
# BlueprintBodyPart — toJson only (creation type, Decision C31)
# =============================================================================

func emitOpt(node: var JsonNode, key: string, opt: Opt[string]) =
  ## Emit optional string field only when present; omit when absent.
  for val in opt:
    node[key] = %val

func emitLanguage(node: var JsonNode, opt: Opt[seq[string]]) =
  ## Emit optional language array only when present; omit when absent.
  for langs in opt:
    var arr = newJArray()
    for lang in langs:
      arr.add(%lang)
    node["language"] = arr

func bpToJsonImpl(bp: BlueprintBodyPart, depth: int): JsonNode =
  ## Recursive depth-limited serialisation of BlueprintBodyPart.
  var node = newJObject()
  node["type"] = %bp.contentType
  if depth <= 0:
    return node

  # Shared optional fields: OMIT when Opt.none (not null)
  emitOpt(node, "name", bp.name)
  emitOpt(node, "disposition", bp.disposition)
  emitOpt(node, "cid", bp.cid)
  emitLanguage(node, bp.language)
  emitOpt(node, "location", bp.location)

  # extraHeaders (Design §5.2): wire-key composed here per §4.5.3 — the
  # multi-value type has no standalone wire identity.
  for name, mv in bp.extraHeaders:
    let isAll = multiLen(mv) > 1
    node[composeHeaderKey(name, mv.form, isAll)] = blueprintMultiValueToJson(mv)

  # Branch-specific
  if bp.isMultipart:
    var subPartsArr = newJArray()
    for child in bp.subParts:
      subPartsArr.add(bpToJsonImpl(child, depth - 1))
    node["subParts"] = subPartsArr
  else:
    case bp.source
    of bpsInline:
      node["partId"] = bp.partId.toJson()
      # bp.value is NOT emitted here — harvested by EmailBlueprint.toJson
      # into a top-level "bodyValues" object (Design §5.4).
    of bpsBlobRef:
      node["blobId"] = bp.blobId.toJson()
      for val in bp.size:
        node["size"] = val.toJson()
      for val in bp.charset:
        node["charset"] = %val

  return node

func toJson*(bp: BlueprintBodyPart): JsonNode =
  ## Serialise BlueprintBodyPart to JSON. ``Opt.none`` fields are omitted
  ## (not emitted as null). Recursive with depth limit for totality.
  return bpToJsonImpl(bp, MaxBodyPartDepth)
