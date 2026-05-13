# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## RequestBuilder tests: construction, add* methods, build(), capability
## deduplication, call ID generation, read-only accessors, and result
## reference integration.

import std/json
import std/tables

import jmap_client
import jmap_client/internal/types/framework
import jmap_client/internal/serialisation/serde_envelope
import jmap_client/internal/protocol/entity
import jmap_client/internal/protocol/methods
import jmap_client/internal/protocol/dispatch
import jmap_client/internal/protocol/builder
import jmap_client/internal/types/envelope

import ../massertions
import ../mfixtures
import ../mtestblock

# ---------------------------------------------------------------------------
# Mock entity types (local -- compile-time verification only)
# ---------------------------------------------------------------------------

{.push ruleOff: "hasDoc".}
{.push ruleOff: "objects".}
{.push ruleOff: "params".}

type MockFoo = object

proc methodEntity*(T: typedesc[MockFoo]): MethodEntity =
  meTest

proc capabilityUri*(T: typedesc[MockFoo]): CapabilityUri =
  parseCapabilityUri("urn:test:mockfoo").get()

proc getMethodName*(T: typedesc[MockFoo]): MethodName =
  mnMailboxGet

proc changesMethodName*(T: typedesc[MockFoo]): MethodName =
  mnMailboxChanges

proc setMethodName*(T: typedesc[MockFoo]): MethodName =
  mnMailboxSet

proc copyMethodName*(T: typedesc[MockFoo]): MethodName =
  mnEmailCopy

template changesResponseType*(T: typedesc[MockFoo]): typedesc =
  ChangesResponse[MockFoo]

template copyItemType*(T: typedesc[MockFoo]): typedesc =
  MockFoo

template copyResponseType*(T: typedesc[MockFoo]): typedesc =
  CopyResponse[MockFoo]

func toJson*(f: MockFoo): JsonNode =
  ## Test stub — ``SetRequest`` / ``CopyRequest`` generics resolve
  ## ``C.toJson`` via ``mixin`` at instantiation, so every MockFoo used
  ## in a typed create map must have a visible ``toJson``.
  discard f
  newJObject()

registerJmapEntity(MockFoo)

type MockFilter = object

type MockQueryable = object

proc methodEntity*(T: typedesc[MockQueryable]): MethodEntity =
  meTest

proc capabilityUri*(T: typedesc[MockQueryable]): CapabilityUri =
  parseCapabilityUri("urn:test:mockqueryable").get()

proc getMethodName*(T: typedesc[MockQueryable]): MethodName =
  mnMailboxGet

proc changesMethodName*(T: typedesc[MockQueryable]): MethodName =
  mnMailboxChanges

proc setMethodName*(T: typedesc[MockQueryable]): MethodName =
  mnMailboxSet

proc queryMethodName*(T: typedesc[MockQueryable]): MethodName =
  mnEmailQuery

proc queryChangesMethodName*(T: typedesc[MockQueryable]): MethodName =
  mnEmailQueryChanges

template filterType*(T: typedesc[MockQueryable]): typedesc =
  MockFilter

template changesResponseType*(T: typedesc[MockQueryable]): typedesc =
  ChangesResponse[MockQueryable]

func toJson(c: MockFilter): JsonNode =
  %*{"mock": true}

registerJmapEntity(MockQueryable)
registerQueryableEntity(MockQueryable)

{.pop.} # params
{.pop.} # objects
{.pop.} # hasDoc

# ===========================================================================
# A. Constructor & build
# ===========================================================================

testCase initBuilderEmpty:
  ## Fresh builder has no invocations, pre-declares the foundational
  ## ``urn:ietf:params:jmap:core`` capability (RFC 8620 §3.2 — clients
  ## MUST declare every capability they use; ``core`` is implicit in
  ## every method), and builds an otherwise empty Request.
  let b = initRequestBuilder(makeBuilderId())
  doAssert b.isEmpty
  assertEq b.methodCallCount, 0
  assertLen b.capabilities, 1
  assertEq b.capabilities[0], "urn:ietf:params:jmap:core"
  let req = b.freeze().request
  assertLen req.`using`, 1
  assertEq req.`using`[0], "urn:ietf:params:jmap:core"
  assertLen req.methodCalls, 0
  doAssert req.createdIds.isNone

# ===========================================================================
# B. Call ID generation
# ===========================================================================

testCase callIdAutoIncrement:
  ## Successive add* calls produce auto-incrementing call IDs "c0", "c1", "c2".
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, h0) = b0.addEcho(%*{})
  let (b2, h1) = b1.addEcho(%*{})
  let (_, h2) = b2.addEcho(%*{})
  assertEq $h0, "c0"
  assertEq $h1, "c1"
  assertEq $h2, "c2"

testCase callIdResetPerBuilder:
  ## Each builder instance starts its counter at zero independently.
  let ba0 = initRequestBuilder(makeBuilderId())
  let bb0 = initRequestBuilder(makeBuilderId())
  let (_, h1) = ba0.addEcho(%*{})
  let (_, h2) = bb0.addEcho(%*{})
  assertEq $h1, "c0"
  assertEq $h2, "c0"

# ===========================================================================
# C. Capability deduplication
# ===========================================================================

testCase capabilityDedup:
  ## Two addGet calls for the same entity register the entity capability
  ## only once. ``urn:ietf:params:jmap:core`` is pre-declared by
  ## ``initRequestBuilder``, so the resulting set carries it alongside
  ## the entity URI.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addGet[MockFoo](b0, makeAccountId())
  let (b2, _) = addGet[MockFoo](b1, makeAccountId())
  let caps = b2.capabilities
  assertLen caps, 2
  doAssert "urn:ietf:params:jmap:core" in caps
  doAssert "urn:test:mockfoo" in caps

testCase multipleCapabilities:
  ## Calls for different entities accumulate distinct entity capability
  ## URIs alongside the pre-declared ``urn:ietf:params:jmap:core``.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addGet[MockFoo](b0, makeAccountId())
  let (b2, _) = addGet[MockQueryable](b1, makeAccountId())
  let caps = b2.capabilities
  assertLen caps, 3
  doAssert "urn:ietf:params:jmap:core" in caps
  doAssert "urn:test:mockfoo" in caps
  doAssert "urn:test:mockqueryable" in caps

# ===========================================================================
# D. Read-only accessors
# ===========================================================================

testCase accessorsAfterOperations:
  ## After two addEcho calls the accessors reflect the accumulated state.
  let b0 = initRequestBuilder(makeBuilderId())
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

testCase addEchoHappyPath:
  ## addEcho produces an invocation named "Core/echo" with the core
  ## capability URI.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = b0.addEcho(%*{"hello": "world"})
  let req = b1.freeze().request
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, mnCoreEcho
  doAssert "urn:ietf:params:jmap:core" in req.`using`

testCase addEchoArgsPreserved:
  ## The arguments JSON passed to addEcho is preserved unchanged in the
  ## built Request invocation.
  let b0 = initRequestBuilder(makeBuilderId())
  let args = %*{"key": "value", "num": 42}
  let (b1, _) = b0.addEcho(args)
  let req = b1.freeze().request
  let inv = req.methodCalls[0]
  assertEq inv.arguments{"key"}.getStr(""), "value"
  assertEq inv.arguments{"num"}.getBiggestInt(0), 42

# ===========================================================================
# F. addGet
# ===========================================================================

testCase addGetMinimal:
  ## addGet with only accountId omits ids and properties from arguments.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addGet[MockFoo](b0, makeAccountId("a1"))
  let req = b1.freeze().request
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, mnMailboxGet
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  doAssert inv.arguments{"ids"}.isNil
  doAssert inv.arguments{"properties"}.isNil

testCase addGetWithDirectIds:
  ## addGet with direct ids emits an "ids" array in arguments.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addGet[MockFoo](
    b0, makeAccountId("a1"), ids = Opt.some(direct(@[makeId("x1"), makeId("x2")]))
  )
  let req = b1.freeze().request
  let inv = req.methodCalls[0]
  doAssert inv.arguments{"ids"}.kind == JArray
  assertLen inv.arguments{"ids"}.getElems(@[]), 2
  doAssert inv.arguments{"#ids"}.isNil

testCase addGetWithReferenceIds:
  ## addGet with referenced ids emits a "#ids" key with a ResultReference
  ## object instead of a plain "ids" array.
  let b0 = initRequestBuilder(makeBuilderId())
  let rr = makeResultReference(mcid = makeMcid("c0"), name = mnEmailQuery, path = rpIds)
  let (b1, _) =
    addGet[MockFoo](b0, makeAccountId("a1"), ids = Opt.some(referenceTo[seq[Id]](rr)))
  let req = b1.freeze().request
  let inv = req.methodCalls[0]
  doAssert inv.arguments{"ids"}.isNil
  doAssert inv.arguments{"#ids"}.kind == JObject
  assertEq inv.arguments{"#ids"}{"resultOf"}.getStr(""), "c0"

testCase addGetWithProperties:
  ## addGet with properties emits a "properties" array in arguments.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) =
    addGet[MockFoo](b0, makeAccountId("a1"), properties = Opt.some(@["name", "size"]))
  let req = b1.freeze().request
  let inv = req.methodCalls[0]
  doAssert inv.arguments{"properties"}.kind == JArray
  assertLen inv.arguments{"properties"}.getElems(@[]), 2

# ===========================================================================
# G. addChanges
# ===========================================================================

testCase addChangesMinimal:
  ## addChanges with only required fields produces "MockFoo/changes".
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addChanges[MockFoo](b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.freeze().request
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, mnMailboxChanges
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  assertEq inv.arguments{"sinceState"}.getStr(""), "s0"
  doAssert inv.arguments{"maxChanges"}.isNil

testCase addChangesWithMaxChanges:
  ## addChanges with maxChanges emits the value in arguments.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addChanges[MockFoo](
    b0, makeAccountId("a1"), makeState("s0"), maxChanges = Opt.some(makeMaxChanges(50))
  )
  let req = b1.freeze().request
  let inv = req.methodCalls[0]
  assertEq inv.arguments{"maxChanges"}.getBiggestInt(0), 50

# ===========================================================================
# I. addCopy
# ===========================================================================

testCase addCopyMinimal:
  ## addCopy with required fields only produces "MockFoo/copy". Typed
  ## create slot: ``Table[CreationId, MockFoo]``; per-entry serialisation
  ## dispatches through ``MockFoo.toJson`` via the widened
  ## ``CopyRequest[T, CopyItem]`` generic.
  var createTbl = initTable[CreationId, MockFoo]()
  createTbl[makeCreationId("k1")] = MockFoo()
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addCopy[MockFoo](
    b0,
    fromAccountId = makeAccountId("from1"),
    accountId = makeAccountId("to1"),
    create = createTbl,
  )
  let req = b1.freeze().request
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, mnEmailCopy
  assertEq inv.arguments{"fromAccountId"}.getStr(""), "from1"
  assertEq inv.arguments{"accountId"}.getStr(""), "to1"
  doAssert inv.arguments{"create"}.kind == JObject

# ===========================================================================
# J. addQuery
# ===========================================================================

testCase addQueryMinimal:
  ## addQuery with only accountId produces "MockQueryable/query". Leaf
  ## condition ``MockFilter.toJson`` resolves via the ``mixin toJson``
  ## cascade through ``serializeOptFilter`` → ``Filter[C].toJson``.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addQuery[MockQueryable, MockFilter, Comparator](b0, makeAccountId("a1"))
  let req = b1.freeze().request
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, mnEmailQuery
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  doAssert inv.arguments{"filter"}.isNil

testCase addQueryWithFilter:
  ## addQuery with a filter condition emits the filter in arguments JSON.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addQuery[MockQueryable, MockFilter, Comparator](
    b0, makeAccountId("a1"), filter = Opt.some(filterCondition(MockFilter()))
  )
  let req = b1.freeze().request
  let inv = req.methodCalls[0]
  doAssert inv.arguments{"filter"}.kind == JObject
  doAssert inv.arguments{"filter"}{"mock"}.getBool(false) == true

# ===========================================================================
# J2. Single-type-parameter addQuery[T] (mixin-resolved)
# ===========================================================================

testCase addQuerySingleParam:
  ## addQuery[T] resolves ``filterType(T)`` via template expansion and
  ## ``C.toJson`` via the mixin cascade. Produces the same invocation
  ## as the three-type-parameter version.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addQuery[MockQueryable](b0, makeAccountId("a1"))
  let req = b1.freeze().request
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, mnEmailQuery
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"

testCase addQuerySingleParamMatchesTwoParam:
  ## Single-param and three-type-param produce identical Request structures.
  let ba0 = initRequestBuilder(makeBuilderId())
  let (ba1, _) =
    addQuery[MockQueryable, MockFilter, Comparator](ba0, makeAccountId("a1"))
  let bb0 = initRequestBuilder(makeBuilderId())
  let (bb1, _) = addQuery[MockQueryable](bb0, makeAccountId("a1"))
  let r1 = ba1.freeze().request
  let r2 = bb1.freeze().request
  assertEq r1.methodCalls[0].name, r2.methodCalls[0].name
  assertEq $r1.`using`, $r2.`using`

# ===========================================================================
# K. addQueryChanges
# ===========================================================================

testCase addQueryChangesMinimal:
  ## addQueryChanges with required fields produces "MockQueryable/queryChanges".
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addQueryChanges[MockQueryable, MockFilter, Comparator](
    b0, makeAccountId("a1"), makeState("qs0")
  )
  let req = b1.freeze().request
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, mnEmailQueryChanges
  assertEq inv.arguments{"sinceQueryState"}.getStr(""), "qs0"

# ===========================================================================
# K2. Single-type-parameter addQueryChanges[T]
# ===========================================================================

testCase addQueryChangesSingleParam:
  ## addQueryChanges[T] resolves filter via mixin, matching two-param version.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) =
    addQueryChanges[MockQueryable](b0, makeAccountId("a1"), makeState("qs0"))
  let req = b1.freeze().request
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnEmailQueryChanges

# ===========================================================================
# K3. QueryParams integration
# ===========================================================================

testCase addQueryWithQueryParams:
  ## QueryParams fields are unpacked into the query request arguments.
  ## Unset fields retain RFC 8620 section 5.5 defaults.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addQuery[MockQueryable, MockFilter, Comparator](
    b0,
    makeAccountId("a1"),
    queryParams = QueryParams(position: parseJmapInt(10).get(), calculateTotal: true),
  )
  let req = b1.freeze().request
  let inv = req.methodCalls[0]
  # Explicitly set fields
  assertEq inv.arguments{"position"}.getBiggestInt(0), 10
  assertEq inv.arguments{"calculateTotal"}.getBool(false), true
  # Unset anchor implies anchorOffset is omitted from the wire.
  doAssert inv.arguments{"anchor"}.isNil
  doAssert inv.arguments{"anchorOffset"}.isNil
  doAssert inv.arguments{"limit"}.isNil

testCase addQueryDefaultQueryParams:
  ## Default QueryParams() matches RFC 8620 section 5.5 defaults. With
  ## anchor absent, anchorOffset is omitted from the emitted JSON
  ## (RFC 8620 §5.5: anchorOffset is meaningful only with anchor).
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addQuery[MockQueryable, MockFilter, Comparator](b0, makeAccountId("a1"))
  let req = b1.freeze().request
  let inv = req.methodCalls[0]
  assertEq inv.arguments{"position"}.getBiggestInt(-1), 0
  assertEq inv.arguments{"calculateTotal"}.getBool(true), false
  doAssert inv.arguments{"anchor"}.isNil
  doAssert inv.arguments{"anchorOffset"}.isNil
  doAssert inv.arguments{"limit"}.isNil

testCase addQueryChangesCalculateTotalFlow:
  ## ``calculateTotal`` flows through to queryChanges arguments.
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addQueryChanges[MockQueryable, MockFilter, Comparator](
    b0, makeAccountId("a1"), makeState("qs0"), calculateTotal = true
  )
  let req = b1.freeze().request
  let inv = req.methodCalls[0]
  assertEq inv.arguments{"calculateTotal"}.getBool(false), true

testCase addQueryChangesRejectsWindowParams:
  ## RFC 8620 §5.6 defines no window parameters for /queryChanges; the
  ## signature enforces this structurally. Passing ``position``,
  ## ``anchor``, ``anchorOffset``, or ``limit`` is a compile error.
  assertNotCompiles:
    let b0 = initRequestBuilder(makeBuilderId())
    discard addQueryChanges[MockQueryable, MockFilter, Comparator](
      b0, makeAccountId("a1"), makeState("qs0"), position = parseJmapInt(99).get()
    )

# ===========================================================================
# L. Result reference integration (golden test)
# ===========================================================================

testCase queryToGetWithResultReference:
  ## Pipeline: addQuery, take idsRef from the query handle, pass to addGet.
  ## The built Request must have two invocations with the second referencing
  ## the first via "#ids".
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, queryHandle) =
    addQuery[MockQueryable, MockFilter, Comparator](b0, makeAccountId("a1"))
  let idsReference = queryHandle.idsRef()
  let (b2, _) =
    addGet[MockQueryable](b1, makeAccountId("a1"), ids = Opt.some(idsReference))
  let req = b2.freeze().request
  assertLen req.methodCalls, 2
  # First invocation is the query
  let queryInv = req.methodCalls[0]
  assertEq queryInv.name, mnEmailQuery
  # Second invocation is the get with a back-reference
  let getInv = req.methodCalls[1]
  assertEq getInv.name, mnMailboxGet
  doAssert getInv.arguments{"ids"}.isNil
  doAssert getInv.arguments{"#ids"}.kind == JObject
  let refObj = getInv.arguments{"#ids"}
  assertEq refObj{"resultOf"}.getStr(""), $queryHandle
  assertEq refObj{"name"}.getStr(""), "Email/query"
  assertEq refObj{"path"}.getStr(""), "/ids"

# ===========================================================================
# M. Type-safe reference compile-time check
# ===========================================================================

testCase idsRefRejectsGetHandle:
  ## idsRef only compiles on ResponseHandle[QueryResponse[T]].
  ## A GetResponse handle must be rejected at compile time.
  let b0 = initRequestBuilder(makeBuilderId())
  let (_, getHandle) = addGet[MockFoo](b0, makeAccountId("a1"))
  assertNotCompiles(getHandle.idsRef())

# ===========================================================================
# N. Argument-construction helpers
# ===========================================================================

testCase directIdsWrapsCorrectly:
  ## directIds produces Opt.some(direct(@[ids])) for use with addGet.
  let ids = directIds(@[makeId("x1"), makeId("x2")])
  doAssert ids.isSome
  let r = ids.get()
  doAssert r.kind == rkDirect
  assertLen r.value, 2
  assertEq $r.value[0], "x1"
  assertEq $r.value[1], "x2"

testCase directIdsEmpty:
  ## directIds with an empty seq produces Opt.some(direct(@[])).
  let ids = directIds(newSeq[Id]())
  doAssert ids.isSome
  doAssert ids.get().kind == rkDirect
  assertLen ids.get().value, 0

testCase directIdsWithAddGet:
  ## directIds integrates with addGet — replaces Opt.some(direct(@[...])).
  let b0 = initRequestBuilder(makeBuilderId())
  let (b1, _) = addGet[MockFoo](
    b0, makeAccountId("a1"), ids = directIds(@[makeId("x1"), makeId("x2")])
  )
  let req = b1.freeze().request
  assertLen req.methodCalls, 1
  let ids = req.methodCalls[0].arguments{"ids"}
  doAssert ids.kind == JArray
  assertLen ids.elems, 2

testCase initCreatesBuildsTable:
  ## initCreates builds an Opt-wrapped Table from CreationId/JsonNode pairs.
  let creates = initCreates(
    {makeCreationId("k1"): %*{"name": "A"}, makeCreationId("k2"): %*{"name": "B"}}
  )
  doAssert creates.isSome
  let tbl = creates.get()
  assertLen tbl, 2
  doAssert tbl[makeCreationId("k1")]["name"].getStr("") == "A"
  doAssert tbl[makeCreationId("k2")]["name"].getStr("") == "B"
