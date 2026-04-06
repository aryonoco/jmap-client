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

registerJmapEntity(MockQueryable)
registerQueryableEntity(MockQueryable)

proc mockFilterToJson(c: MockFilter): JsonNode {.noSideEffect, raises: [].} =
  %*{"mock": true}

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
  ## build() is a pure snapshot. Adding more calls after the first build
  ## produces a larger second snapshot without altering the first.
  var b = initRequestBuilder()
  discard b.addEcho(%*{"ping": 1})
  let req1 = b.build()
  discard b.addEcho(%*{"ping": 2})
  let req2 = b.build()
  assertLen req1.methodCalls, 1
  assertLen req2.methodCalls, 2

# ===========================================================================
# B. Call ID generation
# ===========================================================================

block callIdAutoIncrement:
  ## Successive add* calls produce auto-incrementing call IDs "c0", "c1", "c2".
  var b = initRequestBuilder()
  let h0 = b.addEcho(%*{})
  let h1 = b.addEcho(%*{})
  let h2 = b.addEcho(%*{})
  assertEq $h0, "c0"
  assertEq $h1, "c1"
  assertEq $h2, "c2"

block callIdResetPerBuilder:
  ## Each builder instance starts its counter at zero independently.
  var b1 = initRequestBuilder()
  var b2 = initRequestBuilder()
  let h1 = b1.addEcho(%*{})
  let h2 = b2.addEcho(%*{})
  assertEq $h1, "c0"
  assertEq $h2, "c0"

# ===========================================================================
# C. Capability deduplication
# ===========================================================================

block capabilityDedup:
  ## Two addGet calls for the same entity register the capability only once.
  var b = initRequestBuilder()
  discard addGet[MockFoo](b, makeAccountId())
  discard addGet[MockFoo](b, makeAccountId())
  let caps = b.capabilities
  assertLen caps, 1
  assertEq caps[0], "urn:test:mockfoo"

block multipleCapabilities:
  ## Calls for different entities accumulate distinct capability URIs.
  var b = initRequestBuilder()
  discard addGet[MockFoo](b, makeAccountId())
  discard addGet[MockQueryable](b, makeAccountId())
  let caps = b.capabilities
  assertLen caps, 2
  doAssert "urn:test:mockfoo" in caps
  doAssert "urn:test:mockqueryable" in caps

# ===========================================================================
# D. Read-only accessors
# ===========================================================================

block accessorsAfterOperations:
  ## After two addEcho calls the accessors reflect the accumulated state.
  var b = initRequestBuilder()
  discard b.addEcho(%*{"a": 1})
  discard b.addEcho(%*{"b": 2})
  assertEq b.methodCallCount, 2
  doAssert not b.isEmpty
  let caps = b.capabilities
  assertLen caps, 1
  assertEq caps[0], "urn:ietf:params:jmap:core"

# ===========================================================================
# E. addEcho
# ===========================================================================

block addEchoHappyPath:
  ## addEcho produces an invocation named "Core/echo" with the core
  ## capability URI.
  var b = initRequestBuilder()
  discard b.addEcho(%*{"hello": "world"})
  let req = b.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "Core/echo"
  doAssert "urn:ietf:params:jmap:core" in req.`using`

block addEchoArgsPreserved:
  ## The arguments JSON passed to addEcho is preserved unchanged in the
  ## built Request invocation.
  var b = initRequestBuilder()
  let args = %*{"key": "value", "num": 42}
  discard b.addEcho(args)
  let req = b.build()
  let inv = req.methodCalls[0]
  assertEq inv.arguments{"key"}.getStr(""), "value"
  assertEq inv.arguments{"num"}.getBiggestInt(0), 42

# ===========================================================================
# F. addGet
# ===========================================================================

block addGetMinimal:
  ## addGet with only accountId omits ids and properties from arguments.
  var b = initRequestBuilder()
  discard addGet[MockFoo](b, makeAccountId("a1"))
  let req = b.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "MockFoo/get"
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  doAssert inv.arguments{"ids"}.isNil
  doAssert inv.arguments{"properties"}.isNil

block addGetWithDirectIds:
  ## addGet with direct ids emits an "ids" array in arguments.
  var b = initRequestBuilder()
  discard addGet[MockFoo](
    b, makeAccountId("a1"), ids = Opt.some(direct(@[makeId("x1"), makeId("x2")]))
  )
  let req = b.build()
  let inv = req.methodCalls[0]
  doAssert inv.arguments{"ids"}.kind == JArray
  assertLen inv.arguments{"ids"}.getElems(@[]), 2
  doAssert inv.arguments{"#ids"}.isNil

block addGetWithReferenceIds:
  ## addGet with referenced ids emits a "#ids" key with a ResultReference
  ## object instead of a plain "ids" array.
  var b = initRequestBuilder()
  let rr =
    makeResultReference(mcid = makeMcid("c0"), name = "MockFoo/query", path = "/ids")
  discard
    addGet[MockFoo](b, makeAccountId("a1"), ids = Opt.some(referenceTo[seq[Id]](rr)))
  let req = b.build()
  let inv = req.methodCalls[0]
  doAssert inv.arguments{"ids"}.isNil
  doAssert inv.arguments{"#ids"}.kind == JObject
  assertEq inv.arguments{"#ids"}{"resultOf"}.getStr(""), "c0"

block addGetWithProperties:
  ## addGet with properties emits a "properties" array in arguments.
  var b = initRequestBuilder()
  discard
    addGet[MockFoo](b, makeAccountId("a1"), properties = Opt.some(@["name", "size"]))
  let req = b.build()
  let inv = req.methodCalls[0]
  doAssert inv.arguments{"properties"}.kind == JArray
  assertLen inv.arguments{"properties"}.getElems(@[]), 2

# ===========================================================================
# G. addChanges
# ===========================================================================

block addChangesMinimal:
  ## addChanges with only required fields produces "MockFoo/changes".
  var b = initRequestBuilder()
  discard addChanges[MockFoo](b, makeAccountId("a1"), makeState("s0"))
  let req = b.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "MockFoo/changes"
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  assertEq inv.arguments{"sinceState"}.getStr(""), "s0"
  doAssert inv.arguments{"maxChanges"}.isNil

block addChangesWithMaxChanges:
  ## addChanges with maxChanges emits the value in arguments.
  var b = initRequestBuilder()
  discard addChanges[MockFoo](
    b, makeAccountId("a1"), makeState("s0"), maxChanges = Opt.some(makeMaxChanges(50))
  )
  let req = b.build()
  let inv = req.methodCalls[0]
  assertEq inv.arguments{"maxChanges"}.getBiggestInt(0), 50

# ===========================================================================
# H. addSet
# ===========================================================================

block addSetMinimal:
  ## addSet with only accountId produces "MockFoo/set" with no optional fields.
  var b = initRequestBuilder()
  discard addSet[MockFoo](b, makeAccountId("a1"))
  let req = b.build()
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
  var b = initRequestBuilder()
  discard addSet[MockFoo](
    b,
    makeAccountId("a1"),
    ifInState = Opt.some(makeState("s0")),
    create = Opt.some(createTbl),
    update = Opt.some(updateTbl),
    destroy = Opt.some(direct(@[makeId("d1")])),
  )
  let req = b.build()
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
  var b = initRequestBuilder()
  discard addCopy[MockFoo](
    b,
    fromAccountId = makeAccountId("from1"),
    accountId = makeAccountId("to1"),
    create = createTbl,
  )
  let req = b.build()
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
  var b = initRequestBuilder()
  discard addQuery[MockQueryable, MockFilter](b, makeAccountId("a1"), mockFilterToJson)
  let req = b.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "MockQueryable/query"
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  doAssert inv.arguments{"filter"}.isNil

block addQueryWithFilter:
  ## addQuery with a filter condition emits the filter in arguments JSON.
  var b = initRequestBuilder()
  discard addQuery[MockQueryable, MockFilter](
    b,
    makeAccountId("a1"),
    mockFilterToJson,
    filter = Opt.some(filterCondition(MockFilter())),
  )
  let req = b.build()
  let inv = req.methodCalls[0]
  doAssert inv.arguments{"filter"}.kind == JObject
  doAssert inv.arguments{"filter"}{"mock"}.getBool(false) == true

# ===========================================================================
# K. addQueryChanges
# ===========================================================================

block addQueryChangesMinimal:
  ## addQueryChanges with required fields produces "MockQueryable/queryChanges".
  var b = initRequestBuilder()
  discard addQueryChanges[MockQueryable, MockFilter](
    b, makeAccountId("a1"), makeState("qs0"), mockFilterToJson
  )
  let req = b.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "MockQueryable/queryChanges"
  assertEq inv.arguments{"sinceQueryState"}.getStr(""), "qs0"

# ===========================================================================
# L. Result reference integration (golden test)
# ===========================================================================

block queryToGetWithResultReference:
  ## Pipeline: addQuery, take idsRef from the query handle, pass to addGet.
  ## The built Request must have two invocations with the second referencing
  ## the first via "#ids".
  var b = initRequestBuilder()
  let queryHandle =
    addQuery[MockQueryable, MockFilter](b, makeAccountId("a1"), mockFilterToJson)
  let idsReference = queryHandle.idsRef()
  discard addGet[MockQueryable](b, makeAccountId("a1"), ids = Opt.some(idsReference))
  let req = b.build()
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
  var b = initRequestBuilder()
  let getHandle = addGet[MockFoo](b, makeAccountId("a1"))
  assertNotCompiles(getHandle.idsRef())
