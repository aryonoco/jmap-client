# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for Layer 2 error serialisation: RequestError, MethodError, and
## SetError round-trip, structural, edge-case, and property-based tests.

import std/json
import std/random
import std/strutils

import results

import jmap_client/serde
import jmap_client/serde_errors
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/errors
import jmap_client/validation

import ../massertions
import ../mfixtures
import ../mproperty

# ---------------------------------------------------------------------------
# Helper definitions
# ---------------------------------------------------------------------------

func setErrorEq(a, b: SetError): bool =
  ## Deep value equality for SetError (case object). Required because
  ## auto-generated == may not handle Opt[JsonNode] refs correctly.
  if a.rawType != b.rawType or a.errorType != b.errorType or
      a.description != b.description or a.extras != b.extras:
    return false
  case a.errorType
  of setInvalidProperties:
    a.properties == b.properties
  of setAlreadyExists:
    a.existingId == b.existingId
  else:
    true

template assertSetOkEq(r: untyped, expected: SetError) =
  ## Verifies Result is Ok and its SetError value equals expected.
  doAssert r.isOk, "expected Ok, got Err"
  let v = r.get()
  doAssert setErrorEq(v, expected), "SetError values differ"

# =============================================================================
# A. Round-trip tests
# =============================================================================

block roundTripRequestErrorMinimal:
  let original = makeRequestError()
  assertOkEq RequestError.fromJson(original.toJson()), original

block roundTripRequestErrorFull:
  {.cast(noSideEffect).}:
    let extras = newJObject()
    extras["vendor"] = %"ext-info"
    let original = requestError(
      rawType = "urn:ietf:params:jmap:error:limit",
      status = Opt.some(429),
      title = Opt.some("Rate limit exceeded"),
      detail = Opt.some("Too many requests in the last minute"),
      limit = Opt.some("maxCallsInRequest"),
      extras = Opt.some(extras),
    )
    assertOkEq RequestError.fromJson(original.toJson()), original

block roundTripRequestErrorUnknownType:
  let original = requestError(rawType = "urn:example:custom:error")
  doAssert original.errorType == retUnknown
  let rt = RequestError.fromJson(original.toJson())
  assertOk rt
  assertEq rt.get().rawType, "urn:example:custom:error"
  doAssert rt.get().errorType == retUnknown

block roundTripMethodErrorMinimal:
  let original = makeMethodError()
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorFull:
  {.cast(noSideEffect).}:
    let extras = newJObject()
    extras["serverHint"] = %"retry after 5s"
    let original = methodError(
      rawType = "serverFail",
      description = Opt.some("Internal server error"),
      extras = Opt.some(extras),
    )
    assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorUnknownType:
  let original = methodError(rawType = "customVendorError")
  doAssert original.errorType == metUnknown
  let rt = MethodError.fromJson(original.toJson())
  assertOk rt
  assertEq rt.get().rawType, "customVendorError"
  doAssert rt.get().errorType == metUnknown

block roundTripSetErrorForbidden:
  let original = setError("forbidden")
  doAssert original.errorType == setForbidden
  assertSetOkEq SetError.fromJson(original.toJson()), original

block roundTripSetErrorInvalidProperties:
  let original = makeSetErrorInvalidProperties()
  assertSetOkEq SetError.fromJson(original.toJson()), original

block roundTripSetErrorInvalidPropertiesEmpty:
  let original = setErrorInvalidProperties("invalidProperties", @[])
  assertSetOkEq SetError.fromJson(original.toJson()), original

block roundTripSetErrorAlreadyExists:
  let original = makeSetErrorAlreadyExists()
  assertSetOkEq SetError.fromJson(original.toJson()), original

block roundTripSetErrorUnknownType:
  let original = setError("vendorSpecific")
  doAssert original.errorType == setUnknown
  let rt = SetError.fromJson(original.toJson())
  assertOk rt
  let v = rt.get()
  assertEq v.rawType, "vendorSpecific"
  doAssert v.errorType == setUnknown

# =============================================================================
# B. toJson structural correctness
# =============================================================================

block requestErrorToJsonFieldNames:
  let re = makeRequestError()
  let j = re.toJson()
  doAssert j.kind == JObject
  doAssert j{"type"} != nil
  doAssert j{"type"}.kind == JString
  # Minimal error: optional fields absent
  doAssert j{"status"}.isNil
  doAssert j{"title"}.isNil
  doAssert j{"detail"}.isNil
  doAssert j{"limit"}.isNil

block requestErrorToJsonExtrasFlattened:
  {.cast(noSideEffect).}:
    let extras = newJObject()
    extras["vendorExt"] = %"data"
    let re = requestError(
      rawType = "urn:ietf:params:jmap:error:notJSON", extras = Opt.some(extras)
    )
    let j = re.toJson()
    doAssert j{"vendorExt"} != nil
    assertEq j{"vendorExt"}.getStr(""), "data"

block methodErrorToJsonFieldNames:
  let me = methodError(rawType = "invalidArguments", description = Opt.some("bad args"))
  let j = me.toJson()
  doAssert j.kind == JObject
  doAssert j{"type"} != nil
  assertEq j{"type"}.getStr(""), "invalidArguments"
  doAssert j{"description"} != nil
  assertEq j{"description"}.getStr(""), "bad args"

block setErrorToJsonInvalidProperties:
  let se = makeSetErrorInvalidProperties()
  let j = se.toJson()
  doAssert j{"type"} != nil
  assertEq j{"type"}.getStr(""), "invalidProperties"
  doAssert j{"properties"} != nil
  doAssert j{"properties"}.kind == JArray
  doAssert j{"properties"}.len > 0

block setErrorToJsonInvalidPropertiesEmpty:
  let se = setErrorInvalidProperties("invalidProperties", @[])
  let j = se.toJson()
  doAssert j{"properties"} != nil, "properties key must be present even when empty"
  doAssert j{"properties"}.kind == JArray
  assertEq j{"properties"}.len, 0

block setErrorToJsonAlreadyExists:
  let se = makeSetErrorAlreadyExists()
  let j = se.toJson()
  doAssert j{"type"} != nil
  assertEq j{"type"}.getStr(""), "alreadyExists"
  doAssert j{"existingId"} != nil
  doAssert j{"existingId"}.kind == JString

block setErrorToJsonGenericNoVariantFields:
  let se = setError("forbidden")
  let j = se.toJson()
  doAssert j{"type"} != nil
  assertEq j{"type"}.getStr(""), "forbidden"
  doAssert j{"properties"}.isNil
  doAssert j{"existingId"}.isNil

# =============================================================================
# C. Edge-case deserialization
# =============================================================================

# --- RequestError ---

block requestErrorDeserMissingType:
  {.cast(noSideEffect).}:
    let j = %*{"status": 400}
    assertErr RequestError.fromJson(j)

block requestErrorDeserTypeWrongKind:
  {.cast(noSideEffect).}:
    let j = %*{"type": 42}
    assertErr RequestError.fromJson(j)

block requestErrorDeserEmptyType:
  {.cast(noSideEffect).}:
    let j = %*{"type": ""}
    assertErrContains RequestError.fromJson(j), "empty type field"

block requestErrorDeserUnknownType:
  {.cast(noSideEffect).}:
    let j = %*{"type": "urn:example:custom"}
    let r = RequestError.fromJson(j)
    assertOk r
    doAssert r.get().errorType == retUnknown
    assertEq r.get().rawType, "urn:example:custom"

block requestErrorDeserExtrasCollected:
  {.cast(noSideEffect).}:
    let j = %*{"type": "urn:ietf:params:jmap:error:notJSON", "vendorField": "data"}
    let r = RequestError.fromJson(j)
    assertOk r
    doAssert r.get().extras.isSome

block requestErrorDeserStatusWrongKindLenient:
  {.cast(noSideEffect).}:
    let j = %*{"type": "urn:ietf:params:jmap:error:limit", "status": "bad"}
    let r = RequestError.fromJson(j)
    assertOk r
    doAssert r.get().status.isNone, "wrong kind status should be treated as none"

block requestErrorDeserNil:
  const nilNode: JsonNode = nil
  assertErr RequestError.fromJson(nilNode)

block requestErrorDeserJNull:
  assertErr RequestError.fromJson(newJNull())

# --- MethodError ---

block methodErrorDeserMissingType:
  {.cast(noSideEffect).}:
    let j = %*{"description": "foo"}
    assertErr MethodError.fromJson(j)

block methodErrorDeserTypeWrongKind:
  {.cast(noSideEffect).}:
    let j = %*{"type": 42}
    assertErr MethodError.fromJson(j)

block methodErrorDeserEmptyType:
  {.cast(noSideEffect).}:
    let j = %*{"type": ""}
    assertErrContains MethodError.fromJson(j), "empty type field"

block methodErrorDeserUnknownType:
  {.cast(noSideEffect).}:
    let j = %*{"type": "customVendorError"}
    let r = MethodError.fromJson(j)
    assertOk r
    doAssert r.get().errorType == metUnknown

block methodErrorDeserDescriptionWrongKindLenient:
  {.cast(noSideEffect).}:
    let j = %*{"type": "serverFail", "description": 42}
    let r = MethodError.fromJson(j)
    assertOk r
    doAssert r.get().description.isNone,
      "wrong kind description should be treated as none"

block methodErrorDeserExtrasCollected:
  {.cast(noSideEffect).}:
    let j = %*{"type": "serverFail", "extra": "vendor"}
    let r = MethodError.fromJson(j)
    assertOk r
    doAssert r.get().extras.isSome

block methodErrorDeserNil:
  const nilNode: JsonNode = nil
  assertErr MethodError.fromJson(nilNode)

block methodErrorDeserJNull:
  assertErr MethodError.fromJson(newJNull())

# --- SetError ---

block setErrorDeserForbidden:
  {.cast(noSideEffect).}:
    let j = %*{"type": "forbidden"}
    let r = SetError.fromJson(j)
    assertOk r
    doAssert r.get().errorType == setForbidden

block setErrorDeserInvalidPropertiesWithProps:
  {.cast(noSideEffect).}:
    let j = %*{"type": "invalidProperties", "properties": ["name", "role"]}
    let r = SetError.fromJson(j)
    assertOk r
    let v = r.get()
    doAssert v.errorType == setInvalidProperties
    assertEq v.properties.len, 2

block setErrorDeserInvalidPropertiesEmptyArray:
  {.cast(noSideEffect).}:
    let j = %*{"type": "invalidProperties", "properties": []}
    let r = SetError.fromJson(j)
    assertOk r
    let v = r.get()
    doAssert v.errorType == setInvalidProperties
    assertEq v.properties.len, 0

block setErrorDeserInvalidPropertiesMissing:
  {.cast(noSideEffect).}:
    let j = %*{"type": "invalidProperties"}
    let r = SetError.fromJson(j)
    assertOk r
    doAssert r.get().errorType == setUnknown, "defensive fallback to setUnknown"

block setErrorDeserInvalidPropertiesWrongKind:
  {.cast(noSideEffect).}:
    let j = %*{"type": "invalidProperties", "properties": 42}
    let r = SetError.fromJson(j)
    assertOk r
    doAssert r.get().errorType == setUnknown, "wrong kind triggers defensive fallback"

block setErrorDeserInvalidPropertiesNonStringElement:
  {.cast(noSideEffect).}:
    let j = %*{"type": "invalidProperties", "properties": [42]}
    assertErrContains SetError.fromJson(j), "properties element must be string"

block setErrorDeserAlreadyExistsWithId:
  {.cast(noSideEffect).}:
    let j = %*{"type": "alreadyExists", "existingId": "msg42"}
    let r = SetError.fromJson(j)
    assertOk r
    let v = r.get()
    doAssert v.errorType == setAlreadyExists
    assertEq string(v.existingId), "msg42"

block setErrorDeserAlreadyExistsMissing:
  {.cast(noSideEffect).}:
    let j = %*{"type": "alreadyExists"}
    let r = SetError.fromJson(j)
    assertOk r
    doAssert r.get().errorType == setUnknown, "defensive fallback to setUnknown"

block setErrorDeserAlreadyExistsWrongKind:
  {.cast(noSideEffect).}:
    let j = %*{"type": "alreadyExists", "existingId": 42}
    let r = SetError.fromJson(j)
    assertOk r
    doAssert r.get().errorType == setUnknown, "wrong kind triggers defensive fallback"

block setErrorDeserAlreadyExistsEmptyId:
  {.cast(noSideEffect).}:
    let j = %*{"type": "alreadyExists", "existingId": ""}
    assertErr SetError.fromJson(j)

block setErrorDeserVendorSpecific:
  {.cast(noSideEffect).}:
    let j = %*{"type": "vendorSpecific"}
    let r = SetError.fromJson(j)
    assertOk r
    assertEq r.get().rawType, "vendorSpecific"
    doAssert r.get().errorType == setUnknown

block setErrorDeserPerVariantKnownKeys:
  {.cast(noSideEffect).}:
    let j = %*{"type": "forbidden", "properties": ["name"]}
    let r = SetError.fromJson(j)
    assertOk r
    let v = r.get()
    doAssert v.errorType == setForbidden
    doAssert v.extras.isSome, "misplaced properties should be in extras"

block setErrorDeserDescriptionWrongKindLenient:
  {.cast(noSideEffect).}:
    let j = %*{"type": "forbidden", "description": 42}
    let r = SetError.fromJson(j)
    assertOk r
    doAssert r.get().description.isNone

block setErrorDeserMissingType:
  {.cast(noSideEffect).}:
    let j = %*{"description": "foo"}
    assertErr SetError.fromJson(j)

block setErrorDeserNil:
  const nilNode: JsonNode = nil
  assertErr SetError.fromJson(nilNode)

block setErrorDeserJNull:
  assertErr SetError.fromJson(newJNull())

# =============================================================================
# D. Property-based round-trip tests
# =============================================================================

checkProperty "RequestError round-trip":
  let original = rng.genRequestError()
  assertOkEq RequestError.fromJson(original.toJson()), original

checkProperty "MethodError round-trip":
  let original = rng.genMethodError()
  assertOkEq MethodError.fromJson(original.toJson()), original

checkProperty "SetError round-trip":
  let original = rng.genSetError()
  let rt = SetError.fromJson(original.toJson())
  doAssert rt.isOk, "SetError round-trip failed"
  doAssert setErrorEq(rt.get(), original), "SetError values differ"
