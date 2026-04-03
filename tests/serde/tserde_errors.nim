# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for Layer 2 error serialisation: RequestError, MethodError, and
## SetError round-trip, structural, edge-case, and property-based tests.

import std/json
import std/options
import std/random
import std/strutils

import jmap_client/serde_errors
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
  let extras = newJObject()
  extras["vendor"] = %"ext-info"
  let original = requestError(
    rawType = "urn:ietf:params:jmap:error:limit",
    status = some(429),
    title = some("Rate limit exceeded"),
    detail = some("Too many requests in the last minute"),
    limit = some("maxCallsInRequest"),
    extras = some(extras),
  )
  assertOkEq RequestError.fromJson(original.toJson()), original

block roundTripRequestErrorUnknownType:
  let original = requestError(rawType = "urn:example:custom:error")
  doAssert original.errorType == retUnknown
  let rt = RequestError.fromJson(original.toJson())
  assertEq rt.rawType, "urn:example:custom:error"
  doAssert rt.errorType == retUnknown

block roundTripMethodErrorMinimal:
  let original = makeMethodError()
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorFull:
  let extras = newJObject()
  extras["serverHint"] = %"retry after 5s"
  let original = methodError(
    rawType = "serverFail",
    description = some("Internal server error"),
    extras = some(extras),
  )
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorUnknownType:
  let original = methodError(rawType = "customVendorError")
  doAssert original.errorType == metUnknown
  let rt = MethodError.fromJson(original.toJson())
  assertEq rt.rawType, "customVendorError"
  doAssert rt.errorType == metUnknown

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
  let v = SetError.fromJson(original.toJson())
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
  let extras = newJObject()
  extras["vendorExt"] = %"data"
  let re =
    requestError(rawType = "urn:ietf:params:jmap:error:notJSON", extras = some(extras))
  let j = re.toJson()
  doAssert j{"vendorExt"} != nil
  assertEq j{"vendorExt"}.getStr(""), "data"

block methodErrorToJsonFieldNames:
  let me = methodError(rawType = "invalidArguments", description = some("bad args"))
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
  let j = %*{"status": 400}
  assertErr RequestError.fromJson(j)

block requestErrorDeserTypeWrongKind:
  let j = %*{"type": 42}
  assertErr RequestError.fromJson(j)

block requestErrorDeserEmptyType:
  let j = %*{"type": ""}
  assertErrContains RequestError.fromJson(j), "empty type field"

block requestErrorDeserUnknownType:
  let j = %*{"type": "urn:example:custom"}
  let r = RequestError.fromJson(j)
  doAssert r.errorType == retUnknown
  assertEq r.rawType, "urn:example:custom"

block requestErrorDeserExtrasCollected:
  let j = %*{"type": "urn:ietf:params:jmap:error:notJSON", "vendorField": "data"}
  let r = RequestError.fromJson(j)
  doAssert r.extras.isSome

block requestErrorDeserStatusWrongKindLenient:
  let j = %*{"type": "urn:ietf:params:jmap:error:limit", "status": "bad"}
  let r = RequestError.fromJson(j)
  doAssert r.status.isNone, "wrong kind status should be treated as none"

block requestErrorDeserNil:
  const nilNode: JsonNode = nil
  assertErr RequestError.fromJson(nilNode)

block requestErrorDeserJNull:
  assertErr RequestError.fromJson(newJNull())

# --- MethodError ---

block methodErrorDeserMissingType:
  let j = %*{"description": "foo"}
  assertErr MethodError.fromJson(j)

block methodErrorDeserTypeWrongKind:
  let j = %*{"type": 42}
  assertErr MethodError.fromJson(j)

block methodErrorDeserEmptyType:
  let j = %*{"type": ""}
  assertErrContains MethodError.fromJson(j), "empty type field"

block methodErrorDeserUnknownType:
  let j = %*{"type": "customVendorError"}
  let r = MethodError.fromJson(j)
  doAssert r.errorType == metUnknown

block methodErrorDeserDescriptionWrongKindLenient:
  let j = %*{"type": "serverFail", "description": 42}
  let r = MethodError.fromJson(j)
  doAssert r.description.isNone, "wrong kind description should be treated as none"

block methodErrorDeserExtrasCollected:
  let j = %*{"type": "serverFail", "extra": "vendor"}
  let r = MethodError.fromJson(j)
  doAssert r.extras.isSome

block methodErrorDeserNil:
  const nilNode: JsonNode = nil
  assertErr MethodError.fromJson(nilNode)

block methodErrorDeserJNull:
  assertErr MethodError.fromJson(newJNull())

# --- SetError ---

block setErrorDeserForbidden:
  let j = %*{"type": "forbidden"}
  let r = SetError.fromJson(j)
  doAssert r.errorType == setForbidden

block setErrorDeserInvalidPropertiesWithProps:
  let j = %*{"type": "invalidProperties", "properties": ["name", "role"]}
  let r = SetError.fromJson(j)
  doAssert r.errorType == setInvalidProperties
  assertEq r.properties.len, 2

block setErrorDeserInvalidPropertiesEmptyArray:
  let j = %*{"type": "invalidProperties", "properties": []}
  let r = SetError.fromJson(j)
  doAssert r.errorType == setInvalidProperties
  assertEq r.properties.len, 0

block setErrorDeserInvalidPropertiesMissing:
  let j = %*{"type": "invalidProperties"}
  let r = SetError.fromJson(j)
  doAssert r.errorType == setUnknown, "defensive fallback to setUnknown"

block setErrorDeserInvalidPropertiesWrongKind:
  let j = %*{"type": "invalidProperties", "properties": 42}
  let r = SetError.fromJson(j)
  doAssert r.errorType == setUnknown, "wrong kind triggers defensive fallback"

block setErrorDeserInvalidPropertiesNonStringElement:
  let j = %*{"type": "invalidProperties", "properties": [42]}
  assertErrContains SetError.fromJson(j), "properties element must be string"

block setErrorDeserAlreadyExistsWithId:
  let j = %*{"type": "alreadyExists", "existingId": "msg42"}
  let v = SetError.fromJson(j)
  doAssert v.errorType == setAlreadyExists
  assertEq string(v.existingId), "msg42"

block setErrorDeserAlreadyExistsMissing:
  let j = %*{"type": "alreadyExists"}
  let r = SetError.fromJson(j)
  doAssert r.errorType == setUnknown, "defensive fallback to setUnknown"

block setErrorDeserAlreadyExistsWrongKind:
  let j = %*{"type": "alreadyExists", "existingId": 42}
  let r = SetError.fromJson(j)
  doAssert r.errorType == setUnknown, "wrong kind triggers defensive fallback"

block setErrorDeserAlreadyExistsEmptyId:
  ## Empty existingId triggers defensive fallback to setUnknown (not err).
  let j = %*{"type": "alreadyExists", "existingId": ""}
  let r = SetError.fromJson(j)
  doAssert r.errorType == setUnknown, "empty existingId triggers defensive fallback"

block setErrorDeserVendorSpecific:
  let j = %*{"type": "vendorSpecific"}
  let r = SetError.fromJson(j)
  assertEq r.rawType, "vendorSpecific"
  doAssert r.errorType == setUnknown

block setErrorDeserPerVariantKnownKeys:
  let j = %*{"type": "forbidden", "properties": ["name"]}
  let v = SetError.fromJson(j)
  doAssert v.errorType == setForbidden
  doAssert v.extras.isSome, "misplaced properties should be in extras"

block setErrorDeserDescriptionWrongKindLenient:
  let j = %*{"type": "forbidden", "description": 42}
  let r = SetError.fromJson(j)
  doAssert r.description.isNone

block setErrorDeserMissingType:
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
  doAssert setErrorEq(rt, original), "SetError values differ"

# =============================================================================
# E. MC/DC coverage for lenient optional field helpers
# =============================================================================

# --- MC/DC: optString leniency ---

block requestErrorTitleAbsentMcdc:
  ## MC/DC: child.isNil=true — absent field yields none.
  let j = %*{"type": "urn:ietf:params:jmap:error:limit"}
  let r = RequestError.fromJson(j)
  assertNone r.title

block requestErrorTitleWrongKindMcdc:
  ## MC/DC: child.isNil=false, kind!=JString=true — wrong kind yields none.
  let j = %*{"type": "urn:ietf:params:jmap:error:limit", "title": 42}
  let r = RequestError.fromJson(j)
  assertNone r.title

block requestErrorTitlePresentMcdc:
  ## MC/DC: child.isNil=false, kind=JString — correct kind yields some.
  let j = %*{"type": "urn:ietf:params:jmap:error:limit", "title": "Rate limited"}
  let r = RequestError.fromJson(j)
  assertSome r.title
  assertSomeEq r.title, "Rate limited"

# --- MC/DC: optInt leniency ---

block requestErrorStatusAbsentMcdc:
  ## MC/DC: child.isNil=true — absent status yields none.
  let j = %*{"type": "urn:ietf:params:jmap:error:limit"}
  let r = RequestError.fromJson(j)
  assertNone r.status

block requestErrorStatusWrongKindStringMcdc:
  ## MC/DC: child.isNil=false, kind!=JInt=true — string status yields none.
  let j = %*{"type": "urn:ietf:params:jmap:error:limit", "status": "429"}
  let r = RequestError.fromJson(j)
  assertNone r.status

block requestErrorStatusPresentMcdc:
  ## MC/DC: child.isNil=false, kind=JInt — correct kind yields some.
  let j = %*{"type": "urn:ietf:params:jmap:error:limit", "status": 429}
  let r = RequestError.fromJson(j)
  assertSome r.status
  assertSomeEq r.status, 429

block requestErrorStatusJFloatLenient:
  ## MC/DC: JFloat status (e.g., 429.5) is not JInt, so optInt yields none.
  ## Verifies lenient handling: parse succeeds but status is absent.
  let j = %*{"type": "urn:ietf:params:jmap:error:limit", "status": 429.5}
  let r = RequestError.fromJson(j)
  assertNone r.status

# --- MC/DC: MethodError description ---

block methodErrorDescriptionWrongKindMcdc:
  ## MC/DC: description present but JInt (not JString) yields none.
  let j = %*{"type": "serverFail", "description": 123}
  let r = MethodError.fromJson(j)
  assertNone r.description

block methodErrorDescriptionPresentMcdc:
  ## MC/DC: description present as JString yields some.
  let j = %*{"type": "serverFail", "description": "Internal error"}
  let r = MethodError.fromJson(j)
  assertSomeEq r.description, "Internal error"

block methodErrorDescriptionJArrayLenient:
  ## MC/DC: description as JArray (not JString) yields none (lenient).
  let j = %*{"type": "serverFail", "description": [1, 2, 3]}
  let r = MethodError.fromJson(j)
  assertNone r.description

block methodErrorDescriptionJObjectLenient:
  ## MC/DC: description as JObject (not JString) yields none (lenient).
  let j = %*{"type": "serverFail", "description": {"x": 1}}
  let r = MethodError.fromJson(j)
  assertNone r.description

# =============================================================================
# F. Additional edge-case and isolation tests
# =============================================================================

block setErrorEmptyTypeField:
  ## Empty type string must return error.
  let j = %*{"type": ""}
  assertErr SetError.fromJson(j)

block setErrorInvalidPropertiesWithExistingIdExtras:
  ## For invalidProperties variant, "existingId" is not a known key and
  ## must be preserved in extras, not silently consumed.
  let j = %*{
    "type": "invalidProperties", "properties": ["foo"], "existingId": "shouldBeExtras"
  }
  let r = SetError.fromJson(j)
  assertSome r.extras
  doAssert r.extras.get(){"existingId"} != nil,
    "existingId must be in extras for invalidProperties variant"

# =============================================================================
# G. Round-trip tests with all optional fields populated
# =============================================================================

block requestErrorExtrasRoundTrip:
  ## Non-standard fields preserved through toJson -> fromJson.
  let extras = newJObject()
  extras["vendorField"] = %"vendorValue"
  extras["customCode"] = %12345
  let original =
    requestError(rawType = "urn:ietf:params:jmap:error:limit", extras = some(extras))
  let rt = RequestError.fromJson(original.toJson())
  assertSome rt.extras
  let rtExtras = rt.extras.get()
  doAssert rtExtras{"vendorField"} != nil
  assertEq rtExtras{"vendorField"}.getStr(""), "vendorValue"
  doAssert rtExtras{"customCode"} != nil
  assertEq rtExtras{"customCode"}.getBiggestInt(0), 12345

block methodErrorAllOptionalFieldsRoundTrip:
  ## MethodError with description + extras both populated survives round-trip.
  let extras = newJObject()
  extras["serverInfo"] = %"debug-data"
  let original = methodError(
    rawType = "serverFail",
    description = some("Something went wrong"),
    extras = some(extras),
  )
  let rt = MethodError.fromJson(original.toJson())
  assertSomeEq rt.description, "Something went wrong"
  assertSome rt.extras
  assertEq rt.extras.get(){"serverInfo"}.getStr(""), "debug-data"

# =============================================================================
# H. SetError adversarial edge cases (Phase 4F)
# =============================================================================

block setErrorAlreadyExistsEmptyId:
  ## Build SetError JSON with "type": "alreadyExists", "existingId": "".
  ## The empty string is rejected by parseIdFromServer (Id requires 1-255
  ## octets). Defensive fallback maps to setUnknown, not err.
  let j = %*{"type": "alreadyExists", "existingId": ""}
  let r = SetError.fromJson(j)
  doAssert r.errorType == setUnknown, "empty existingId triggers defensive fallback"

block setErrorInvalidPropertiesNonArrayProperties:
  ## Build SetError JSON with "type": "invalidProperties", "properties": "notAnArray".
  ## When "properties" is present but not a JArray, the defensive fallback
  ## treats it as if the variant data is missing and falls back to setUnknown.
  let j = %*{"type": "invalidProperties", "properties": "notAnArray"}
  let r = SetError.fromJson(j)
  doAssert r.errorType == setUnknown,
    "non-array properties should trigger defensive fallback to setUnknown"

# =============================================================================
# H. Phase 3C: Collection scale tests (errors)
# =============================================================================

block collectExtrasLarge100Keys:
  ## MethodError JSON with 100+ non-standard fields. Verify extras preserves
  ## them all through round-trip.
  var j = newJObject()
  j["type"] = %"serverFail"
  for i in 0 ..< 100:
    j["extra" & $i] = %i
  let r = MethodError.fromJson(j)
  assertSome r.extras
  # Verify all 100 extra keys are preserved
  let extras = r.extras.get()
  var count = 0
  for key, val in extras.pairs:
    inc count
  assertEq count, 100

# =============================================================================
# Phase 3A: Full enum coverage — individual round-trip tests for every
# RequestError, MethodError, and SetError type variant.
# =============================================================================

# --- RequestError: all 4 known types ---

block roundTripRequestErrorUnknownCapability:
  ## RFC 8620 section 3.6.1: unknownCapability with full RFC 7807 structure.
  let original = requestError(
    rawType = "urn:ietf:params:jmap:error:unknownCapability",
    status = some(400),
    title = some("Unknown Capability"),
    detail = some("The request used an unknown capability URI"),
  )
  doAssert original.errorType == retUnknownCapability
  let j = original.toJson()
  assertEq j{"type"}.getStr(""), "urn:ietf:params:jmap:error:unknownCapability"
  let rt = RequestError.fromJson(j)
  assertOkEq rt, original

block roundTripRequestErrorNotJson:
  ## RFC 8620 section 3.6.1: notJSON.
  let original = requestError(
    rawType = "urn:ietf:params:jmap:error:notJSON",
    status = some(400),
    title = some("Not JSON"),
    detail = some("The request body was not valid JSON"),
  )
  doAssert original.errorType == retNotJson
  let j = original.toJson()
  assertEq j{"type"}.getStr(""), "urn:ietf:params:jmap:error:notJSON"
  let rt = RequestError.fromJson(j)
  assertOkEq rt, original

block roundTripRequestErrorNotRequest:
  ## RFC 8620 section 3.6.1: notRequest.
  let original = requestError(
    rawType = "urn:ietf:params:jmap:error:notRequest",
    status = some(400),
    title = some("Not a Request"),
    detail = some("The JSON was valid but not a valid JMAP request"),
  )
  doAssert original.errorType == retNotRequest
  let j = original.toJson()
  assertEq j{"type"}.getStr(""), "urn:ietf:params:jmap:error:notRequest"
  let rt = RequestError.fromJson(j)
  assertOkEq rt, original

block roundTripRequestErrorLimit:
  ## RFC 8620 section 3.6.1: limit with limit field populated.
  let original = requestError(
    rawType = "urn:ietf:params:jmap:error:limit",
    status = some(400),
    title = some("Request Too Large"),
    detail = some("Exceeded maxCallsInRequest"),
    limit = some("maxCallsInRequest"),
  )
  doAssert original.errorType == retLimit
  let j = original.toJson()
  assertEq j{"type"}.getStr(""), "urn:ietf:params:jmap:error:limit"
  doAssert j{"limit"} != nil
  assertEq j{"limit"}.getStr(""), "maxCallsInRequest"
  let rt = RequestError.fromJson(j)
  assertOkEq rt, original

# --- MethodError: all 19 known types ---

block roundTripMethodErrorServerUnavailable:
  let original = methodError("serverUnavailable")
  doAssert original.errorType == metServerUnavailable
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorServerFail:
  let original = methodError("serverFail")
  doAssert original.errorType == metServerFail
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorServerPartialFail:
  let original = methodError("serverPartialFail")
  doAssert original.errorType == metServerPartialFail
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorUnknownMethod:
  let original = methodError("unknownMethod")
  doAssert original.errorType == metUnknownMethod
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorInvalidArguments:
  let original = methodError("invalidArguments")
  doAssert original.errorType == metInvalidArguments
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorInvalidResultReference:
  let original = methodError("invalidResultReference")
  doAssert original.errorType == metInvalidResultReference
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorForbidden:
  let original = methodError("forbidden")
  doAssert original.errorType == metForbidden
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorAccountNotFound:
  let original = methodError("accountNotFound")
  doAssert original.errorType == metAccountNotFound
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorAccountNotSupportedByMethod:
  let original = methodError("accountNotSupportedByMethod")
  doAssert original.errorType == metAccountNotSupportedByMethod
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorAccountReadOnly:
  let original = methodError("accountReadOnly")
  doAssert original.errorType == metAccountReadOnly
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorAnchorNotFound:
  let original = methodError("anchorNotFound")
  doAssert original.errorType == metAnchorNotFound
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorUnsupportedSort:
  let original = methodError("unsupportedSort")
  doAssert original.errorType == metUnsupportedSort
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorUnsupportedFilter:
  let original = methodError("unsupportedFilter")
  doAssert original.errorType == metUnsupportedFilter
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorCannotCalculateChanges:
  let original = methodError("cannotCalculateChanges")
  doAssert original.errorType == metCannotCalculateChanges
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorTooManyChanges:
  let original = methodError("tooManyChanges")
  doAssert original.errorType == metTooManyChanges
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorRequestTooLarge:
  let original = methodError("requestTooLarge")
  doAssert original.errorType == metRequestTooLarge
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorStateMismatch:
  let original = methodError("stateMismatch")
  doAssert original.errorType == metStateMismatch
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorFromAccountNotFound:
  let original = methodError("fromAccountNotFound")
  doAssert original.errorType == metFromAccountNotFound
  assertOkEq MethodError.fromJson(original.toJson()), original

block roundTripMethodErrorFromAccountNotSupportedByMethod:
  let original = methodError("fromAccountNotSupportedByMethod")
  doAssert original.errorType == metFromAccountNotSupportedByMethod
  assertOkEq MethodError.fromJson(original.toJson()), original

# --- SetError: all 10 known types ---

block roundTripSetErrorForbiddenEnum:
  let original = setError("forbidden")
  doAssert original.errorType == setForbidden
  assertSetOkEq SetError.fromJson(original.toJson()), original

block roundTripSetErrorOverQuota:
  let original = setError("overQuota")
  doAssert original.errorType == setOverQuota
  assertSetOkEq SetError.fromJson(original.toJson()), original

block roundTripSetErrorTooLarge:
  let original = setError("tooLarge")
  doAssert original.errorType == setTooLarge
  assertSetOkEq SetError.fromJson(original.toJson()), original

block roundTripSetErrorRateLimit:
  let original = setError("rateLimit")
  doAssert original.errorType == setRateLimit
  assertSetOkEq SetError.fromJson(original.toJson()), original

block roundTripSetErrorNotFound:
  let original = setError("notFound")
  doAssert original.errorType == setNotFound
  assertSetOkEq SetError.fromJson(original.toJson()), original

block roundTripSetErrorInvalidPatch:
  let original = setError("invalidPatch")
  doAssert original.errorType == setInvalidPatch
  assertSetOkEq SetError.fromJson(original.toJson()), original

block roundTripSetErrorWillDestroy:
  let original = setError("willDestroy")
  doAssert original.errorType == setWillDestroy
  assertSetOkEq SetError.fromJson(original.toJson()), original

block roundTripSetErrorSingleton:
  let original = setError("singleton")
  doAssert original.errorType == setSingleton
  assertSetOkEq SetError.fromJson(original.toJson()), original

block roundTripSetErrorInvalidPropertiesWithData:
  ## invalidProperties variant with a list of property names.
  let original =
    setErrorInvalidProperties("invalidProperties", @["from", "subject", "body"])
  doAssert original.errorType == setInvalidProperties
  assertSetOkEq SetError.fromJson(original.toJson()), original

block roundTripSetErrorAlreadyExistsWithData:
  ## alreadyExists variant with an existing record ID.
  let original = setErrorAlreadyExists("alreadyExists", makeId("existing42"))
  doAssert original.errorType == setAlreadyExists
  assertSetOkEq SetError.fromJson(original.toJson()), original

# =============================================================================
# Extras collision: standard field names in extras must not overwrite
# =============================================================================

block requestErrorExtrasCollisionTypeField:
  ## Extras containing "type" must not overwrite the standard type field.
  let extras = newJObject()
  extras["type"] = %"evil"
  extras["vendor"] = %"safe"
  let re =
    requestError(rawType = "urn:ietf:params:jmap:error:limit", extras = some(extras))
  let j = re.toJson()
  assertJsonFieldEq j, "type", %"urn:ietf:params:jmap:error:limit"
  assertJsonFieldEq j, "vendor", %"safe"

block requestErrorExtrasCollisionAllStandardFields:
  ## Extras containing all 5 standard field names must not overwrite any.
  let extras = newJObject()
  extras["type"] = %"evil"
  extras["status"] = %999
  extras["title"] = %"evil-title"
  extras["detail"] = %"evil-detail"
  extras["limit"] = %"evil-limit"
  extras["vendor"] = %"safe"
  let re = requestError(
    rawType = "urn:ietf:params:jmap:error:limit",
    status = some(429),
    title = some("Rate Limit"),
    detail = some("Too many requests"),
    limit = some("maxCallsInRequest"),
    extras = some(extras),
  )
  let j = re.toJson()
  assertJsonFieldEq j, "type", %"urn:ietf:params:jmap:error:limit"
  assertJsonFieldEq j, "status", %429
  assertJsonFieldEq j, "title", %"Rate Limit"
  assertJsonFieldEq j, "detail", %"Too many requests"
  assertJsonFieldEq j, "limit", %"maxCallsInRequest"
  assertJsonFieldEq j, "vendor", %"safe"

block methodErrorExtrasCollisionTypeField:
  let extras = newJObject()
  extras["type"] = %"evil"
  extras["description"] = %"evil-desc"
  extras["vendor"] = %"safe"
  let me = methodError(
    rawType = "invalidArguments",
    description = some("real description"),
    extras = some(extras),
  )
  let j = me.toJson()
  assertJsonFieldEq j, "type", %"invalidArguments"
  assertJsonFieldEq j, "description", %"real description"
  assertJsonFieldEq j, "vendor", %"safe"

block setErrorExtrasCollisionTypeField:
  let extras = newJObject()
  extras["type"] = %"evil"
  extras["vendor"] = %"safe"
  let se = setError(
    rawType = "forbidden", description = some("real desc"), extras = some(extras)
  )
  let j = se.toJson()
  assertJsonFieldEq j, "type", %"forbidden"
  assertJsonFieldEq j, "vendor", %"safe"

block setErrorInvalidPropertiesExtrasCollisionProperties:
  let extras = newJObject()
  extras["properties"] = %*["evil"]
  extras["vendor"] = %"safe"
  let se = setErrorInvalidProperties(
    rawType = "invalidProperties",
    properties = @["subject", "body"],
    extras = some(extras),
  )
  let j = se.toJson()
  assertJsonFieldEq j, "type", %"invalidProperties"
  let propsNode = j{"properties"}
  assertFalse propsNode.isNil, "properties field must be present"
  assertEq propsNode.getElems(@[]).len, 2
  assertJsonFieldEq j, "vendor", %"safe"
