# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Entity type framework registration tests. Verifies that
## ``registerJmapEntity`` and ``registerQueryableEntity`` templates detect
## missing overloads at compile time with domain-specific error messages.

import jmap_client/validation
import jmap_client/entity

import ../massertions

# ---------------------------------------------------------------------------
# Mock entity types (local — compile-time verification only)
# ---------------------------------------------------------------------------

{.push ruleOff: "hasDoc".}
{.push ruleOff: "objects".}
{.push ruleOff: "params".}

type MockFoo = object

func methodNamespace*(T: typedesc[MockFoo]): string =
  "MockFoo"

func capabilityUri*(T: typedesc[MockFoo]): string =
  "urn:test:mockfoo"

registerJmapEntity(MockFoo)

type MockFilterCondition = object

type MockQueryable = object

func methodNamespace*(T: typedesc[MockQueryable]): string =
  "MockQueryable"

func capabilityUri*(T: typedesc[MockQueryable]): string =
  "urn:test:mockqueryable"

registerJmapEntity(MockQueryable)

template filterType*(T: typedesc[MockQueryable]): typedesc =
  MockFilterCondition

registerQueryableEntity(MockQueryable)

# Types for negative tests (deliberately missing overloads)

type NoBoth = object

type NoCapUri = object

func methodNamespace*(T: typedesc[NoCapUri]): string =
  "NoCapUri"

type NoMethodNs = object

func capabilityUri*(T: typedesc[NoMethodNs]): string =
  "urn:test:nomethodns"

{.pop.} # ruleOff: "params"
{.pop.} # ruleOff: "objects"
{.pop.} # ruleOff: "hasDoc"

# ---------------------------------------------------------------------------
# A. Positive registration tests
# ---------------------------------------------------------------------------

block registerBasicEntity:
  ## MockFoo registered at module scope with both required overloads.
  ## If this module compiles, registration succeeded.
  doAssert true

block registerQueryableEntity:
  ## MockQueryable registered with filterType template.
  ## Both registerJmapEntity and registerQueryableEntity succeeded.
  doAssert true

block overloadValuesCorrect:
  ## Overloads return the expected values.
  doAssert methodNamespace(MockFoo) == "MockFoo"
  doAssert capabilityUri(MockFoo) == "urn:test:mockfoo"
  doAssert methodNamespace(MockQueryable) == "MockQueryable"
  doAssert capabilityUri(MockQueryable) == "urn:test:mockqueryable"

# ---------------------------------------------------------------------------
# B. Negative registration tests (compile-time error detection)
# ---------------------------------------------------------------------------

block missingBothOverloads:
  ## Type with no overloads — registerJmapEntity must fail.
  assertNotCompiles(registerJmapEntity(NoBoth))

block missingCapabilityUri:
  ## Type with only methodNamespace — registerJmapEntity must fail.
  assertNotCompiles(registerJmapEntity(NoCapUri))

block missingMethodNamespace:
  ## Type with only capabilityUri — registerJmapEntity must fail.
  assertNotCompiles(registerJmapEntity(NoMethodNs))

block missingFilterType:
  ## MockFoo has no filterType — registerQueryableEntity must fail.
  assertNotCompiles(registerQueryableEntity(MockFoo))
