# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for JMAP error types: RequestError (RFC 7807 problem
## details), MethodError (per-invocation), and SetError (per-item in /set
## responses). Design doc §8.

{.push raises: [].}

import std/json

import ./serde
import ./types

# =============================================================================
# Lenient Option field helpers (§1.4b: absent, null, or wrong kind -> none)
# =============================================================================

func optString(node: JsonNode, key: string): Opt[string] =
  ## Extract an optional string field leniently: absent or wrong kind -> none.
  Opt.some((?optJsonField(node, key, JString)).getStr(""))

func optInt(node: JsonNode, key: string): Opt[int] =
  ## Extract an optional integer field leniently: absent or wrong kind -> none.
  Opt.some(int((?optJsonField(node, key, JInt)).getBiggestInt(0)))

# =============================================================================
# RequestError
# =============================================================================

const RequestErrorKnownKeys = ["type", "status", "title", "detail", "limit"]

func toJson*(re: RequestError): JsonNode =
  ## Serialise RequestError to RFC 7807 problem details JSON.
  ## Extras with keys colliding with standard fields are silently skipped
  ## to prevent manual construction from corrupting the wire format.
  result = newJObject()
  result["type"] = %re.rawType
  for v in re.status:
    result["status"] = %v
  for v in re.title:
    result["title"] = %v
  for v in re.detail:
    result["detail"] = %v
  for v in re.limit:
    result["limit"] = %v
  for extras in re.extras:
    for key, val in extras.pairs:
      if key notin RequestErrorKnownKeys:
        result[key] = val

func fromJson*(
    T: typedesc[RequestError], node: JsonNode
): Result[RequestError, ValidationError] =
  ## Deserialise RFC 7807 problem details JSON to RequestError.
  ?checkJsonKind(node, JObject, $T)
  ?checkJsonKind(node{"type"}, JString, $T, "missing or invalid type")
  let rawType = node{"type"}.getStr("")
  if rawType.len == 0:
    return err(parseError($T, "empty type field"))
  let status = optInt(node, "status")
  let title = optString(node, "title")
  let detail = optString(node, "detail")
  let limit = optString(node, "limit")
  let extras = collectExtras(node, RequestErrorKnownKeys)
  ok(
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
  result = newJObject()
  result["type"] = %me.rawType
  for v in me.description:
    result["description"] = %v
  for extras in me.extras:
    for key, val in extras.pairs:
      if key notin MethodErrorKnownKeys:
        result[key] = val

func fromJson*(
    T: typedesc[MethodError], node: JsonNode
): Result[MethodError, ValidationError] =
  ## Deserialise error invocation arguments to MethodError.
  ?checkJsonKind(node, JObject, $T)
  ?checkJsonKind(node{"type"}, JString, $T, "missing or invalid type")
  let rawType = node{"type"}.getStr("")
  if rawType.len == 0:
    return err(parseError($T, "empty type field"))
  let description = optString(node, "description")
  let extras = collectExtras(node, MethodErrorKnownKeys)
  ok(methodError(rawType = rawType, description = description, extras = extras))

# =============================================================================
# SetError
# =============================================================================

func setErrorKnownKeys(errorType: SetErrorType): seq[string] =
  ## Returns the set of known JSON keys for a given SetError variant.
  ## Used by both toJson and fromJson to determine which keys belong in extras.
  case errorType
  of setInvalidProperties:
    @["type", "description", "properties"]
  of setAlreadyExists:
    @["type", "description", "existingId"]
  else:
    @["type", "description"]

func toJson*(se: SetError): JsonNode =
  ## Serialise SetError to JSON (RFC 8620 §5.3, §5.4).
  ## Extras with keys colliding with standard or variant-specific fields are
  ## silently skipped.
  result = newJObject()
  result["type"] = %se.rawType
  for v in se.description:
    result["description"] = %v
  case se.errorType
  of setInvalidProperties:
    result["properties"] = %se.properties
  of setAlreadyExists:
    result["existingId"] = %string(se.existingId)
  else:
    discard
  for extras in se.extras:
    let knownKeys = setErrorKnownKeys(se.errorType)
    for key, val in extras.pairs:
      if key notin knownKeys:
        result[key] = val

func fromJson*(
    T: typedesc[SetError], node: JsonNode
): Result[SetError, ValidationError] =
  ## Deserialise JSON to SetError with defensive fallback (Layer 1 §8.10).
  ?checkJsonKind(node, JObject, $T)
  ?checkJsonKind(node{"type"}, JString, $T, "missing or invalid type")
  let rawType = node{"type"}.getStr("")
  if rawType.len == 0:
    return err(parseError($T, "empty type field"))
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
      for item in propsNode.getElems(@[]):
        if item.isNil:
          return err(parseError($T, "properties element is nil"))
        ?checkJsonKind(item, JString, $T, "properties element must be string")
        properties.add(item.getStr(""))
      return ok(setErrorInvalidProperties(rawType, properties, description, extras))
    ok(setError(rawType, description, extras))
  of setAlreadyExists:
    let idNode = node{"existingId"}
    if not idNode.isNil and idNode.kind == JString:
      let idResult = parseIdFromServer(idNode.getStr(""))
      if idResult.isOk:
        return ok(setErrorAlreadyExists(rawType, idResult.get(), description, extras))
      # fall through to generic setError
    ok(setError(rawType, description, extras))
  else:
    ok(setError(rawType, description, extras))
