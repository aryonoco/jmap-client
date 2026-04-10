# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## RequestBuilder tests: construction, add* methods, build(), capability
## deduplication, call ID generation, read-only accessors, and result
## reference integration.

import std/json
import std/tables

import jmap_client/types
import jmap_client/serialisation
import jmap_client/serde_envelope
import jmap_client/entity
import jmap_client/methods
import jmap_client/dispatch
import jmap_client/builder

import ../massertions
import ../mfixtures

# ---------------------------------------------------------------------------
# Mock entity types (local -- compile-time verification only)
# ---------------------------------------------------------------------------

{.push ruleOff: "hasDoc".}
{.push ruleOff: "objects".}
{.push ruleOff: "params".}

type MockFoo = object

proc methodNamespace*(T: typedesc[MockFoo]): string =
  "MockFoo"

proc capabilityUri*(T: typedesc[MockFoo]): string =
  "urn:test:mockfoo"

registerJmapEntity(MockFoo)

type MockFilter = object

type MockQueryable = object

proc methodNamespace*(T: typedesc[MockQueryable]): string =
  "MockQueryable"

proc capabilityUri*(T: typedesc[MockQueryable]): string =
  "urn:test:mockqueryable"

template filterType*(T: typedesc[MockQueryable]): typedesc =
  MockFilter

proc filterConditionToJson(c: MockFilter): JsonNode {.noSideEffect, raises: [].} =
  %*{"mock": true}

registerJmapEntity(MockQueryable)
registerQueryableEntity(MockQueryable)

{.pop.} # params
{.pop.} # objects
{.pop.} # hasDoc

# ===========================================================================
# A. Constructor & build
# ===========================================================================

block initBuilderEmpty:
  ## Fresh builder has no invocations, no capabilities, and builds an
  ## empty Request.
  let b = initRequestBuilder()
  doAssert b.isEmpty
  assertEq b.methodCallCount, 0
  assertLen b.capabilities, 0
  let req = b.build()
  assertLen req.`using`, 0
  assertLen req.methodCalls, 0
  doAssert req.createdIds.isNone

block buildDoesNotMutate:
  ## build() is a pure snapshot. Branching from the same builder state
  ## produces independent snapshots.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEcho(%*{"ping": 1})
  let req1 = b1.build()
  let (b2, _) = b1.addEcho(%*{"ping": 2})
  let req2 = b2.build()
  assertLen req1.methodCalls, 1
  assertLen req2.methodCalls, 2

# ===========================================================================
# B. Call ID generation
# ===========================================================================

block callIdAutoIncrement:
  ## Successive add* calls produce auto-incrementing call IDs "c0", "c1", "c2".
  let b0 = initRequestBuilder()
  let (b1, h0) = b0.addEcho(%*{})
  let (b2, h1) = b1.addEcho(%*{})
  let (_, h2) = b2.addEcho(%*{})
  assertEq $h0, "c0"
  assertEq $h1, "c1"
  assertEq $h2, "c2"

block callIdResetPerBuilder:
  ## Each builder instance starts its counter at zero independently.
  let ba0 = initRequestBuilder()
  let bb0 = initRequestBuilder()
  let (_, h1) = ba0.addEcho(%*{})
  let (_, h2) = bb0.addEcho(%*{})
  assertEq $h1, "c0"
  assertEq $h2, "c0"

# ===========================================================================
# C. Capability deduplication
# ===========================================================================

block capabilityDedup:
  ## Two addGet calls for the same entity register the capability only once.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[MockFoo](b0, makeAccountId())
  let (b2, _) = addGet[MockFoo](b1, makeAccountId())
  let caps = b2.capabilities
  assertLen caps, 1
  assertEq caps[0], "urn:test:mockfoo"

block multipleCapabilities:
  ## Calls for different entities accumulate distinct capability URIs.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[MockFoo](b0, makeAccountId())
  let (b2, _) = addGet[MockQueryable](b1, makeAccountId())
  let caps = b2.capabilities
  assertLen caps, 2
  doAssert "urn:test:mockfoo" in caps
  doAssert "urn:test:mockqueryable" in caps

# ===========================================================================
# D. Read-only accessors
# ===========================================================================

block accessorsAfterOperations:
  ## After two addEcho calls the accessors reflect the accumulated state.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEcho(%*{"a": 1})
  let (b2, _) = b1.addEcho(%*{"b": 2})
  assertEq b2.methodCallCount, 2
  doAssert not b2.isEmpty
  let caps = b2.capabilities
  assertLen caps, 1
  assertEq caps[0], "urn:ietf:params:jmap:core"

# ===========================================================================
# E. addEcho
# ===========================================================================

block addEchoHappyPath:
  ## addEcho produces an invocation named "Core/echo" with the core
  ## capability URI.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEcho(%*{"hello": "world"})
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "Core/echo"
  doAssert "urn:ietf:params:jmap:core" in req.`using`

block addEchoArgsPreserved:
  ## The arguments JSON passed to addEcho is preserved unchanged in the
  ## built Request invocation.
  let b0 = initRequestBuilder()
  let args = %*{"key": "value", "num": 42}
  let (b1, _) = b0.addEcho(args)
  let req = b1.build()
  let inv = req.methodCalls[0]
  assertEq inv.arguments{"key"}.getStr(""), "value"
  assertEq inv.arguments{"num"}.getBiggestInt(0), 42

# ===========================================================================
# F. addGet
# ===========================================================================

block addGetMinimal:
  ## addGet with only accountId omits ids and properties from arguments.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[MockFoo](b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "MockFoo/get"
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  doAssert inv.arguments{"ids"}.isNil
  doAssert inv.arguments{"properties"}.isNil

block addGetWithDirectIds:
  ## addGet with direct ids emits an "ids" array in arguments.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[MockFoo](
    b0, makeAccountId("a1"), ids = Opt.some(direct(@[makeId("x1"), makeId("x2")]))
  )
  let req = b1.build()
  let inv = req.methodCalls[0]
  doAssert inv.arguments{"ids"}.kind == JArray
  assertLen inv.arguments{"ids"}.getElems(@[]), 2
  doAssert inv.arguments{"#ids"}.isNil

block addGetWithReferenceIds:
  ## addGet with referenced ids emits a "#ids" key with a ResultReference
  ## object instead of a plain "ids" array.
  let b0 = initRequestBuilder()
  let rr =
    makeResultReference(mcid = makeMcid("c0"), name = "MockFoo/query", path = "/ids")
  let (b1, _) =
    addGet[MockFoo](b0, makeAccountId("a1"), ids = Opt.some(referenceTo[seq[Id]](rr)))
  let req = b1.build()
  let inv = req.methodCalls[0]
  doAssert inv.arguments{"ids"}.isNil
  doAssert inv.arguments{"#ids"}.kind == JObject
  assertEq inv.arguments{"#ids"}{"resultOf"}.getStr(""), "c0"

block addGetWithProperties:
  ## addGet with properties emits a "properties" array in arguments.
  let b0 = initRequestBuilder()
  let (b1, _) =
    addGet[MockFoo](b0, makeAccountId("a1"), properties = Opt.some(@["name", "size"]))
  let req = b1.build()
  let inv = req.methodCalls[0]
  doAssert inv.arguments{"properties"}.kind == JArray
  assertLen inv.arguments{"properties"}.getElems(@[]), 2

# ===========================================================================
# G. addChanges
# ===========================================================================

block addChangesMinimal:
  ## addChanges with only required fields produces "MockFoo/changes".
  let b0 = initRequestBuilder()
  let (b1, _) = addChanges[MockFoo](b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "MockFoo/changes"
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  assertEq inv.arguments{"sinceState"}.getStr(""), "s0"
  doAssert inv.arguments{"maxChanges"}.isNil

block addChangesWithMaxChanges:
  ## addChanges with maxChanges emits the value in arguments.
  let b0 = initRequestBuilder()
  let (b1, _) = addChanges[MockFoo](
    b0, makeAccountId("a1"), makeState("s0"), maxChanges = Opt.some(makeMaxChanges(50))
  )
  let req = b1.build()
  let inv = req.methodCalls[0]
  assertEq inv.arguments{"maxChanges"}.getBiggestInt(0), 50

# ===========================================================================
# H. addSet
# ===========================================================================

block addSetMinimal:
  ## addSet with only accountId produces "MockFoo/set" with no optional fields.
  let b0 = initRequestBuilder()
  let (b1, _) = addSet[MockFoo](b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "MockFoo/set"
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  doAssert inv.arguments{"ifInState"}.isNil
  doAssert inv.arguments{"create"}.isNil
  doAssert inv.arguments{"update"}.isNil
  doAssert inv.arguments{"destroy"}.isNil

block addSetWithAllFields:
  ## addSet with create, update, and destroy all emitted in arguments.
  var createTbl = initTable[CreationId, JsonNode]()
  createTbl[makeCreationId("k1")] = %*{"name": "New"}
  var updateTbl = initTable[Id, PatchObject]()
  updateTbl[makeId("id1")] = emptyPatch()
  let b0 = initRequestBuilder()
  let (b1, _) = addSet[MockFoo](
    b0,
    makeAccountId("a1"),
    ifInState = Opt.some(makeState("s0")),
    create = Opt.some(createTbl),
    update = Opt.some(updateTbl),
    destroy = Opt.some(direct(@[makeId("d1")])),
  )
  let req = b1.build()
  let inv = req.methodCalls[0]
  doAssert inv.arguments{"ifInState"}.getStr("") == "s0"
  doAssert inv.arguments{"create"}.kind == JObject
  doAssert inv.arguments{"update"}.kind == JObject
  doAssert inv.arguments{"destroy"}.kind == JArray

# ===========================================================================
# I. addCopy
# ===========================================================================

block addCopyMinimal:
  ## addCopy with required fields only produces "MockFoo/copy".
  var createTbl = initTable[CreationId, JsonNode]()
  createTbl[makeCreationId("k1")] = %*{"id": "src1"}
  let b0 = initRequestBuilder()
  let (b1, _) = addCopy[MockFoo](
    b0,
    fromAccountId = makeAccountId("from1"),
    accountId = makeAccountId("to1"),
    create = createTbl,
  )
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "MockFoo/copy"
  assertEq inv.arguments{"fromAccountId"}.getStr(""), "from1"
  assertEq inv.arguments{"accountId"}.getStr(""), "to1"
  doAssert inv.arguments{"create"}.kind == JObject

# ===========================================================================
# J. addQuery
# ===========================================================================

block addQueryMinimal:
  ## addQuery with only accountId and callback produces "MockQueryable/query".
  let b0 = initRequestBuilder()
  let (b1, _) =
    addQuery[MockQueryable, MockFilter](b0, makeAccountId("a1"), filterConditionToJson)
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "MockQueryable/query"
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  doAssert inv.arguments{"filter"}.isNil

block addQueryWithFilter:
  ## addQuery with a filter condition emits the filter in arguments JSON.
  let b0 = initRequestBuilder()
  let (b1, _) = addQuery[MockQueryable, MockFilter](
    b0,
    makeAccountId("a1"),
    filterConditionToJson,
    filter = Opt.some(filterCondition(MockFilter())),
  )
  let req = b1.build()
  let inv = req.methodCalls[0]
  doAssert inv.arguments{"filter"}.kind == JObject
  doAssert inv.arguments{"filter"}{"mock"}.getBool(false) == true

# ===========================================================================
# J2. Single-type-parameter addQuery[T] (mixin-resolved)
# ===========================================================================

block addQuerySingleParam:
  ## addQuery[T] resolves filterType and filterConditionToJson via mixin.
  ## Produces the same invocation as the two-parameter version.
  let b0 = initRequestBuilder()
  let (b1, _) = addQuery[MockQueryable](b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "MockQueryable/query"
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"

block addQuerySingleParamMatchesTwoParam:
  ## Single-param and two-param produce identical Request structures.
  let ba0 = initRequestBuilder()
  let (ba1, _) =
    addQuery[MockQueryable, MockFilter](ba0, makeAccountId("a1"), filterConditionToJson)
  let bb0 = initRequestBuilder()
  let (bb1, _) = addQuery[MockQueryable](bb0, makeAccountId("a1"))
  let r1 = ba1.build()
  let r2 = bb1.build()
  assertEq r1.methodCalls[0].name, r2.methodCalls[0].name
  assertEq $r1.`using`, $r2.`using`

# ===========================================================================
# K. addQueryChanges
# ===========================================================================

block addQueryChangesMinimal:
  ## addQueryChanges with required fields produces "MockQueryable/queryChanges".
  let b0 = initRequestBuilder()
  let (b1, _) = addQueryChanges[MockQueryable, MockFilter](
    b0, makeAccountId("a1"), makeState("qs0"), filterConditionToJson
  )
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "MockQueryable/queryChanges"
  assertEq inv.arguments{"sinceQueryState"}.getStr(""), "qs0"

# ===========================================================================
# K2. Single-type-parameter addQueryChanges[T]
# ===========================================================================

block addQueryChangesSingleParam:
  ## addQueryChanges[T] resolves filter via mixin, matching two-param version.
  let b0 = initRequestBuilder()
  let (b1, _) =
    addQueryChanges[MockQueryable](b0, makeAccountId("a1"), makeState("qs0"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "MockQueryable/queryChanges"

# ===========================================================================
# K3. QueryParams integration
# ===========================================================================

block addQueryWithQueryParams:
  ## QueryParams fields are unpacked into the query request arguments.
  ## Unset fields retain RFC 8620 section 5.5 defaults.
  let b0 = initRequestBuilder()
  let (b1, _) = addQuery[MockQueryable, MockFilter](
    b0,
    makeAccountId("a1"),
    filterConditionToJson,
    queryParams = QueryParams(position: JmapInt(10), calculateTotal: true),
  )
  let req = b1.build()
  let inv = req.methodCalls[0]
  # Explicitly set fields
  assertEq inv.arguments{"position"}.getBiggestInt(0), 10
  assertEq inv.arguments{"calculateTotal"}.getBool(false), true
  # Unset fields retain defaults
  assertEq inv.arguments{"anchorOffset"}.getBiggestInt(-1), 0
  doAssert inv.arguments{"anchor"}.isNil
  doAssert inv.arguments{"limit"}.isNil

block addQueryDefaultQueryParams:
  ## Default QueryParams() matches RFC 8620 section 5.5 defaults.
  let b0 = initRequestBuilder()
  let (b1, _) =
    addQuery[MockQueryable, MockFilter](b0, makeAccountId("a1"), filterConditionToJson)
  let req = b1.build()
  let inv = req.methodCalls[0]
  assertEq inv.arguments{"position"}.getBiggestInt(-1), 0
  assertEq inv.arguments{"anchorOffset"}.getBiggestInt(-1), 0
  assertEq inv.arguments{"calculateTotal"}.getBool(true), false
  doAssert inv.arguments{"anchor"}.isNil
  doAssert inv.arguments{"limit"}.isNil

block addQueryChangesWithQueryParams:
  ## QueryParams.calculateTotal flows through to queryChanges arguments.
  let b0 = initRequestBuilder()
  let (b1, _) = addQueryChanges[MockQueryable, MockFilter](
    b0,
    makeAccountId("a1"),
    makeState("qs0"),
    filterConditionToJson,
    queryParams = QueryParams(calculateTotal: true),
  )
  let req = b1.build()
  let inv = req.methodCalls[0]
  assertEq inv.arguments{"calculateTotal"}.getBool(false), true

block addQueryChangesIgnoresNonApplicableFields:
  ## Non-applicable QueryParams fields (position, anchor, anchorOffset, limit)
  ## are NOT emitted in queryChanges arguments — they are silently ignored
  ## per RFC 8620 section 5.6.
  let b0 = initRequestBuilder()
  let (b1, _) = addQueryChanges[MockQueryable, MockFilter](
    b0,
    makeAccountId("a1"),
    makeState("qs0"),
    filterConditionToJson,
    queryParams = QueryParams(position: JmapInt(99), calculateTotal: true),
  )
  let req = b1.build()
  let inv = req.methodCalls[0]
  # calculateTotal flows through
  assertEq inv.arguments{"calculateTotal"}.getBool(false), true
  # position does NOT appear (not applicable to /queryChanges)
  doAssert inv.arguments{"position"}.isNil
  # anchor and limit also absent
  doAssert inv.arguments{"anchor"}.isNil
  doAssert inv.arguments{"limit"}.isNil

# ===========================================================================
# L. Result reference integration (golden test)
# ===========================================================================

block queryToGetWithResultReference:
  ## Pipeline: addQuery, take idsRef from the query handle, pass to addGet.
  ## The built Request must have two invocations with the second referencing
  ## the first via "#ids".
  let b0 = initRequestBuilder()
  let (b1, queryHandle) =
    addQuery[MockQueryable, MockFilter](b0, makeAccountId("a1"), filterConditionToJson)
  let idsReference = queryHandle.idsRef()
  let (b2, _) =
    addGet[MockQueryable](b1, makeAccountId("a1"), ids = Opt.some(idsReference))
  let req = b2.build()
  assertLen req.methodCalls, 2
  # First invocation is the query
  let queryInv = req.methodCalls[0]
  assertEq queryInv.name, "MockQueryable/query"
  # Second invocation is the get with a back-reference
  let getInv = req.methodCalls[1]
  assertEq getInv.name, "MockQueryable/get"
  doAssert getInv.arguments{"ids"}.isNil
  doAssert getInv.arguments{"#ids"}.kind == JObject
  let refObj = getInv.arguments{"#ids"}
  assertEq refObj{"resultOf"}.getStr(""), $queryHandle
  assertEq refObj{"name"}.getStr(""), "MockQueryable/query"
  assertEq refObj{"path"}.getStr(""), "/ids"

# ===========================================================================
# M. Type-safe reference compile-time check
# ===========================================================================

block idsRefRejectsGetHandle:
  ## idsRef only compiles on ResponseHandle[QueryResponse[T]].
  ## A GetResponse handle must be rejected at compile time.
  let b0 = initRequestBuilder()
  let (_, getHandle) = addGet[MockFoo](b0, makeAccountId("a1"))
  assertNotCompiles(getHandle.idsRef())

# ===========================================================================
# N. Argument-construction helpers
# ===========================================================================

block directIdsWrapsCorrectly:
  ## directIds produces Opt.some(direct(@[ids])) for use with addGet.
  let ids = directIds(@[makeId("x1"), makeId("x2")])
  doAssert ids.isSome
  let r = ids.get()
  doAssert r.kind == rkDirect
  assertLen r.value, 2
  assertEq $r.value[0], "x1"
  assertEq $r.value[1], "x2"

block directIdsEmpty:
  ## directIds with an empty seq produces Opt.some(direct(@[])).
  let ids = directIds(newSeq[Id]())
  doAssert ids.isSome
  doAssert ids.get().kind == rkDirect
  assertLen ids.get().value, 0

block directIdsWithAddGet:
  ## directIds integrates with addGet — replaces Opt.some(direct(@[...])).
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[MockFoo](
    b0, makeAccountId("a1"), ids = directIds(@[makeId("x1"), makeId("x2")])
  )
  let req = b1.build()
  assertLen req.methodCalls, 1
  let ids = req.methodCalls[0].arguments{"ids"}
  doAssert ids.kind == JArray
  assertLen ids.elems, 2

block initCreatesBuildsTable:
  ## initCreates builds an Opt-wrapped Table from CreationId/JsonNode pairs.
  let creates = initCreates(
    {makeCreationId("k1"): %*{"name": "A"}, makeCreationId("k2"): %*{"name": "B"}}
  )
  doAssert creates.isSome
  let tbl = creates.get()
  assertLen tbl, 2
  doAssert tbl[makeCreationId("k1")]["name"].getStr("") == "A"
  doAssert tbl[makeCreationId("k2")]["name"].getStr("") == "B"

block initCreatesWithAddSet:
  ## initCreates integrates with addSet — replaces manual table construction.
  let b0 = initRequestBuilder()
  let (b1, _) = addSet[MockFoo](
    b0,
    makeAccountId("a1"),
    create = initCreates({makeCreationId("k1"): %*{"name": "New"}}),
  )
  let req = b1.build()
  let inv = req.methodCalls[0]
  doAssert inv.arguments{"create"}.kind == JObject
  doAssert inv.arguments{"create"}{"k1"}{"name"}.getStr("") == "New"

block initUpdatesBuildsTable:
  ## initUpdates builds an Opt-wrapped Table from Id/PatchObject pairs.
  let updates = initUpdates({makeId("id1"): emptyPatch()})
  doAssert updates.isSome
  assertLen updates.get(), 1
