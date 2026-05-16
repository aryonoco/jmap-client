# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for JMAP error types: RequestError (RFC 7807 problem
## details), MethodError (per-invocation), and SetError (per-item in /set
## responses). Design doc §8.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json

import ./serde
import ./serde_diagnostics
import ./serde_helpers
import ../types

# =============================================================================
# Lenient Option field helpers (§1.4b: absent, null, or wrong kind -> none)
# =============================================================================

func optString(node: JsonNode, key: string): Opt[string] =
  ## Extract an optional string field leniently: absent or wrong kind -> none.
  return Opt.some((?optJsonField(node, key, JString)).getStr(""))

func optInt(node: JsonNode, key: string): Opt[int] =
  ## Extract an optional integer field leniently: absent or wrong kind -> none.
  return Opt.some(int((?optJsonField(node, key, JInt)).getBiggestInt(0)))

# =============================================================================
# RequestError
# =============================================================================

const RequestErrorKnownKeys = ["type", "status", "title", "detail", "limit"]

func toJson*(re: RequestError): JsonNode =
  ## Serialise RequestError to RFC 7807 problem details JSON.
  ## Extras with keys colliding with standard fields are silently skipped
  ## to prevent manual construction from corrupting the wire format.
  var node = newJObject()
  node["type"] = %re.rawType
  for v in re.status:
    node["status"] = %v
  for v in re.title:
    node["title"] = %v
  for v in re.detail:
    node["detail"] = %v
  for v in re.limit:
    node["limit"] = %v
  for extras in re.extras:
    for key, val in extras.pairs:
      if key notin RequestErrorKnownKeys:
        node[key] = val
  return node

func fromJson*(
    T: typedesc[RequestError], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[RequestError, SerdeViolation] =
  ## Deserialise RFC 7807 problem details JSON to RequestError.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let typeNode = ?fieldJString(node, "type", path)
  let rawType = typeNode.getStr("")
  ?nonEmptyStr(rawType, "type field", path / "type")
  let status = optInt(node, "status")
  let title = optString(node, "title")
  let detail = optString(node, "detail")
  let limit = optString(node, "limit")
  let extras = collectExtras(node, RequestErrorKnownKeys)
  return ok(
    requestError(
      rawType = rawType,
      status = status,
      title = title,
      detail = detail,
      limit = limit,
      extras = extras,
    )
  )

# =============================================================================
# MethodError
# =============================================================================

const MethodErrorKnownKeys = ["type", "description"]

func toJson*(me: MethodError): JsonNode =
  ## Serialise MethodError to JSON (RFC 8620 §3.6.2).
  ## Extras with keys colliding with standard fields are silently skipped.
  var node = newJObject()
  node["type"] = %me.rawType
  for v in me.description:
    node["description"] = %v
  for extras in me.extras:
    for key, val in extras.pairs:
      if key notin MethodErrorKnownKeys:
        node[key] = val
  return node

func fromJson*(
    T: typedesc[MethodError], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[MethodError, SerdeViolation] =
  ## Deserialise error invocation arguments to MethodError.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let typeNode = ?fieldJString(node, "type", path)
  let rawType = typeNode.getStr("")
  ?nonEmptyStr(rawType, "type field", path / "type")
  let description = optString(node, "description")
  let extras = collectExtras(node, MethodErrorKnownKeys)
  return ok(methodError(rawType = rawType, description = description, extras = extras))

# =============================================================================
# SetError
# =============================================================================

func setErrorKnownKeys(errorType: SetErrorType): seq[string] =
  ## Returns the set of known JSON keys for a given SetError variant.
  ## Used by both toJson and fromJson to determine which keys belong in
  ## extras. Each payload-bearing variant names its RFC wire field so
  ## parsers on a non-matching variant preserve the field in ``extras``
  ## rather than silently dropping it (Decision 1.7C: lossless).
  case errorType
  of setInvalidProperties:
    return @["type", "description", "properties"]
  of setAlreadyExists:
    return @["type", "description", "existingId"]
  of setBlobNotFound:
    return @["type", "description", "notFound"]
  of setInvalidEmail:
    return @["type", "description", "properties"]
  of setTooManyRecipients:
    return @["type", "description", "maxRecipients"]
  of setInvalidRecipients:
    return @["type", "description", "invalidRecipients"]
  of setTooLarge:
    return @["type", "description", "maxSize"]
  else:
    return @["type", "description"]

func toJson*(se: SetError): JsonNode =
  ## Serialise SetError to JSON (RFC 8620 §5.3 / §5.4, RFC 8621 §4.6 / §7.5).
  ## Extras with keys colliding with standard or variant-specific fields
  ## are silently skipped. Seven payload-bearing arms emit their RFC-named
  ## field; ``setTooLarge`` omits ``maxSize`` when ``Opt.none`` (SHOULD,
  ## not MUST, per §7.5).
  var node = newJObject()
  node["type"] = %se.rawType
  for v in se.description:
    node["description"] = %v
  case se.errorType
  of setInvalidProperties:
    node["properties"] = %se.properties
  of setAlreadyExists:
    node["existingId"] = %($se.existingId)
  of setBlobNotFound:
    var arr = newJArray()
    for id in se.notFound:
      arr.add(%($id))
    node["notFound"] = arr
  of setInvalidEmail:
    node["properties"] = %se.invalidEmailPropertyNames
  of setTooManyRecipients:
    node["maxRecipients"] = %se.maxRecipientCount.toInt64
  of setInvalidRecipients:
    node["invalidRecipients"] = %se.invalidRecipients
  of setTooLarge:
    for v in se.maxSizeOctets:
      node["maxSize"] = %v.toInt64
  else:
    discard
  for extras in se.extras:
    let knownKeys = setErrorKnownKeys(se.errorType)
    for key, val in extras.pairs:
      if key notin knownKeys:
        node[key] = val
  return node

func parseStringArrayField(
    node: JsonNode, fieldName: string, path: JsonPath
): Result[seq[string], SerdeViolation] =
  ## Parses a JSON string array at ``fieldName`` from ``node``. Rejects
  ## non-string elements with a typed violation. Shared by fromJson arms
  ## for ``properties``, ``invalidRecipients``, and invalidEmail's
  ## ``properties`` key.
  let arr = node{fieldName}
  var items: seq[string] = @[]
  if arr.isNil or arr.kind != JArray:
    return ok(items)
  for i, item in arr.getElems(@[]):
    ?expectKind(item, JString, path / fieldName / i)
    items.add(item.getStr(""))
  return ok(items)

func fromJsonBlobNotFound(
    rawType: string,
    description: Opt[string],
    extras: Opt[JsonNode],
    node: JsonNode,
    path: JsonPath,
): Result[SetError, SerdeViolation] =
  ## Parses ``setBlobNotFound`` payload. Absent or wrong-kind ``notFound``
  ## falls through to generic ``setError``, which maps the variant to
  ## ``setUnknown`` — the server failed to supply the MUST field.
  let arr = node{"notFound"}
  if arr.isNil or arr.kind != JArray:
    return ok(setError(rawType, description, extras))
  var ids: seq[BlobId] = @[]
  for i, item in arr.getElems(@[]):
    ?expectKind(item, JString, path / "notFound" / i)
    let idResult = parseBlobId(item.getStr(""))
    if idResult.isErr:
      return ok(setError(rawType, description, extras))
    ids.add(idResult.get())
  return ok(setErrorBlobNotFound(rawType, ids, description, extras))

func fromJsonInvalidEmail(
    rawType: string,
    description: Opt[string],
    extras: Opt[JsonNode],
    node: JsonNode,
    path: JsonPath,
): Result[SetError, SerdeViolation] =
  ## Parses ``setInvalidEmail`` payload — the ``properties`` array of
  ## invalid Email property names (RFC 8621 §7.5 SHOULD).
  let arr = node{"properties"}
  if arr.isNil or arr.kind != JArray:
    return ok(setError(rawType, description, extras))
  let properties = ?parseStringArrayField(node, "properties", path)
  return ok(setErrorInvalidEmail(rawType, properties, description, extras))

func fromJsonTooManyRecipients(
    rawType: string,
    description: Opt[string],
    extras: Opt[JsonNode],
    node: JsonNode,
    path: JsonPath,
): Result[SetError, SerdeViolation] =
  ## Parses ``setTooManyRecipients`` payload — the server's recipient cap
  ## (RFC 8621 §7.5 MUST).
  discard $path # consumed for nimalyzer params rule
  let n = node{"maxRecipients"}
  if n.isNil or n.kind != JInt:
    return ok(setError(rawType, description, extras))
  let uiResult = parseUnsignedInt(n.getBiggestInt(0))
  if uiResult.isErr:
    return ok(setError(rawType, description, extras))
  return ok(setErrorTooManyRecipients(rawType, uiResult.get(), description, extras))

func fromJsonInvalidRecipients(
    rawType: string,
    description: Opt[string],
    extras: Opt[JsonNode],
    node: JsonNode,
    path: JsonPath,
): Result[SetError, SerdeViolation] =
  ## Parses ``setInvalidRecipients`` payload — the list of recipient
  ## addresses that failed validation (RFC 8621 §7.5 MUST).
  let arr = node{"invalidRecipients"}
  if arr.isNil or arr.kind != JArray:
    return ok(setError(rawType, description, extras))
  let addrs = ?parseStringArrayField(node, "invalidRecipients", path)
  return ok(setErrorInvalidRecipients(rawType, addrs, description, extras))

func fromJsonTooLarge(
    rawType: string, description: Opt[string], extras: Opt[JsonNode], node: JsonNode
): SetError =
  ## Parses ``setTooLarge`` payload — the server's optional size cap
  ## (RFC 8621 §7.5 SHOULD). Absent ``maxSize`` yields an ``Opt.none``
  ## arm; the variant is preserved regardless of whether the cap was
  ## supplied.
  let n = node{"maxSize"}
  var maxSize = Opt.none(UnsignedInt)
  if not n.isNil and n.kind == JInt:
    let uiResult = parseUnsignedInt(n.getBiggestInt(0))
    if uiResult.isOk:
      maxSize = Opt.some(uiResult.get())
  return setErrorTooLarge(rawType, maxSize, description, extras)

func fromJsonInvalidProperties(
    rawType: string,
    description: Opt[string],
    extras: Opt[JsonNode],
    node: JsonNode,
    path: JsonPath,
): Result[SetError, SerdeViolation] =
  ## Parses ``setInvalidProperties`` payload — the list of invalid
  ## property names (RFC 8620 §5.3 SHOULD).
  let arr = node{"properties"}
  if arr.isNil or arr.kind != JArray:
    return ok(setError(rawType, description, extras))
  let properties = ?parseStringArrayField(node, "properties", path)
  return ok(setErrorInvalidProperties(rawType, properties, description, extras))

func fromJsonAlreadyExists(
    rawType: string, description: Opt[string], extras: Opt[JsonNode], node: JsonNode
): SetError =
  ## Parses ``setAlreadyExists`` payload — the existing record's ID
  ## (RFC 8620 §5.4 MUST).
  let idNode = node{"existingId"}
  if not idNode.isNil and idNode.kind == JString:
    let idResult = parseIdFromServer(idNode.getStr(""))
    if idResult.isOk:
      return setErrorAlreadyExists(rawType, idResult.get(), description, extras)
  return setError(rawType, description, extras)

func fromJson*(
    T: typedesc[SetError], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[SetError, SerdeViolation] =
  ## Deserialise JSON to SetError with defensive fallback (Layer 1 §8.10).
  ## Dispatches across the seven payload-bearing arms; missing or
  ## malformed payload falls through to ``setError`` which maps the
  ## required-payload variants to ``setUnknown``.
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let typeNode = ?fieldJString(node, "type", path)
  let rawType = typeNode.getStr("")
  ?nonEmptyStr(rawType, "type field", path / "type")
  let description = optString(node, "description")
  let errorType = parseSetErrorType(rawType)
  let knownKeys = setErrorKnownKeys(errorType)
  let extras = collectExtras(node, knownKeys)
  case errorType
  of setInvalidProperties:
    return fromJsonInvalidProperties(rawType, description, extras, node, path)
  of setAlreadyExists:
    return ok(fromJsonAlreadyExists(rawType, description, extras, node))
  of setBlobNotFound:
    return fromJsonBlobNotFound(rawType, description, extras, node, path)
  of setInvalidEmail:
    return fromJsonInvalidEmail(rawType, description, extras, node, path)
  of setTooManyRecipients:
    return fromJsonTooManyRecipients(rawType, description, extras, node, path)
  of setInvalidRecipients:
    return fromJsonInvalidRecipients(rawType, description, extras, node, path)
  of setTooLarge:
    return ok(fromJsonTooLarge(rawType, description, extras, node))
  else:
    return ok(setError(rawType, description, extras))
