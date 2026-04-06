# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Request toJson and response fromJson tests for all six standard JMAP methods
## (RFC 8620 sections 5.1-5.6), plus SetResponse merging and CopyResponse
## merging. Covers golden tests sections 14.2 and 14.4, all Step 3 edge-case
## rows from section 14.6, and lenient Option helper coverage.

import std/json
import std/tables

import jmap_client/validation
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/envelope
import jmap_client/framework
import jmap_client/errors
import jmap_client/serde
import jmap_client/serde_envelope
import jmap_client/serde_framework
import jmap_client/entity
import jmap_client/methods

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

proc mockFilterToJson(c: MockFilter): JsonNode =
  %*{"mock": true}

{.pop.} # params
{.pop.} # objects
{.pop.} # hasDoc

# ===========================================================================
# A. Golden tests (sections 14.2, 14.4)
# ===========================================================================

block goldenSetRequestToJson:
  ## Golden test section 14.2: SetRequest with create/update/destroy.
  let acctId = makeAccountId("A13824")
  let ifState = makeState("abc123")
  let cid = makeCreationId("k1")
  let uid = makeId("id1")
  let did1 = makeId("id2")
  let did2 = makeId("id3")
  let createData = %*{"name": "New Item"}
  let updateData = setProp(emptyPatch(), "name", %*"Updated").get()
  var createTbl = initTable[CreationId, JsonNode]()
  createTbl[cid] = createData
  var updateTbl = initTable[Id, PatchObject]()
  updateTbl[uid] = updateData
  let req = SetRequest[MockFoo](
    accountId: acctId,
    ifInState: Opt.some(ifState),
    create: Opt.some(createTbl),
    update: Opt.some(updateTbl),
    destroy: Opt.some(direct(@[did1, did2])),
  )
  let j = req.toJson()
  doAssert j{"accountId"}.getStr("") == "A13824"
  doAssert j{"ifInState"}.getStr("") == "abc123"
  doAssert j{"create"}.kind == JObject
  doAssert j{"create"}{"k1"} != nil
  doAssert j{"update"}.kind == JObject
  doAssert j{"update"}{"id1"} != nil
  doAssert j{"destroy"}.kind == JArray
  assertLen j{"destroy"}.getElems(@[]), 2

block goldenSetResponseMerging:
  ## Golden test section 14.4: SetResponse merging with mixed success/failure.
  let j = %*{
    "accountId": "A13824",
    "oldState": "state1",
    "newState": "state2",
    "created": {"k1": {"id": "id-new-1", "name": "Created Item"}},
    "notCreated": {"k2": {"type": "forbidden"}},
    "updated": {"id1": nil, "id2": {"serverprop": "changed"}},
    "notUpdated": {"id3": {"type": "notFound"}},
    "destroyed": ["id4"],
    "notDestroyed": {"id5": {"type": "forbidden"}},
  }
  let sr = SetResponse[MockFoo].fromJson(j).get()
  doAssert sr.accountId == makeAccountId("A13824")
  doAssert sr.oldState.isSome
  doAssert sr.oldState.get() == makeState("state1")
  doAssert sr.newState == makeState("state2")
  # created: k1 ok, notCreated: k2 err
  assertLen sr.created, 1
  assertLen sr.notCreated, 1
  doAssert makeCreationId("k1") in sr.created
  doAssert sr.notCreated[makeCreationId("k2")].errorType == setForbidden
  # updated: id1 none, id2 some; notUpdated: id3 err
  assertLen sr.updated, 2
  assertLen sr.notUpdated, 1
  doAssert sr.updated[makeId("id1")].isNone
  doAssert sr.updated[makeId("id2")].isSome
  doAssert sr.notUpdated[makeId("id3")].errorType == setNotFound
  # destroyed: id4; notDestroyed: id5 err
  assertLen sr.destroyed, 1
  assertLen sr.notDestroyed, 1
  doAssert makeId("id4") in sr.destroyed
  doAssert sr.notDestroyed[makeId("id5")].errorType == setForbidden

# ===========================================================================
# B. Request toJson tests
# ===========================================================================

block getRequestAllDefaults:
  ## GetRequest with all none produces only accountId.
  let req = GetRequest[MockFoo](
    accountId: makeAccountId("a1"),
    ids: Opt.none(Referencable[seq[Id]]),
    properties: Opt.none(seq[string]),
  )
  let j = req.toJson()
  doAssert j{"accountId"}.getStr("") == "a1"
  doAssert j{"ids"}.isNil
  doAssert j{"properties"}.isNil

block getRequestDirectIds:
  ## GetRequest with direct ids produces "ids" array.
  let req = GetRequest[MockFoo](
    accountId: makeAccountId("a1"),
    ids: Opt.some(direct(@[makeId("x1"), makeId("x2")])),
    properties: Opt.none(seq[string]),
  )
  let j = req.toJson()
  doAssert j{"ids"}.kind == JArray
  assertLen j{"ids"}.getElems(@[]), 2
  doAssert j{"#ids"}.isNil

block getRequestReferenceIds:
  ## GetRequest with reference ids produces "#ids" with ResultReference.
  let rr =
    ResultReference(resultOf: makeMcid("c0"), name: "MockFoo/query", path: "/ids")
  let req = GetRequest[MockFoo](
    accountId: makeAccountId("a1"),
    ids: Opt.some(referenceTo[seq[Id]](rr)),
    properties: Opt.none(seq[string]),
  )
  let j = req.toJson()
  doAssert j{"ids"}.isNil
  doAssert j{"#ids"}.kind == JObject
  doAssert j{"#ids"}{"resultOf"}.getStr("") == "c0"

block getRequestWithProperties:
  ## GetRequest with properties produces "properties" array.
  let req = GetRequest[MockFoo](
    accountId: makeAccountId("a1"),
    ids: Opt.none(Referencable[seq[Id]]),
    properties: Opt.some(@["name", "email"]),
  )
  let j = req.toJson()
  doAssert j{"properties"}.kind == JArray
  assertLen j{"properties"}.getElems(@[]), 2

block changesRequestMinimal:
  ## ChangesRequest with only required fields.
  let req = ChangesRequest[MockFoo](
    accountId: makeAccountId("a1"),
    sinceState: makeState("s0"),
    maxChanges: Opt.none(MaxChanges),
  )
  let j = req.toJson()
  doAssert j{"accountId"}.getStr("") == "a1"
  doAssert j{"sinceState"}.getStr("") == "s0"
  doAssert j{"maxChanges"}.isNil

block changesRequestWithMaxChanges:
  ## ChangesRequest with maxChanges emitted.
  let req = ChangesRequest[MockFoo](
    accountId: makeAccountId("a1"),
    sinceState: makeState("s0"),
    maxChanges: Opt.some(makeMaxChanges(50)),
  )
  let j = req.toJson()
  doAssert j{"maxChanges"}.getBiggestInt(0) == 50

block setRequestMinimal:
  ## SetRequest with only accountId.
  let req = SetRequest[MockFoo](
    accountId: makeAccountId("a1"),
    ifInState: Opt.none(JmapState),
    create: Opt.none(Table[CreationId, JsonNode]),
    update: Opt.none(Table[Id, PatchObject]),
    destroy: Opt.none(Referencable[seq[Id]]),
  )
  let j = req.toJson()
  doAssert j{"accountId"}.getStr("") == "a1"
  doAssert j{"ifInState"}.isNil
  doAssert j{"create"}.isNil
  doAssert j{"update"}.isNil
  doAssert j{"destroy"}.isNil

block setRequestWithReferencableDestroy:
  ## SetRequest destroy with result reference produces "#destroy".
  let rr =
    ResultReference(resultOf: makeMcid("c0"), name: "MockFoo/query", path: "/ids")
  let req = SetRequest[MockFoo](
    accountId: makeAccountId("a1"),
    ifInState: Opt.none(JmapState),
    create: Opt.none(Table[CreationId, JsonNode]),
    update: Opt.none(Table[Id, PatchObject]),
    destroy: Opt.some(referenceTo[seq[Id]](rr)),
  )
  let j = req.toJson()
  doAssert j{"destroy"}.isNil
  doAssert j{"#destroy"}.kind == JObject
  doAssert j{"#destroy"}{"resultOf"}.getStr("") == "c0"

block copyRequestMinimal:
  ## CopyRequest with required fields and defaults.
  var createTbl = initTable[CreationId, JsonNode]()
  createTbl[makeCreationId("k1")] = %*{"id": "src1"}
  let req = CopyRequest[MockFoo](
    fromAccountId: makeAccountId("from1"),
    ifFromInState: Opt.none(JmapState),
    accountId: makeAccountId("to1"),
    ifInState: Opt.none(JmapState),
    create: createTbl,
    onSuccessDestroyOriginal: false,
    destroyFromIfInState: Opt.none(JmapState),
  )
  let j = req.toJson()
  doAssert j{"fromAccountId"}.getStr("") == "from1"
  doAssert j{"accountId"}.getStr("") == "to1"
  doAssert j{"create"}.kind == JObject
  doAssert j{"onSuccessDestroyOriginal"}.getBool(true) == false

block copyRequestOnSuccessTrue:
  ## CopyRequest with onSuccessDestroyOriginal true always emitted.
  var createTbl = initTable[CreationId, JsonNode]()
  createTbl[makeCreationId("k1")] = %*{"id": "src1"}
  let req = CopyRequest[MockFoo](
    fromAccountId: makeAccountId("from1"),
    ifFromInState: Opt.none(JmapState),
    accountId: makeAccountId("to1"),
    ifInState: Opt.none(JmapState),
    create: createTbl,
    onSuccessDestroyOriginal: true,
    destroyFromIfInState: Opt.none(JmapState),
  )
  let j = req.toJson()
  doAssert j{"onSuccessDestroyOriginal"}.getBool(false) == true

block queryRequestMinimal:
  ## QueryRequest with only required fields.
  let req = QueryRequest[MockQueryable, MockFilter](
    accountId: makeAccountId("a1"),
    filter: Opt.none(Filter[MockFilter]),
    sort: Opt.none(seq[Comparator]),
    position: JmapInt(0),
    anchor: Opt.none(Id),
    anchorOffset: JmapInt(0),
    limit: Opt.none(UnsignedInt),
    calculateTotal: false,
  )
  let j = req.toJson(mockFilterToJson)
  doAssert j{"accountId"}.getStr("") == "a1"
  doAssert j{"filter"}.isNil
  doAssert j{"sort"}.isNil
  doAssert j{"position"}.getBiggestInt(-1) == 0
  doAssert j{"anchorOffset"}.getBiggestInt(-1) == 0
  doAssert j{"calculateTotal"}.getBool(true) == false

block queryRequestWithFilter:
  ## QueryRequest with filter via callback -- proves filterType(T) expansion.
  let req = QueryRequest[MockQueryable, MockFilter](
    accountId: makeAccountId("a1"),
    filter: Opt.some(filterCondition(MockFilter())),
    sort: Opt.none(seq[Comparator]),
    position: JmapInt(0),
    anchor: Opt.none(Id),
    anchorOffset: JmapInt(0),
    limit: Opt.none(UnsignedInt),
    calculateTotal: false,
  )
  let j = req.toJson(mockFilterToJson)
  doAssert j{"filter"}.kind == JObject
  doAssert j{"filter"}{"mock"}.getBool(false) == true

block queryChangesRequestMinimal:
  ## QueryChangesRequest with only required fields.
  let req = QueryChangesRequest[MockQueryable, MockFilter](
    accountId: makeAccountId("a1"),
    filter: Opt.none(Filter[MockFilter]),
    sort: Opt.none(seq[Comparator]),
    sinceQueryState: makeState("qs0"),
    maxChanges: Opt.none(MaxChanges),
    upToId: Opt.none(Id),
    calculateTotal: false,
  )
  let j = req.toJson(mockFilterToJson)
  doAssert j{"sinceQueryState"}.getStr("") == "qs0"
  doAssert j{"calculateTotal"}.getBool(true) == false
  doAssert j{"filter"}.isNil

block queryChangesRequestAllFields:
  ## QueryChangesRequest with all fields populated.
  let comp = parseComparator(makePropertyName("name"), true, Opt.none(string))
  var sortSeq: seq[Comparator]
  sortSeq.add(comp)
  let req = QueryChangesRequest[MockQueryable, MockFilter](
    accountId: makeAccountId("a1"),
    filter: Opt.some(filterCondition(MockFilter())),
    sort: Opt.some(sortSeq),
    sinceQueryState: makeState("qs0"),
    maxChanges: Opt.some(makeMaxChanges(10)),
    upToId: Opt.some(makeId("upTo1")),
    calculateTotal: true,
  )
  let j = req.toJson(mockFilterToJson)
  doAssert j{"filter"}.kind == JObject
  doAssert j{"sort"}.kind == JArray
  doAssert j{"maxChanges"}.getBiggestInt(0) == 10
  doAssert j{"upToId"}.getStr("") == "upTo1"
  doAssert j{"calculateTotal"}.getBool(false) == true

block changesRequestMinimalToJson:
  ## Section 14.6: ChangesRequest minimal produces accountId + sinceState only.
  let req = ChangesRequest[MockFoo](
    accountId: makeAccountId("a1"),
    sinceState: makeState("s0"),
    maxChanges: Opt.none(MaxChanges),
  )
  let j = req.toJson()
  doAssert j.len == 2

# ===========================================================================
# C. GetResponse fromJson tests
# ===========================================================================

block getResponseHappyPath:
  ## Valid GetResponse JSON with all fields.
  let j =
    %*{"accountId": "a1", "state": "s1", "list": [{"id": "x1"}], "notFound": ["x2"]}
  let gr = GetResponse[MockFoo].fromJson(j).get()
  doAssert gr.accountId == makeAccountId("a1")
  doAssert gr.state == makeState("s1")
  assertLen gr.list, 1
  assertLen gr.notFound, 1
  doAssert gr.notFound[0] == makeId("x2")

block getResponseMissingState:
  ## Missing state field produces err.
  let j = %*{"accountId": "a1", "list": [], "notFound": []}
  assertErr GetResponse[MockFoo].fromJson(j)

block getResponseStateWrongKind:
  ## State is JInt instead of JString produces err.
  let j = %*{"accountId": "a1", "state": 42, "list": [], "notFound": []}
  assertErr GetResponse[MockFoo].fromJson(j)

block getResponseListWrongKind:
  ## List is JString instead of JArray produces err.
  let j = %*{"accountId": "a1", "state": "s1", "list": "wrong"}
  assertErr GetResponse[MockFoo].fromJson(j)

block getResponseNotFoundAbsent:
  ## NotFound absent produces ok with empty notFound.
  let j = %*{"accountId": "a1", "state": "s1", "list": []}
  let gr = GetResponse[MockFoo].fromJson(j).get()
  assertLen gr.notFound, 0

block getResponseListEmpty:
  ## Empty list is valid.
  let j = %*{"accountId": "a1", "state": "s1", "list": []}
  assertOk GetResponse[MockFoo].fromJson(j)

block getResponseExtraFields:
  ## Extra unknown fields are ignored.
  let j = %*{"accountId": "a1", "state": "s1", "list": [], "unknown": "ignored"}
  assertOk GetResponse[MockFoo].fromJson(j)

block getResponseAccountIdEmpty:
  ## Empty accountId string produces err.
  let j = %*{"accountId": "", "state": "s1", "list": []}
  assertErr GetResponse[MockFoo].fromJson(j)

# ===========================================================================
# D. ChangesResponse fromJson tests
# ===========================================================================

block changesResponseHappyPath:
  ## Valid ChangesResponse JSON.
  let j = %*{
    "accountId": "a1",
    "oldState": "s0",
    "newState": "s1",
    "hasMoreChanges": false,
    "created": ["c1"],
    "updated": ["u1"],
    "destroyed": ["d1"],
  }
  let cr = ChangesResponse[MockFoo].fromJson(j).get()
  assertLen cr.created, 1
  assertLen cr.updated, 1
  assertLen cr.destroyed, 1
  doAssert not cr.hasMoreChanges

block changesResponseHasMoreTrue:
  ## hasMoreChanges true is preserved.
  let j = %*{
    "accountId": "a1",
    "oldState": "s0",
    "newState": "s1",
    "hasMoreChanges": true,
    "created": [],
    "updated": [],
    "destroyed": [],
  }
  let cr = ChangesResponse[MockFoo].fromJson(j).get()
  doAssert cr.hasMoreChanges

block changesResponseHasMoreWrongKind:
  ## hasMoreChanges is JString produces err.
  let j = %*{
    "accountId": "a1",
    "oldState": "s0",
    "newState": "s1",
    "hasMoreChanges": "true",
    "created": [],
    "updated": [],
    "destroyed": [],
  }
  assertErr ChangesResponse[MockFoo].fromJson(j)

block changesResponseHasMoreAbsent:
  ## hasMoreChanges absent produces err.
  let j = %*{
    "accountId": "a1",
    "oldState": "s0",
    "newState": "s1",
    "created": [],
    "updated": [],
    "destroyed": [],
  }
  assertErr ChangesResponse[MockFoo].fromJson(j)

block changesResponseMissingNewState:
  ## Missing newState produces err.
  let j = %*{
    "accountId": "a1",
    "oldState": "s0",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
  }
  assertErr ChangesResponse[MockFoo].fromJson(j)

block changesResponseEmptyArrays:
  ## Empty created/updated/destroyed arrays are valid.
  let j = %*{
    "accountId": "a1",
    "oldState": "s0",
    "newState": "s1",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
  }
  let cr = ChangesResponse[MockFoo].fromJson(j).get()
  assertLen cr.created, 0

# ===========================================================================
# E. SetResponse fromJson tests
# ===========================================================================

block setResponseBothNull:
  ## Both created and notCreated null produces empty tables.
  let j = %*{"accountId": "a1", "newState": "s1"}
  let sr = SetResponse[MockFoo].fromJson(j).get()
  assertLen sr.created, 0
  assertLen sr.notCreated, 0
  assertLen sr.updated, 0
  assertLen sr.notUpdated, 0
  assertLen sr.destroyed, 0
  assertLen sr.notDestroyed, 0

block setResponseCreatedOnly:
  ## Created entries only -- all ok.
  let j = %*{"accountId": "a1", "newState": "s1", "created": {"k1": {"id": "id1"}}}
  let sr = SetResponse[MockFoo].fromJson(j).get()
  assertLen sr.created, 1
  doAssert makeCreationId("k1") in sr.created

block setResponseNotCreatedOnly:
  ## NotCreated entries only -- all err.
  let j =
    %*{"accountId": "a1", "newState": "s1", "notCreated": {"k1": {"type": "forbidden"}}}
  let sr = SetResponse[MockFoo].fromJson(j).get()
  assertLen sr.notCreated, 1
  doAssert makeCreationId("k1") in sr.notCreated

block setResponseMixedCreateResults:
  ## Mixed created and notCreated.
  let j = %*{
    "accountId": "a1",
    "newState": "s1",
    "created": {"k1": {"id": "id1"}},
    "notCreated": {"k2": {"type": "forbidden"}},
  }
  let sr = SetResponse[MockFoo].fromJson(j).get()
  assertLen sr.created, 1
  assertLen sr.notCreated, 1

block setResponseUpdatedNull:
  ## Updated entry with null value produces none.
  let j = %*{"accountId": "a1", "newState": "s1", "updated": {"id1": nil}}
  let sr = SetResponse[MockFoo].fromJson(j).get()
  doAssert sr.updated[makeId("id1")].isNone

block setResponseUpdatedObject:
  ## Updated entry with object value produces some.
  let j = %*{"accountId": "a1", "newState": "s1", "updated": {"id1": {"prop": "val"}}}
  let sr = SetResponse[MockFoo].fromJson(j).get()
  doAssert sr.updated[makeId("id1")].isSome

block setResponseDestroyedEmpty:
  ## Destroyed empty array produces empty destroyed.
  let j = %*{"accountId": "a1", "newState": "s1", "destroyed": []}
  let sr = SetResponse[MockFoo].fromJson(j).get()
  assertLen sr.destroyed, 0

block setResponseOldStateAbsent:
  ## OldState absent produces none.
  let j = %*{"accountId": "a1", "newState": "s1"}
  let sr = SetResponse[MockFoo].fromJson(j).get()
  doAssert sr.oldState.isNone

block setResponseNotCreatedMissingType:
  ## NotCreated value missing "type" field produces err.
  let j = %*{
    "accountId": "a1", "newState": "s1", "notCreated": {"k1": {"description": "oops"}}
  }
  assertErr SetResponse[MockFoo].fromJson(j)

block setResponseNotCreatedUnknownType:
  ## NotCreated unknown type produces err with setUnknown, rawType preserved.
  let j = %*{
    "accountId": "a1", "newState": "s1", "notCreated": {"k1": {"type": "futureError"}}
  }
  let sr = SetResponse[MockFoo].fromJson(j).get()
  let se = sr.notCreated[makeCreationId("k1")]
  doAssert se.errorType == setUnknown
  doAssert se.rawType == "futureError"

block setResponseDuplicateIdLastWriterWins:
  ## Same id in created and notCreated -- last writer (notCreated) wins.
  let j = %*{
    "accountId": "a1",
    "newState": "s1",
    "created": {"k1": {"id": "id1"}},
    "notCreated": {"k1": {"type": "forbidden"}},
  }
  let sr = SetResponse[MockFoo].fromJson(j).get()
  assertLen sr.created, 0
  assertLen sr.notCreated, 1
  doAssert makeCreationId("k1") in sr.notCreated

block setResponseMalformedNotCreatedEntry:
  ## Malformed notCreated entry (non-object) aborts entire merge with err.
  ## Documents strict abort behaviour under parse-don't-validate.
  let j = %*{"accountId": "a1", "newState": "s1", "notCreated": {"k1": 123}}
  assertErr SetResponse[MockFoo].fromJson(j)

# ===========================================================================
# F. CopyResponse fromJson tests
# ===========================================================================

block copyResponseAlreadyExists:
  ## All notCreated with alreadyExists.
  let j = %*{
    "fromAccountId": "from1",
    "accountId": "to1",
    "newState": "s1",
    "notCreated": {"k1": {"type": "alreadyExists", "existingId": "existing1"}},
  }
  let cr = CopyResponse[MockFoo].fromJson(j).get()
  let se = cr.notCreated[makeCreationId("k1")]
  doAssert se.errorType == setAlreadyExists

block copyResponseMalformedExistingId:
  ## Malformed existingId degrades to setUnknown with rawType preserved.
  let j = %*{
    "fromAccountId": "from1",
    "accountId": "to1",
    "newState": "s1",
    "notCreated": {"k1": {"type": "alreadyExists", "existingId": ""}},
  }
  let cr = CopyResponse[MockFoo].fromJson(j).get()
  let se = cr.notCreated[makeCreationId("k1")]
  doAssert se.rawType == "alreadyExists"

block copyResponseAllFailed:
  ## Created null, notCreated has entries -- all copies failed.
  let j = %*{
    "fromAccountId": "from1",
    "accountId": "to1",
    "newState": "s1",
    "notCreated": {"k1": {"type": "forbidden"}},
  }
  let cr = CopyResponse[MockFoo].fromJson(j).get()
  assertLen cr.notCreated, 1
  doAssert makeCreationId("k1") in cr.notCreated

block copyResponseValidCreated:
  ## Valid created entry with server-set id.
  let j = %*{
    "fromAccountId": "from1",
    "accountId": "to1",
    "newState": "s1",
    "created": {"k1": {"id": "newid1"}},
  }
  let cr = CopyResponse[MockFoo].fromJson(j).get()
  doAssert makeCreationId("k1") in cr.created

block copyResponseCreatedNullNotCreatedPresent:
  ## Created null + notCreated entries.
  let j = %*{
    "fromAccountId": "from1",
    "accountId": "to1",
    "newState": "s1",
    "notCreated": {"k1": {"type": "forbidden"}, "k2": {"type": "overQuota"}},
  }
  let cr = CopyResponse[MockFoo].fromJson(j).get()
  assertLen cr.notCreated, 2

# ===========================================================================
# G. QueryResponse fromJson tests
# ===========================================================================

block queryResponseHappyPath:
  ## Valid QueryResponse JSON.
  let j = %*{
    "accountId": "a1",
    "queryState": "qs1",
    "canCalculateChanges": true,
    "position": 0,
    "ids": ["x1", "x2"],
    "total": 100,
    "limit": 50,
  }
  let qr = QueryResponse[MockFoo].fromJson(j).get()
  assertLen qr.ids, 2
  doAssert qr.canCalculateChanges
  doAssert qr.total.isSome
  doAssert qr.limit.isSome

block queryResponseTotalAbsent:
  ## Total absent produces none.
  let j = %*{
    "accountId": "a1",
    "queryState": "qs1",
    "canCalculateChanges": false,
    "position": 0,
    "ids": [],
  }
  let qr = QueryResponse[MockFoo].fromJson(j).get()
  doAssert qr.total.isNone

block queryResponseLimitAbsent:
  ## Limit absent produces none.
  let j = %*{
    "accountId": "a1",
    "queryState": "qs1",
    "canCalculateChanges": false,
    "position": 0,
    "ids": [],
  }
  let qr = QueryResponse[MockFoo].fromJson(j).get()
  doAssert qr.limit.isNone

block queryResponseIdsEmpty:
  ## Empty ids array is valid (position >= total).
  let j = %*{
    "accountId": "a1",
    "queryState": "qs1",
    "canCalculateChanges": false,
    "position": 0,
    "ids": [],
  }
  assertOk QueryResponse[MockFoo].fromJson(j)

block queryResponsePositionWrongKind:
  ## Position is JString produces err.
  let j = %*{
    "accountId": "a1",
    "queryState": "qs1",
    "canCalculateChanges": false,
    "position": "wrong",
    "ids": [],
  }
  assertErr QueryResponse[MockFoo].fromJson(j)

block queryResponseCanCalculateChangesMissing:
  ## canCalculateChanges missing produces err.
  let j = %*{"accountId": "a1", "queryState": "qs1", "position": 0, "ids": []}
  assertErr QueryResponse[MockFoo].fromJson(j)

block queryResponseCanCalculateChangesWrongKind:
  ## canCalculateChanges is JInt produces err.
  let j = %*{
    "accountId": "a1",
    "queryState": "qs1",
    "canCalculateChanges": 1,
    "position": 0,
    "ids": [],
  }
  assertErr QueryResponse[MockFoo].fromJson(j)

# ===========================================================================
# H. QueryChangesResponse fromJson tests
# ===========================================================================

block queryChangesResponseHappyPath:
  ## Valid QueryChangesResponse with removed + added.
  let j = %*{
    "accountId": "a1",
    "oldQueryState": "qs0",
    "newQueryState": "qs1",
    "removed": ["r1"],
    "added": [{"id": "a1", "index": 0}],
  }
  let qcr = QueryChangesResponse[MockFoo].fromJson(j).get()
  assertLen qcr.removed, 1
  assertLen qcr.added, 1

block queryChangesResponseEmptyRemovedNonEmptyAdded:
  ## Empty removed with non-empty added is valid.
  let j = %*{
    "accountId": "a1",
    "oldQueryState": "qs0",
    "newQueryState": "qs1",
    "removed": [],
    "added": [{"id": "a1", "index": 0}],
  }
  let qcr = QueryChangesResponse[MockFoo].fromJson(j).get()
  assertLen qcr.removed, 0
  assertLen qcr.added, 1

block queryChangesResponseTotalAbsent:
  ## Total absent produces none.
  let j = %*{
    "accountId": "a1",
    "oldQueryState": "qs0",
    "newQueryState": "qs1",
    "removed": [],
    "added": [],
  }
  let qcr = QueryChangesResponse[MockFoo].fromJson(j).get()
  doAssert qcr.total.isNone

block queryChangesResponseTotalPresent:
  ## Total present with valid value.
  let j = %*{
    "accountId": "a1",
    "oldQueryState": "qs0",
    "newQueryState": "qs1",
    "total": 42,
    "removed": [],
    "added": [],
  }
  let qcr = QueryChangesResponse[MockFoo].fromJson(j).get()
  doAssert qcr.total.isSome

block queryChangesResponseAddedInvalidIndex:
  ## Added with invalid index propagates err from AddedItem.fromJson.
  let j = %*{
    "accountId": "a1",
    "oldQueryState": "qs0",
    "newQueryState": "qs1",
    "removed": [],
    "added": [{"id": "a1", "index": -1}],
  }
  assertErr QueryChangesResponse[MockFoo].fromJson(j)

# ===========================================================================
# I. Lenient Option helper tests
# ===========================================================================

block optStateLeniency:
  ## Test optState helper with multiple inputs.
  ## nil, JNull, wrong kind, empty string (invalid), valid string.
  # nil node -- absent key
  let absent = %*{"other": "val"}
  doAssert optState(absent, "oldState").isNone
  # JNull
  let jnull = %*{"oldState": nil}
  doAssert optState(jnull, "oldState").isNone
  # Wrong kind (JInt)
  let wrongKind = %*{"oldState": 42}
  doAssert optState(wrongKind, "oldState").isNone
  # Empty string (invalid for JmapState)
  let emptyStr = %*{"oldState": ""}
  doAssert optState(emptyStr, "oldState").isNone
  # Valid string
  let valid = %*{"oldState": "state1"}
  let result = optState(valid, "oldState")
  doAssert result.isSome
  doAssert result.get() == makeState("state1")

block optUnsignedIntLeniency:
  ## Test optUnsignedInt helper with multiple inputs.
  ## nil, JNull, wrong kind, negative (invalid), valid int.
  # nil node -- absent key
  let absent = %*{"other": "val"}
  doAssert optUnsignedInt(absent, "total").isNone
  # JNull
  let jnull = %*{"total": nil}
  doAssert optUnsignedInt(jnull, "total").isNone
  # Wrong kind (JString)
  let wrongKind = %*{"total": "42"}
  doAssert optUnsignedInt(wrongKind, "total").isNone
  # Negative (invalid for UnsignedInt)
  let negative = %*{"total": -1}
  doAssert optUnsignedInt(negative, "total").isNone
  # Valid int
  let valid = %*{"total": 100}
  let result = optUnsignedInt(valid, "total")
  doAssert result.isSome
