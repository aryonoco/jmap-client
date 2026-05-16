# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Systematic type mismatch tests: every fromJson function tested against
## every wrong JsonNodeKind. Verifies that Layer 2 deserialisers gracefully
## reject all incorrect JSON kinds.

import std/json

import jmap_client/internal/serialisation/serde
import jmap_client/internal/serialisation/serde_envelope
import jmap_client/internal/serialisation/serde_primitives
import jmap_client/internal/serialisation/serde_session
import jmap_client/internal/serialisation/serde_framework
import jmap_client/internal/serialisation/serde_errors
import jmap_client/internal/types/primitives
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/session
import jmap_client/internal/types/envelope
import jmap_client/internal/types/framework
import jmap_client/internal/types/errors

import ../massertions
import ../mfixtures
import ../mserde_fixtures
import ../mtestblock

const nilNode: JsonNode = nil

# =============================================================================
# A. String-backed type mismatch (expect JString)
# =============================================================================

# --- Id ---

testCase idWrongKindNil:
  assertErr Id.fromJson(nilNode)

testCase idWrongKindJNull:
  assertErr Id.fromJson(newJNull())

testCase idWrongKindJBool:
  assertErr Id.fromJson(newJBool(true))

testCase idWrongKindJInt:
  assertErr Id.fromJson(%42)

testCase idWrongKindJFloat:
  assertErr Id.fromJson(newJFloat(3.14))

testCase idWrongKindJArray:
  assertErr Id.fromJson(%*[1, 2])

testCase idWrongKindJObject:
  assertErr Id.fromJson(%*{"x": 1})

# --- AccountId ---

testCase accountIdWrongKindNil:
  assertErr AccountId.fromJson(nilNode)

testCase accountIdWrongKindJNull:
  assertErr AccountId.fromJson(newJNull())

testCase accountIdWrongKindJBool:
  assertErr AccountId.fromJson(newJBool(true))

testCase accountIdWrongKindJInt:
  assertErr AccountId.fromJson(%42)

testCase accountIdWrongKindJFloat:
  assertErr AccountId.fromJson(newJFloat(3.14))

testCase accountIdWrongKindJArray:
  assertErr AccountId.fromJson(%*[1, 2])

testCase accountIdWrongKindJObject:
  assertErr AccountId.fromJson(%*{"x": 1})

# --- JmapState ---

testCase jmapStateWrongKindNil:
  assertErr JmapState.fromJson(nilNode)

testCase jmapStateWrongKindJNull:
  assertErr JmapState.fromJson(newJNull())

testCase jmapStateWrongKindJBool:
  assertErr JmapState.fromJson(newJBool(true))

testCase jmapStateWrongKindJInt:
  assertErr JmapState.fromJson(%42)

testCase jmapStateWrongKindJFloat:
  assertErr JmapState.fromJson(newJFloat(3.14))

testCase jmapStateWrongKindJArray:
  assertErr JmapState.fromJson(%*[1, 2])

testCase jmapStateWrongKindJObject:
  assertErr JmapState.fromJson(%*{"x": 1})

# --- MethodCallId ---

testCase methodCallIdWrongKindNil:
  assertErr MethodCallId.fromJson(nilNode)

testCase methodCallIdWrongKindJNull:
  assertErr MethodCallId.fromJson(newJNull())

testCase methodCallIdWrongKindJBool:
  assertErr MethodCallId.fromJson(newJBool(true))

testCase methodCallIdWrongKindJInt:
  assertErr MethodCallId.fromJson(%42)

testCase methodCallIdWrongKindJFloat:
  assertErr MethodCallId.fromJson(newJFloat(3.14))

testCase methodCallIdWrongKindJArray:
  assertErr MethodCallId.fromJson(%*[1, 2])

testCase methodCallIdWrongKindJObject:
  assertErr MethodCallId.fromJson(%*{"x": 1})

# --- CreationId ---

testCase creationIdWrongKindNil:
  assertErr CreationId.fromJson(nilNode)

testCase creationIdWrongKindJNull:
  assertErr CreationId.fromJson(newJNull())

testCase creationIdWrongKindJBool:
  assertErr CreationId.fromJson(newJBool(true))

testCase creationIdWrongKindJInt:
  assertErr CreationId.fromJson(%42)

testCase creationIdWrongKindJFloat:
  assertErr CreationId.fromJson(newJFloat(3.14))

testCase creationIdWrongKindJArray:
  assertErr CreationId.fromJson(%*[1, 2])

testCase creationIdWrongKindJObject:
  assertErr CreationId.fromJson(%*{"x": 1})

# --- UriTemplate ---

testCase uriTemplateWrongKindNil:
  assertErr UriTemplate.fromJson(nilNode)

testCase uriTemplateWrongKindJNull:
  assertErr UriTemplate.fromJson(newJNull())

testCase uriTemplateWrongKindJBool:
  assertErr UriTemplate.fromJson(newJBool(true))

testCase uriTemplateWrongKindJInt:
  assertErr UriTemplate.fromJson(%42)

testCase uriTemplateWrongKindJFloat:
  assertErr UriTemplate.fromJson(newJFloat(3.14))

testCase uriTemplateWrongKindJArray:
  assertErr UriTemplate.fromJson(%*[1, 2])

testCase uriTemplateWrongKindJObject:
  assertErr UriTemplate.fromJson(%*{"x": 1})

# --- PropertyName ---

testCase propertyNameWrongKindNil:
  assertErr PropertyName.fromJson(nilNode)

testCase propertyNameWrongKindJNull:
  assertErr PropertyName.fromJson(newJNull())

testCase propertyNameWrongKindJBool:
  assertErr PropertyName.fromJson(newJBool(true))

testCase propertyNameWrongKindJInt:
  assertErr PropertyName.fromJson(%42)

testCase propertyNameWrongKindJFloat:
  assertErr PropertyName.fromJson(newJFloat(3.14))

testCase propertyNameWrongKindJArray:
  assertErr PropertyName.fromJson(%*[1, 2])

testCase propertyNameWrongKindJObject:
  assertErr PropertyName.fromJson(%*{"x": 1})

# --- Date ---

testCase dateWrongKindNil:
  assertErr Date.fromJson(nilNode)

testCase dateWrongKindJNull:
  assertErr Date.fromJson(newJNull())

testCase dateWrongKindJBool:
  assertErr Date.fromJson(newJBool(true))

testCase dateWrongKindJInt:
  assertErr Date.fromJson(%42)

testCase dateWrongKindJFloat:
  assertErr Date.fromJson(newJFloat(3.14))

testCase dateWrongKindJArray:
  assertErr Date.fromJson(%*[1, 2])

testCase dateWrongKindJObject:
  assertErr Date.fromJson(%*{"x": 1})

# --- UTCDate ---

testCase utcDateWrongKindNil:
  assertErr UTCDate.fromJson(nilNode)

testCase utcDateWrongKindJNull:
  assertErr UTCDate.fromJson(newJNull())

testCase utcDateWrongKindJBool:
  assertErr UTCDate.fromJson(newJBool(true))

testCase utcDateWrongKindJInt:
  assertErr UTCDate.fromJson(%42)

testCase utcDateWrongKindJFloat:
  assertErr UTCDate.fromJson(newJFloat(3.14))

testCase utcDateWrongKindJArray:
  assertErr UTCDate.fromJson(%*[1, 2])

testCase utcDateWrongKindJObject:
  assertErr UTCDate.fromJson(%*{"x": 1})

# =============================================================================
# B. Integer-backed type mismatch (expect JInt)
# =============================================================================

# --- UnsignedInt ---

testCase unsignedIntWrongKindNil:
  assertErr UnsignedInt.fromJson(nilNode)

testCase unsignedIntWrongKindJNull:
  assertErr UnsignedInt.fromJson(newJNull())

testCase unsignedIntWrongKindJBool:
  assertErr UnsignedInt.fromJson(newJBool(true))

testCase unsignedIntWrongKindJString:
  assertErr UnsignedInt.fromJson(%"42")

testCase unsignedIntWrongKindJFloat:
  assertErr UnsignedInt.fromJson(newJFloat(3.14))

testCase unsignedIntWrongKindJArray:
  assertErr UnsignedInt.fromJson(%*[1, 2])

testCase unsignedIntWrongKindJObject:
  assertErr UnsignedInt.fromJson(%*{"x": 1})

# --- JmapInt ---

testCase jmapIntWrongKindNil:
  assertErr JmapInt.fromJson(nilNode)

testCase jmapIntWrongKindJNull:
  assertErr JmapInt.fromJson(newJNull())

testCase jmapIntWrongKindJBool:
  assertErr JmapInt.fromJson(newJBool(true))

testCase jmapIntWrongKindJString:
  assertErr JmapInt.fromJson(%"42")

testCase jmapIntWrongKindJFloat:
  assertErr JmapInt.fromJson(newJFloat(3.14))

testCase jmapIntWrongKindJArray:
  assertErr JmapInt.fromJson(%*[1, 2])

testCase jmapIntWrongKindJObject:
  assertErr JmapInt.fromJson(%*{"x": 1})

# =============================================================================
# C. Object-backed type mismatch (expect JObject)
# =============================================================================

# --- CoreCapabilities ---

testCase coreCapsWrongKindNil:
  assertErr CoreCapabilities.fromJson(nilNode)

testCase coreCapsWrongKindJNull:
  assertErr CoreCapabilities.fromJson(newJNull())

testCase coreCapsWrongKindJBool:
  assertErr CoreCapabilities.fromJson(newJBool(true))

testCase coreCapsWrongKindJInt:
  assertErr CoreCapabilities.fromJson(%42)

testCase coreCapsWrongKindJFloat:
  assertErr CoreCapabilities.fromJson(newJFloat(3.14))

testCase coreCapsWrongKindJString:
  assertErr CoreCapabilities.fromJson(%"hello")

testCase coreCapsWrongKindJArray:
  assertErr CoreCapabilities.fromJson(%*[1, 2])

# --- Account ---

testCase accountWrongKindNil:
  assertErr Account.fromJson(nilNode)

testCase accountWrongKindJNull:
  assertErr Account.fromJson(newJNull())

testCase accountWrongKindJBool:
  assertErr Account.fromJson(newJBool(true))

testCase accountWrongKindJInt:
  assertErr Account.fromJson(%42)

testCase accountWrongKindJFloat:
  assertErr Account.fromJson(newJFloat(3.14))

testCase accountWrongKindJString:
  assertErr Account.fromJson(%"hello")

testCase accountWrongKindJArray:
  assertErr Account.fromJson(%*[1, 2])

# --- Request ---

testCase requestWrongKindNil:
  assertErr Request.fromJson(nilNode)

testCase requestWrongKindJNull:
  assertErr Request.fromJson(newJNull())

testCase requestWrongKindJBool:
  assertErr Request.fromJson(newJBool(true))

testCase requestWrongKindJInt:
  assertErr Request.fromJson(%42)

testCase requestWrongKindJFloat:
  assertErr Request.fromJson(newJFloat(3.14))

testCase requestWrongKindJString:
  assertErr Request.fromJson(%"hello")

testCase requestWrongKindJArray:
  assertErr Request.fromJson(%*[1, 2])

# --- Response ---

testCase responseWrongKindNil:
  assertErr Response.fromJson(nilNode)

testCase responseWrongKindJNull:
  assertErr Response.fromJson(newJNull())

testCase responseWrongKindJBool:
  assertErr Response.fromJson(newJBool(true))

testCase responseWrongKindJInt:
  assertErr Response.fromJson(%42)

testCase responseWrongKindJFloat:
  assertErr Response.fromJson(newJFloat(3.14))

testCase responseWrongKindJString:
  assertErr Response.fromJson(%"hello")

testCase responseWrongKindJArray:
  assertErr Response.fromJson(%*[1, 2])

# --- ResultReference ---

testCase resultRefWrongKindNil:
  assertErr ResultReference.fromJson(nilNode)

testCase resultRefWrongKindJNull:
  assertErr ResultReference.fromJson(newJNull())

testCase resultRefWrongKindJBool:
  assertErr ResultReference.fromJson(newJBool(true))

testCase resultRefWrongKindJInt:
  assertErr ResultReference.fromJson(%42)

testCase resultRefWrongKindJFloat:
  assertErr ResultReference.fromJson(newJFloat(3.14))

testCase resultRefWrongKindJString:
  assertErr ResultReference.fromJson(%"hello")

testCase resultRefWrongKindJArray:
  assertErr ResultReference.fromJson(%*[1, 2])

# --- Comparator ---

testCase comparatorWrongKindNil:
  assertErr Comparator.fromJson(nilNode)

testCase comparatorWrongKindJNull:
  assertErr Comparator.fromJson(newJNull())

testCase comparatorWrongKindJBool:
  assertErr Comparator.fromJson(newJBool(true))

testCase comparatorWrongKindJInt:
  assertErr Comparator.fromJson(%42)

testCase comparatorWrongKindJFloat:
  assertErr Comparator.fromJson(newJFloat(3.14))

testCase comparatorWrongKindJString:
  assertErr Comparator.fromJson(%"hello")

testCase comparatorWrongKindJArray:
  assertErr Comparator.fromJson(%*[1, 2])

# --- AddedItem ---

testCase addedItemWrongKindNil:
  assertErr AddedItem.fromJson(nilNode)

testCase addedItemWrongKindJNull:
  assertErr AddedItem.fromJson(newJNull())

testCase addedItemWrongKindJBool:
  assertErr AddedItem.fromJson(newJBool(true))

testCase addedItemWrongKindJInt:
  assertErr AddedItem.fromJson(%42)

testCase addedItemWrongKindJFloat:
  assertErr AddedItem.fromJson(newJFloat(3.14))

testCase addedItemWrongKindJString:
  assertErr AddedItem.fromJson(%"hello")

testCase addedItemWrongKindJArray:
  assertErr AddedItem.fromJson(%*[1, 2])

# --- RequestError ---

testCase requestErrorWrongKindNil:
  assertErr RequestError.fromJson(nilNode)

testCase requestErrorWrongKindJNull:
  assertErr RequestError.fromJson(newJNull())

testCase requestErrorWrongKindJBool:
  assertErr RequestError.fromJson(newJBool(true))

testCase requestErrorWrongKindJInt:
  assertErr RequestError.fromJson(%42)

testCase requestErrorWrongKindJFloat:
  assertErr RequestError.fromJson(newJFloat(3.14))

testCase requestErrorWrongKindJString:
  assertErr RequestError.fromJson(%"hello")

testCase requestErrorWrongKindJArray:
  assertErr RequestError.fromJson(%*[1, 2])

# --- MethodError ---

testCase methodErrorWrongKindNil:
  assertErr MethodError.fromJson(nilNode)

testCase methodErrorWrongKindJNull:
  assertErr MethodError.fromJson(newJNull())

testCase methodErrorWrongKindJBool:
  assertErr MethodError.fromJson(newJBool(true))

testCase methodErrorWrongKindJInt:
  assertErr MethodError.fromJson(%42)

testCase methodErrorWrongKindJFloat:
  assertErr MethodError.fromJson(newJFloat(3.14))

testCase methodErrorWrongKindJString:
  assertErr MethodError.fromJson(%"hello")

testCase methodErrorWrongKindJArray:
  assertErr MethodError.fromJson(%*[1, 2])

# --- SetError ---

testCase setErrorWrongKindNil:
  assertErr SetError.fromJson(nilNode)

testCase setErrorWrongKindJNull:
  assertErr SetError.fromJson(newJNull())

testCase setErrorWrongKindJBool:
  assertErr SetError.fromJson(newJBool(true))

testCase setErrorWrongKindJInt:
  assertErr SetError.fromJson(%42)

testCase setErrorWrongKindJFloat:
  assertErr SetError.fromJson(newJFloat(3.14))

testCase setErrorWrongKindJString:
  assertErr SetError.fromJson(%"hello")

testCase setErrorWrongKindJArray:
  assertErr SetError.fromJson(%*[1, 2])

# --- Filter[int] ---

testCase filterWrongKindNil:
  assertErr Filter[int].fromJson(nilNode, fromIntCondition)

testCase filterWrongKindJNull:
  assertErr Filter[int].fromJson(newJNull(), fromIntCondition)

testCase filterWrongKindJBool:
  assertErr Filter[int].fromJson(newJBool(true), fromIntCondition)

testCase filterWrongKindJInt:
  assertErr Filter[int].fromJson(%42, fromIntCondition)

testCase filterWrongKindJFloat:
  assertErr Filter[int].fromJson(newJFloat(3.14), fromIntCondition)

testCase filterWrongKindJString:
  assertErr Filter[int].fromJson(%"hello", fromIntCondition)

testCase filterWrongKindJArray:
  assertErr Filter[int].fromJson(%*[1, 2], fromIntCondition)

# =============================================================================
# D. Array-backed type mismatch (Invocation expects JArray)
# =============================================================================

testCase invocationWrongKindNil:
  assertErr Invocation.fromJson(nilNode)

testCase invocationWrongKindJNull:
  assertErr Invocation.fromJson(newJNull())

testCase invocationWrongKindJBool:
  assertErr Invocation.fromJson(newJBool(true))

testCase invocationWrongKindJInt:
  assertErr Invocation.fromJson(%42)

testCase invocationWrongKindJFloat:
  assertErr Invocation.fromJson(newJFloat(3.14))

testCase invocationWrongKindJString:
  assertErr Invocation.fromJson(%"hello")

testCase invocationWrongKindJObject:
  assertErr Invocation.fromJson(%*{"x": 1})

# =============================================================================
# E. Enum type mismatch (FilterOperator expects JString)
# =============================================================================

testCase filterOperatorWrongKindNil:
  assertErr FilterOperator.fromJson(nilNode)

testCase filterOperatorWrongKindJNull:
  assertErr FilterOperator.fromJson(newJNull())

testCase filterOperatorWrongKindJBool:
  assertErr FilterOperator.fromJson(newJBool(true))

testCase filterOperatorWrongKindJInt:
  assertErr FilterOperator.fromJson(%42)

testCase filterOperatorWrongKindJFloat:
  assertErr FilterOperator.fromJson(newJFloat(3.14))

testCase filterOperatorWrongKindJArray:
  assertErr FilterOperator.fromJson(%*[1, 2])

testCase filterOperatorWrongKindJObject:
  assertErr FilterOperator.fromJson(%*{"x": 1})

# =============================================================================
# F. ServerCapability type mismatch (core URI expects JObject for data)
# =============================================================================

testCase serverCapCoreWrongKindNil:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", nilNode)

testCase serverCapCoreWrongKindJNull:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", newJNull())

testCase serverCapCoreWrongKindJBool:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", newJBool(true))

testCase serverCapCoreWrongKindJInt:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", %42)

testCase serverCapCoreWrongKindJFloat:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", newJFloat(3.14))

testCase serverCapCoreWrongKindJString:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", %"hello")

testCase serverCapCoreWrongKindJArray:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", %*[1, 2])

# Non-core capability URIs accept any kind for rawData (pass-through).

testCase serverCapMailAcceptsNil:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", nilNode)

testCase serverCapMailAcceptsJNull:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", newJNull())

testCase serverCapMailAcceptsJBool:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", newJBool(true))

testCase serverCapMailAcceptsJInt:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", %42)

testCase serverCapMailAcceptsJString:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", %"hello")

testCase serverCapMailAcceptsJArray:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", %*[1, 2])

testCase serverCapMailAcceptsJObject:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", %*{"x": 1})

# =============================================================================
# G. Nested field wrong kinds (CoreCapabilities per-field replacement)
# =============================================================================

proc validCoreCapsJson(): JsonNode =
  ## Construct a valid CoreCapabilities JSON object for per-field testing.
  %*{
    "maxSizeUpload": 50000000,
    "maxConcurrentUpload": 8,
    "maxSizeRequest": 10000000,
    "maxConcurrentRequests": 8,
    "maxCallsInRequest": 32,
    "maxObjectsInGet": 256,
    "maxObjectsInSet": 128,
    "collationAlgorithms": ["i;ascii-numeric"],
  }

proc coreCapsWithField(field: string, value: JsonNode): JsonNode =
  ## Return a valid CoreCapabilities JSON with one field replaced.
  result = validCoreCapsJson()
  result[field] = value

testCase coreCapsFieldMaxSizeUploadWrongKind:
  assertErr CoreCapabilities.fromJson(coreCapsWithField("maxSizeUpload", %"bad"))

testCase coreCapsFieldMaxConcurrentUploadWrongKind:
  assertErr CoreCapabilities.fromJson(coreCapsWithField("maxConcurrentUpload", %"bad"))

testCase coreCapsFieldMaxSizeRequestWrongKind:
  assertErr CoreCapabilities.fromJson(coreCapsWithField("maxSizeRequest", %"bad"))

testCase coreCapsFieldMaxConcurrentRequestsWrongKind:
  assertErr CoreCapabilities.fromJson(
    coreCapsWithField("maxConcurrentRequests", %"bad")
  )

testCase coreCapsFieldMaxCallsInRequestWrongKind:
  assertErr CoreCapabilities.fromJson(coreCapsWithField("maxCallsInRequest", %"bad"))

testCase coreCapsFieldMaxObjectsInGetWrongKind:
  assertErr CoreCapabilities.fromJson(coreCapsWithField("maxObjectsInGet", %"bad"))

testCase coreCapsFieldMaxObjectsInSetWrongKind:
  assertErr CoreCapabilities.fromJson(coreCapsWithField("maxObjectsInSet", %"bad"))

testCase coreCapsFieldCollationAlgorithmsWrongKind:
  assertErr CoreCapabilities.fromJson(coreCapsWithField("collationAlgorithms", %"bad"))

# =============================================================================
# F. Cross-type confusion tests
# =============================================================================

testCase crossTypeIdAndAccountIdSameJson:
  ## Id.toJson and AccountId.toJson produce identical JSON for the same string,
  ## but both fromJson validate correctly through their respective constructors.
  let idVal = makeId("testval")
  let aidVal = makeAccountId("testval")
  let idJson = idVal.toJson()
  let aidJson = aidVal.toJson()
  # Same JSON output
  assertEq idJson.getStr(""), aidJson.getStr("")
  # Both round-trip correctly through their own type
  assertOk Id.fromJson(idJson)
  assertOk AccountId.fromJson(aidJson)

testCase distinctTypeRoundTripIsolation:
  ## Distinct types serialise identically but remain type-safe in Nim.
  ## This test verifies the serde layer preserves type semantics.
  let mcid = makeMcid("c0")
  let cid = makeCreationId("c0")
  let mcidJson = mcid.toJson()
  let cidJson = cid.toJson()
  # Same JSON string representation
  assertEq mcidJson.getStr(""), cidJson.getStr("")
  # Both round-trip through their own parsers
  assertOk MethodCallId.fromJson(mcidJson)
  assertOk CreationId.fromJson(cidJson)
