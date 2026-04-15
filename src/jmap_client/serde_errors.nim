# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for JMAP error types: RequestError (RFC 7807 problem
## details), MethodError (per-invocation), and SetError (per-item in /set
## responses). Design doc §8.

{.push raises: [], noSideEffect.}

import std/json

import ./serde
import ./types

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
  ## Used by both toJson and fromJson to determine which keys belong in extras.
  case errorType
  of setInvalidProperties:
    return @["type", "description", "properties"]
  of setAlreadyExists:
    return @["type", "description", "existingId"]
  else:
    return @["type", "description"]

func toJson*(se: SetError): JsonNode =
  ## Serialise SetError to JSON (RFC 8620 §5.3, §5.4).
  ## Extras with keys colliding with standard or variant-specific fields are
  ## silently skipped.
  var node = newJObject()
  node["type"] = %se.rawType
  for v in se.description:
    node["description"] = %v
  case se.errorType
  of setInvalidProperties:
    node["properties"] = %se.properties
  of setAlreadyExists:
    node["existingId"] = %string(se.existingId)
  else:
    discard
  for extras in se.extras:
    let knownKeys = setErrorKnownKeys(se.errorType)
    for key, val in extras.pairs:
      if key notin knownKeys:
        node[key] = val
  return node

func fromJson*(
    T: typedesc[SetError], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[SetError, SerdeViolation] =
  ## Deserialise JSON to SetError with defensive fallback (Layer 1 §8.10).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let typeNode = ?fieldJString(node, "type", path)
  let rawType = typeNode.getStr("")
  ?nonEmptyStr(rawType, "type field", path / "type")
  let description = optString(node, "description")
  let errorType = parseSetErrorType(rawType)
  # Per-variant known keys: variant-specific fields are "known" only for
  # their own variant. Misplaced RFC fields on other variants are preserved
  # in extras rather than silently dropped (Decision 1.7C: lossless).
  let knownKeys = setErrorKnownKeys(errorType)
  let extras = collectExtras(node, knownKeys)
  # Defensive fallback: dispatch to variant-specific constructors only
  # when variant data is present. Otherwise fall back to generic setError
  # which maps invalidProperties/alreadyExists to setUnknown.
  case errorType
  of setInvalidProperties:
    let propsNode = node{"properties"}
    if not propsNode.isNil and propsNode.kind == JArray:
      var properties: seq[string] = @[]
      for i, item in propsNode.getElems(@[]):
        ?expectKind(item, JString, path / "properties" / i)
        properties.add(item.getStr(""))
      return ok(setErrorInvalidProperties(rawType, properties, description, extras))
    return ok(setError(rawType, description, extras))
  of setAlreadyExists:
    let idNode = node{"existingId"}
    if not idNode.isNil and idNode.kind == JString:
      let idResult = parseIdFromServer(idNode.getStr(""))
      if idResult.isOk:
        return ok(setErrorAlreadyExists(rawType, idResult.get(), description, extras))
      # fall through to generic setError
    return ok(setError(rawType, description, extras))
  else:
    return ok(setError(rawType, description, extras))
