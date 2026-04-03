# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-time type safety verification via doAssert not compiles(...).

from std/json import JsonNode
import std/options
import std/sets

import jmap_client/types

# --- Distinct type isolation ---

block distinctTypeIsolation:
  let id = parseId("abc")
  let aid = parseAccountId("abc")
  let state = parseJmapState("abc")
  doAssert not compiles(id == aid)
  doAssert not compiles(id == state)
  doAssert not compiles(aid == state)

block distinctTypeNoConcatenation:
  let a = parseId("abc")
  let b = parseId("def")
  doAssert not compiles(a & b)

block unsignedIntNoArithmetic:
  let a = parseUnsignedInt(1)
  let b = parseUnsignedInt(2)
  doAssert not compiles(a + b)
  doAssert not compiles(a - b)
  doAssert not compiles(a * b)

block jmapIntNoArithmetic:
  let a = parseJmapInt(1)
  let b = parseJmapInt(2)
  doAssert not compiles(a + b)
  doAssert not compiles(a - b)
  doAssert not compiles(a * b)
  doAssert compiles(-a)

# --- Case object construction type safety ---

block transportErrorWrongVariantConstruction:
  doAssert not compiles(TransportError(kind: tekNetwork, httpStatus: 404, msg: "fail"))

block clientErrorWrongVariantConstruction:
  doAssert not compiles(
    ClientError(
      kind: cekTransport,
      request: RequestError(
        errorType: retUnknown,
        rawType: "x",
        status: none(int),
        title: none(string),
        detail: none(string),
        limit: none(string),
        extras: none(JsonNode),
      ),
    )
  )

block referencableWrongVariantConstruction:
  doAssert not compiles(
    Referencable[int](
      kind: rkDirect,
      reference: ResultReference(
        resultOf: parseMethodCallId("c1"), name: "Foo/get", path: "/ids"
      ),
    )
  )

block filterWrongVariantConstruction:
  doAssert not compiles(
    Filter[int](kind: fkCondition, operator: foAnd, conditions: @[])
  )

# --- Hash divergence (non-degenerate hash smoke test) ---

block hashDivergenceId:
  doAssert hash(parseId("abc")) != hash(parseId("xyz"))

block hashDivergenceAccountId:
  doAssert hash(parseAccountId("abc")) != hash(parseAccountId("xyz"))

block hashDivergenceJmapState:
  doAssert hash(parseJmapState("abc")) != hash(parseJmapState("xyz"))

block hashDivergenceUriTemplate:
  doAssert hash(parseUriTemplate("https://a.com")) !=
    hash(parseUriTemplate("https://b.com"))

block hashDivergencePropertyName:
  doAssert hash(parsePropertyName("name")) != hash(parsePropertyName("other"))

# =============================================================================
# Additional distinct type isolation
# =============================================================================

block methodCallIdVsCreationIdIsolation:
  doAssert not compiles(parseMethodCallId("a") == parseCreationId("a"))

block jmapStateVsMethodCallIdIsolation:
  doAssert not compiles(parseJmapState("a") == parseMethodCallId("a"))

block jmapStateVsPropertyNameIsolation:
  doAssert not compiles(parseJmapState("a") == parsePropertyName("a"))

block uriTemplateVsPropertyNameIsolation:
  doAssert not compiles(parseUriTemplate("a") == parsePropertyName("a"))

block creationIdVsJmapStateIsolation:
  doAssert not compiles(parseCreationId("a") == parseJmapState("a"))

block dateVsUtcDateIsolation:
  doAssert not compiles(
    parseDate("2024-01-01T12:00:00Z") == parseUtcDate("2024-01-01T12:00:00Z")
  )

block uriTemplateVsAccountIdIsolation:
  doAssert not compiles(parseUriTemplate("a") == parseAccountId("a"))

block creationIdVsPropertyNameIsolation:
  doAssert not compiles(parseCreationId("a") == parsePropertyName("a"))

# =============================================================================
# Operator restriction verification
# =============================================================================

block unsignedIntNoNegation:
  ## UnsignedInt does not borrow unary negation (only JmapInt does).
  doAssert not compiles(-parseUnsignedInt(0))

block idNoConcatenation:
  ## No string concatenation on Id.
  doAssert not compiles(parseId("a") & parseId("b"))

block accountIdNoConcatenation:
  doAssert not compiles(parseAccountId("a") & parseAccountId("b"))

block jmapStateNoLen:
  ## JmapState deliberately does not borrow len (semantically meaningless).
  doAssert not compiles(parseJmapState("abc").len)

block methodCallIdNoLen:
  doAssert not compiles(parseMethodCallId("abc").len)

block creationIdNoLen:
  doAssert not compiles(parseCreationId("abc").len)

# =============================================================================
# Case object construction completeness
# =============================================================================

block transportErrorMissingHttpStatus:
  ## SetError(setInvalidProperties) must not accept existingId (wrong variant).
  let testId = parseId("abc")
  doAssert not compiles(
    SetError(
      errorType: setInvalidProperties,
      rawType: "invalidProperties",
      description: none(string),
      extras: none(JsonNode),
      existingId: testId,
    )
  )

# =============================================================================
# Case object wrong-variant construction rejection
# =============================================================================

block serverCapabilityWrongVariantCoreOnMail:
  ## Constructing a ckMail ServerCapability with the ckCore-branch core field
  ## is rejected by {.strictCaseObjects.}.
  doAssert not compiles(
    ServerCapability(
      kind: ckMail,
      rawUri: "urn:ietf:params:jmap:mail",
      core: CoreCapabilities(
        maxSizeUpload: parseUnsignedInt(1),
        maxConcurrentUpload: parseUnsignedInt(1),
        maxSizeRequest: parseUnsignedInt(1),
        maxConcurrentRequests: parseUnsignedInt(1),
        maxCallsInRequest: parseUnsignedInt(1),
        maxObjectsInGet: parseUnsignedInt(1),
        maxObjectsInSet: parseUnsignedInt(1),
        collationAlgorithms: initHashSet[string](),
      ),
    )
  )

block setErrorPropertiesOnNonInvalidProperties:
  ## Constructing a setForbidden SetError with the setInvalidProperties-branch
  ## properties field is rejected by {.strictCaseObjects.}.
  doAssert not compiles(
    SetError(
      errorType: setForbidden,
      rawType: "forbidden",
      description: none(string),
      extras: none(JsonNode),
      properties: @["name"],
    )
  )

block setErrorExistingIdOnNonAlreadyExists:
  ## Constructing a setForbidden SetError with the setAlreadyExists-branch
  ## existingId field is rejected by {.strictCaseObjects.}.
  let testId = parseId("abc")
  doAssert not compiles(
    SetError(
      errorType: setForbidden,
      rawType: "forbidden",
      description: none(string),
      extras: none(JsonNode),
      existingId: testId,
    )
  )

block referencableReferenceOnDirect:
  ## Constructing an rkDirect Referencable with the rkReference-branch
  ## reference field is rejected by {.strictCaseObjects.}.
  doAssert not compiles(
    Referencable[int](
      kind: rkDirect,
      reference: ResultReference(
        resultOf: parseMethodCallId("c1"), name: "Foo/get", path: "/ids"
      ),
    )
  )

block referencableValueOnReference:
  ## Constructing an rkReference Referencable with the rkDirect-branch
  ## value field is rejected by {.strictCaseObjects.}.
  doAssert not compiles(Referencable[int](kind: rkReference, value: 42))
