# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Entity type framework registration tests. Verifies that
## ``registerJmapEntity`` and ``registerQueryableEntity`` templates detect
## missing overloads at compile time with domain-specific error messages.

import std/json

import jmap_client/internal/types/capabilities
import jmap_client/internal/types/methods_enum
import jmap_client/internal/types/validation
import jmap_client/internal/protocol/entity

import ../massertions
import ../mtestblock

# ---------------------------------------------------------------------------
# Mock entity types (local — compile-time verification only)
# ---------------------------------------------------------------------------

{.push ruleOff: "hasDoc".}
{.push ruleOff: "objects".}
{.push ruleOff: "params".}

type MockFoo = object

func methodEntity*(T: typedesc[MockFoo]): MethodEntity =
  meTest

func capabilityUri*(T: typedesc[MockFoo]): CapabilityUri =
  parseCapabilityUri("urn:test:mockfoo").get()

registerJmapEntity(MockFoo)

type MockFilterCondition = object

type MockQueryable = object

func methodEntity*(T: typedesc[MockQueryable]): MethodEntity =
  meTest

func capabilityUri*(T: typedesc[MockQueryable]): CapabilityUri =
  parseCapabilityUri("urn:test:mockqueryable").get()

registerJmapEntity(MockQueryable)

template filterType*(T: typedesc[MockQueryable]): typedesc =
  MockFilterCondition

func toJson*(c: MockFilterCondition): JsonNode =
  newJObject()

registerQueryableEntity(MockQueryable)

# Types for negative tests (deliberately missing overloads)

type NoBoth = object

type NoCapUri = object

func methodEntity*(T: typedesc[NoCapUri]): MethodEntity =
  meTest

type NoMethodNs = object

func capabilityUri*(T: typedesc[NoMethodNs]): CapabilityUri =
  parseCapabilityUri("urn:test:nomethodns").get()

type NoFilterToJson = object

func methodEntity*(T: typedesc[NoFilterToJson]): MethodEntity =
  meTest

func capabilityUri*(T: typedesc[NoFilterToJson]): CapabilityUri =
  parseCapabilityUri("urn:test:nofj").get()

type NoFilterToJsonFilter = object

template filterType*(T: typedesc[NoFilterToJson]): typedesc =
  NoFilterToJsonFilter

registerJmapEntity(NoFilterToJson)
## Has filterType but no toJson on the filter — registerQueryableEntity must fail.

{.pop.} # ruleOff: "params"
{.pop.} # ruleOff: "objects"
{.pop.} # ruleOff: "hasDoc"

# ---------------------------------------------------------------------------
# A. Positive registration tests
# ---------------------------------------------------------------------------

testCase registerBasicEntity:
  ## MockFoo registered at module scope with both required overloads.
  ## If this module compiles, registration succeeded.
  doAssert true

testCase registerQueryableEntity:
  ## MockQueryable registered with filterType template.
  ## Both registerJmapEntity and registerQueryableEntity succeeded.
  doAssert true

testCase overloadValuesCorrect:
  ## Overloads return the expected values. Typed dispatch: methodEntity
  ## resolves per typedesc to the test sentinel; capabilityUri yields the
  ## distinct URI registered for each mock.
  doAssert methodEntity(MockFoo) == meTest
  doAssert $capabilityUri(MockFoo) == "urn:test:mockfoo"
  doAssert methodEntity(MockQueryable) == meTest
  doAssert $capabilityUri(MockQueryable) == "urn:test:mockqueryable"

# ---------------------------------------------------------------------------
# B. Negative registration tests (compile-time error detection)
# ---------------------------------------------------------------------------

testCase missingBothOverloads:
  ## Type with no overloads — registerJmapEntity must fail.
  assertNotCompiles(registerJmapEntity(NoBoth))

testCase missingCapabilityUri:
  ## Type with only methodEntity — registerJmapEntity must fail.
  assertNotCompiles(registerJmapEntity(NoCapUri))

testCase missingMethodEntity:
  ## Type with only capabilityUri — registerJmapEntity must fail.
  assertNotCompiles(registerJmapEntity(NoMethodNs))

testCase missingFilterType:
  ## MockFoo has no filterType — registerQueryableEntity must fail.
  assertNotCompiles(registerQueryableEntity(MockFoo))

testCase missingFilterToJson:
  ## Type with filterType but no ``toJson`` on the filter must fail.
  ## ``NoFilterToJson`` (defined at module level) has ``filterType`` but
  ## deliberately omits ``toJson(NoFilterToJsonFilter)``.
  assertNotCompiles(registerQueryableEntity(NoFilterToJson))
