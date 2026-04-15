# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Standard method request and response types for the six JMAP methods
## (RFC 8620 sections 5.1-5.6): get, changes, set, copy, query, queryChanges.
##
## Request types receive ``toJson`` (Pattern L3-A); response types receive
## ``fromJson`` (Pattern L3-B). Serialisation is unidirectional (Decision D3.7).
## ``SetResponse`` and ``CopyResponse`` merging follows Pattern L3-C (section 8).
##
## Entity data is raw ``JsonNode`` (Decision D3.6) -- entity-specific parsing
## is the caller's responsibility.

{.push raises: [], noSideEffect.}

import std/json
import std/tables

import ./types
import ./serialisation

# =============================================================================
# Lenient Option helpers (internal, not exported)
# =============================================================================

func optState*(node: JsonNode, key: string): Opt[JmapState] =
  ## Lenient optional JmapState extraction (section 5a.5 leniency).
  ## Absent, null, wrong kind, or invalid content all produce none.
  return parseJmapState((?optJsonField(node, key, JString)).getStr("")).optValue

func optUnsignedInt*(node: JsonNode, key: string): Opt[UnsignedInt] =
  ## Lenient optional UnsignedInt extraction (section 5a.5 leniency).
  ## Absent, null, wrong kind, or invalid content all produce none.
  return parseUnsignedInt((?optJsonField(node, key, JInt)).getBiggestInt(0)).optValue

# =============================================================================
# Request type definitions (section 6)
# =============================================================================

type GetRequest*[T] = object
  ## Request arguments for Foo/get (RFC 8620 section 5.1).
  ## Fetches objects of type T by their identifiers, optionally returning
  ## only a subset of properties.
  accountId*: AccountId ## The identifier of the account to use.
  ids*: Opt[Referencable[seq[Id]]]
    ## The identifiers of the Foo objects to return. If none, all records
    ## of the data type are returned. Referencable: may be a direct seq or
    ## a result reference to a previous call's output.
  properties*: Opt[seq[string]]
    ## If supplied, only the listed properties are returned for each object.
    ## The "id" property is always returned even if not explicitly requested.

type ChangesRequest*[T] = object
  ## Request arguments for Foo/changes (RFC 8620 section 5.2).
  ## Retrieves identifiers for records that have changed since a given state.
  accountId*: AccountId ## The identifier of the account to use.
  sinceState*: JmapState
    ## The current state of the client, as returned in a previous Foo/get
    ## response. The server returns changes since this state.
  maxChanges*: Opt[MaxChanges]
    ## The maximum number of identifiers to return. Must be > 0 per RFC
    ## (enforced by the MaxChanges smart constructor).

type SetRequest*[T] = object
  ## Request arguments for Foo/set (RFC 8620 section 5.3).
  ## Creates, updates, and/or destroys records of type T in a single method
  ## call. Each operation is atomic; the method as a whole is NOT atomic.
  accountId*: AccountId ## The identifier of the account to use.
  ifInState*: Opt[JmapState]
    ## If supplied, must match the current state; otherwise the method is
    ## aborted with a "stateMismatch" error.
  create*: Opt[Table[CreationId, JsonNode]]
    ## A map of creation identifiers to entity data objects. Entity data is
    ## JsonNode because Layer 3 Core cannot know T's serialisation format.
  destroy*: Opt[Referencable[seq[Id]]]
    ## A list of identifiers for records to permanently delete. Referencable:
    ## may be a direct seq or a result reference.

type CopyRequest*[T] = object
  ## Request arguments for Foo/copy (RFC 8620 section 5.4).
  ## Copies records from one account to another.
  fromAccountId*: AccountId ## The identifier of the account to copy records from.
  ifFromInState*: Opt[JmapState]
    ## If supplied, must match the current state of the from-account.
  accountId*: AccountId ## The identifier of the account to copy records to.
  ifInState*: Opt[JmapState]
    ## If supplied, must match the current state of the destination account.
  create*: Table[CreationId, JsonNode]
    ## A map of creation identifiers to entity data objects. Required (not
    ## optional). Each Foo object must contain an "id" property referencing
    ## the record in the from-account.
  onSuccessDestroyOriginal*: bool
    ## If true, the server attempts to destroy the originals after successful
    ## copies via an implicit Foo/set call.
  destroyFromIfInState*: Opt[JmapState]
    ## Passed as "ifInState" to the implicit Foo/set call when
    ## onSuccessDestroyOriginal is true.

type QueryRequest*[T, C] = object
  ## Request arguments for Foo/query (RFC 8620 section 5.5).
  ## Searches, sorts, and windows the data type on the server, returning
  ## a list of identifiers matching the criteria. ``C`` is the filter
  ## condition type, resolved from ``filterType(T)`` by the builder.
  accountId*: AccountId ## The identifier of the account to use.
  filter*: Opt[Filter[C]]
    ## Determines the set of Foos returned. Generic over the filter
    ## condition type C (resolved from filterType(T) at the call site).
  sort*: Opt[seq[Comparator]]
    ## Sort criteria. If none or empty, sort order is server-dependent but
    ## must be stable between calls.
  position*: JmapInt
    ## The zero-based index of the first identifier to return. Default: 0.
    ## Negative values are offset from the end. Ignored if anchor is supplied.
  anchor*: Opt[Id] ## A Foo identifier. If supplied, position is ignored.
  anchorOffset*: JmapInt
    ## The index of the first result relative to the anchor's index.
    ## May be negative. Default: 0.
  limit*: Opt[UnsignedInt] ## The maximum number of results to return.
  calculateTotal*: bool ## Whether the client wishes to know the total number of results.

type QueryChangesRequest*[T, C] = object
  ## Request arguments for Foo/queryChanges (RFC 8620 section 5.6).
  ## Efficiently updates a cached query to match the new server state.
  ## ``C`` is the filter condition type, resolved from ``filterType(T)``
  ## by the builder.
  accountId*: AccountId ## The identifier of the account to use.
  filter*: Opt[Filter[C]]
    ## The filter argument that was used with the original Foo/query.
  sort*: Opt[seq[Comparator]]
    ## The sort argument that was used with the original Foo/query.
  sinceQueryState*: JmapState
    ## The current state of the query in the client, as returned by a
    ## previous Foo/query response with the same sort/filter.
  maxChanges*: Opt[MaxChanges] ## The maximum number of changes to return.
  upToId*: Opt[Id]
    ## The last (highest-index) identifier the client has cached.
    ## Optimisation: only applies when sort and filter are both on
    ## immutable properties.
  calculateTotal*: bool ## Whether the client wishes to know the total number of results.

# =============================================================================
# Response type definitions (section 7)
# =============================================================================

type GetResponse*[T] = object
  ## Response arguments for Foo/get (RFC 8620 section 5.1).
  ## Contains the requested objects and any identifiers not found.
  accountId*: AccountId ## The identifier of the account used for the call.
  state*: JmapState
    ## A string representing the state on the server for ALL data of this
    ## type in the account. If the data changes, this string must change.
  list*: seq[JsonNode]
    ## The Foo objects requested. Raw JsonNode entities -- entity-specific
    ## parsing is the caller's responsibility (Decision D3.6).
  notFound*: seq[Id] ## Identifiers passed to the method for records that do not exist.

type ChangesResponse*[T] = object
  ## Response arguments for Foo/changes (RFC 8620 section 5.2).
  ## Lists identifiers for records that have been created, updated, or
  ## destroyed since the given state.
  accountId*: AccountId ## The identifier of the account used for the call.
  oldState*: JmapState ## The "sinceState" argument echoed back.
  newState*: JmapState ## The state the client will be in after applying the changes.
  hasMoreChanges*: bool
    ## If true, the client may call Foo/changes again with newState to get
    ## further updates.
  created*: seq[Id] ## Identifiers for records created since the old state.
  updated*: seq[Id] ## Identifiers for records updated since the old state.
  destroyed*: seq[Id] ## Identifiers for records destroyed since the old state.

type SetResponse*[T] = object
  ## Response arguments for Foo/set (RFC 8620 section 5.3).
  ## Wire format uses parallel maps (created/notCreated, etc.); the internal
  ## representation merges these into unified Result maps (Decision 3.9B).
  ## Each identifier has exactly one outcome — impossible for an ID to
  ## appear in both success and failure branches.
  accountId*: AccountId ## The identifier of the account used for the call.
  oldState*: Opt[JmapState]
    ## The state before making the requested changes, or none if the server
    ## does not know the previous state.
  newState*: JmapState ## The state that will now be returned by Foo/get.
  createResults*: Table[CreationId, Result[JsonNode, SetError]]
    ## Merged create outcomes. Wire ``created`` entries become
    ## ``Result.ok(entityJson)``; wire ``notCreated`` entries become
    ## ``Result.err(setError)``. Last-writer-wins on duplicate keys.
  updateResults*: Table[Id, Result[Opt[JsonNode], SetError]]
    ## Merged update outcomes. Wire ``updated`` entries with null value
    ## become ``ok(Opt.none(JsonNode))``; non-null values become
    ## ``ok(Opt.some(entityJson))``. Wire ``notUpdated`` entries become
    ## ``Result.err(setError)``.
  destroyResults*: Table[Id, Result[void, SetError]]
    ## Merged destroy outcomes. Wire ``destroyed`` entries become
    ## ``Result.ok()``; wire ``notDestroyed`` entries become
    ## ``Result.err(setError)``.

type CopyResponse*[T] = object
  ## Response arguments for Foo/copy (RFC 8620 section 5.4).
  ## Structurally similar to SetResponse but only has create results.
  ## Uses unified Result maps (Decision 3.9B).
  fromAccountId*: AccountId ## The identifier of the account records were copied from.
  accountId*: AccountId ## The identifier of the account records were copied to.
  oldState*: Opt[JmapState] ## The state of the destination account before the copy.
  newState*: JmapState
    ## The state that will now be returned by Foo/get on the destination
    ## account.
  createResults*: Table[CreationId, Result[JsonNode, SetError]]
    ## Merged copy outcomes. Same merging semantics as SetResponse
    ## create branch (Decision 3.9B).

type QueryResponse*[T] = object
  ## Response arguments for Foo/query (RFC 8620 section 5.5).
  ## Returns a windowed list of identifiers matching the query criteria.
  accountId*: AccountId ## The identifier of the account used for the call.
  queryState*: JmapState
    ## A string encoding the current state of the query on the server.
  canCalculateChanges*: bool
    ## True if the server supports calling Foo/queryChanges with these
    ## filter/sort parameters.
  position*: UnsignedInt
    ## The zero-based index of the first result in the ids array within the
    ## complete list of query results.
  ids*: seq[Id] ## The list of identifiers for each Foo in the query results.
  total*: Opt[UnsignedInt]
    ## The total number of Foos matching the filter. Only present if
    ## calculateTotal was true in the request.
  limit*: Opt[UnsignedInt]
    ## The limit enforced by the server. Only returned if the server set a
    ## limit or used a different limit than requested.

type QueryChangesResponse*[T] = object
  ## Response arguments for Foo/queryChanges (RFC 8620 section 5.6).
  ## Allows a client to update a cached query to match the new server state
  ## via a splice algorithm.
  accountId*: AccountId ## The identifier of the account used for the call.
  oldQueryState*: JmapState ## The "sinceQueryState" argument echoed back.
  newQueryState*: JmapState ## The state the query will be in after applying the changes.
  total*: Opt[UnsignedInt]
    ## The total number of Foos matching the filter. Only present if
    ## calculateTotal was true in the request.
  removed*: seq[Id]
    ## Identifiers for every Foo that was in the query results in the old
    ## state but is not in the new state.
  added*: seq[AddedItem]
    ## The identifier and index in the new query results for every Foo that
    ## has been added since the old state AND every Foo in the current results
    ## that was included in removed (due to mutable property changes).

# =============================================================================
# Pre-serialised wrappers (serialise-then-assemble pattern)
# =============================================================================

type
  SerializedSort* = distinct JsonNode
    ## Pre-serialised sort array. Wraps an already-serialised JArray.
    ## Distinct from SerializedFilter — newtype prevents accidental swap.
  SerializedFilter* = distinct JsonNode
    ## Pre-serialised filter tree. Wraps an already-serialised JObject/JArray.

func toJsonNode*(s: SerializedSort): JsonNode =
  ## Unwrap a pre-serialised sort array to its underlying JsonNode.
  JsonNode(s)

func toJsonNode*(f: SerializedFilter): JsonNode =
  ## Unwrap a pre-serialised filter tree to its underlying JsonNode.
  JsonNode(f)

# =============================================================================
# Serialisers
# =============================================================================

func serializeOptSort*[S](sort: Opt[seq[S]]): Opt[SerializedSort] =
  ## Pre-serialise an optional sort array. Generic over sort element type.
  ## Resolves ``toJson`` via ``mixin`` at instantiation site — works for
  ## both ``Comparator`` and ``EmailComparator``.
  mixin toJson
  for sortSeq in sort:
    var arr = newJArray()
    for c in sortSeq:
      arr.add(c.toJson())
    return Opt.some(SerializedSort(arr))
  Opt.none(SerializedSort)

func serializeOptFilter*[C](
    filter: Opt[Filter[C]],
    filterConditionToJson: proc(c: C): JsonNode {.noSideEffect, raises: [].},
): Opt[SerializedFilter] =
  ## Pre-serialise an optional filter tree via the entity-specific callback.
  for f in filter:
    return Opt.some(SerializedFilter(f.toJson(filterConditionToJson)))
  Opt.none(SerializedFilter)

func serializeFilter*[C](
    filter: Filter[C],
    filterConditionToJson: proc(c: C): JsonNode {.noSideEffect, raises: [].},
): SerializedFilter =
  ## Pre-serialise a required filter tree. Non-Opt variant for builders
  ## where the filter is mandatory (e.g. SearchSnippet/get).
  SerializedFilter(filter.toJson(filterConditionToJson))

# =============================================================================
# Assembly functions
# =============================================================================

func assembleQueryArgs*(
    accountId: AccountId,
    filter: Opt[SerializedFilter],
    sort: Opt[SerializedSort],
    queryParams: QueryParams,
): JsonNode =
  ## Build standard Foo/query request arguments from pre-serialised parts.
  ## Single source of truth for the query protocol frame.
  var node = newJObject()
  node["accountId"] = accountId.toJson()
  for f in filter:
    node["filter"] = f.toJsonNode()
  for s in sort:
    node["sort"] = s.toJsonNode()
  node["position"] = queryParams.position.toJson()
  for a in queryParams.anchor:
    node["anchor"] = a.toJson()
  node["anchorOffset"] = queryParams.anchorOffset.toJson()
  for lim in queryParams.limit:
    node["limit"] = lim.toJson()
  node["calculateTotal"] = %queryParams.calculateTotal
  return node

func assembleQueryChangesArgs*(
    accountId: AccountId,
    sinceQueryState: JmapState,
    filter: Opt[SerializedFilter],
    sort: Opt[SerializedSort],
    maxChanges: Opt[MaxChanges],
    upToId: Opt[Id],
    calculateTotal: bool,
): JsonNode =
  ## Build standard Foo/queryChanges request arguments from pre-serialised parts.
  var node = newJObject()
  node["accountId"] = accountId.toJson()
  for f in filter:
    node["filter"] = f.toJsonNode()
  for s in sort:
    node["sort"] = s.toJsonNode()
  node["sinceQueryState"] = sinceQueryState.toJson()
  for mc in maxChanges:
    node["maxChanges"] = mc.toJson()
  for uid in upToId:
    node["upToId"] = uid.toJson()
  node["calculateTotal"] = %calculateTotal
  return node

# =============================================================================
# Request toJson (Pattern L3-A)
# =============================================================================

func toJson*[T](req: GetRequest[T]): JsonNode =
  ## Serialise GetRequest to JSON arguments object (RFC 8620 section 5.1).
  ## Omits ``ids`` and ``properties`` when none.
  ## Dispatches Referencable ids via referencableKey.
  var node = newJObject()
  node["accountId"] = req.accountId.toJson()
  for idsVal in req.ids:
    let idsKey = referencableKey("ids", idsVal)
    case idsVal.kind
    of rkDirect:
      var arr = newJArray()
      for id in idsVal.value:
        arr.add(id.toJson())
      node[idsKey] = arr
    of rkReference:
      node[idsKey] = idsVal.reference.toJson()
  for props in req.properties:
    var arr = newJArray()
    for p in props:
      arr.add(%p)
    node["properties"] = arr
  return node

func toJson*[T](req: ChangesRequest[T]): JsonNode =
  ## Serialise ChangesRequest to JSON arguments object (RFC 8620 section 5.2).
  ## Omits ``maxChanges`` when none.
  var node = newJObject()
  node["accountId"] = req.accountId.toJson()
  node["sinceState"] = req.sinceState.toJson()
  for mc in req.maxChanges:
    node["maxChanges"] = mc.toJson()
  return node

func toJson*[T](req: SetRequest[T]): JsonNode =
  ## Serialise SetRequest to JSON arguments object (RFC 8620 section 5.3).
  ## Common fields only — ``update`` is assembled by entity-specific
  ## builders from their typed update algebras (``EmailUpdateSet``,
  ## ``MailboxUpdateSet``, ``VacationResponseUpdateSet``) and merged into
  ## the args after this call returns.
  var node = newJObject()
  node["accountId"] = req.accountId.toJson()
  for s in req.ifInState:
    node["ifInState"] = s.toJson()
  for createMap in req.create:
    var createObj = newJObject()
    for k, v in createMap:
      createObj[string(k)] = v
    node["create"] = createObj
  for destroyVal in req.destroy:
    let destroyKey = referencableKey("destroy", destroyVal)
    case destroyVal.kind
    of rkDirect:
      var arr = newJArray()
      for id in destroyVal.value:
        arr.add(id.toJson())
      node[destroyKey] = arr
    of rkReference:
      node[destroyKey] = destroyVal.reference.toJson()
  return node

func toJson*[T](req: CopyRequest[T]): JsonNode =
  ## Serialise CopyRequest to JSON arguments object (RFC 8620 section 5.4).
  ## ``create`` is required (always emitted). ``onSuccessDestroyOriginal``
  ## always emitted.
  var node = newJObject()
  node["fromAccountId"] = req.fromAccountId.toJson()
  for s in req.ifFromInState:
    node["ifFromInState"] = s.toJson()
  node["accountId"] = req.accountId.toJson()
  for s in req.ifInState:
    node["ifInState"] = s.toJson()
  var createObj = newJObject()
  for k, v in req.create:
    createObj[string(k)] = v
  node["create"] = createObj
  node["onSuccessDestroyOriginal"] = %req.onSuccessDestroyOriginal
  for s in req.destroyFromIfInState:
    node["destroyFromIfInState"] = s.toJson()
  return node

func toJson*[T, C](
    req: QueryRequest[T, C],
    filterConditionToJson: proc(c: C): JsonNode {.noSideEffect, raises: [].},
): JsonNode =
  ## Serialise QueryRequest to JSON arguments object (RFC 8620 section 5.5).
  ## Delegates to ``assembleQueryArgs`` — single source of truth for the
  ## query protocol frame.
  assembleQueryArgs(
    req.accountId,
    serializeOptFilter(req.filter, filterConditionToJson),
    serializeOptSort(req.sort),
    QueryParams(
      position: req.position,
      anchor: req.anchor,
      anchorOffset: req.anchorOffset,
      limit: req.limit,
      calculateTotal: req.calculateTotal,
    ),
  )

func toJson*[T, C](
    req: QueryChangesRequest[T, C],
    filterConditionToJson: proc(c: C): JsonNode {.noSideEffect, raises: [].},
): JsonNode =
  ## Serialise QueryChangesRequest to JSON arguments object
  ## (RFC 8620 section 5.6). Delegates to ``assembleQueryChangesArgs`` —
  ## single source of truth for the queryChanges protocol frame.
  assembleQueryChangesArgs(
    req.accountId,
    req.sinceQueryState,
    serializeOptFilter(req.filter, filterConditionToJson),
    serializeOptSort(req.sort),
    req.maxChanges,
    req.upToId,
    req.calculateTotal,
  )

# =============================================================================
# SetResponse merging helpers (section 8)
# =============================================================================

func mergeCreateResults(
    node: JsonNode
): Result[Table[CreationId, Result[JsonNode, SetError]], ValidationError] =
  ## Merge wire ``created``/``notCreated`` maps into a unified Result table
  ## (RFC 8620 section 5.3, Decision 3.9B). Used by both SetResponse and
  ## CopyResponse. Last-writer-wins for duplicate keys (section 8.5).
  var tbl = initTable[CreationId, Result[JsonNode, SetError]]()
  let createdNode = node{"created"}
  if not createdNode.isNil and createdNode.kind == JObject:
    for k, v in createdNode.pairs:
      let cid = ?parseCreationId(k)
      tbl[cid] = Result[JsonNode, SetError].ok(v)
  let notCreatedNode = node{"notCreated"}
  if not notCreatedNode.isNil and notCreatedNode.kind == JObject:
    for k, v in notCreatedNode.pairs:
      let cid = ?parseCreationId(k)
      let se = ?SetError.fromJson(v)
      tbl[cid] = Result[JsonNode, SetError].err(se)
  return ok(tbl)

func mergeUpdateResults(
    node: JsonNode
): Result[Table[Id, Result[Opt[JsonNode], SetError]], ValidationError] =
  ## Merge wire ``updated``/``notUpdated`` maps into a unified Result table
  ## (RFC 8620 section 5.3, Decision 3.9B). Null value in ``updated`` means
  ## no server-set properties changed; non-null contains changed properties.
  ## Last-writer-wins for duplicate keys (section 8.5).
  var tbl = initTable[Id, Result[Opt[JsonNode], SetError]]()
  let updatedNode = node{"updated"}
  if not updatedNode.isNil and updatedNode.kind == JObject:
    for k, v in updatedNode.pairs:
      let id = ?parseIdFromServer(k)
      if v.isNil or v.kind == JNull:
        tbl[id] = Result[Opt[JsonNode], SetError].ok(Opt.none(JsonNode))
      else:
        tbl[id] = Result[Opt[JsonNode], SetError].ok(Opt.some(v))
  let notUpdatedNode = node{"notUpdated"}
  if not notUpdatedNode.isNil and notUpdatedNode.kind == JObject:
    for k, v in notUpdatedNode.pairs:
      let id = ?parseIdFromServer(k)
      let se = ?SetError.fromJson(v)
      tbl[id] = Result[Opt[JsonNode], SetError].err(se)
  return ok(tbl)

func mergeDestroyResults(
    node: JsonNode
): Result[Table[Id, Result[void, SetError]], ValidationError] =
  ## Merge wire ``destroyed``/``notDestroyed`` into a unified Result table
  ## (RFC 8620 section 5.3, Decision 3.9B). ``destroyed`` is a flat array
  ## on the wire; each ID becomes ``Result.ok()``. ``notDestroyed`` entries
  ## become ``Result.err(setError)``. Last-writer-wins on duplicate keys.
  var tbl = initTable[Id, Result[void, SetError]]()
  let destroyedNode = node{"destroyed"}
  if not destroyedNode.isNil and destroyedNode.kind == JArray:
    for _, elem in destroyedNode.getElems(@[]):
      let id = ?parseIdFromServer(elem.getStr(""))
      tbl[id] = Result[void, SetError].ok()
  let notDestroyedNode = node{"notDestroyed"}
  if not notDestroyedNode.isNil and notDestroyedNode.kind == JObject:
    for k, v in notDestroyedNode.pairs:
      let id = ?parseIdFromServer(k)
      let se = ?SetError.fromJson(v)
      tbl[id] = Result[void, SetError].err(se)
  return ok(tbl)

# =============================================================================
# Response fromJson (Pattern L3-B)
# =============================================================================

func fromJson*[T](
    R: typedesc[GetResponse[T]], node: JsonNode
): Result[GetResponse[T], ValidationError] =
  ## Deserialise JSON arguments to GetResponse (RFC 8620 section 5.1).
  ## Uses lenient constructors for server-assigned identifiers. ``list``
  ## contains raw JsonNode entities -- entity-specific parsing is the
  ## caller's responsibility.
  ?checkJsonKind(node, JObject, $R)
  let accountId = ?parseAccountId(node{"accountId"}.getStr(""))
  let state = ?parseJmapState(node{"state"}.getStr(""))
  let listNode = node{"list"}
  ?checkJsonKind(listNode, JArray, "GetResponse", "list must be array")
  let list = listNode.getElems(@[])
  let notFound = ?parseOptIdArray(node{"notFound"})
  return ok(
    GetResponse[T](accountId: accountId, state: state, list: list, notFound: notFound)
  )

func fromJson*[T](
    R: typedesc[ChangesResponse[T]], node: JsonNode
): Result[ChangesResponse[T], ValidationError] =
  ## Deserialise JSON arguments to ChangesResponse (RFC 8620 section 5.2).
  ?checkJsonKind(node, JObject, $R)
  let accountId = ?parseAccountId(node{"accountId"}.getStr(""))
  let oldState = ?parseJmapState(node{"oldState"}.getStr(""))
  let newState = ?parseJmapState(node{"newState"}.getStr(""))
  let hmcNode = node{"hasMoreChanges"}
  ?checkJsonKind(hmcNode, JBool, "ChangesResponse", "hasMoreChanges must be boolean")
  let hasMoreChanges = hmcNode.getBool(false)
  let created = ?parseIdArray(node{"created"}, "ChangesResponse", "created")
  let updated = ?parseIdArray(node{"updated"}, "ChangesResponse", "updated")
  let destroyed = ?parseIdArray(node{"destroyed"}, "ChangesResponse", "destroyed")
  return ok(
    ChangesResponse[T](
      accountId: accountId,
      oldState: oldState,
      newState: newState,
      hasMoreChanges: hasMoreChanges,
      created: created,
      updated: updated,
      destroyed: destroyed,
    )
  )

func fromJson*[T](
    R: typedesc[SetResponse[T]], node: JsonNode
): Result[SetResponse[T], ValidationError] =
  ## Deserialise JSON arguments to SetResponse (RFC 8620 section 5.3).
  ## Merges parallel wire maps into separate success/failure tables (section 8).
  ?checkJsonKind(node, JObject, $R)
  let accountId = ?parseAccountId(node{"accountId"}.getStr(""))
  let newState = ?parseJmapState(node{"newState"}.getStr(""))
  let oldState = optState(node, "oldState")
  let createResults = ?mergeCreateResults(node)
  let updateResults = ?mergeUpdateResults(node)
  let destroyResults = ?mergeDestroyResults(node)
  return ok(
    SetResponse[T](
      accountId: accountId,
      newState: newState,
      oldState: oldState,
      createResults: createResults,
      updateResults: updateResults,
      destroyResults: destroyResults,
    )
  )

func fromJson*[T](
    R: typedesc[CopyResponse[T]], node: JsonNode
): Result[CopyResponse[T], ValidationError] =
  ## Deserialise JSON arguments to CopyResponse (RFC 8620 section 5.4).
  ## Merges created/notCreated wire maps into separate success/failure
  ## tables (section 8).
  ?checkJsonKind(node, JObject, $R)
  let fromAccountId = ?parseAccountId(node{"fromAccountId"}.getStr(""))
  let accountId = ?parseAccountId(node{"accountId"}.getStr(""))
  let newState = ?parseJmapState(node{"newState"}.getStr(""))
  let oldState = optState(node, "oldState")
  let createResults = ?mergeCreateResults(node)
  return ok(
    CopyResponse[T](
      fromAccountId: fromAccountId,
      accountId: accountId,
      newState: newState,
      oldState: oldState,
      createResults: createResults,
    )
  )

func fromJson*[T](
    R: typedesc[QueryResponse[T]], node: JsonNode
): Result[QueryResponse[T], ValidationError] =
  ## Deserialise JSON arguments to QueryResponse (RFC 8620 section 5.5).
  ## ``total`` and ``limit`` use lenient Option handling (absent -> none).
  ?checkJsonKind(node, JObject, $R)
  let accountId = ?parseAccountId(node{"accountId"}.getStr(""))
  let queryState = ?parseJmapState(node{"queryState"}.getStr(""))
  let cccNode = node{"canCalculateChanges"}
  ?checkJsonKind(cccNode, JBool, "QueryResponse", "canCalculateChanges must be boolean")
  let canCalculateChanges = cccNode.getBool(false)
  let posNode = node{"position"}
  ?checkJsonKind(posNode, JInt, "QueryResponse", "position must be integer")
  let position = ?parseUnsignedInt(posNode.getBiggestInt(0))
  let ids = ?parseIdArray(node{"ids"}, "QueryResponse", "ids")
  let total = optUnsignedInt(node, "total")
  let limit = optUnsignedInt(node, "limit")
  return ok(
    QueryResponse[T](
      accountId: accountId,
      queryState: queryState,
      canCalculateChanges: canCalculateChanges,
      position: position,
      ids: ids,
      total: total,
      limit: limit,
    )
  )

func fromJson*[T](
    R: typedesc[QueryChangesResponse[T]], node: JsonNode
): Result[QueryChangesResponse[T], ValidationError] =
  ## Deserialise JSON arguments to QueryChangesResponse (RFC 8620 section 5.6).
  ## ``total`` uses lenient Option handling (absent -> none). ``added`` elements
  ## parsed via AddedItem.fromJson (Layer 2).
  ?checkJsonKind(node, JObject, $R)
  let accountId = ?parseAccountId(node{"accountId"}.getStr(""))
  let oldQueryState = ?parseJmapState(node{"oldQueryState"}.getStr(""))
  let newQueryState = ?parseJmapState(node{"newQueryState"}.getStr(""))
  let total = optUnsignedInt(node, "total")
  let removed = ?parseIdArray(node{"removed"}, "QueryChangesResponse", "removed")
  let addedNode = node{"added"}
  ?checkJsonKind(addedNode, JArray, "QueryChangesResponse", "added must be array")
  var added: seq[AddedItem] = @[]
  for _, elem in addedNode.getElems(@[]):
    let item = ?AddedItem.fromJson(elem)
    added.add(item)
  return ok(
    QueryChangesResponse[T](
      accountId: accountId,
      oldQueryState: oldQueryState,
      newQueryState: newQueryState,
      total: total,
      removed: removed,
      added: added,
    )
  )
