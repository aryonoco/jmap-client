# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for Layer 2 error serialisation: RequestError, MethodError, and
## SetError round-trip, structural, edge-case, and property-based tests.

import std/json
import std/random
import std/strutils

import jmap_client/internal/serialisation/serde_errors
import jmap_client/internal/types/errors
import jmap_client/internal/types/validation

import ../massertions
import ../mfixtures
import ../mproperty
import ../mtestblock

# =============================================================================
# A. Round-trip tests
# =============================================================================

testCase roundTripRequestErrorMinimal:
  let original = makeRequestError()
  assertOkEq RequestError.fromJson(original.toJson()), original

testCase roundTripRequestErrorFull:
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

testCase roundTripRequestErrorUnknownType:
  let original = requestError(rawType = "urn:example:custom:error")
  doAssert original.errorType == retUnknown
  let rt = RequestError.fromJson(original.toJson()).get()
  assertEq rt.rawType, "urn:example:custom:error"
  doAssert rt.errorType == retUnknown

testCase roundTripMethodErrorMinimal:
  let original = makeMethodError()
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorFull:
  let extras = newJObject()
  extras["serverHint"] = %"retry after 5s"
  let original = methodError(
    rawType = "serverFail",
    description = Opt.some("Internal server error"),
    extras = Opt.some(extras),
  )
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorUnknownType:
  let original = methodError(rawType = "customVendorError")
  doAssert original.errorType == metUnknown
  let rt = MethodError.fromJson(original.toJson()).get()
  assertEq rt.rawType, "customVendorError"
  doAssert rt.errorType == metUnknown

testCase roundTripSetErrorForbidden:
  let original = setError("forbidden")
  doAssert original.errorType == setForbidden
  assertSetOkEq SetError.fromJson(original.toJson()).get(), original

testCase roundTripSetErrorInvalidProperties:
  let original = makeSetErrorInvalidProperties()
  assertSetOkEq SetError.fromJson(original.toJson()).get(), original

testCase roundTripSetErrorInvalidPropertiesEmpty:
  let original = setErrorInvalidProperties("invalidProperties", @[])
  assertSetOkEq SetError.fromJson(original.toJson()).get(), original

testCase roundTripSetErrorAlreadyExists:
  let original = makeSetErrorAlreadyExists()
  assertSetOkEq SetError.fromJson(original.toJson()).get(), original

testCase roundTripSetErrorUnknownType:
  let original = setError("vendorSpecific")
  doAssert original.errorType == setUnknown
  let v = SetError.fromJson(original.toJson()).get()
  assertEq v.rawType, "vendorSpecific"
  doAssert v.errorType == setUnknown

# =============================================================================
# B. toJson structural correctness
# =============================================================================

testCase requestErrorToJsonFieldNames:
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

testCase requestErrorToJsonExtrasFlattened:
  let extras = newJObject()
  extras["vendorExt"] = %"data"
  let re = requestError(
    rawType = "urn:ietf:params:jmap:error:notJSON", extras = Opt.some(extras)
  )
  let j = re.toJson()
  doAssert j{"vendorExt"} != nil
  assertEq j{"vendorExt"}.getStr(""), "data"

testCase methodErrorToJsonFieldNames:
  let me = methodError(rawType = "invalidArguments", description = Opt.some("bad args"))
  let j = me.toJson()
  doAssert j.kind == JObject
  doAssert j{"type"} != nil
  assertEq j{"type"}.getStr(""), "invalidArguments"
  doAssert j{"description"} != nil
  assertEq j{"description"}.getStr(""), "bad args"

testCase setErrorToJsonInvalidProperties:
  let se = makeSetErrorInvalidProperties()
  let j = se.toJson()
  doAssert j{"type"} != nil
  assertEq j{"type"}.getStr(""), "invalidProperties"
  doAssert j{"properties"} != nil
  doAssert j{"properties"}.kind == JArray
  doAssert j{"properties"}.len > 0

testCase setErrorToJsonInvalidPropertiesEmpty:
  let se = setErrorInvalidProperties("invalidProperties", @[])
  let j = se.toJson()
  doAssert j{"properties"} != nil, "properties key must be present even when empty"
  doAssert j{"properties"}.kind == JArray
  assertEq j{"properties"}.len, 0

testCase setErrorToJsonAlreadyExists:
  let se = makeSetErrorAlreadyExists()
  let j = se.toJson()
  doAssert j{"type"} != nil
  assertEq j{"type"}.getStr(""), "alreadyExists"
  doAssert j{"existingId"} != nil
  doAssert j{"existingId"}.kind == JString

testCase setErrorToJsonGenericNoVariantFields:
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

testCase requestErrorDeserMissingType:
  let j = %*{"status": 400}
  assertErr RequestError.fromJson(j)

testCase requestErrorDeserTypeWrongKind:
  let j = %*{"type": 42}
  assertErr RequestError.fromJson(j)

testCase requestErrorDeserEmptyType:
  let j = %*{"type": ""}
  assertErrContains RequestError.fromJson(j), "type field must not be empty"

testCase requestErrorDeserUnknownType:
  let j = %*{"type": "urn:example:custom"}
  let r = RequestError.fromJson(j).get()
  doAssert r.errorType == retUnknown
  assertEq r.rawType, "urn:example:custom"

testCase requestErrorDeserExtrasCollected:
  let j = %*{"type": "urn:ietf:params:jmap:error:notJSON", "vendorField": "data"}
  let r = RequestError.fromJson(j).get()
  doAssert r.extras.isSome

testCase requestErrorDeserStatusWrongKindLenient:
  let j = %*{"type": "urn:ietf:params:jmap:error:limit", "status": "bad"}
  let r = RequestError.fromJson(j).get()
  doAssert r.status.isNone, "wrong kind status should be treated as none"

testCase requestErrorDeserNil:
  const nilNode: JsonNode = nil
  assertErr RequestError.fromJson(nilNode)

testCase requestErrorDeserJNull:
  assertErr RequestError.fromJson(newJNull())

# --- MethodError ---

testCase methodErrorDeserMissingType:
  let j = %*{"description": "foo"}
  assertErr MethodError.fromJson(j)

testCase methodErrorDeserTypeWrongKind:
  let j = %*{"type": 42}
  assertErr MethodError.fromJson(j)

testCase methodErrorDeserEmptyType:
  let j = %*{"type": ""}
  assertErrContains MethodError.fromJson(j), "type field must not be empty"

testCase methodErrorDeserUnknownType:
  let j = %*{"type": "customVendorError"}
  let r = MethodError.fromJson(j).get()
  doAssert r.errorType == metUnknown

testCase methodErrorDeserDescriptionWrongKindLenient:
  let j = %*{"type": "serverFail", "description": 42}
  let r = MethodError.fromJson(j).get()
  doAssert r.description.isNone, "wrong kind description should be treated as none"

testCase methodErrorDeserExtrasCollected:
  let j = %*{"type": "serverFail", "extra": "vendor"}
  let r = MethodError.fromJson(j).get()
  doAssert r.extras.isSome

testCase methodErrorDeserNil:
  const nilNode: JsonNode = nil
  assertErr MethodError.fromJson(nilNode)

testCase methodErrorDeserJNull:
  assertErr MethodError.fromJson(newJNull())

# --- SetError ---

testCase setErrorDeserForbidden:
  let j = %*{"type": "forbidden"}
  let r = SetError.fromJson(j).get()
  doAssert r.errorType == setForbidden

testCase setErrorDeserInvalidPropertiesWithProps:
  let j = %*{"type": "invalidProperties", "properties": ["name", "role"]}
  let r = SetError.fromJson(j).get()
  doAssert r.errorType == setInvalidProperties
  assertEq r.properties.len, 2

testCase setErrorDeserInvalidPropertiesEmptyArray:
  let j = %*{"type": "invalidProperties", "properties": []}
  let r = SetError.fromJson(j).get()
  doAssert r.errorType == setInvalidProperties
  assertEq r.properties.len, 0

testCase setErrorDeserInvalidPropertiesMissing:
  let j = %*{"type": "invalidProperties"}
  let r = SetError.fromJson(j).get()
  doAssert r.errorType == setUnknown, "defensive fallback to setUnknown"

testCase setErrorDeserInvalidPropertiesWrongKind:
  let j = %*{"type": "invalidProperties", "properties": 42}
  let r = SetError.fromJson(j).get()
  doAssert r.errorType == setUnknown, "wrong kind triggers defensive fallback"

testCase setErrorDeserInvalidPropertiesNonStringElement:
  let j = %*{"type": "invalidProperties", "properties": [42]}
  assertErrContains SetError.fromJson(j), "at /properties/"

testCase setErrorDeserAlreadyExistsWithId:
  let j = %*{"type": "alreadyExists", "existingId": "msg42"}
  let v = SetError.fromJson(j).get()
  doAssert v.errorType == setAlreadyExists
  assertEq string(v.existingId), "msg42"

testCase setErrorDeserAlreadyExistsMissing:
  let j = %*{"type": "alreadyExists"}
  let r = SetError.fromJson(j).get()
  doAssert r.errorType == setUnknown, "defensive fallback to setUnknown"

testCase setErrorDeserAlreadyExistsWrongKind:
  let j = %*{"type": "alreadyExists", "existingId": 42}
  let r = SetError.fromJson(j).get()
  doAssert r.errorType == setUnknown, "wrong kind triggers defensive fallback"

testCase setErrorDeserAlreadyExistsEmptyId:
  ## Empty existingId triggers defensive fallback to setUnknown (not err).
  let j = %*{"type": "alreadyExists", "existingId": ""}
  let r = SetError.fromJson(j).get()
  doAssert r.errorType == setUnknown, "empty existingId triggers defensive fallback"

testCase setErrorDeserVendorSpecific:
  let j = %*{"type": "vendorSpecific"}
  let r = SetError.fromJson(j).get()
  assertEq r.rawType, "vendorSpecific"
  doAssert r.errorType == setUnknown

testCase setErrorDeserPerVariantKnownKeys:
  let j = %*{"type": "forbidden", "properties": ["name"]}
  let v = SetError.fromJson(j).get()
  doAssert v.errorType == setForbidden
  doAssert v.extras.isSome, "misplaced properties should be in extras"

testCase setErrorDeserDescriptionWrongKindLenient:
  let j = %*{"type": "forbidden", "description": 42}
  let r = SetError.fromJson(j).get()
  doAssert r.description.isNone

testCase setErrorDeserMissingType:
  let j = %*{"description": "foo"}
  assertErr SetError.fromJson(j)

testCase setErrorDeserNil:
  const nilNode: JsonNode = nil
  assertErr SetError.fromJson(nilNode)

testCase setErrorDeserJNull:
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
  let rt = SetError.fromJson(original.toJson()).get()
  doAssert setErrorEq(rt, original), "SetError values differ"

# =============================================================================
# E. MC/DC coverage for lenient optional field helpers
# =============================================================================

# --- MC/DC: optString leniency ---

testCase requestErrorTitleAbsentMcdc:
  ## MC/DC: child.isNil=true — absent field yields none.
  let j = %*{"type": "urn:ietf:params:jmap:error:limit"}
  let r = RequestError.fromJson(j).get()
  assertNone r.title

testCase requestErrorTitleWrongKindMcdc:
  ## MC/DC: child.isNil=false, kind!=JString=true — wrong kind yields none.
  let j = %*{"type": "urn:ietf:params:jmap:error:limit", "title": 42}
  let r = RequestError.fromJson(j).get()
  assertNone r.title

testCase requestErrorTitlePresentMcdc:
  ## MC/DC: child.isNil=false, kind=JString — correct kind yields some.
  let j = %*{"type": "urn:ietf:params:jmap:error:limit", "title": "Rate limited"}
  let r = RequestError.fromJson(j).get()
  assertSome r.title
  assertSomeEq r.title, "Rate limited"

# --- MC/DC: optInt leniency ---

testCase requestErrorStatusAbsentMcdc:
  ## MC/DC: child.isNil=true — absent status yields none.
  let j = %*{"type": "urn:ietf:params:jmap:error:limit"}
  let r = RequestError.fromJson(j).get()
  assertNone r.status

testCase requestErrorStatusWrongKindStringMcdc:
  ## MC/DC: child.isNil=false, kind!=JInt=true — string status yields none.
  let j = %*{"type": "urn:ietf:params:jmap:error:limit", "status": "429"}
  let r = RequestError.fromJson(j).get()
  assertNone r.status

testCase requestErrorStatusPresentMcdc:
  ## MC/DC: child.isNil=false, kind=JInt — correct kind yields some.
  let j = %*{"type": "urn:ietf:params:jmap:error:limit", "status": 429}
  let r = RequestError.fromJson(j).get()
  assertSome r.status
  assertSomeEq r.status, 429

testCase requestErrorStatusJFloatLenient:
  ## MC/DC: JFloat status (e.g., 429.5) is not JInt, so optInt yields none.
  ## Verifies lenient handling: parse succeeds but status is absent.
  let j = %*{"type": "urn:ietf:params:jmap:error:limit", "status": 429.5}
  let r = RequestError.fromJson(j).get()
  assertNone r.status

# --- MC/DC: MethodError description ---

testCase methodErrorDescriptionWrongKindMcdc:
  ## MC/DC: description present but JInt (not JString) yields none.
  let j = %*{"type": "serverFail", "description": 123}
  let r = MethodError.fromJson(j).get()
  assertNone r.description

testCase methodErrorDescriptionPresentMcdc:
  ## MC/DC: description present as JString yields some.
  let j = %*{"type": "serverFail", "description": "Internal error"}
  let r = MethodError.fromJson(j).get()
  assertSomeEq r.description, "Internal error"

testCase methodErrorDescriptionJArrayLenient:
  ## MC/DC: description as JArray (not JString) yields none (lenient).
  let j = %*{"type": "serverFail", "description": [1, 2, 3]}
  let r = MethodError.fromJson(j).get()
  assertNone r.description

testCase methodErrorDescriptionJObjectLenient:
  ## MC/DC: description as JObject (not JString) yields none (lenient).
  let j = %*{"type": "serverFail", "description": {"x": 1}}
  let r = MethodError.fromJson(j).get()
  assertNone r.description

# =============================================================================
# F. Additional edge-case and isolation tests
# =============================================================================

testCase setErrorEmptyTypeField:
  ## Empty type string must return error.
  let j = %*{"type": ""}
  assertErr SetError.fromJson(j)

testCase setErrorInvalidPropertiesWithExistingIdExtras:
  ## For invalidProperties variant, "existingId" is not a known key and
  ## must be preserved in extras, not silently consumed.
  let j = %*{
    "type": "invalidProperties", "properties": ["foo"], "existingId": "shouldBeExtras"
  }
  let r = SetError.fromJson(j).get()
  assertSome r.extras
  doAssert r.extras.get(){"existingId"} != nil,
    "existingId must be in extras for invalidProperties variant"

# =============================================================================
# G. Round-trip tests with all optional fields populated
# =============================================================================

testCase requestErrorExtrasRoundTrip:
  ## Non-standard fields preserved through toJson -> fromJson.
  let extras = newJObject()
  extras["vendorField"] = %"vendorValue"
  extras["customCode"] = %12345
  let original = requestError(
    rawType = "urn:ietf:params:jmap:error:limit", extras = Opt.some(extras)
  )
  let rt = RequestError.fromJson(original.toJson()).get()
  assertSome rt.extras
  let rtExtras = rt.extras.get()
  doAssert rtExtras{"vendorField"} != nil
  assertEq rtExtras{"vendorField"}.getStr(""), "vendorValue"
  doAssert rtExtras{"customCode"} != nil
  assertEq rtExtras{"customCode"}.getBiggestInt(0), 12345

testCase methodErrorAllOptionalFieldsRoundTrip:
  ## MethodError with description + extras both populated survives round-trip.
  let extras = newJObject()
  extras["serverInfo"] = %"debug-data"
  let original = methodError(
    rawType = "serverFail",
    description = Opt.some("Something went wrong"),
    extras = Opt.some(extras),
  )
  let rt = MethodError.fromJson(original.toJson()).get()
  assertSomeEq rt.description, "Something went wrong"
  assertSome rt.extras
  assertEq rt.extras.get(){"serverInfo"}.getStr(""), "debug-data"

# =============================================================================
# H. SetError adversarial edge cases (Phase 4F)
# =============================================================================

testCase setErrorAlreadyExistsEmptyId:
  ## Build SetError JSON with "type": "alreadyExists", "existingId": "".
  ## The empty string is rejected by parseIdFromServer (Id requires 1-255
  ## octets). Defensive fallback maps to setUnknown, not err.
  let j = %*{"type": "alreadyExists", "existingId": ""}
  let r = SetError.fromJson(j).get()
  doAssert r.errorType == setUnknown, "empty existingId triggers defensive fallback"

testCase setErrorInvalidPropertiesNonArrayProperties:
  ## Build SetError JSON with "type": "invalidProperties", "properties": "notAnArray".
  ## When "properties" is present but not a JArray, the defensive fallback
  ## treats it as if the variant data is missing and falls back to setUnknown.
  let j = %*{"type": "invalidProperties", "properties": "notAnArray"}
  let r = SetError.fromJson(j).get()
  doAssert r.errorType == setUnknown,
    "non-array properties should trigger defensive fallback to setUnknown"

# =============================================================================
# H. Phase 3C: Collection scale tests (errors)
# =============================================================================

testCase collectExtrasLarge100Keys:
  ## MethodError JSON with 100+ non-standard fields. Verify extras preserves
  ## them all through round-trip.
  var j = newJObject()
  j["type"] = %"serverFail"
  for i in 0 ..< 100:
    j["extra" & $i] = %i
  let r = MethodError.fromJson(j).get()
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

testCase roundTripRequestErrorUnknownCapability:
  ## RFC 8620 section 3.6.1: unknownCapability with full RFC 7807 structure.
  let original = requestError(
    rawType = "urn:ietf:params:jmap:error:unknownCapability",
    status = Opt.some(400),
    title = Opt.some("Unknown Capability"),
    detail = Opt.some("The request used an unknown capability URI"),
  )
  doAssert original.errorType == retUnknownCapability
  let j = original.toJson()
  assertEq j{"type"}.getStr(""), "urn:ietf:params:jmap:error:unknownCapability"
  let rt = RequestError.fromJson(j).get()
  assertEq rt, original

testCase roundTripRequestErrorNotJson:
  ## RFC 8620 section 3.6.1: notJSON.
  let original = requestError(
    rawType = "urn:ietf:params:jmap:error:notJSON",
    status = Opt.some(400),
    title = Opt.some("Not JSON"),
    detail = Opt.some("The request body was not valid JSON"),
  )
  doAssert original.errorType == retNotJson
  let j = original.toJson()
  assertEq j{"type"}.getStr(""), "urn:ietf:params:jmap:error:notJSON"
  let rt = RequestError.fromJson(j).get()
  assertEq rt, original

testCase roundTripRequestErrorNotRequest:
  ## RFC 8620 section 3.6.1: notRequest.
  let original = requestError(
    rawType = "urn:ietf:params:jmap:error:notRequest",
    status = Opt.some(400),
    title = Opt.some("Not a Request"),
    detail = Opt.some("The JSON was valid but not a valid JMAP request"),
  )
  doAssert original.errorType == retNotRequest
  let j = original.toJson()
  assertEq j{"type"}.getStr(""), "urn:ietf:params:jmap:error:notRequest"
  let rt = RequestError.fromJson(j).get()
  assertEq rt, original

testCase roundTripRequestErrorLimit:
  ## RFC 8620 section 3.6.1: limit with limit field populated.
  let original = requestError(
    rawType = "urn:ietf:params:jmap:error:limit",
    status = Opt.some(400),
    title = Opt.some("Request Too Large"),
    detail = Opt.some("Exceeded maxCallsInRequest"),
    limit = Opt.some("maxCallsInRequest"),
  )
  doAssert original.errorType == retLimit
  let j = original.toJson()
  assertEq j{"type"}.getStr(""), "urn:ietf:params:jmap:error:limit"
  doAssert j{"limit"} != nil
  assertEq j{"limit"}.getStr(""), "maxCallsInRequest"
  let rt = RequestError.fromJson(j).get()
  assertEq rt, original

# --- MethodError: all 19 known types ---

testCase roundTripMethodErrorServerUnavailable:
  let original = methodError("serverUnavailable")
  doAssert original.errorType == metServerUnavailable
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorServerFail:
  let original = methodError("serverFail")
  doAssert original.errorType == metServerFail
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorServerPartialFail:
  let original = methodError("serverPartialFail")
  doAssert original.errorType == metServerPartialFail
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorUnknownMethod:
  let original = methodError("unknownMethod")
  doAssert original.errorType == metUnknownMethod
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorInvalidArguments:
  let original = methodError("invalidArguments")
  doAssert original.errorType == metInvalidArguments
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorInvalidResultReference:
  let original = methodError("invalidResultReference")
  doAssert original.errorType == metInvalidResultReference
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorForbidden:
  let original = methodError("forbidden")
  doAssert original.errorType == metForbidden
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorAccountNotFound:
  let original = methodError("accountNotFound")
  doAssert original.errorType == metAccountNotFound
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorAccountNotSupportedByMethod:
  let original = methodError("accountNotSupportedByMethod")
  doAssert original.errorType == metAccountNotSupportedByMethod
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorAccountReadOnly:
  let original = methodError("accountReadOnly")
  doAssert original.errorType == metAccountReadOnly
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorAnchorNotFound:
  let original = methodError("anchorNotFound")
  doAssert original.errorType == metAnchorNotFound
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorUnsupportedSort:
  let original = methodError("unsupportedSort")
  doAssert original.errorType == metUnsupportedSort
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorUnsupportedFilter:
  let original = methodError("unsupportedFilter")
  doAssert original.errorType == metUnsupportedFilter
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorCannotCalculateChanges:
  let original = methodError("cannotCalculateChanges")
  doAssert original.errorType == metCannotCalculateChanges
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorTooManyChanges:
  let original = methodError("tooManyChanges")
  doAssert original.errorType == metTooManyChanges
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorRequestTooLarge:
  let original = methodError("requestTooLarge")
  doAssert original.errorType == metRequestTooLarge
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorStateMismatch:
  let original = methodError("stateMismatch")
  doAssert original.errorType == metStateMismatch
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorFromAccountNotFound:
  let original = methodError("fromAccountNotFound")
  doAssert original.errorType == metFromAccountNotFound
  assertOkEq MethodError.fromJson(original.toJson()), original

testCase roundTripMethodErrorFromAccountNotSupportedByMethod:
  let original = methodError("fromAccountNotSupportedByMethod")
  doAssert original.errorType == metFromAccountNotSupportedByMethod
  assertOkEq MethodError.fromJson(original.toJson()), original

# --- SetError: all 10 known types ---

testCase roundTripSetErrorForbiddenEnum:
  let original = setError("forbidden")
  doAssert original.errorType == setForbidden
  assertSetOkEq SetError.fromJson(original.toJson()).get(), original

testCase roundTripSetErrorOverQuota:
  let original = setError("overQuota")
  doAssert original.errorType == setOverQuota
  assertSetOkEq SetError.fromJson(original.toJson()).get(), original

testCase roundTripSetErrorTooLarge:
  let original = setError("tooLarge")
  doAssert original.errorType == setTooLarge
  assertSetOkEq SetError.fromJson(original.toJson()).get(), original

testCase roundTripSetErrorRateLimit:
  let original = setError("rateLimit")
  doAssert original.errorType == setRateLimit
  assertSetOkEq SetError.fromJson(original.toJson()).get(), original

testCase roundTripSetErrorNotFound:
  let original = setError("notFound")
  doAssert original.errorType == setNotFound
  assertSetOkEq SetError.fromJson(original.toJson()).get(), original

testCase roundTripSetErrorInvalidPatch:
  let original = setError("invalidPatch")
  doAssert original.errorType == setInvalidPatch
  assertSetOkEq SetError.fromJson(original.toJson()).get(), original

testCase roundTripSetErrorWillDestroy:
  let original = setError("willDestroy")
  doAssert original.errorType == setWillDestroy
  assertSetOkEq SetError.fromJson(original.toJson()).get(), original

testCase roundTripSetErrorSingleton:
  let original = setError("singleton")
  doAssert original.errorType == setSingleton
  assertSetOkEq SetError.fromJson(original.toJson()).get(), original

testCase roundTripSetErrorInvalidPropertiesWithData:
  ## invalidProperties variant with a list of property names.
  let original =
    setErrorInvalidProperties("invalidProperties", @["from", "subject", "body"])
  doAssert original.errorType == setInvalidProperties
  assertSetOkEq SetError.fromJson(original.toJson()).get(), original

testCase roundTripSetErrorAlreadyExistsWithData:
  ## alreadyExists variant with an existing record ID.
  let original = setErrorAlreadyExists("alreadyExists", makeId("existing42"))
  doAssert original.errorType == setAlreadyExists
  assertSetOkEq SetError.fromJson(original.toJson()).get(), original

# =============================================================================
# Extras collision: standard field names in extras must not overwrite
# =============================================================================

testCase requestErrorExtrasCollisionTypeField:
  ## Extras containing "type" must not overwrite the standard type field.
  let extras = newJObject()
  extras["type"] = %"evil"
  extras["vendor"] = %"safe"
  let re = requestError(
    rawType = "urn:ietf:params:jmap:error:limit", extras = Opt.some(extras)
  )
  let j = re.toJson()
  assertJsonFieldEq j, "type", %"urn:ietf:params:jmap:error:limit"
  assertJsonFieldEq j, "vendor", %"safe"

testCase requestErrorExtrasCollisionAllStandardFields:
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
    status = Opt.some(429),
    title = Opt.some("Rate Limit"),
    detail = Opt.some("Too many requests"),
    limit = Opt.some("maxCallsInRequest"),
    extras = Opt.some(extras),
  )
  let j = re.toJson()
  assertJsonFieldEq j, "type", %"urn:ietf:params:jmap:error:limit"
  assertJsonFieldEq j, "status", %429
  assertJsonFieldEq j, "title", %"Rate Limit"
  assertJsonFieldEq j, "detail", %"Too many requests"
  assertJsonFieldEq j, "limit", %"maxCallsInRequest"
  assertJsonFieldEq j, "vendor", %"safe"

testCase methodErrorExtrasCollisionTypeField:
  let extras = newJObject()
  extras["type"] = %"evil"
  extras["description"] = %"evil-desc"
  extras["vendor"] = %"safe"
  let me = methodError(
    rawType = "invalidArguments",
    description = Opt.some("real description"),
    extras = Opt.some(extras),
  )
  let j = me.toJson()
  assertJsonFieldEq j, "type", %"invalidArguments"
  assertJsonFieldEq j, "description", %"real description"
  assertJsonFieldEq j, "vendor", %"safe"

testCase setErrorExtrasCollisionTypeField:
  let extras = newJObject()
  extras["type"] = %"evil"
  extras["vendor"] = %"safe"
  let se = setError(
    rawType = "forbidden",
    description = Opt.some("real desc"),
    extras = Opt.some(extras),
  )
  let j = se.toJson()
  assertJsonFieldEq j, "type", %"forbidden"
  assertJsonFieldEq j, "vendor", %"safe"

testCase setErrorInvalidPropertiesExtrasCollisionProperties:
  let extras = newJObject()
  extras["properties"] = %*["evil"]
  extras["vendor"] = %"safe"
  let se = setErrorInvalidProperties(
    rawType = "invalidProperties",
    properties = @["subject", "body"],
    extras = Opt.some(extras),
  )
  let j = se.toJson()
  assertJsonFieldEq j, "type", %"invalidProperties"
  let propsNode = j{"properties"}
  assertFalse propsNode.isNil, "properties field must be present"
  assertEq propsNode.getElems(@[]).len, 2
  assertJsonFieldEq j, "vendor", %"safe"
