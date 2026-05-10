# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Request toJson and response fromJson tests for all six standard JMAP methods
## (RFC 8620 sections 5.1-5.6), plus SetResponse merging and CopyResponse
## merging. Covers golden tests sections 14.2 and 14.4, all Step 3 edge-case
## rows from section 14.6, and lenient Option helper coverage.

import std/json
import std/tables

import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/envelope
import jmap_client/internal/types/framework
import jmap_client/internal/types/errors
import jmap_client/internal/types/methods_enum
import jmap_client/internal/serialisation/serde
import jmap_client/internal/serialisation/serde_envelope
import jmap_client/internal/serialisation/serde_framework
import jmap_client/internal/protocol/entity
import jmap_client/internal/protocol/methods
import jmap_client/internal/protocol/builder

import ../massertions
import ../mfixtures

# ---------------------------------------------------------------------------
# Mock entity types (local -- compile-time verification only)
# ---------------------------------------------------------------------------

{.push ruleOff: "hasDoc".}
{.push ruleOff: "objects".}
{.push ruleOff: "params".}

type MockFoo = object

proc methodEntity*(T: typedesc[MockFoo]): MethodEntity =
  meTest

proc capabilityUri*(T: typedesc[MockFoo]): string =
  "urn:test:mockfoo"

proc getMethodName*(T: typedesc[MockFoo]): MethodName =
  mnMailboxGet

proc changesMethodName*(T: typedesc[MockFoo]): MethodName =
  mnMailboxChanges

proc setMethodName*(T: typedesc[MockFoo]): MethodName =
  mnMailboxSet

func fromJson*(
    T: typedesc[MockFoo], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[MockFoo, SerdeViolation] =
  ## Permissive MockFoo deserialiser — the promoted ``SetResponse[T]`` /
  ## ``CopyResponse[T]`` resolves ``T.fromJson`` via ``mixin`` at
  ## instantiation. Tests only assert ``isOk``/``isErr``; the concrete
  ## ``MockFoo()`` value is never inspected.
  discard $T
  ?expectKind(node, JObject, path)
  ok(MockFoo())

func toJson*(f: MockFoo): JsonNode =
  ## Permissive MockFoo serialiser — the widened ``SetRequest[T, C, U]`` /
  ## ``CopyRequest[T, CopyItem]`` generics resolve ``C.toJson`` /
  ## ``U.toJson`` via ``mixin`` at instantiation. Tests only assert the
  ## produced key set; the emitted object is never inspected.
  discard f
  newJObject()

template changesResponseType*(T: typedesc[MockFoo]): typedesc =
  ChangesResponse[MockFoo]

registerJmapEntity(MockFoo)

type MockFilter = object

type MockQueryable = object

proc methodEntity*(T: typedesc[MockQueryable]): MethodEntity =
  meTest

proc capabilityUri*(T: typedesc[MockQueryable]): string =
  "urn:test:mockqueryable"

proc getMethodName*(T: typedesc[MockQueryable]): MethodName =
  mnMailboxGet

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
# A. Golden tests (sections 14.2, 14.4)
# ===========================================================================

block goldenSetRequestToJson:
  ## Golden test section 14.2: SetRequest with create/destroy (common fields).
  ## ``SetRequest[T, C, U]`` carries ``update: Opt[U]`` — ``Opt.none`` emits
  ## no ``update`` key on the wire, keeping the wire shape byte-identical
  ## to the pre-widen golden.
  let acctId = makeAccountId("A13824")
  let ifState = makeState("abc123")
  let cid = makeCreationId("k1")
  let did1 = makeId("id2")
  let did2 = makeId("id3")
  var createTbl = initTable[CreationId, MockFoo]()
  createTbl[cid] = MockFoo()
  let req = SetRequest[MockFoo, MockFoo, MockFoo](
    accountId: acctId,
    ifInState: Opt.some(ifState),
    create: Opt.some(createTbl),
    update: Opt.none(MockFoo),
    destroy: Opt.some(direct(@[did1, did2])),
  )
  let j = req.toJson()
  doAssert j{"accountId"}.getStr("") == "A13824"
  doAssert j{"ifInState"}.getStr("") == "abc123"
  doAssert j{"create"}.kind == JObject
  doAssert j{"create"}{"k1"} != nil
  doAssert j{"update"}.isNil
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
  assertSomeEq sr.newState, makeState("state2")
  # createResults: k1 ok, k2 err (Decision 3.9B unified Result maps)
  assertLen sr.createResults, 2
  doAssert sr.createResults[makeCreationId("k1")].isOk
  doAssert sr.createResults[makeCreationId("k2")].isErr
  doAssert sr.createResults[makeCreationId("k2")].error().errorType == setForbidden
  # updateResults: id1 ok(none), id2 ok(some), id3 err
  assertLen sr.updateResults, 3
  doAssert sr.updateResults[makeId("id1")].isOk
  doAssert sr.updateResults[makeId("id1")].get().isNone
  doAssert sr.updateResults[makeId("id2")].isOk
  doAssert sr.updateResults[makeId("id2")].get().isSome
  doAssert sr.updateResults[makeId("id3")].isErr
  doAssert sr.updateResults[makeId("id3")].error().errorType == setNotFound
  # destroyResults: id4 ok, id5 err
  assertLen sr.destroyResults, 2
  doAssert sr.destroyResults[makeId("id4")].isOk
  doAssert sr.destroyResults[makeId("id5")].isErr
  doAssert sr.destroyResults[makeId("id5")].error().errorType == setForbidden

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
    initResultReference(resultOf = makeMcid("c0"), name = mnEmailQuery, path = rpIds)
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
  ## SetRequest with only accountId. ``SetRequest[T, C, U]`` with all
  ## optional fields ``Opt.none`` emits only ``accountId``; every other
  ## key (``ifInState``, ``create``, ``destroy``, ``update``) is absent.
  let req = SetRequest[MockFoo, MockFoo, MockFoo](
    accountId: makeAccountId("a1"),
    ifInState: Opt.none(JmapState),
    create: Opt.none(Table[CreationId, MockFoo]),
    update: Opt.none(MockFoo),
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
    initResultReference(resultOf = makeMcid("c0"), name = mnEmailQuery, path = rpIds)
  let req = SetRequest[MockFoo, MockFoo, MockFoo](
    accountId: makeAccountId("a1"),
    ifInState: Opt.none(JmapState),
    create: Opt.none(Table[CreationId, MockFoo]),
    update: Opt.none(MockFoo),
    destroy: Opt.some(referenceTo[seq[Id]](rr)),
  )
  let j = req.toJson()
  doAssert j{"destroy"}.isNil
  doAssert j{"#destroy"}.kind == JObject
  doAssert j{"#destroy"}{"resultOf"}.getStr("") == "c0"

block copyRequestMinimal:
  ## CopyRequest with required fields and ``keepOriginals()`` mode. Per
  ## RFC 8620 §5.4 spec default, ``onSuccessDestroyOriginal`` is OMITTED
  ## from the wire when the value would be ``false`` — the key is not
  ## emitted.
  var createTbl = initTable[CreationId, MockFoo]()
  createTbl[makeCreationId("k1")] = MockFoo()
  let req = CopyRequest[MockFoo, MockFoo](
    fromAccountId: makeAccountId("from1"),
    ifFromInState: Opt.none(JmapState),
    accountId: makeAccountId("to1"),
    ifInState: Opt.none(JmapState),
    create: createTbl,
    destroyMode: keepOriginals(),
  )
  let j = req.toJson()
  doAssert j{"fromAccountId"}.getStr("") == "from1"
  doAssert j{"accountId"}.getStr("") == "to1"
  doAssert j{"create"}.kind == JObject
  doAssert j{"onSuccessDestroyOriginal"}.isNil

block copyRequestOnSuccessTrue:
  ## CopyRequest with destroy-after-success mode emits
  ## ``onSuccessDestroyOriginal: true`` — the non-default case, where the
  ## server must take a side effect, is the only case the wire carries.
  var createTbl = initTable[CreationId, MockFoo]()
  createTbl[makeCreationId("k1")] = MockFoo()
  let req = CopyRequest[MockFoo, MockFoo](
    fromAccountId: makeAccountId("from1"),
    ifFromInState: Opt.none(JmapState),
    accountId: makeAccountId("to1"),
    ifInState: Opt.none(JmapState),
    create: createTbl,
    destroyMode: destroyAfterSuccess(),
  )
  let j = req.toJson()
  doAssert j{"onSuccessDestroyOriginal"}.getBool(false) == true

block queryRequestMinimal:
  ## addQuery with only required fields emits accountId and nothing else
  ## for the optional query window. ``anchorOffset`` is omitted when
  ## ``anchor`` is absent (see ``assembleQueryArgs`` for the rationale).
  let b0 = initRequestBuilder()
  let (b1, _) = addQuery[MockQueryable, MockFilter, Comparator](b0, makeAccountId("a1"))
  let args = b1.build().methodCalls[0].arguments
  doAssert args{"accountId"}.getStr("") == "a1"
  doAssert args{"filter"}.isNil
  doAssert args{"sort"}.isNil
  doAssert args{"position"}.getBiggestInt(-1) == 0
  doAssert args{"anchor"}.isNil
  doAssert args{"anchorOffset"}.isNil
  doAssert args{"calculateTotal"}.getBool(true) == false

block queryRequestWithFilter:
  ## addQuery with a filter condition emits ``filter`` in the invocation args.
  let b0 = initRequestBuilder()
  let (b1, _) = addQuery[MockQueryable, MockFilter, Comparator](
    b0, makeAccountId("a1"), filter = Opt.some(filterCondition(MockFilter()))
  )
  let args = b1.build().methodCalls[0].arguments
  doAssert args{"filter"}.kind == JObject
  doAssert args{"filter"}{"mock"}.getBool(false) == true

block queryChangesRequestMinimal:
  ## addQueryChanges with only required fields emits accountId +
  ## sinceQueryState; all other optional fields are absent (filter) or
  ## carry their default (calculateTotal: false).
  let b0 = initRequestBuilder()
  let (b1, _) = addQueryChanges[MockQueryable, MockFilter, Comparator](
    b0, makeAccountId("a1"), makeState("qs0")
  )
  let args = b1.build().methodCalls[0].arguments
  doAssert args{"sinceQueryState"}.getStr("") == "qs0"
  doAssert args{"calculateTotal"}.getBool(true) == false
  doAssert args{"filter"}.isNil

block queryChangesRequestAllFields:
  ## addQueryChanges with every optional field populated emits each one
  ## and preserves sort-array ordering.
  let comp =
    parseComparator(makePropertyName("name"), true, Opt.none(CollationAlgorithm))
  let b0 = initRequestBuilder()
  let (b1, _) = addQueryChanges[MockQueryable, MockFilter, Comparator](
    b0,
    makeAccountId("a1"),
    makeState("qs0"),
    filter = Opt.some(filterCondition(MockFilter())),
    sort = Opt.some(@[comp]),
    maxChanges = Opt.some(makeMaxChanges(10)),
    upToId = Opt.some(makeId("upTo1")),
    calculateTotal = true,
  )
  let args = b1.build().methodCalls[0].arguments
  doAssert args{"filter"}.kind == JObject
  doAssert args{"sort"}.kind == JArray
  doAssert args{"maxChanges"}.getBiggestInt(0) == 10
  doAssert args{"upToId"}.getStr("") == "upTo1"
  doAssert args{"calculateTotal"}.getBool(false) == true

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
  ## Both created and notCreated null produces empty Result tables.
  let j = %*{"accountId": "a1", "newState": "s1"}
  let sr = SetResponse[MockFoo].fromJson(j).get()
  assertLen sr.createResults, 0
  assertLen sr.updateResults, 0
  assertLen sr.destroyResults, 0

block setResponseMissingNewStateLenient:
  ## RFC 8620 §5.3 mandates newState; Stalwart 0.15.5 omits it
  ## for failed-only /set responses. Library is lenient on receive
  ## per Postel's law (Phase K0).
  let j = %*{"accountId": "a1"}
  let sr = SetResponse[MockFoo].fromJson(j).get()
  doAssert sr.newState.isNone

block copyResponseMissingNewStateLenient:
  ## Same lenience contract for CopyResponse.
  let j = %*{"fromAccountId": "from1", "accountId": "to1"}
  let cr = CopyResponse[MockFoo].fromJson(j).get()
  doAssert cr.newState.isNone

block setResponseCreatedOnly:
  ## Created entries only — all ok in unified Result map.
  let j = %*{"accountId": "a1", "newState": "s1", "created": {"k1": {"id": "id1"}}}
  let sr = SetResponse[MockFoo].fromJson(j).get()
  assertLen sr.createResults, 1
  doAssert sr.createResults[makeCreationId("k1")].isOk

block setResponseNotCreatedOnly:
  ## NotCreated entries only — all err in unified Result map.
  let j =
    %*{"accountId": "a1", "newState": "s1", "notCreated": {"k1": {"type": "forbidden"}}}
  let sr = SetResponse[MockFoo].fromJson(j).get()
  assertLen sr.createResults, 1
  doAssert sr.createResults[makeCreationId("k1")].isErr

block setResponseMixedCreateResults:
  ## Mixed created and notCreated in unified Result map.
  let j = %*{
    "accountId": "a1",
    "newState": "s1",
    "created": {"k1": {"id": "id1"}},
    "notCreated": {"k2": {"type": "forbidden"}},
  }
  let sr = SetResponse[MockFoo].fromJson(j).get()
  assertLen sr.createResults, 2
  doAssert sr.createResults[makeCreationId("k1")].isOk
  doAssert sr.createResults[makeCreationId("k2")].isErr

block setResponseUpdatedNull:
  ## Updated entry with null value produces ok(none) in unified Result map.
  let j = %*{"accountId": "a1", "newState": "s1", "updated": {"id1": nil}}
  let sr = SetResponse[MockFoo].fromJson(j).get()
  doAssert sr.updateResults[makeId("id1")].isOk
  doAssert sr.updateResults[makeId("id1")].get().isNone

block setResponseUpdatedObject:
  ## Updated entry with object value produces ok(some) in unified Result map.
  let j = %*{"accountId": "a1", "newState": "s1", "updated": {"id1": {"prop": "val"}}}
  let sr = SetResponse[MockFoo].fromJson(j).get()
  doAssert sr.updateResults[makeId("id1")].isOk
  doAssert sr.updateResults[makeId("id1")].get().isSome

block setResponseDestroyedEmpty:
  ## Destroyed empty array produces empty destroyResults.
  let j = %*{"accountId": "a1", "newState": "s1", "destroyed": []}
  let sr = SetResponse[MockFoo].fromJson(j).get()
  assertLen sr.destroyResults, 0

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
  doAssert sr.createResults[makeCreationId("k1")].isErr
  let se = sr.createResults[makeCreationId("k1")].error()
  doAssert se.errorType == setUnknown
  doAssert se.rawType == "futureError"

block setResponseDuplicateIdLastWriterWins:
  ## Same id in created and notCreated — last writer (notCreated) wins.
  ## Unified Result map: single entry, err (not two separate entries).
  let j = %*{
    "accountId": "a1",
    "newState": "s1",
    "created": {"k1": {"id": "id1"}},
    "notCreated": {"k1": {"type": "forbidden"}},
  }
  let sr = SetResponse[MockFoo].fromJson(j).get()
  assertLen sr.createResults, 1
  doAssert sr.createResults[makeCreationId("k1")].isErr

block setResponseMalformedNotCreatedEntry:
  ## Malformed notCreated entry (non-object) aborts entire merge with err.
  ## Documents strict abort behaviour under parse-don't-validate.
  let j = %*{"accountId": "a1", "newState": "s1", "notCreated": {"k1": 123}}
  assertErr SetResponse[MockFoo].fromJson(j)

# ===========================================================================
# F. CopyResponse fromJson tests
# ===========================================================================

block copyResponseAlreadyExists:
  ## All notCreated with alreadyExists — unified Result map err branch.
  let j = %*{
    "fromAccountId": "from1",
    "accountId": "to1",
    "newState": "s1",
    "notCreated": {"k1": {"type": "alreadyExists", "existingId": "existing1"}},
  }
  let cr = CopyResponse[MockFoo].fromJson(j).get()
  doAssert cr.createResults[makeCreationId("k1")].isErr
  let se = cr.createResults[makeCreationId("k1")].error()
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
  doAssert cr.createResults[makeCreationId("k1")].isErr
  let se = cr.createResults[makeCreationId("k1")].error()
  doAssert se.rawType == "alreadyExists"

block copyResponseAllFailed:
  ## Created null, notCreated has entries — all copies failed (unified err).
  let j = %*{
    "fromAccountId": "from1",
    "accountId": "to1",
    "newState": "s1",
    "notCreated": {"k1": {"type": "forbidden"}},
  }
  let cr = CopyResponse[MockFoo].fromJson(j).get()
  assertLen cr.createResults, 1
  doAssert cr.createResults[makeCreationId("k1")].isErr

block copyResponseValidCreated:
  ## Valid created entry with server-set id — unified ok branch.
  let j = %*{
    "fromAccountId": "from1",
    "accountId": "to1",
    "newState": "s1",
    "created": {"k1": {"id": "newid1"}},
  }
  let cr = CopyResponse[MockFoo].fromJson(j).get()
  doAssert cr.createResults[makeCreationId("k1")].isOk

block copyResponseCreatedNullNotCreatedPresent:
  ## Created null + notCreated entries — all err in unified map.
  let j = %*{
    "fromAccountId": "from1",
    "accountId": "to1",
    "newState": "s1",
    "notCreated": {"k1": {"type": "forbidden"}, "k2": {"type": "overQuota"}},
  }
  let cr = CopyResponse[MockFoo].fromJson(j).get()
  assertLen cr.createResults, 2
  doAssert cr.createResults[makeCreationId("k1")].isErr
  doAssert cr.createResults[makeCreationId("k2")].isErr

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
# J. SerializedSort / SerializedFilter distinct types
# ===========================================================================

block serializeOptSortNone:
  ## serializeOptSort with Opt.none produces Opt.none(SerializedSort).
  let result = serializeOptSort(Opt.none(seq[Comparator]))
  doAssert result.isNone

block serializeOptSortSome:
  ## serializeOptSort with a Comparator seq produces Opt.some(SerializedSort)
  ## containing a JArray with the expected shape.
  let comp =
    parseComparator(makePropertyName("name"), true, Opt.none(CollationAlgorithm))
  let result = serializeOptSort(Opt.some(@[comp]))
  doAssert result.isSome
  let arr = result.get().toJsonNode()
  doAssert arr.kind == JArray
  assertLen arr.getElems(@[]), 1
  doAssert arr[0]{"property"}.getStr("") == "name"
  doAssert arr[0]{"isAscending"}.getBool(false) == true

block serializeOptFilterNone:
  ## serializeOptFilter with Opt.none produces Opt.none(SerializedFilter).
  let result = serializeOptFilter(Opt.none(Filter[MockFilter]))
  doAssert result.isNone

block serializeOptFilterSome:
  ## serializeOptFilter with a filter tree produces serialised JSON.
  ## ``MockFilter.toJson`` resolves via the ``mixin toJson`` cascade.
  let f = filterCondition(MockFilter())
  let result = serializeOptFilter(Opt.some(f))
  doAssert result.isSome
  let node = result.get().toJsonNode()
  doAssert node{"mock"}.getBool(false) == true

block serializeFilterRequired:
  ## serializeFilter (non-Opt) wraps the filter JSON in SerializedFilter.
  let f = filterCondition(MockFilter())
  let result = serializeFilter(f)
  let node = result.toJsonNode()
  doAssert node{"mock"}.getBool(false) == true

block assembleQueryArgsMinimal:
  ## assembleQueryArgs with default QueryParams — minimal JSON. The
  ## ``anchorOffset`` field is meaningful only when ``anchor`` is set
  ## (RFC 8620 §5.5), so it is omitted from the wire when anchor is
  ## absent — strict servers (Apache James 3.9) reject it otherwise.
  let j = assembleQueryArgs(
    makeAccountId("a1"),
    Opt.none(SerializedFilter),
    Opt.none(SerializedSort),
    QueryParams(),
  )
  doAssert j{"accountId"}.getStr("") == "a1"
  doAssert j{"filter"}.isNil
  doAssert j{"sort"}.isNil
  doAssert j{"position"}.getBiggestInt(-1) == 0
  doAssert j{"anchor"}.isNil
  doAssert j{"anchorOffset"}.isNil
  doAssert j{"calculateTotal"}.getBool(true) == false

block assembleQueryArgsAllFields:
  ## assembleQueryArgs with all fields populated.
  let comp =
    parseComparator(makePropertyName("name"), true, Opt.none(CollationAlgorithm))
  let f = filterCondition(MockFilter())
  let qp = QueryParams(
    position: JmapInt(5),
    anchor: Opt.some(makeId("anchor1")),
    anchorOffset: JmapInt(-2),
    limit: Opt.some(parseUnsignedInt(25).get()),
    calculateTotal: true,
  )
  let j = assembleQueryArgs(
    makeAccountId("a1"),
    serializeOptFilter(Opt.some(f)),
    serializeOptSort(Opt.some(@[comp])),
    qp,
  )
  doAssert j{"accountId"}.getStr("") == "a1"
  doAssert j{"filter"}{"mock"}.getBool(false) == true
  doAssert j{"sort"}.kind == JArray
  assertLen j{"sort"}.getElems(@[]), 1
  doAssert j{"position"}.getBiggestInt(0) == 5
  doAssert j{"anchor"}.getStr("") == "anchor1"
  doAssert j{"anchorOffset"}.getBiggestInt(0) == -2
  doAssert j{"limit"}.getBiggestInt(0) == 25
  doAssert j{"calculateTotal"}.getBool(false) == true

block assembleQueryChangesArgsMinimal:
  ## assembleQueryChangesArgs with only required fields.
  let j = assembleQueryChangesArgs(
    makeAccountId("a1"),
    makeState("qs0"),
    Opt.none(SerializedFilter),
    Opt.none(SerializedSort),
    Opt.none(MaxChanges),
    Opt.none(Id),
    false,
  )
  doAssert j{"accountId"}.getStr("") == "a1"
  doAssert j{"sinceQueryState"}.getStr("") == "qs0"
  doAssert j{"filter"}.isNil
  doAssert j{"sort"}.isNil
  doAssert j{"maxChanges"}.isNil
  doAssert j{"upToId"}.isNil
  doAssert j{"calculateTotal"}.getBool(true) == false

block assembleQueryChangesArgsAllFields:
  ## assembleQueryChangesArgs with all fields populated.
  let comp =
    parseComparator(makePropertyName("name"), true, Opt.none(CollationAlgorithm))
  let f = filterCondition(MockFilter())
  let j = assembleQueryChangesArgs(
    makeAccountId("a1"),
    makeState("qs0"),
    serializeOptFilter(Opt.some(f)),
    serializeOptSort(Opt.some(@[comp])),
    Opt.some(makeMaxChanges(10)),
    Opt.some(makeId("upTo1")),
    true,
  )
  doAssert j{"filter"}{"mock"}.getBool(false) == true
  doAssert j{"sort"}.kind == JArray
  doAssert j{"sinceQueryState"}.getStr("") == "qs0"
  doAssert j{"maxChanges"}.getBiggestInt(0) == 10
  doAssert j{"upToId"}.getStr("") == "upTo1"
  doAssert j{"calculateTotal"}.getBool(false) == true

block serializedSortFilterTypeSafety:
  ## SerializedSort and SerializedFilter are distinct — cannot assign between them.
  assertNotCompiles:
    let s = SerializedSort(newJArray())
    let f: SerializedFilter = s
  assertNotCompiles:
    let f = SerializedFilter(newJObject())
    let s: SerializedSort = f
