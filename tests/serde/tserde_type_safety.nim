# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Systematic type mismatch tests: every fromJson function tested against
## every wrong JsonNodeKind. Verifies that Layer 2 deserialisers gracefully
## reject all incorrect JSON kinds.

import std/json

import jmap_client/serde
import jmap_client/serde_envelope
import jmap_client/serde_session
import jmap_client/serde_framework
import jmap_client/serde_errors
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/session
import jmap_client/envelope
import jmap_client/framework
import jmap_client/errors

import ../massertions
import ../mfixtures
import ../mserde_fixtures

const nilNode: JsonNode = nil

# =============================================================================
# A. String-backed type mismatch (expect JString)
# =============================================================================

# --- Id ---

block idWrongKindNil:
  assertErr Id.fromJson(nilNode)

block idWrongKindJNull:
  assertErr Id.fromJson(newJNull())

block idWrongKindJBool:
  assertErr Id.fromJson(newJBool(true))

block idWrongKindJInt:
  assertErr Id.fromJson(%42)

block idWrongKindJFloat:
  assertErr Id.fromJson(newJFloat(3.14))

block idWrongKindJArray:
  assertErr Id.fromJson(%*[1, 2])

block idWrongKindJObject:
  assertErr Id.fromJson(%*{"x": 1})

# --- AccountId ---

block accountIdWrongKindNil:
  assertErr AccountId.fromJson(nilNode)

block accountIdWrongKindJNull:
  assertErr AccountId.fromJson(newJNull())

block accountIdWrongKindJBool:
  assertErr AccountId.fromJson(newJBool(true))

block accountIdWrongKindJInt:
  assertErr AccountId.fromJson(%42)

block accountIdWrongKindJFloat:
  assertErr AccountId.fromJson(newJFloat(3.14))

block accountIdWrongKindJArray:
  assertErr AccountId.fromJson(%*[1, 2])

block accountIdWrongKindJObject:
  assertErr AccountId.fromJson(%*{"x": 1})

# --- JmapState ---

block jmapStateWrongKindNil:
  assertErr JmapState.fromJson(nilNode)

block jmapStateWrongKindJNull:
  assertErr JmapState.fromJson(newJNull())

block jmapStateWrongKindJBool:
  assertErr JmapState.fromJson(newJBool(true))

block jmapStateWrongKindJInt:
  assertErr JmapState.fromJson(%42)

block jmapStateWrongKindJFloat:
  assertErr JmapState.fromJson(newJFloat(3.14))

block jmapStateWrongKindJArray:
  assertErr JmapState.fromJson(%*[1, 2])

block jmapStateWrongKindJObject:
  assertErr JmapState.fromJson(%*{"x": 1})

# --- MethodCallId ---

block methodCallIdWrongKindNil:
  assertErr MethodCallId.fromJson(nilNode)

block methodCallIdWrongKindJNull:
  assertErr MethodCallId.fromJson(newJNull())

block methodCallIdWrongKindJBool:
  assertErr MethodCallId.fromJson(newJBool(true))

block methodCallIdWrongKindJInt:
  assertErr MethodCallId.fromJson(%42)

block methodCallIdWrongKindJFloat:
  assertErr MethodCallId.fromJson(newJFloat(3.14))

block methodCallIdWrongKindJArray:
  assertErr MethodCallId.fromJson(%*[1, 2])

block methodCallIdWrongKindJObject:
  assertErr MethodCallId.fromJson(%*{"x": 1})

# --- CreationId ---

block creationIdWrongKindNil:
  assertErr CreationId.fromJson(nilNode)

block creationIdWrongKindJNull:
  assertErr CreationId.fromJson(newJNull())

block creationIdWrongKindJBool:
  assertErr CreationId.fromJson(newJBool(true))

block creationIdWrongKindJInt:
  assertErr CreationId.fromJson(%42)

block creationIdWrongKindJFloat:
  assertErr CreationId.fromJson(newJFloat(3.14))

block creationIdWrongKindJArray:
  assertErr CreationId.fromJson(%*[1, 2])

block creationIdWrongKindJObject:
  assertErr CreationId.fromJson(%*{"x": 1})

# --- UriTemplate ---

block uriTemplateWrongKindNil:
  assertErr UriTemplate.fromJson(nilNode)

block uriTemplateWrongKindJNull:
  assertErr UriTemplate.fromJson(newJNull())

block uriTemplateWrongKindJBool:
  assertErr UriTemplate.fromJson(newJBool(true))

block uriTemplateWrongKindJInt:
  assertErr UriTemplate.fromJson(%42)

block uriTemplateWrongKindJFloat:
  assertErr UriTemplate.fromJson(newJFloat(3.14))

block uriTemplateWrongKindJArray:
  assertErr UriTemplate.fromJson(%*[1, 2])

block uriTemplateWrongKindJObject:
  assertErr UriTemplate.fromJson(%*{"x": 1})

# --- PropertyName ---

block propertyNameWrongKindNil:
  assertErr PropertyName.fromJson(nilNode)

block propertyNameWrongKindJNull:
  assertErr PropertyName.fromJson(newJNull())

block propertyNameWrongKindJBool:
  assertErr PropertyName.fromJson(newJBool(true))

block propertyNameWrongKindJInt:
  assertErr PropertyName.fromJson(%42)

block propertyNameWrongKindJFloat:
  assertErr PropertyName.fromJson(newJFloat(3.14))

block propertyNameWrongKindJArray:
  assertErr PropertyName.fromJson(%*[1, 2])

block propertyNameWrongKindJObject:
  assertErr PropertyName.fromJson(%*{"x": 1})

# --- Date ---

block dateWrongKindNil:
  assertErr Date.fromJson(nilNode)

block dateWrongKindJNull:
  assertErr Date.fromJson(newJNull())

block dateWrongKindJBool:
  assertErr Date.fromJson(newJBool(true))

block dateWrongKindJInt:
  assertErr Date.fromJson(%42)

block dateWrongKindJFloat:
  assertErr Date.fromJson(newJFloat(3.14))

block dateWrongKindJArray:
  assertErr Date.fromJson(%*[1, 2])

block dateWrongKindJObject:
  assertErr Date.fromJson(%*{"x": 1})

# --- UTCDate ---

block utcDateWrongKindNil:
  assertErr UTCDate.fromJson(nilNode)

block utcDateWrongKindJNull:
  assertErr UTCDate.fromJson(newJNull())

block utcDateWrongKindJBool:
  assertErr UTCDate.fromJson(newJBool(true))

block utcDateWrongKindJInt:
  assertErr UTCDate.fromJson(%42)

block utcDateWrongKindJFloat:
  assertErr UTCDate.fromJson(newJFloat(3.14))

block utcDateWrongKindJArray:
  assertErr UTCDate.fromJson(%*[1, 2])

block utcDateWrongKindJObject:
  assertErr UTCDate.fromJson(%*{"x": 1})

# =============================================================================
# B. Integer-backed type mismatch (expect JInt)
# =============================================================================

# --- UnsignedInt ---

block unsignedIntWrongKindNil:
  assertErr UnsignedInt.fromJson(nilNode)

block unsignedIntWrongKindJNull:
  assertErr UnsignedInt.fromJson(newJNull())

block unsignedIntWrongKindJBool:
  assertErr UnsignedInt.fromJson(newJBool(true))

block unsignedIntWrongKindJString:
  assertErr UnsignedInt.fromJson(%"42")

block unsignedIntWrongKindJFloat:
  assertErr UnsignedInt.fromJson(newJFloat(3.14))

block unsignedIntWrongKindJArray:
  assertErr UnsignedInt.fromJson(%*[1, 2])

block unsignedIntWrongKindJObject:
  assertErr UnsignedInt.fromJson(%*{"x": 1})

# --- JmapInt ---

block jmapIntWrongKindNil:
  assertErr JmapInt.fromJson(nilNode)

block jmapIntWrongKindJNull:
  assertErr JmapInt.fromJson(newJNull())

block jmapIntWrongKindJBool:
  assertErr JmapInt.fromJson(newJBool(true))

block jmapIntWrongKindJString:
  assertErr JmapInt.fromJson(%"42")

block jmapIntWrongKindJFloat:
  assertErr JmapInt.fromJson(newJFloat(3.14))

block jmapIntWrongKindJArray:
  assertErr JmapInt.fromJson(%*[1, 2])

block jmapIntWrongKindJObject:
  assertErr JmapInt.fromJson(%*{"x": 1})

# =============================================================================
# C. Object-backed type mismatch (expect JObject)
# =============================================================================

# --- CoreCapabilities ---

block coreCapsWrongKindNil:
  assertErr CoreCapabilities.fromJson(nilNode)

block coreCapsWrongKindJNull:
  assertErr CoreCapabilities.fromJson(newJNull())

block coreCapsWrongKindJBool:
  assertErr CoreCapabilities.fromJson(newJBool(true))

block coreCapsWrongKindJInt:
  assertErr CoreCapabilities.fromJson(%42)

block coreCapsWrongKindJFloat:
  assertErr CoreCapabilities.fromJson(newJFloat(3.14))

block coreCapsWrongKindJString:
  assertErr CoreCapabilities.fromJson(%"hello")

block coreCapsWrongKindJArray:
  assertErr CoreCapabilities.fromJson(%*[1, 2])

# --- Account ---

block accountWrongKindNil:
  assertErr Account.fromJson(nilNode)

block accountWrongKindJNull:
  assertErr Account.fromJson(newJNull())

block accountWrongKindJBool:
  assertErr Account.fromJson(newJBool(true))

block accountWrongKindJInt:
  assertErr Account.fromJson(%42)

block accountWrongKindJFloat:
  assertErr Account.fromJson(newJFloat(3.14))

block accountWrongKindJString:
  assertErr Account.fromJson(%"hello")

block accountWrongKindJArray:
  assertErr Account.fromJson(%*[1, 2])

# --- Request ---

block requestWrongKindNil:
  assertErr Request.fromJson(nilNode)

block requestWrongKindJNull:
  assertErr Request.fromJson(newJNull())

block requestWrongKindJBool:
  assertErr Request.fromJson(newJBool(true))

block requestWrongKindJInt:
  assertErr Request.fromJson(%42)

block requestWrongKindJFloat:
  assertErr Request.fromJson(newJFloat(3.14))

block requestWrongKindJString:
  assertErr Request.fromJson(%"hello")

block requestWrongKindJArray:
  assertErr Request.fromJson(%*[1, 2])

# --- Response ---

block responseWrongKindNil:
  assertErr Response.fromJson(nilNode)

block responseWrongKindJNull:
  assertErr Response.fromJson(newJNull())

block responseWrongKindJBool:
  assertErr Response.fromJson(newJBool(true))

block responseWrongKindJInt:
  assertErr Response.fromJson(%42)

block responseWrongKindJFloat:
  assertErr Response.fromJson(newJFloat(3.14))

block responseWrongKindJString:
  assertErr Response.fromJson(%"hello")

block responseWrongKindJArray:
  assertErr Response.fromJson(%*[1, 2])

# --- ResultReference ---

block resultRefWrongKindNil:
  assertErr ResultReference.fromJson(nilNode)

block resultRefWrongKindJNull:
  assertErr ResultReference.fromJson(newJNull())

block resultRefWrongKindJBool:
  assertErr ResultReference.fromJson(newJBool(true))

block resultRefWrongKindJInt:
  assertErr ResultReference.fromJson(%42)

block resultRefWrongKindJFloat:
  assertErr ResultReference.fromJson(newJFloat(3.14))

block resultRefWrongKindJString:
  assertErr ResultReference.fromJson(%"hello")

block resultRefWrongKindJArray:
  assertErr ResultReference.fromJson(%*[1, 2])

# --- Comparator ---

block comparatorWrongKindNil:
  assertErr Comparator.fromJson(nilNode)

block comparatorWrongKindJNull:
  assertErr Comparator.fromJson(newJNull())

block comparatorWrongKindJBool:
  assertErr Comparator.fromJson(newJBool(true))

block comparatorWrongKindJInt:
  assertErr Comparator.fromJson(%42)

block comparatorWrongKindJFloat:
  assertErr Comparator.fromJson(newJFloat(3.14))

block comparatorWrongKindJString:
  assertErr Comparator.fromJson(%"hello")

block comparatorWrongKindJArray:
  assertErr Comparator.fromJson(%*[1, 2])

# --- PatchObject ---

block patchObjectWrongKindNil:
  assertErr PatchObject.fromJson(nilNode)

block patchObjectWrongKindJNull:
  assertErr PatchObject.fromJson(newJNull())

block patchObjectWrongKindJBool:
  assertErr PatchObject.fromJson(newJBool(true))

block patchObjectWrongKindJInt:
  assertErr PatchObject.fromJson(%42)

block patchObjectWrongKindJFloat:
  assertErr PatchObject.fromJson(newJFloat(3.14))

block patchObjectWrongKindJString:
  assertErr PatchObject.fromJson(%"hello")

block patchObjectWrongKindJArray:
  assertErr PatchObject.fromJson(%*[1, 2])

# --- AddedItem ---

block addedItemWrongKindNil:
  assertErr AddedItem.fromJson(nilNode)

block addedItemWrongKindJNull:
  assertErr AddedItem.fromJson(newJNull())

block addedItemWrongKindJBool:
  assertErr AddedItem.fromJson(newJBool(true))

block addedItemWrongKindJInt:
  assertErr AddedItem.fromJson(%42)

block addedItemWrongKindJFloat:
  assertErr AddedItem.fromJson(newJFloat(3.14))

block addedItemWrongKindJString:
  assertErr AddedItem.fromJson(%"hello")

block addedItemWrongKindJArray:
  assertErr AddedItem.fromJson(%*[1, 2])

# --- RequestError ---

block requestErrorWrongKindNil:
  assertErr RequestError.fromJson(nilNode)

block requestErrorWrongKindJNull:
  assertErr RequestError.fromJson(newJNull())

block requestErrorWrongKindJBool:
  assertErr RequestError.fromJson(newJBool(true))

block requestErrorWrongKindJInt:
  assertErr RequestError.fromJson(%42)

block requestErrorWrongKindJFloat:
  assertErr RequestError.fromJson(newJFloat(3.14))

block requestErrorWrongKindJString:
  assertErr RequestError.fromJson(%"hello")

block requestErrorWrongKindJArray:
  assertErr RequestError.fromJson(%*[1, 2])

# --- MethodError ---

block methodErrorWrongKindNil:
  assertErr MethodError.fromJson(nilNode)

block methodErrorWrongKindJNull:
  assertErr MethodError.fromJson(newJNull())

block methodErrorWrongKindJBool:
  assertErr MethodError.fromJson(newJBool(true))

block methodErrorWrongKindJInt:
  assertErr MethodError.fromJson(%42)

block methodErrorWrongKindJFloat:
  assertErr MethodError.fromJson(newJFloat(3.14))

block methodErrorWrongKindJString:
  assertErr MethodError.fromJson(%"hello")

block methodErrorWrongKindJArray:
  assertErr MethodError.fromJson(%*[1, 2])

# --- SetError ---

block setErrorWrongKindNil:
  assertErr SetError.fromJson(nilNode)

block setErrorWrongKindJNull:
  assertErr SetError.fromJson(newJNull())

block setErrorWrongKindJBool:
  assertErr SetError.fromJson(newJBool(true))

block setErrorWrongKindJInt:
  assertErr SetError.fromJson(%42)

block setErrorWrongKindJFloat:
  assertErr SetError.fromJson(newJFloat(3.14))

block setErrorWrongKindJString:
  assertErr SetError.fromJson(%"hello")

block setErrorWrongKindJArray:
  assertErr SetError.fromJson(%*[1, 2])

# --- Filter[int] ---

block filterWrongKindNil:
  assertErr Filter[int].fromJson(nilNode, fromIntCondition)

block filterWrongKindJNull:
  assertErr Filter[int].fromJson(newJNull(), fromIntCondition)

block filterWrongKindJBool:
  assertErr Filter[int].fromJson(newJBool(true), fromIntCondition)

block filterWrongKindJInt:
  assertErr Filter[int].fromJson(%42, fromIntCondition)

block filterWrongKindJFloat:
  assertErr Filter[int].fromJson(newJFloat(3.14), fromIntCondition)

block filterWrongKindJString:
  assertErr Filter[int].fromJson(%"hello", fromIntCondition)

block filterWrongKindJArray:
  assertErr Filter[int].fromJson(%*[1, 2], fromIntCondition)

# =============================================================================
# D. Array-backed type mismatch (Invocation expects JArray)
# =============================================================================

block invocationWrongKindNil:
  assertErr Invocation.fromJson(nilNode)

block invocationWrongKindJNull:
  assertErr Invocation.fromJson(newJNull())

block invocationWrongKindJBool:
  assertErr Invocation.fromJson(newJBool(true))

block invocationWrongKindJInt:
  assertErr Invocation.fromJson(%42)

block invocationWrongKindJFloat:
  assertErr Invocation.fromJson(newJFloat(3.14))

block invocationWrongKindJString:
  assertErr Invocation.fromJson(%"hello")

block invocationWrongKindJObject:
  assertErr Invocation.fromJson(%*{"x": 1})

# =============================================================================
# E. Enum type mismatch (FilterOperator expects JString)
# =============================================================================

block filterOperatorWrongKindNil:
  assertErr FilterOperator.fromJson(nilNode)

block filterOperatorWrongKindJNull:
  assertErr FilterOperator.fromJson(newJNull())

block filterOperatorWrongKindJBool:
  assertErr FilterOperator.fromJson(newJBool(true))

block filterOperatorWrongKindJInt:
  assertErr FilterOperator.fromJson(%42)

block filterOperatorWrongKindJFloat:
  assertErr FilterOperator.fromJson(newJFloat(3.14))

block filterOperatorWrongKindJArray:
  assertErr FilterOperator.fromJson(%*[1, 2])

block filterOperatorWrongKindJObject:
  assertErr FilterOperator.fromJson(%*{"x": 1})

# =============================================================================
# F. ServerCapability type mismatch (core URI expects JObject for data)
# =============================================================================

block serverCapCoreWrongKindNil:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", nilNode)

block serverCapCoreWrongKindJNull:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", newJNull())

block serverCapCoreWrongKindJBool:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", newJBool(true))

block serverCapCoreWrongKindJInt:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", %42)

block serverCapCoreWrongKindJFloat:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", newJFloat(3.14))

block serverCapCoreWrongKindJString:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", %"hello")

block serverCapCoreWrongKindJArray:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", %*[1, 2])

# Non-core capability URIs accept any kind for rawData (pass-through).

block serverCapMailAcceptsNil:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", nilNode)

block serverCapMailAcceptsJNull:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", newJNull())

block serverCapMailAcceptsJBool:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", newJBool(true))

block serverCapMailAcceptsJInt:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", %42)

block serverCapMailAcceptsJString:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", %"hello")

block serverCapMailAcceptsJArray:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", %*[1, 2])

block serverCapMailAcceptsJObject:
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

block coreCapsFieldMaxSizeUploadWrongKind:
  assertErr CoreCapabilities.fromJson(coreCapsWithField("maxSizeUpload", %"bad"))

block coreCapsFieldMaxConcurrentUploadWrongKind:
  assertErr CoreCapabilities.fromJson(
    coreCapsWithField("maxConcurrentUpload", %"bad")
  )

block coreCapsFieldMaxSizeRequestWrongKind:
  assertErr CoreCapabilities.fromJson(coreCapsWithField("maxSizeRequest", %"bad"))

block coreCapsFieldMaxConcurrentRequestsWrongKind:
  assertErr CoreCapabilities.fromJson(
    coreCapsWithField("maxConcurrentRequests", %"bad")
  )

block coreCapsFieldMaxCallsInRequestWrongKind:
  assertErr CoreCapabilities.fromJson(coreCapsWithField("maxCallsInRequest", %"bad"))

block coreCapsFieldMaxObjectsInGetWrongKind:
  assertErr CoreCapabilities.fromJson(coreCapsWithField("maxObjectsInGet", %"bad"))

block coreCapsFieldMaxObjectsInSetWrongKind:
  assertErr CoreCapabilities.fromJson(coreCapsWithField("maxObjectsInSet", %"bad"))

block coreCapsFieldCollationAlgorithmsWrongKind:
  assertErr CoreCapabilities.fromJson(
    coreCapsWithField("collationAlgorithms", %"bad")
  )

# =============================================================================
# F. Cross-type confusion tests
# =============================================================================

block crossTypeIdAndAccountIdSameJson:
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

block distinctTypeRoundTripIsolation:
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
