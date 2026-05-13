# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for body sub-types (RFC 8621 sections 4.1.4, 4.6).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/strutils
import std/tables

import ../serialisation/serde
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

func parseOptString(node: JsonNode, key: string): Opt[string] =
  ## Extracts an optional string field: absent, null, or wrong kind → none.
  let f = optJsonField(node, key, JString)
  if f.isSome:
    return Opt.some(f.get().getStr(""))
  return Opt.none(string)

func parseOptDisposition(
    node: JsonNode, path: JsonPath
): Result[Opt[ContentDisposition], SerdeViolation] =
  ## Parses the optional ``disposition`` field. Absent, null, or wrong kind
  ## yields none; present-string goes through ``parseContentDisposition`` so
  ## malformed wire tokens surface at the parsing boundary rather than being
  ## silently round-tripped.
  let f = optJsonField(node, "disposition", JString)
  if f.isSome:
    let d =
      ?wrapInner(parseContentDisposition(f.get().getStr("")), path / "disposition")
    return ok(Opt.some(d))
  return ok(Opt.none(ContentDisposition))

func parseCharsetField(node: JsonNode, ctLower: string): Opt[string] =
  ## Parse charset with text/* default (Decision C20).
  let f = optJsonField(node, "charset", JString)
  if f.isSome:
    return Opt.some(f.get().getStr(""))
  if ctLower.startsWith("text/"):
    return Opt.some("us-ascii")
  return Opt.none(string)

func parseLanguageField(
    node: JsonNode, path: JsonPath
): Result[Opt[seq[string]], SerdeViolation] =
  ## Parse optional language tag array.
  let langNode = node{"language"}
  if langNode.isNil or langNode.kind == JNull or langNode.kind != JArray:
    return ok(Opt.none(seq[string]))
  var langs: seq[string] = @[]
  for i, elem in langNode.getElems(@[]):
    ?expectKind(elem, JString, path / "language" / i)
    langs.add(elem.getStr(""))
  return ok(Opt.some(langs))

func parseSizeField(
    node: JsonNode, isMultipart: bool, path: JsonPath
): Result[UnsignedInt, SerdeViolation] =
  ## Parse size: required on leaf, default 0 on multipart (Decision C16).
  let sizeNode = node{"size"}
  if isMultipart and (sizeNode.isNil or sizeNode.kind != JInt):
    return ok(parseUnsignedInt(0).get())
  return UnsignedInt.fromJson(sizeNode, path / "size")

func parseHeadersField(
    node: JsonNode, path: JsonPath
): Result[seq[EmailHeader], SerdeViolation] =
  ## Parse optional headers array: absent or non-array yields empty seq.
  var headers: seq[EmailHeader] = @[]
  let headersNode = node{"headers"}
  if not headersNode.isNil and headersNode.kind == JArray:
    for i, elem in headersNode.getElems(@[]):
      headers.add(?EmailHeader.fromJson(elem, path / "headers" / i))
  return ok(headers)

func fromJsonImpl(
    node: JsonNode, depth: int, path: JsonPath
): Result[EmailBodyPart, SerdeViolation] =
  ## Recursive depth-limited deserialisation of EmailBodyPart.
  ?expectKind(node, JObject, path)
  if depth <= 0:
    return err(
      SerdeViolation(kind: svkDepthExceeded, path: path, maxDepth: MaxBodyPartDepth)
    )

  # contentType from "type" wire key (Decision C19)
  let typeNode = ?fieldJString(node, "type", path)
  let contentType = typeNode.getStr("")
  let ctLower = contentType.toLowerAscii()
  let isMultipart = ctLower.startsWith("multipart/")

  # --- Shared fields ---
  let headers = ?parseHeadersField(node, path)
  let name = parseOptString(node, "name")
  let disposition = ?parseOptDisposition(node, path)
  let cid = parseOptString(node, "cid")
  let location = parseOptString(node, "location")
  let charset = parseCharsetField(node, ctLower)
  let language = ?parseLanguageField(node, path)
  let size = ?parseSizeField(node, isMultipart, path)

  # --- Branch-specific fields ---
  if isMultipart:
    var subParts: seq[EmailBodyPart] = @[]
    let subPartsNode = node{"subParts"}
    if not subPartsNode.isNil and subPartsNode.kind == JArray:
      for i, elem in subPartsNode.getElems(@[]):
        subParts.add(?fromJsonImpl(elem, depth - 1, path / "subParts" / i))
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

  let partIdNode = ?fieldJString(node, "partId", path)
  let partId = ?PartId.fromJson(partIdNode, path / "partId")
  let blobIdNode = ?fieldJString(node, "blobId", path)
  let blobId = ?BlobId.fromJson(blobIdNode, path / "blobId")
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
    T: typedesc[EmailBodyPart], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[EmailBodyPart, SerdeViolation] =
  ## Deserialise JSON to EmailBodyPart. Recursive with depth limit.
  ## ``isMultipart`` is derived from ``contentType`` (case-insensitive).
  discard $T
  return fromJsonImpl(node, MaxBodyPartDepth, path)

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
  node["name"] = part.name.optStringToJsonOrNull()
  node["charset"] = part.charset.optStringToJsonOrNull()
  if part.disposition.isSome:
    node["disposition"] = %($part.disposition.get())
  else:
    node["disposition"] = newJNull()
  node["cid"] = part.cid.optStringToJsonOrNull()
  emitLanguageOrNull(node, part.language)
  node["location"] = part.location.optStringToJsonOrNull()
  node["size"] = part.size.toJson()

  # Branch-specific — case on isMultipart (not if) for strictCaseObjects.
  case part.isMultipart
  of true:
    var subPartsArr = newJArray()
    for child in part.subParts:
      subPartsArr.add(toJsonImpl(child, depth - 1))
    node["subParts"] = subPartsArr
  of false:
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
    T: typedesc[EmailBodyValue], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[EmailBodyValue, SerdeViolation] =
  ## Deserialise JSON to EmailBodyValue.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let valueNode = ?fieldJString(node, "value", path)
  let value = valueNode.getStr("")

  # Bool flags: absent/null → default false; present non-bool → err
  let epNode = node{"isEncodingProblem"}
  if not epNode.isNil and epNode.kind != JNull and epNode.kind != JBool:
    return err(
      SerdeViolation(
        kind: svkWrongKind,
        path: path / "isEncodingProblem",
        expectedKind: JBool,
        actualKind: epNode.kind,
      )
    )
  let isEncodingProblem = epNode.getBool(false)

  let trNode = node{"isTruncated"}
  if not trNode.isNil and trNode.kind != JNull and trNode.kind != JBool:
    return err(
      SerdeViolation(
        kind: svkWrongKind,
        path: path / "isTruncated",
        expectedKind: JBool,
        actualKind: trNode.kind,
      )
    )
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

func bpToJsonImpl(bp: BlueprintBodyPart): JsonNode =
  ## Recursive serialisation of BlueprintBodyPart. Unbounded by construction:
  ## ``parseEmailBlueprint`` rejects trees exceeding ``MaxBodyPartDepth``
  ## via ``ebcBodyPartDepthExceeded``, so a well-typed blueprint's tree is
  ## guaranteed to fit the stack budget.
  var node = newJObject()
  node["type"] = %bp.contentType

  # Shared optional fields: OMIT when Opt.none (not null)
  emitOpt(node, "name", bp.name)
  for d in bp.disposition:
    node["disposition"] = %($d)
  emitOpt(node, "cid", bp.cid)
  emitLanguage(node, bp.language)
  emitOpt(node, "location", bp.location)

  # extraHeaders (Design §5.2): wire-key composed here per §4.5.3 — the
  # multi-value type has no standalone wire identity.
  for name, mv in bp.extraHeaders:
    let isAll = multiLen(mv) > 1
    node[composeHeaderKey(name, mv.form, isAll)] = blueprintMultiValueToJson(mv)

  # Branch-specific — outer case on BlueprintBodyPart.isMultipart, inner
  # case on BlueprintLeafPart.source. Each discriminator is on its own
  # type, so strict tracks them independently (nested case objects on the
  # same type would be rejected).
  case bp.isMultipart
  of true:
    var subPartsArr = newJArray()
    for child in bp.subParts:
      subPartsArr.add(bpToJsonImpl(child))
    node["subParts"] = subPartsArr
  of false:
    case bp.leaf.source
    of bpsInline:
      node["partId"] = bp.leaf.partId.toJson()
      # bp.leaf.value is NOT emitted here — harvested by EmailBlueprint.toJson
      # into a top-level "bodyValues" object (Design §5.4).
    of bpsBlobRef:
      node["blobId"] = bp.leaf.blobId.toJson()
      for val in bp.leaf.size:
        node["size"] = val.toJson()
      for val in bp.leaf.charset:
        node["charset"] = %val

  return node

func toJson*(bp: BlueprintBodyPart): JsonNode =
  ## Serialise BlueprintBodyPart to JSON. ``Opt.none`` fields are omitted
  ## (not emitted as null). Bounded by construction — see ``bpToJsonImpl``.
  return bpToJsonImpl(bp)
