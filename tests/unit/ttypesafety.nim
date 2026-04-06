# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-time type safety verification via doAssert not compiles(...).

from std/json import JsonNode
import std/sets

import jmap_client/types

# --- Distinct type isolation ---

block distinctTypeIsolation:
  let id = parseId("abc").get()
  let aid = parseAccountId("abc").get()
  let state = parseJmapState("abc").get()
  doAssert not compiles(id == aid)
  doAssert not compiles(id == state)
  doAssert not compiles(aid == state)

block distinctTypeNoConcatenation:
  let a = parseId("abc").get()
  let b = parseId("def").get()
  doAssert not compiles(a & b)

block unsignedIntNoArithmetic:
  let a = parseUnsignedInt(1).get()
  let b = parseUnsignedInt(2).get()
  doAssert not compiles(a + b)
  doAssert not compiles(a - b)
  doAssert not compiles(a * b)

block jmapIntNoArithmetic:
  let a = parseJmapInt(1).get()
  let b = parseJmapInt(2).get()
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
        status: Opt.none(int),
        title: Opt.none(string),
        detail: Opt.none(string),
        limit: Opt.none(string),
        extras: Opt.none(JsonNode),
      ),
    )
  )

block referencableWrongVariantConstruction:
  doAssert not compiles(
    Referencable[int](
      kind: rkDirect,
      reference: ResultReference(
        resultOf: parseMethodCallId("c1").get(), name: "Foo/get", path: "/ids"
      ),
    )
  )

block filterWrongVariantConstruction:
  doAssert not compiles(
    Filter[int](kind: fkCondition, operator: foAnd, conditions: @[])
  )

# --- Hash divergence (non-degenerate hash smoke test) ---

block hashDivergenceId:
  doAssert hash(parseId("abc").get()) != hash(parseId("xyz").get())

block hashDivergenceAccountId:
  doAssert hash(parseAccountId("abc").get()) != hash(parseAccountId("xyz").get())

block hashDivergenceJmapState:
  doAssert hash(parseJmapState("abc").get()) != hash(parseJmapState("xyz").get())

block hashDivergenceUriTemplate:
  doAssert hash(parseUriTemplate("https://a.com").get()) !=
    hash(parseUriTemplate("https://b.com").get())

block hashDivergencePropertyName:
  doAssert hash(parsePropertyName("name").get()) !=
    hash(parsePropertyName("other").get())

# =============================================================================
# Additional distinct type isolation
# =============================================================================

block methodCallIdVsCreationIdIsolation:
  doAssert not compiles(parseMethodCallId("a").get() == parseCreationId("a").get())

block jmapStateVsMethodCallIdIsolation:
  doAssert not compiles(parseJmapState("a").get() == parseMethodCallId("a").get())

block jmapStateVsPropertyNameIsolation:
  doAssert not compiles(parseJmapState("a").get() == parsePropertyName("a").get())

block uriTemplateVsPropertyNameIsolation:
  doAssert not compiles(parseUriTemplate("a").get() == parsePropertyName("a").get())

block creationIdVsJmapStateIsolation:
  doAssert not compiles(parseCreationId("a").get() == parseJmapState("a").get())

block dateVsUtcDateIsolation:
  doAssert not compiles(
    parseDate("2024-01-01T12:00:00Z").get() == parseUtcDate("2024-01-01T12:00:00Z").get()
  )

block uriTemplateVsAccountIdIsolation:
  doAssert not compiles(parseUriTemplate("a").get() == parseAccountId("a").get())

block creationIdVsPropertyNameIsolation:
  doAssert not compiles(parseCreationId("a").get() == parsePropertyName("a").get())

# =============================================================================
# Operator restriction verification
# =============================================================================

block unsignedIntNoNegation:
  ## UnsignedInt does not borrow unary negation (only JmapInt does).
  doAssert not compiles(-parseUnsignedInt(0).get())

block idNoConcatenation:
  ## No string concatenation on Id.
  doAssert not compiles(parseId("a").get() & parseId("b").get())

block accountIdNoConcatenation:
  doAssert not compiles(parseAccountId("a").get() & parseAccountId("b").get())

block jmapStateNoLen:
  ## JmapState deliberately does not borrow len (semantically meaningless).
  doAssert not compiles(parseJmapState("abc").get().len)

block methodCallIdNoLen:
  doAssert not compiles(parseMethodCallId("abc").get().len)

block creationIdNoLen:
  doAssert not compiles(parseCreationId("abc").get().len)

# =============================================================================
# Case object construction completeness
# =============================================================================

block transportErrorMissingHttpStatus:
  ## SetError(setInvalidProperties) must not accept existingId (wrong variant).
  let testId = parseId("abc").get()
  doAssert not compiles(
    SetError(
      errorType: setInvalidProperties,
      rawType: "invalidProperties",
      description: Opt.none(string),
      extras: Opt.none(JsonNode),
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
        maxSizeUpload: parseUnsignedInt(1).get(),
        maxConcurrentUpload: parseUnsignedInt(1).get(),
        maxSizeRequest: parseUnsignedInt(1).get(),
        maxConcurrentRequests: parseUnsignedInt(1).get(),
        maxCallsInRequest: parseUnsignedInt(1).get(),
        maxObjectsInGet: parseUnsignedInt(1).get(),
        maxObjectsInSet: parseUnsignedInt(1).get(),
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
      description: Opt.none(string),
      extras: Opt.none(JsonNode),
      properties: @["name"],
    )
  )

block setErrorExistingIdOnNonAlreadyExists:
  ## Constructing a setForbidden SetError with the setAlreadyExists-branch
  ## existingId field is rejected by {.strictCaseObjects.}.
  let testId = parseId("abc").get()
  doAssert not compiles(
    SetError(
      errorType: setForbidden,
      rawType: "forbidden",
      description: Opt.none(string),
      extras: Opt.none(JsonNode),
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
        resultOf: parseMethodCallId("c1").get(), name: "Foo/get", path: "/ids"
      ),
    )
  )

block referencableValueOnReference:
  ## Constructing an rkReference Referencable with the rkDirect-branch
  ## value field is rejected by {.strictCaseObjects.}.
  doAssert not compiles(Referencable[int](kind: rkReference, value: 42))
