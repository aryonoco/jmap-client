# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Systematic type mismatch tests: every fromJson function tested against
## every wrong JsonNodeKind. Verifies that Layer 2 deserialisers gracefully
## reject all incorrect JSON kinds.

import std/json

import results

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
import jmap_client/validation

import ../massertions
import ../mfixtures

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc fromIntCondition(
    n: JsonNode
): Result[int, ValidationError] {.noSideEffect, raises: [].} =
  ## Deserialise a JSON object to int for Filter[int] tests.
  checkJsonKind(n, JObject, "int")
  let vNode = n{"value"}
  checkJsonKind(vNode, JInt, "int", "missing or invalid value")
  ok(vNode.getInt(0))

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
  {.cast(noSideEffect).}:
    assertErr Id.fromJson(newJBool(true))

block idWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr Id.fromJson(%42)

block idWrongKindJFloat:
  assertErr Id.fromJson(newJFloat(3.14))

block idWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr Id.fromJson(%*[1, 2])

block idWrongKindJObject:
  {.cast(noSideEffect).}:
    assertErr Id.fromJson(%*{"x": 1})

# --- AccountId ---

block accountIdWrongKindNil:
  assertErr AccountId.fromJson(nilNode)

block accountIdWrongKindJNull:
  assertErr AccountId.fromJson(newJNull())

block accountIdWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr AccountId.fromJson(newJBool(true))

block accountIdWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr AccountId.fromJson(%42)

block accountIdWrongKindJFloat:
  assertErr AccountId.fromJson(newJFloat(3.14))

block accountIdWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr AccountId.fromJson(%*[1, 2])

block accountIdWrongKindJObject:
  {.cast(noSideEffect).}:
    assertErr AccountId.fromJson(%*{"x": 1})

# --- JmapState ---

block jmapStateWrongKindNil:
  assertErr JmapState.fromJson(nilNode)

block jmapStateWrongKindJNull:
  assertErr JmapState.fromJson(newJNull())

block jmapStateWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr JmapState.fromJson(newJBool(true))

block jmapStateWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr JmapState.fromJson(%42)

block jmapStateWrongKindJFloat:
  assertErr JmapState.fromJson(newJFloat(3.14))

block jmapStateWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr JmapState.fromJson(%*[1, 2])

block jmapStateWrongKindJObject:
  {.cast(noSideEffect).}:
    assertErr JmapState.fromJson(%*{"x": 1})

# --- MethodCallId ---

block methodCallIdWrongKindNil:
  assertErr MethodCallId.fromJson(nilNode)

block methodCallIdWrongKindJNull:
  assertErr MethodCallId.fromJson(newJNull())

block methodCallIdWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr MethodCallId.fromJson(newJBool(true))

block methodCallIdWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr MethodCallId.fromJson(%42)

block methodCallIdWrongKindJFloat:
  assertErr MethodCallId.fromJson(newJFloat(3.14))

block methodCallIdWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr MethodCallId.fromJson(%*[1, 2])

block methodCallIdWrongKindJObject:
  {.cast(noSideEffect).}:
    assertErr MethodCallId.fromJson(%*{"x": 1})

# --- CreationId ---

block creationIdWrongKindNil:
  assertErr CreationId.fromJson(nilNode)

block creationIdWrongKindJNull:
  assertErr CreationId.fromJson(newJNull())

block creationIdWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr CreationId.fromJson(newJBool(true))

block creationIdWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr CreationId.fromJson(%42)

block creationIdWrongKindJFloat:
  assertErr CreationId.fromJson(newJFloat(3.14))

block creationIdWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr CreationId.fromJson(%*[1, 2])

block creationIdWrongKindJObject:
  {.cast(noSideEffect).}:
    assertErr CreationId.fromJson(%*{"x": 1})

# --- UriTemplate ---

block uriTemplateWrongKindNil:
  assertErr UriTemplate.fromJson(nilNode)

block uriTemplateWrongKindJNull:
  assertErr UriTemplate.fromJson(newJNull())

block uriTemplateWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr UriTemplate.fromJson(newJBool(true))

block uriTemplateWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr UriTemplate.fromJson(%42)

block uriTemplateWrongKindJFloat:
  assertErr UriTemplate.fromJson(newJFloat(3.14))

block uriTemplateWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr UriTemplate.fromJson(%*[1, 2])

block uriTemplateWrongKindJObject:
  {.cast(noSideEffect).}:
    assertErr UriTemplate.fromJson(%*{"x": 1})

# --- PropertyName ---

block propertyNameWrongKindNil:
  assertErr PropertyName.fromJson(nilNode)

block propertyNameWrongKindJNull:
  assertErr PropertyName.fromJson(newJNull())

block propertyNameWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr PropertyName.fromJson(newJBool(true))

block propertyNameWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr PropertyName.fromJson(%42)

block propertyNameWrongKindJFloat:
  assertErr PropertyName.fromJson(newJFloat(3.14))

block propertyNameWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr PropertyName.fromJson(%*[1, 2])

block propertyNameWrongKindJObject:
  {.cast(noSideEffect).}:
    assertErr PropertyName.fromJson(%*{"x": 1})

# --- Date ---

block dateWrongKindNil:
  assertErr Date.fromJson(nilNode)

block dateWrongKindJNull:
  assertErr Date.fromJson(newJNull())

block dateWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr Date.fromJson(newJBool(true))

block dateWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr Date.fromJson(%42)

block dateWrongKindJFloat:
  assertErr Date.fromJson(newJFloat(3.14))

block dateWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr Date.fromJson(%*[1, 2])

block dateWrongKindJObject:
  {.cast(noSideEffect).}:
    assertErr Date.fromJson(%*{"x": 1})

# --- UTCDate ---

block utcDateWrongKindNil:
  assertErr UTCDate.fromJson(nilNode)

block utcDateWrongKindJNull:
  assertErr UTCDate.fromJson(newJNull())

block utcDateWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr UTCDate.fromJson(newJBool(true))

block utcDateWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr UTCDate.fromJson(%42)

block utcDateWrongKindJFloat:
  assertErr UTCDate.fromJson(newJFloat(3.14))

block utcDateWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr UTCDate.fromJson(%*[1, 2])

block utcDateWrongKindJObject:
  {.cast(noSideEffect).}:
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
  {.cast(noSideEffect).}:
    assertErr UnsignedInt.fromJson(newJBool(true))

block unsignedIntWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr UnsignedInt.fromJson(%"42")

block unsignedIntWrongKindJFloat:
  assertErr UnsignedInt.fromJson(newJFloat(3.14))

block unsignedIntWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr UnsignedInt.fromJson(%*[1, 2])

block unsignedIntWrongKindJObject:
  {.cast(noSideEffect).}:
    assertErr UnsignedInt.fromJson(%*{"x": 1})

# --- JmapInt ---

block jmapIntWrongKindNil:
  assertErr JmapInt.fromJson(nilNode)

block jmapIntWrongKindJNull:
  assertErr JmapInt.fromJson(newJNull())

block jmapIntWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr JmapInt.fromJson(newJBool(true))

block jmapIntWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr JmapInt.fromJson(%"42")

block jmapIntWrongKindJFloat:
  assertErr JmapInt.fromJson(newJFloat(3.14))

block jmapIntWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr JmapInt.fromJson(%*[1, 2])

block jmapIntWrongKindJObject:
  {.cast(noSideEffect).}:
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
  {.cast(noSideEffect).}:
    assertErr CoreCapabilities.fromJson(newJBool(true))

block coreCapsWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr CoreCapabilities.fromJson(%42)

block coreCapsWrongKindJFloat:
  assertErr CoreCapabilities.fromJson(newJFloat(3.14))

block coreCapsWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr CoreCapabilities.fromJson(%"hello")

block coreCapsWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr CoreCapabilities.fromJson(%*[1, 2])

# --- Account ---

block accountWrongKindNil:
  assertErr Account.fromJson(nilNode)

block accountWrongKindJNull:
  assertErr Account.fromJson(newJNull())

block accountWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr Account.fromJson(newJBool(true))

block accountWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr Account.fromJson(%42)

block accountWrongKindJFloat:
  assertErr Account.fromJson(newJFloat(3.14))

block accountWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr Account.fromJson(%"hello")

block accountWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr Account.fromJson(%*[1, 2])

# --- Request ---

block requestWrongKindNil:
  assertErr Request.fromJson(nilNode)

block requestWrongKindJNull:
  assertErr Request.fromJson(newJNull())

block requestWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr Request.fromJson(newJBool(true))

block requestWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr Request.fromJson(%42)

block requestWrongKindJFloat:
  assertErr Request.fromJson(newJFloat(3.14))

block requestWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr Request.fromJson(%"hello")

block requestWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr Request.fromJson(%*[1, 2])

# --- Response ---

block responseWrongKindNil:
  assertErr Response.fromJson(nilNode)

block responseWrongKindJNull:
  assertErr Response.fromJson(newJNull())

block responseWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr Response.fromJson(newJBool(true))

block responseWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr Response.fromJson(%42)

block responseWrongKindJFloat:
  assertErr Response.fromJson(newJFloat(3.14))

block responseWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr Response.fromJson(%"hello")

block responseWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr Response.fromJson(%*[1, 2])

# --- ResultReference ---

block resultRefWrongKindNil:
  assertErr ResultReference.fromJson(nilNode)

block resultRefWrongKindJNull:
  assertErr ResultReference.fromJson(newJNull())

block resultRefWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr ResultReference.fromJson(newJBool(true))

block resultRefWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr ResultReference.fromJson(%42)

block resultRefWrongKindJFloat:
  assertErr ResultReference.fromJson(newJFloat(3.14))

block resultRefWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr ResultReference.fromJson(%"hello")

block resultRefWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr ResultReference.fromJson(%*[1, 2])

# --- Comparator ---

block comparatorWrongKindNil:
  assertErr Comparator.fromJson(nilNode)

block comparatorWrongKindJNull:
  assertErr Comparator.fromJson(newJNull())

block comparatorWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr Comparator.fromJson(newJBool(true))

block comparatorWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr Comparator.fromJson(%42)

block comparatorWrongKindJFloat:
  assertErr Comparator.fromJson(newJFloat(3.14))

block comparatorWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr Comparator.fromJson(%"hello")

block comparatorWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr Comparator.fromJson(%*[1, 2])

# --- PatchObject ---

block patchObjectWrongKindNil:
  assertErr PatchObject.fromJson(nilNode)

block patchObjectWrongKindJNull:
  assertErr PatchObject.fromJson(newJNull())

block patchObjectWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr PatchObject.fromJson(newJBool(true))

block patchObjectWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr PatchObject.fromJson(%42)

block patchObjectWrongKindJFloat:
  assertErr PatchObject.fromJson(newJFloat(3.14))

block patchObjectWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr PatchObject.fromJson(%"hello")

block patchObjectWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr PatchObject.fromJson(%*[1, 2])

# --- AddedItem ---

block addedItemWrongKindNil:
  assertErr AddedItem.fromJson(nilNode)

block addedItemWrongKindJNull:
  assertErr AddedItem.fromJson(newJNull())

block addedItemWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr AddedItem.fromJson(newJBool(true))

block addedItemWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr AddedItem.fromJson(%42)

block addedItemWrongKindJFloat:
  assertErr AddedItem.fromJson(newJFloat(3.14))

block addedItemWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr AddedItem.fromJson(%"hello")

block addedItemWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr AddedItem.fromJson(%*[1, 2])

# --- RequestError ---

block requestErrorWrongKindNil:
  assertErr RequestError.fromJson(nilNode)

block requestErrorWrongKindJNull:
  assertErr RequestError.fromJson(newJNull())

block requestErrorWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr RequestError.fromJson(newJBool(true))

block requestErrorWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr RequestError.fromJson(%42)

block requestErrorWrongKindJFloat:
  assertErr RequestError.fromJson(newJFloat(3.14))

block requestErrorWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr RequestError.fromJson(%"hello")

block requestErrorWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr RequestError.fromJson(%*[1, 2])

# --- MethodError ---

block methodErrorWrongKindNil:
  assertErr MethodError.fromJson(nilNode)

block methodErrorWrongKindJNull:
  assertErr MethodError.fromJson(newJNull())

block methodErrorWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr MethodError.fromJson(newJBool(true))

block methodErrorWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr MethodError.fromJson(%42)

block methodErrorWrongKindJFloat:
  assertErr MethodError.fromJson(newJFloat(3.14))

block methodErrorWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr MethodError.fromJson(%"hello")

block methodErrorWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr MethodError.fromJson(%*[1, 2])

# --- SetError ---

block setErrorWrongKindNil:
  assertErr SetError.fromJson(nilNode)

block setErrorWrongKindJNull:
  assertErr SetError.fromJson(newJNull())

block setErrorWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr SetError.fromJson(newJBool(true))

block setErrorWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr SetError.fromJson(%42)

block setErrorWrongKindJFloat:
  assertErr SetError.fromJson(newJFloat(3.14))

block setErrorWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr SetError.fromJson(%"hello")

block setErrorWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr SetError.fromJson(%*[1, 2])

# --- Filter[int] ---

block filterWrongKindNil:
  assertErr Filter[int].fromJson(nilNode, fromIntCondition)

block filterWrongKindJNull:
  assertErr Filter[int].fromJson(newJNull(), fromIntCondition)

block filterWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr Filter[int].fromJson(newJBool(true), fromIntCondition)

block filterWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr Filter[int].fromJson(%42, fromIntCondition)

block filterWrongKindJFloat:
  assertErr Filter[int].fromJson(newJFloat(3.14), fromIntCondition)

block filterWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr Filter[int].fromJson(%"hello", fromIntCondition)

block filterWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr Filter[int].fromJson(%*[1, 2], fromIntCondition)

# =============================================================================
# D. Array-backed type mismatch (Invocation expects JArray)
# =============================================================================

block invocationWrongKindNil:
  assertErr Invocation.fromJson(nilNode)

block invocationWrongKindJNull:
  assertErr Invocation.fromJson(newJNull())

block invocationWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr Invocation.fromJson(newJBool(true))

block invocationWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr Invocation.fromJson(%42)

block invocationWrongKindJFloat:
  assertErr Invocation.fromJson(newJFloat(3.14))

block invocationWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr Invocation.fromJson(%"hello")

block invocationWrongKindJObject:
  {.cast(noSideEffect).}:
    assertErr Invocation.fromJson(%*{"x": 1})

# =============================================================================
# E. Enum type mismatch (FilterOperator expects JString)
# =============================================================================

block filterOperatorWrongKindNil:
  assertErr FilterOperator.fromJson(nilNode)

block filterOperatorWrongKindJNull:
  assertErr FilterOperator.fromJson(newJNull())

block filterOperatorWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr FilterOperator.fromJson(newJBool(true))

block filterOperatorWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr FilterOperator.fromJson(%42)

block filterOperatorWrongKindJFloat:
  assertErr FilterOperator.fromJson(newJFloat(3.14))

block filterOperatorWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr FilterOperator.fromJson(%*[1, 2])

block filterOperatorWrongKindJObject:
  {.cast(noSideEffect).}:
    assertErr FilterOperator.fromJson(%*{"x": 1})

# =============================================================================
# F. ServerCapability type mismatch (core URI expects JObject for data)
# =============================================================================

block serverCapCoreWrongKindNil:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", nilNode)

block serverCapCoreWrongKindJNull:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", newJNull())

block serverCapCoreWrongKindJBool:
  {.cast(noSideEffect).}:
    assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", newJBool(true))

block serverCapCoreWrongKindJInt:
  {.cast(noSideEffect).}:
    assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", %42)

block serverCapCoreWrongKindJFloat:
  assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", newJFloat(3.14))

block serverCapCoreWrongKindJString:
  {.cast(noSideEffect).}:
    assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", %"hello")

block serverCapCoreWrongKindJArray:
  {.cast(noSideEffect).}:
    assertErr ServerCapability.fromJson("urn:ietf:params:jmap:core", %*[1, 2])

# Non-core capability URIs accept any kind for rawData (pass-through).

block serverCapMailAcceptsNil:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", nilNode)

block serverCapMailAcceptsJNull:
  assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", newJNull())

block serverCapMailAcceptsJBool:
  {.cast(noSideEffect).}:
    assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", newJBool(true))

block serverCapMailAcceptsJInt:
  {.cast(noSideEffect).}:
    assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", %42)

block serverCapMailAcceptsJString:
  {.cast(noSideEffect).}:
    assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", %"hello")

block serverCapMailAcceptsJArray:
  {.cast(noSideEffect).}:
    assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", %*[1, 2])

block serverCapMailAcceptsJObject:
  {.cast(noSideEffect).}:
    assertOk ServerCapability.fromJson("urn:ietf:params:jmap:mail", %*{"x": 1})

# =============================================================================
# G. Nested field wrong kinds (CoreCapabilities per-field replacement)
# =============================================================================

proc validCoreCapsJson(): JsonNode {.noSideEffect, raises: [].} =
  ## Construct a valid CoreCapabilities JSON object for per-field testing.
  {.cast(noSideEffect).}:
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

proc coreCapsWithField(
    field: string, value: JsonNode
): JsonNode {.noSideEffect, raises: [].} =
  ## Return a valid CoreCapabilities JSON with one field replaced.
  {.cast(noSideEffect).}:
    result = validCoreCapsJson()
    result[field] = value

block coreCapsFieldMaxSizeUploadWrongKind:
  {.cast(noSideEffect).}:
    assertErr CoreCapabilities.fromJson(coreCapsWithField("maxSizeUpload", %"bad"))

block coreCapsFieldMaxConcurrentUploadWrongKind:
  {.cast(noSideEffect).}:
    assertErr CoreCapabilities.fromJson(
      coreCapsWithField("maxConcurrentUpload", %"bad")
    )

block coreCapsFieldMaxSizeRequestWrongKind:
  {.cast(noSideEffect).}:
    assertErr CoreCapabilities.fromJson(coreCapsWithField("maxSizeRequest", %"bad"))

block coreCapsFieldMaxConcurrentRequestsWrongKind:
  {.cast(noSideEffect).}:
    assertErr CoreCapabilities.fromJson(
      coreCapsWithField("maxConcurrentRequests", %"bad")
    )

block coreCapsFieldMaxCallsInRequestWrongKind:
  {.cast(noSideEffect).}:
    assertErr CoreCapabilities.fromJson(coreCapsWithField("maxCallsInRequest", %"bad"))

block coreCapsFieldMaxObjectsInGetWrongKind:
  {.cast(noSideEffect).}:
    assertErr CoreCapabilities.fromJson(coreCapsWithField("maxObjectsInGet", %"bad"))

block coreCapsFieldMaxObjectsInSetWrongKind:
  {.cast(noSideEffect).}:
    assertErr CoreCapabilities.fromJson(coreCapsWithField("maxObjectsInSet", %"bad"))

block coreCapsFieldCollationAlgorithmsWrongKind:
  {.cast(noSideEffect).}:
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
