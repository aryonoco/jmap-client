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

# =============================================================================
# E. MC/DC coverage for lenient optional field helpers
# =============================================================================

# --- MC/DC: optString leniency ---

block requestErrorTitleAbsentMcdc:
  ## MC/DC: child.isNil=true — absent field yields Opt.none.
  {.cast(noSideEffect).}:
    let j = %*{"type": "urn:ietf:params:jmap:error:limit"}
    let r = RequestError.fromJson(j)
    assertOk r
    assertNone r.get().title

block requestErrorTitleWrongKindMcdc:
  ## MC/DC: child.isNil=false, kind!=JString=true — wrong kind yields Opt.none.
  {.cast(noSideEffect).}:
    let j = %*{"type": "urn:ietf:params:jmap:error:limit", "title": 42}
    let r = RequestError.fromJson(j)
    assertOk r
    assertNone r.get().title

block requestErrorTitlePresentMcdc:
  ## MC/DC: child.isNil=false, kind=JString — correct kind yields Opt.some.
  {.cast(noSideEffect).}:
    let j = %*{"type": "urn:ietf:params:jmap:error:limit", "title": "Rate limited"}
    let r = RequestError.fromJson(j)
    assertOk r
    assertSome r.get().title
    assertSomeEq r.get().title, "Rate limited"

# --- MC/DC: optInt leniency ---

block requestErrorStatusAbsentMcdc:
  ## MC/DC: child.isNil=true — absent status yields Opt.none.
  {.cast(noSideEffect).}:
    let j = %*{"type": "urn:ietf:params:jmap:error:limit"}
    let r = RequestError.fromJson(j)
    assertOk r
    assertNone r.get().status

block requestErrorStatusWrongKindStringMcdc:
  ## MC/DC: child.isNil=false, kind!=JInt=true — string status yields Opt.none.
  {.cast(noSideEffect).}:
    let j = %*{"type": "urn:ietf:params:jmap:error:limit", "status": "429"}
    let r = RequestError.fromJson(j)
    assertOk r
    assertNone r.get().status

block requestErrorStatusPresentMcdc:
  ## MC/DC: child.isNil=false, kind=JInt — correct kind yields Opt.some.
  {.cast(noSideEffect).}:
    let j = %*{"type": "urn:ietf:params:jmap:error:limit", "status": 429}
    let r = RequestError.fromJson(j)
    assertOk r
    assertSome r.get().status
    assertSomeEq r.get().status, 429

block requestErrorStatusJFloatLenient:
  ## MC/DC: JFloat status (e.g., 429.5) is not JInt, so optInt yields Opt.none.
  ## Verifies lenient handling: parse succeeds but status is absent.
  {.cast(noSideEffect).}:
    let j = %*{"type": "urn:ietf:params:jmap:error:limit", "status": 429.5}
    let r = RequestError.fromJson(j)
    assertOk r
    assertNone r.get().status

# --- MC/DC: MethodError description ---

block methodErrorDescriptionWrongKindMcdc:
  ## MC/DC: description present but JInt (not JString) yields Opt.none.
  {.cast(noSideEffect).}:
    let j = %*{"type": "serverFail", "description": 123}
    let r = MethodError.fromJson(j)
    assertOk r
    assertNone r.get().description

block methodErrorDescriptionPresentMcdc:
  ## MC/DC: description present as JString yields Opt.some.
  {.cast(noSideEffect).}:
    let j = %*{"type": "serverFail", "description": "Internal error"}
    let r = MethodError.fromJson(j)
    assertOk r
    assertSomeEq r.get().description, "Internal error"

block methodErrorDescriptionJArrayLenient:
  ## MC/DC: description as JArray (not JString) yields Opt.none (lenient).
  {.cast(noSideEffect).}:
    let j = %*{"type": "serverFail", "description": [1, 2, 3]}
    let r = MethodError.fromJson(j)
    assertOk r
    assertNone r.get().description

block methodErrorDescriptionJObjectLenient:
  ## MC/DC: description as JObject (not JString) yields Opt.none (lenient).
  {.cast(noSideEffect).}:
    let j = %*{"type": "serverFail", "description": {"x": 1}}
    let r = MethodError.fromJson(j)
    assertOk r
    assertNone r.get().description

# =============================================================================
# F. Additional edge-case and isolation tests
# =============================================================================

block setErrorEmptyTypeField:
  ## Empty type string must return error.
  {.cast(noSideEffect).}:
    let j = %*{"type": ""}
    let r = SetError.fromJson(j)
    assertErr r

block setErrorInvalidPropertiesWithExistingIdExtras:
  ## For invalidProperties variant, "existingId" is not a known key and
  ## must be preserved in extras, not silently consumed.
  {.cast(noSideEffect).}:
    let j = %*{
      "type": "invalidProperties", "properties": ["foo"], "existingId": "shouldBeExtras"
    }
    let r = SetError.fromJson(j)
    assertOk r
    assertSome r.get().extras
    doAssert r.get().extras.get(){"existingId"} != nil,
      "existingId must be in extras for invalidProperties variant"

# =============================================================================
# G. Round-trip tests with all optional fields populated
# =============================================================================

block requestErrorExtrasRoundTrip:
  ## Non-standard fields preserved through toJson -> fromJson.
  {.cast(noSideEffect).}:
    let extras = newJObject()
    extras["vendorField"] = %"vendorValue"
    extras["customCode"] = %12345
    let original = requestError(
      rawType = "urn:ietf:params:jmap:error:limit", extras = Opt.some(extras)
    )
    let rt = RequestError.fromJson(original.toJson())
    assertOk rt
    assertSome rt.get().extras
    let rtExtras = rt.get().extras.get()
    doAssert rtExtras{"vendorField"} != nil
    assertEq rtExtras{"vendorField"}.getStr(""), "vendorValue"
    doAssert rtExtras{"customCode"} != nil
    assertEq rtExtras{"customCode"}.getBiggestInt(0), 12345

block methodErrorAllOptionalFieldsRoundTrip:
  ## MethodError with description + extras both populated survives round-trip.
  {.cast(noSideEffect).}:
    let extras = newJObject()
    extras["serverInfo"] = %"debug-data"
    let original = methodError(
      rawType = "serverFail",
      description = Opt.some("Something went wrong"),
      extras = Opt.some(extras),
    )
    let rt = MethodError.fromJson(original.toJson())
    assertOk rt
    assertSomeEq rt.get().description, "Something went wrong"
    assertSome rt.get().extras
    assertEq rt.get().extras.get(){"serverInfo"}.getStr(""), "debug-data"

# =============================================================================
# H. SetError adversarial edge cases (Phase 4F)
# =============================================================================

block setErrorAlreadyExistsEmptyId:
  ## Build SetError JSON with "type": "alreadyExists", "existingId": "".
  ## The empty string is rejected by parseIdFromServer (Id requires 1-255
  ## octets), so the overall SetError.fromJson must return err.
  {.cast(noSideEffect).}:
    let j = %*{"type": "alreadyExists", "existingId": ""}
    assertErr SetError.fromJson(j)

block setErrorInvalidPropertiesNonArrayProperties:
  ## Build SetError JSON with "type": "invalidProperties", "properties": "notAnArray".
  ## When "properties" is present but not a JArray, the defensive fallback
  ## treats it as if the variant data is missing and falls back to setUnknown.
  {.cast(noSideEffect).}:
    let j = %*{"type": "invalidProperties", "properties": "notAnArray"}
    let r = SetError.fromJson(j)
    assertOk r
    doAssert r.get().errorType == setUnknown,
      "non-array properties should trigger defensive fallback to setUnknown"

# =============================================================================
# I. MC/DC: MethodError description with JArray and JObject (Phase 2E2)
# =============================================================================

block methodErrorDescriptionJArrayLenient:
  ## MC/DC: description present as JArray (not JString) yields Opt.none.
  ## The optString helper rejects non-JString values leniently.
  {.cast(noSideEffect).}:
    let j = %*{"type": "serverFail", "description": [1, 2, 3]}
    let r = MethodError.fromJson(j)
    assertOk r
    assertNone r.get().description

block methodErrorDescriptionJObjectLenient:
  ## MC/DC: description present as JObject (not JString) yields Opt.none.
  ## The optString helper rejects non-JString values leniently.
  {.cast(noSideEffect).}:
    let j = %*{"type": "serverFail", "description": {"x": 1}}
    let r = MethodError.fromJson(j)
    assertOk r
    assertNone r.get().description

# =============================================================================
# H. Phase 3C: Collection scale tests (errors)
# =============================================================================

block collectExtrasLarge100Keys:
  ## MethodError JSON with 100+ non-standard fields. Verify extras preserves
  ## them all through round-trip.
  {.cast(noSideEffect).}:
    var j = newJObject()
    j["type"] = %"serverFail"
    for i in 0 ..< 100:
      j["extra" & $i] = %i
    let r = MethodError.fromJson(j)
    assertOk r
    assertSome r.get().extras
    # Verify all 100 extra keys are preserved
    let extras = r.get().extras.get()
    var count = 0
    for key, val in extras.pairs:
      inc count
    assertEq count, 100
