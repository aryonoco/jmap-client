# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-time type safety verification via doAssert not compiles(...).

from std/json import JsonNode
import std/sets

import jmap_client
import ../mtestblock

# --- Distinct type isolation ---

testCase distinctTypeIsolation:
  doAssert not compiles(parseIdFromServer("abc").get() == parseAccountId("abc").get())
  doAssert not compiles(parseIdFromServer("abc").get() == parseJmapState("abc").get())
  doAssert not compiles(parseAccountId("abc").get() == parseJmapState("abc").get())

testCase distinctTypeNoConcatenation:
  doAssert not compiles(parseIdFromServer("abc").get() & parseIdFromServer("def").get())

testCase unsignedIntNoArithmetic:
  doAssert not compiles(parseUnsignedInt(1).get() + parseUnsignedInt(2).get())
  doAssert not compiles(parseUnsignedInt(1).get() - parseUnsignedInt(2).get())
  doAssert not compiles(parseUnsignedInt(1).get() * parseUnsignedInt(2).get())

testCase jmapIntNoArithmetic:
  doAssert not compiles(parseJmapInt(1).get() + parseJmapInt(2).get())
  doAssert not compiles(parseJmapInt(1).get() - parseJmapInt(2).get())
  doAssert not compiles(parseJmapInt(1).get() * parseJmapInt(2).get())
  doAssert compiles(-parseJmapInt(1).get())

# --- Case object construction type safety ---

testCase transportErrorWrongVariantConstruction:
  doAssert not compiles(TransportError(kind: tekNetwork, httpStatus: 404, msg: "fail"))

testCase clientErrorWrongVariantConstruction:
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

testCase referencableWrongVariantConstruction:
  doAssert not compiles(
    Referencable[int](
      kind: rkDirect,
      reference: initResultReference(
        resultOf = parseMethodCallId("c1").get(), name = "Foo/get", path = "/ids"
      ),
    )
  )

testCase filterWrongVariantConstruction:
  doAssert not compiles(
    Filter[int](kind: fkCondition, operator: foAnd, conditions: @[])
  )

# --- Hash divergence (non-degenerate hash smoke test) ---

testCase hashDivergenceId:
  doAssert hash(parseIdFromServer("abc").get()) != hash(parseIdFromServer("xyz").get())

testCase hashDivergenceAccountId:
  doAssert hash(parseAccountId("abc").get()) != hash(parseAccountId("xyz").get())

testCase hashDivergenceJmapState:
  doAssert hash(parseJmapState("abc").get()) != hash(parseJmapState("xyz").get())

testCase hashDivergenceUriTemplate:
  doAssert hash(parseUriTemplate("https://a.com").get()) !=
    hash(parseUriTemplate("https://b.com").get())

testCase hashDivergencePropertyName:
  doAssert hash(parsePropertyName("name").get()) !=
    hash(parsePropertyName("other").get())

# =============================================================================
# Additional distinct type isolation
# =============================================================================

testCase methodCallIdVsCreationIdIsolation:
  doAssert not compiles(parseMethodCallId("a").get() == parseCreationId("a").get())

testCase jmapStateVsMethodCallIdIsolation:
  doAssert not compiles(parseJmapState("a").get() == parseMethodCallId("a").get())

testCase jmapStateVsPropertyNameIsolation:
  doAssert not compiles(parseJmapState("a").get() == parsePropertyName("a").get())

testCase uriTemplateVsPropertyNameIsolation:
  doAssert not compiles(parseUriTemplate("a").get() == parsePropertyName("a").get())

testCase creationIdVsJmapStateIsolation:
  doAssert not compiles(parseCreationId("a").get() == parseJmapState("a").get())

testCase dateVsUtcDateIsolation:
  doAssert not compiles(
    parseDate("2024-01-01T12:00:00Z").get() == parseUtcDate("2024-01-01T12:00:00Z").get()
  )

testCase uriTemplateVsAccountIdIsolation:
  doAssert not compiles(parseUriTemplate("a").get() == parseAccountId("a").get())

testCase creationIdVsPropertyNameIsolation:
  doAssert not compiles(parseCreationId("a").get() == parsePropertyName("a").get())

# =============================================================================
# Operator restriction verification
# =============================================================================

testCase unsignedIntNoNegation:
  ## UnsignedInt does not borrow unary negation (only JmapInt does).
  doAssert not compiles(-parseUnsignedInt(0).get())

testCase idNoConcatenation:
  ## No string concatenation on Id.
  doAssert not compiles(parseIdFromServer("a").get() & parseIdFromServer("b").get())

testCase accountIdNoConcatenation:
  doAssert not compiles(parseAccountId("a").get() & parseAccountId("b").get())

testCase jmapStateNoLen:
  ## JmapState deliberately does not borrow len (semantically meaningless).
  doAssert not compiles(parseJmapState("abc").get().len)

testCase methodCallIdNoLen:
  doAssert not compiles(parseMethodCallId("abc").get().len)

testCase creationIdNoLen:
  doAssert not compiles(parseCreationId("abc").get().len)

# =============================================================================
# Case object construction completeness
# =============================================================================

testCase transportErrorMissingHttpStatus:
  ## SetError(setInvalidProperties) must not accept existingId (wrong variant).
  doAssert not compiles(
    SetError(
      errorType: setInvalidProperties,
      rawType: "invalidProperties",
      description: Opt.none(string),
      extras: Opt.none(JsonNode),
      existingId: parseIdFromServer("abc").get(),
    )
  )

# =============================================================================
# Case object wrong-variant construction rejection
# =============================================================================

testCase serverCapabilityWrongVariantCoreOnMail:
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
        collationAlgorithms: initHashSet[CollationAlgorithm](),
      ),
    )
  )

testCase setErrorPropertiesOnNonInvalidProperties:
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

testCase setErrorExistingIdOnNonAlreadyExists:
  ## Constructing a setForbidden SetError with the setAlreadyExists-branch
  ## existingId field is rejected by {.strictCaseObjects.}.
  doAssert not compiles(
    SetError(
      errorType: setForbidden,
      rawType: "forbidden",
      description: Opt.none(string),
      extras: Opt.none(JsonNode),
      existingId: parseIdFromServer("abc").get(),
    )
  )

testCase referencableReferenceOnDirect:
  ## Constructing an rkDirect Referencable with the rkReference-branch
  ## reference field is rejected by {.strictCaseObjects.}.
  doAssert not compiles(
    Referencable[int](
      kind: rkDirect,
      reference: initResultReference(
        resultOf = parseMethodCallId("c1").get(), name = "Foo/get", path = "/ids"
      ),
    )
  )

testCase referencableValueOnReference:
  ## Constructing an rkReference Referencable with the rkDirect-branch
  ## value field is rejected by {.strictCaseObjects.}.
  doAssert not compiles(Referencable[int](kind: rkReference, value: 42))
