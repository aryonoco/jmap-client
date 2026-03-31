# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}
{.experimental: "strictCaseObjects".}

## Serialisation for JMAP error types: RequestError (RFC 7807 problem
## details), MethodError (per-invocation), and SetError (per-item in /set
## responses). Design doc §8.

import std/json

import results

import ./serde
import ./types

# =============================================================================
# Lenient Opt field helpers (§1.4b: absent, null, or wrong kind -> Opt.none)
# =============================================================================

func optString(node: JsonNode, key: string): Opt[string] =
  ## Extract an optional string field leniently: absent or wrong kind -> none.
  let child = node{key}
  if child.isNil:
    Opt.none(string)
  elif child.kind != JString:
    Opt.none(string)
  else:
    Opt.some(child.getStr(""))

func optInt(node: JsonNode, key: string): Opt[int] =
  ## Extract an optional integer field leniently: absent or wrong kind -> none.
  let child = node{key}
  if child.isNil:
    Opt.none(int)
  elif child.kind != JInt:
    Opt.none(int)
  else:
    Opt.some(int(child.getBiggestInt(0)))

# =============================================================================
# RequestError
# =============================================================================

const RequestErrorKnownKeys = ["type", "status", "title", "detail", "limit"]

func toJson*(re: RequestError): JsonNode =
  ## Serialise RequestError to RFC 7807 problem details JSON.
  ## Extras with keys colliding with standard fields are silently skipped
  ## to prevent manual construction from corrupting the wire format.
  {.cast(noSideEffect).}:
    result = newJObject()
    result["type"] = %re.rawType
    if re.status.isSome:
      result["status"] = %re.status.get()
    if re.title.isSome:
      result["title"] = %re.title.get()
    if re.detail.isSome:
      result["detail"] = %re.detail.get()
    if re.limit.isSome:
      result["limit"] = %re.limit.get()
    if re.extras.isSome:
      for key, val in re.extras.get().pairs:
        if key notin RequestErrorKnownKeys:
          result[key] = val

func fromJson*(
    T: typedesc[RequestError], node: JsonNode
): Result[RequestError, ValidationError] =
  ## Deserialise RFC 7807 problem details JSON to RequestError.
  checkJsonKind(node, JObject, $T)
  checkJsonKind(node{"type"}, JString, $T, "missing or invalid type")
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
  {.cast(noSideEffect).}:
    result = newJObject()
    result["type"] = %me.rawType
    if me.description.isSome:
      result["description"] = %me.description.get()
    if me.extras.isSome:
      for key, val in me.extras.get().pairs:
        if key notin MethodErrorKnownKeys:
          result[key] = val

func fromJson*(
    T: typedesc[MethodError], node: JsonNode
): Result[MethodError, ValidationError] =
  ## Deserialise error invocation arguments to MethodError.
  checkJsonKind(node, JObject, $T)
  checkJsonKind(node{"type"}, JString, $T, "missing or invalid type")
  let rawType = node{"type"}.getStr("")
  if rawType.len == 0:
    return err(parseError($T, "empty type field"))
  let description = optString(node, "description")
  let extras = collectExtras(node, MethodErrorKnownKeys)
  ok(methodError(rawType = rawType, description = description, extras = extras))

# =============================================================================
# SetError
# =============================================================================

func toJson*(se: SetError): JsonNode =
  ## Serialise SetError to JSON (RFC 8620 §5.3, §5.4).
  ## Extras with keys colliding with standard or variant-specific fields are
  ## silently skipped.
  {.cast(noSideEffect).}:
    result = newJObject()
    result["type"] = %se.rawType
    if se.description.isSome:
      result["description"] = %se.description.get()
    case se.errorType
    of setInvalidProperties:
      result["properties"] = %se.properties
    of setAlreadyExists:
      result["existingId"] = %string(se.existingId)
    else:
      discard
    if se.extras.isSome:
      let knownKeys =
        case se.errorType
        of setInvalidProperties:
          @["type", "description", "properties"]
        of setAlreadyExists:
          @["type", "description", "existingId"]
        else:
          @["type", "description"]
      for key, val in se.extras.get().pairs:
        if key notin knownKeys:
          result[key] = val

func fromJson*(
    T: typedesc[SetError], node: JsonNode
): Result[SetError, ValidationError] =
  ## Deserialise JSON to SetError with defensive fallback (Layer 1 §8.10).
  checkJsonKind(node, JObject, $T)
  checkJsonKind(node{"type"}, JString, $T, "missing or invalid type")
  let rawType = node{"type"}.getStr("")
  if rawType.len == 0:
    return err(parseError($T, "empty type field"))
  let description = optString(node, "description")
  let errorType = parseSetErrorType(rawType)
  # Per-variant known keys: variant-specific fields are "known" only for
  # their own variant. Misplaced RFC fields on other variants are preserved
  # in extras rather than silently dropped (Decision 1.7C: lossless).
  let knownKeys =
    case errorType
    of setInvalidProperties:
      @["type", "description", "properties"]
    of setAlreadyExists:
      @["type", "description", "existingId"]
    else:
      @["type", "description"]
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
        checkJsonKind(item, JString, $T, "properties element must be string")
        properties.add(item.getStr(""))
      return ok(setErrorInvalidProperties(rawType, properties, description, extras))
    ok(setError(rawType, description, extras))
  of setAlreadyExists:
    let idNode = node{"existingId"}
    if not idNode.isNil and idNode.kind == JString:
      let existingIdResult = parseIdFromServer(idNode.getStr(""))
      if existingIdResult.isOk:
        return ok(
          setErrorAlreadyExists(rawType, existingIdResult.get(), description, extras)
        )
    ok(setError(rawType, description, extras))
  else:
    ok(setError(rawType, description, extras))
