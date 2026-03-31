# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}
{.experimental: "strictCaseObjects".}

## Standard method request and response types for the six JMAP methods
## (RFC 8620 sections 5.1-5.6): get, changes, set, copy, query, queryChanges.
##
## Request types receive ``toJson`` (Pattern L3-A); response types receive
## ``fromJson`` (Pattern L3-B). Serialisation is unidirectional (Decision D3.7).
## ``SetResponse`` and ``CopyResponse`` merging follows Pattern L3-C (section 8).
##
## Entity data is raw ``JsonNode`` (Decision D3.6) -- entity-specific parsing
## is the caller's responsibility.

import std/json
import std/tables

import results

import ./types
import ./serialisation

# =============================================================================
# Lenient Opt helpers (internal, not exported)
# =============================================================================

func optState*(node: JsonNode, key: string): Opt[JmapState] =
  ## Lenient optional JmapState extraction (section 5a.5 leniency).
  ## Absent, null, wrong kind, or invalid content all produce Opt.none.
  let child = node{key}
  if child.isNil:
    return Opt.none(JmapState)
  if child.kind != JString:
    return Opt.none(JmapState)
  let r = parseJmapState(child.getStr(""))
  if r.isErr:
    return Opt.none(JmapState)
  Opt.some(r.get())

func optUnsignedInt*(node: JsonNode, key: string): Opt[UnsignedInt] =
  ## Lenient optional UnsignedInt extraction (section 5a.5 leniency).
  ## Absent, null, wrong kind, or invalid content all produce Opt.none.
  let child = node{key}
  if child.isNil:
    return Opt.none(UnsignedInt)
  if child.kind != JInt:
    return Opt.none(UnsignedInt)
  let r = parseUnsignedInt(child.getBiggestInt(0))
  if r.isErr:
    return Opt.none(UnsignedInt)
  Opt.some(r.get())

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
  update*: Opt[Table[Id, PatchObject]]
    ## A map of record identifiers to PatchObject values representing the
    ## changes to apply.
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
  accountId*: AccountId ## The identifier of the account used for the call.
  oldState*: Opt[JmapState]
    ## The state before making the requested changes, or none if the server
    ## does not know the previous state.
  newState*: JmapState ## The state that will now be returned by Foo/get.
  createResults*: Table[CreationId, Result[JsonNode, SetError]]
    ## Merged map of create outcomes. Wire ``created`` entries become
    ## Result.ok(entityJson); wire ``notCreated`` entries become
    ## Result.err(setError).
  updateResults*: Table[Id, Result[Opt[JsonNode], SetError]]
    ## Merged map of update outcomes. Wire ``updated`` entries with null
    ## value become ok(Opt.none(JsonNode)); non-null values become
    ## ok(Opt.some(entityJson)). Wire ``notUpdated`` entries become
    ## Result.err(setError).
  destroyResults*: Table[Id, Result[void, SetError]]
    ## Merged map of destroy outcomes. Wire ``destroyed`` entries become
    ## Result.ok(); wire ``notDestroyed`` entries become
    ## Result.err(setError).

type CopyResponse*[T] = object
  ## Response arguments for Foo/copy (RFC 8620 section 5.4).
  ## Structurally similar to SetResponse but only has create results.
  fromAccountId*: AccountId ## The identifier of the account records were copied from.
  accountId*: AccountId ## The identifier of the account records were copied to.
  oldState*: Opt[JmapState] ## The state of the destination account before the copy.
  newState*: JmapState
    ## The state that will now be returned by Foo/get on the destination
    ## account.
  createResults*: Table[CreationId, Result[JsonNode, SetError]]
    ## Merged map of copy outcomes. Same merging as SetResponse create
    ## branch.

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
# Request toJson (Pattern L3-A)
# =============================================================================

func toJson*[T](req: GetRequest[T]): JsonNode =
  ## Serialise GetRequest to JSON arguments object (RFC 8620 section 5.1).
  ## Omits ``ids`` and ``properties`` when Opt.none.
  ## Dispatches Referencable ids via referencableKey.
  {.cast(noSideEffect).}:
    result = newJObject()
    result["accountId"] = req.accountId.toJson()
    if req.ids.isSome:
      let idsVal = req.ids.get()
      let idsKey = referencableKey("ids", idsVal)
      case idsVal.kind
      of rkDirect:
        var arr = newJArray()
        for id in idsVal.value:
          arr.add(id.toJson())
        result[idsKey] = arr
      of rkReference:
        result[idsKey] = idsVal.reference.toJson()
    if req.properties.isSome:
      var arr = newJArray()
      for p in req.properties.get():
        arr.add(%p)
      result["properties"] = arr

func toJson*[T](req: ChangesRequest[T]): JsonNode =
  ## Serialise ChangesRequest to JSON arguments object (RFC 8620 section 5.2).
  ## Omits ``maxChanges`` when Opt.none.
  {.cast(noSideEffect).}:
    result = newJObject()
    result["accountId"] = req.accountId.toJson()
    result["sinceState"] = req.sinceState.toJson()
    if req.maxChanges.isSome:
      result["maxChanges"] = req.maxChanges.get().toJson()

func toJson*[T](req: SetRequest[T]): JsonNode =
  ## Serialise SetRequest to JSON arguments object (RFC 8620 section 5.3).
  ## Omits ``ifInState``, ``create``, ``update``, ``destroy`` when Opt.none.
  ## Dispatches Referencable destroy via referencableKey.
  {.cast(noSideEffect).}:
    result = newJObject()
    result["accountId"] = req.accountId.toJson()
    if req.ifInState.isSome:
      result["ifInState"] = req.ifInState.get().toJson()
    if req.create.isSome:
      var createObj = newJObject()
      for k, v in req.create.get():
        createObj[string(k)] = v
      result["create"] = createObj
    if req.update.isSome:
      var updateObj = newJObject()
      for k, v in req.update.get():
        updateObj[string(k)] = v.toJson()
      result["update"] = updateObj
    if req.destroy.isSome:
      let destroyVal = req.destroy.get()
      let destroyKey = referencableKey("destroy", destroyVal)
      case destroyVal.kind
      of rkDirect:
        var arr = newJArray()
        for id in destroyVal.value:
          arr.add(id.toJson())
        result[destroyKey] = arr
      of rkReference:
        result[destroyKey] = destroyVal.reference.toJson()

func toJson*[T](req: CopyRequest[T]): JsonNode =
  ## Serialise CopyRequest to JSON arguments object (RFC 8620 section 5.4).
  ## ``create`` is required (always emitted). ``onSuccessDestroyOriginal``
  ## always emitted.
  {.cast(noSideEffect).}:
    result = newJObject()
    result["fromAccountId"] = req.fromAccountId.toJson()
    if req.ifFromInState.isSome:
      result["ifFromInState"] = req.ifFromInState.get().toJson()
    result["accountId"] = req.accountId.toJson()
    if req.ifInState.isSome:
      result["ifInState"] = req.ifInState.get().toJson()
    var createObj = newJObject()
    for k, v in req.create:
      createObj[string(k)] = v
    result["create"] = createObj
    result["onSuccessDestroyOriginal"] = %req.onSuccessDestroyOriginal
    if req.destroyFromIfInState.isSome:
      result["destroyFromIfInState"] = req.destroyFromIfInState.get().toJson()

func toJson*[T, C](
    req: QueryRequest[T, C],
    filterConditionToJson: proc(c: C): JsonNode {.noSideEffect, raises: [].},
): JsonNode =
  ## Serialise QueryRequest to JSON arguments object (RFC 8620 section 5.5).
  ## ``position``, ``anchorOffset``, ``calculateTotal`` always emitted.
  ## Filter serialised via ``filterConditionToJson`` callback.
  {.cast(noSideEffect).}:
    result = newJObject()
    result["accountId"] = req.accountId.toJson()
    if req.filter.isSome:
      result["filter"] = req.filter.get().toJson(filterConditionToJson)
    if req.sort.isSome:
      var arr = newJArray()
      for c in req.sort.get():
        arr.add(c.toJson())
      result["sort"] = arr
    result["position"] = req.position.toJson()
    if req.anchor.isSome:
      result["anchor"] = req.anchor.get().toJson()
    result["anchorOffset"] = req.anchorOffset.toJson()
    if req.limit.isSome:
      result["limit"] = req.limit.get().toJson()
    result["calculateTotal"] = %req.calculateTotal

func toJson*[T, C](
    req: QueryChangesRequest[T, C],
    filterConditionToJson: proc(c: C): JsonNode {.noSideEffect, raises: [].},
): JsonNode =
  ## Serialise QueryChangesRequest to JSON arguments object
  ## (RFC 8620 section 5.6). ``calculateTotal`` always emitted.
  ## Filter serialised via ``filterConditionToJson`` callback.
  {.cast(noSideEffect).}:
    result = newJObject()
    result["accountId"] = req.accountId.toJson()
    if req.filter.isSome:
      result["filter"] = req.filter.get().toJson(filterConditionToJson)
    if req.sort.isSome:
      var arr = newJArray()
      for c in req.sort.get():
        arr.add(c.toJson())
      result["sort"] = arr
    result["sinceQueryState"] = req.sinceQueryState.toJson()
    if req.maxChanges.isSome:
      result["maxChanges"] = req.maxChanges.get().toJson()
    if req.upToId.isSome:
      result["upToId"] = req.upToId.get().toJson()
    result["calculateTotal"] = %req.calculateTotal

# =============================================================================
# SetResponse merging helpers (section 8)
# =============================================================================

func mergeCreateResults(
    node: JsonNode
): Result[Table[CreationId, Result[JsonNode, SetError]], ValidationError] =
  ## Merge wire ``created``/``notCreated`` maps into a unified Result table
  ## (RFC 8620 section 5.3). Used by both SetResponse and CopyResponse.
  ## Last-writer-wins for duplicate keys (section 8.5).
  var tbl = initTable[CreationId, Result[JsonNode, SetError]]()
  let createdNode = node{"created"}
  if not createdNode.isNil and createdNode.kind == JObject:
    {.cast(noSideEffect).}:
      for k, v in createdNode.pairs:
        let cid = ?parseCreationId(k)
        tbl[cid] = Result[JsonNode, SetError].ok(v)
  let notCreatedNode = node{"notCreated"}
  if not notCreatedNode.isNil and notCreatedNode.kind == JObject:
    {.cast(noSideEffect).}:
      for k, v in notCreatedNode.pairs:
        let cid = ?parseCreationId(k)
        let se = ?SetError.fromJson(v)
        tbl[cid] = Result[JsonNode, SetError].err(se)
  ok(tbl)

func mergeUpdateResults(
    node: JsonNode
): Result[Table[Id, Result[Opt[JsonNode], SetError]], ValidationError] =
  ## Merge wire ``updated``/``notUpdated`` maps into a unified Result table
  ## (RFC 8620 section 5.3). Null value in ``updated`` means no server-set
  ## properties changed; non-null contains changed properties.
  ## Last-writer-wins for duplicate keys (section 8.5).
  var tbl = initTable[Id, Result[Opt[JsonNode], SetError]]()
  let updatedNode = node{"updated"}
  if not updatedNode.isNil and updatedNode.kind == JObject:
    {.cast(noSideEffect).}:
      for k, v in updatedNode.pairs:
        let id = ?parseIdFromServer(k)
        if v.isNil or v.kind == JNull:
          tbl[id] = Result[Opt[JsonNode], SetError].ok(Opt.none(JsonNode))
        else:
          tbl[id] = Result[Opt[JsonNode], SetError].ok(Opt.some(v))
  let notUpdatedNode = node{"notUpdated"}
  if not notUpdatedNode.isNil and notUpdatedNode.kind == JObject:
    {.cast(noSideEffect).}:
      for k, v in notUpdatedNode.pairs:
        let id = ?parseIdFromServer(k)
        let se = ?SetError.fromJson(v)
        tbl[id] = Result[Opt[JsonNode], SetError].err(se)
  ok(tbl)

func mergeDestroyResults(
    node: JsonNode
): Result[Table[Id, Result[void, SetError]], ValidationError] =
  ## Merge wire ``destroyed``/``notDestroyed`` into a unified Result table
  ## (RFC 8620 section 5.3). No cast needed (Result[void, SetError] has no
  ## ref values). Last-writer-wins for duplicate keys (section 8.5).
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
  ok(tbl)

# =============================================================================
# Response fromJson core helpers (non-generic, for requiresInit workaround)
# =============================================================================

func parseGetResponseCore(
    node: JsonNode
): Result[(AccountId, JmapState, seq[JsonNode], seq[Id]), ValidationError] =
  ## Parse GetResponse fields into a tuple (requiresInit workaround).
  checkJsonKind(node, JObject, "GetResponse")
  let accountId = ?parseAccountId(node{"accountId"}.getStr(""))
  let state = ?parseJmapState(node{"state"}.getStr(""))
  let listNode = node{"list"}
  checkJsonKind(listNode, JArray, "GetResponse", "list must be array")
  var list: seq[JsonNode] = @[]
  {.cast(noSideEffect).}:
    list = listNode.getElems(@[])
  var notFound: seq[Id] = @[]
  let nfNode = node{"notFound"}
  if not nfNode.isNil and nfNode.kind == JArray:
    for _, elem in nfNode.getElems(@[]):
      let id = ?parseIdFromServer(elem.getStr(""))
      notFound.add(id)
  ok((accountId, state, list, notFound))

func parseChangesResponseCore(
    node: JsonNode
): Result[
    (AccountId, JmapState, JmapState, bool, seq[Id], seq[Id], seq[Id]), ValidationError
] =
  ## Parse ChangesResponse fields into a tuple (requiresInit workaround).
  checkJsonKind(node, JObject, "ChangesResponse")
  let accountId = ?parseAccountId(node{"accountId"}.getStr(""))
  let oldState = ?parseJmapState(node{"oldState"}.getStr(""))
  let newState = ?parseJmapState(node{"newState"}.getStr(""))
  let hmcNode = node{"hasMoreChanges"}
  checkJsonKind(hmcNode, JBool, "ChangesResponse", "hasMoreChanges must be boolean")
  let hasMoreChanges = hmcNode.getBool(false)
  let createdNode = node{"created"}
  checkJsonKind(createdNode, JArray, "ChangesResponse", "created must be array")
  var created: seq[Id] = @[]
  for _, elem in createdNode.getElems(@[]):
    let id = ?parseIdFromServer(elem.getStr(""))
    created.add(id)
  let updatedNode = node{"updated"}
  checkJsonKind(updatedNode, JArray, "ChangesResponse", "updated must be array")
  var updated: seq[Id] = @[]
  for _, elem in updatedNode.getElems(@[]):
    let id = ?parseIdFromServer(elem.getStr(""))
    updated.add(id)
  let destroyedNode = node{"destroyed"}
  checkJsonKind(destroyedNode, JArray, "ChangesResponse", "destroyed must be array")
  var destroyed: seq[Id] = @[]
  for _, elem in destroyedNode.getElems(@[]):
    let id = ?parseIdFromServer(elem.getStr(""))
    destroyed.add(id)
  ok((accountId, oldState, newState, hasMoreChanges, created, updated, destroyed))

func parseSetResponseCore(
    node: JsonNode
): Result[(AccountId, JmapState, Opt[JmapState]), ValidationError] =
  ## Parse SetResponse required fields into a tuple (requiresInit workaround).
  checkJsonKind(node, JObject, "SetResponse")
  let accountId = ?parseAccountId(node{"accountId"}.getStr(""))
  let newState = ?parseJmapState(node{"newState"}.getStr(""))
  let oldState = optState(node, "oldState")
  ok((accountId, newState, oldState))

func parseCopyResponseCore(
    node: JsonNode
): Result[(AccountId, AccountId, JmapState, Opt[JmapState]), ValidationError] =
  ## Parse CopyResponse required fields into a tuple (requiresInit workaround).
  checkJsonKind(node, JObject, "CopyResponse")
  let fromAccountId = ?parseAccountId(node{"fromAccountId"}.getStr(""))
  let accountId = ?parseAccountId(node{"accountId"}.getStr(""))
  let newState = ?parseJmapState(node{"newState"}.getStr(""))
  let oldState = optState(node, "oldState")
  ok((fromAccountId, accountId, newState, oldState))

func parseQueryResponseCore(
    node: JsonNode
): Result[
    (
      AccountId,
      JmapState,
      bool,
      UnsignedInt,
      seq[Id],
      Opt[UnsignedInt],
      Opt[UnsignedInt],
    ),
    ValidationError,
] =
  ## Parse QueryResponse fields into a tuple (requiresInit workaround).
  checkJsonKind(node, JObject, "QueryResponse")
  let accountId = ?parseAccountId(node{"accountId"}.getStr(""))
  let queryState = ?parseJmapState(node{"queryState"}.getStr(""))
  let cccNode = node{"canCalculateChanges"}
  checkJsonKind(cccNode, JBool, "QueryResponse", "canCalculateChanges must be boolean")
  let canCalculateChanges = cccNode.getBool(false)
  let posNode = node{"position"}
  checkJsonKind(posNode, JInt, "QueryResponse", "position must be integer")
  let position = ?parseUnsignedInt(posNode.getBiggestInt(0))
  let idsNode = node{"ids"}
  checkJsonKind(idsNode, JArray, "QueryResponse", "ids must be array")
  var ids: seq[Id] = @[]
  for _, elem in idsNode.getElems(@[]):
    let id = ?parseIdFromServer(elem.getStr(""))
    ids.add(id)
  let total = optUnsignedInt(node, "total")
  let limit = optUnsignedInt(node, "limit")
  ok((accountId, queryState, canCalculateChanges, position, ids, total, limit))

func parseQueryChangesResponseCore(
    node: JsonNode
): Result[
    (AccountId, JmapState, JmapState, Opt[UnsignedInt], seq[Id], seq[AddedItem]),
    ValidationError,
] =
  ## Parse QueryChangesResponse fields into a tuple (requiresInit workaround).
  checkJsonKind(node, JObject, "QueryChangesResponse")
  let accountId = ?parseAccountId(node{"accountId"}.getStr(""))
  let oldQueryState = ?parseJmapState(node{"oldQueryState"}.getStr(""))
  let newQueryState = ?parseJmapState(node{"newQueryState"}.getStr(""))
  let total = optUnsignedInt(node, "total")
  let removedNode = node{"removed"}
  checkJsonKind(removedNode, JArray, "QueryChangesResponse", "removed must be array")
  var removed: seq[Id] = @[]
  for _, elem in removedNode.getElems(@[]):
    let id = ?parseIdFromServer(elem.getStr(""))
    removed.add(id)
  let addedNode = node{"added"}
  checkJsonKind(addedNode, JArray, "QueryChangesResponse", "added must be array")
  var added: seq[AddedItem] = @[]
  for _, elem in addedNode.getElems(@[]):
    let item = ?AddedItem.fromJson(elem)
    added.add(item)
  ok((accountId, oldQueryState, newQueryState, total, removed, added))

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
  discard $R
  let coreResult = parseGetResponseCore(node)
  if coreResult.isErr:
    return initResultErr[GetResponse[T], ValidationError](coreResult.error)
  let core = coreResult.get()
  ok(
    GetResponse[T](accountId: core[0], state: core[1], list: core[2], notFound: core[3])
  )

func fromJson*[T](
    R: typedesc[ChangesResponse[T]], node: JsonNode
): Result[ChangesResponse[T], ValidationError] =
  ## Deserialise JSON arguments to ChangesResponse (RFC 8620 section 5.2).
  discard $R
  let coreResult = parseChangesResponseCore(node)
  if coreResult.isErr:
    return initResultErr[ChangesResponse[T], ValidationError](coreResult.error)
  let core = coreResult.get()
  ok(
    ChangesResponse[T](
      accountId: core[0],
      oldState: core[1],
      newState: core[2],
      hasMoreChanges: core[3],
      created: core[4],
      updated: core[5],
      destroyed: core[6],
    )
  )

func fromJson*[T](
    R: typedesc[SetResponse[T]], node: JsonNode
): Result[SetResponse[T], ValidationError] =
  ## Deserialise JSON arguments to SetResponse (RFC 8620 section 5.3).
  ## Merges parallel wire maps into unified Result maps (section 8).
  discard $R
  let coreResult = parseSetResponseCore(node)
  if coreResult.isErr:
    return initResultErr[SetResponse[T], ValidationError](coreResult.error)
  let core = coreResult.get()
  let createRes = mergeCreateResults(node)
  if createRes.isErr:
    return initResultErr[SetResponse[T], ValidationError](createRes.error)
  let updateRes = mergeUpdateResults(node)
  if updateRes.isErr:
    return initResultErr[SetResponse[T], ValidationError](updateRes.error)
  let destroyRes = mergeDestroyResults(node)
  if destroyRes.isErr:
    return initResultErr[SetResponse[T], ValidationError](destroyRes.error)
  ok(
    SetResponse[T](
      accountId: core[0],
      newState: core[1],
      oldState: core[2],
      createResults: createRes.get(),
      updateResults: updateRes.get(),
      destroyResults: destroyRes.get(),
    )
  )

func fromJson*[T](
    R: typedesc[CopyResponse[T]], node: JsonNode
): Result[CopyResponse[T], ValidationError] =
  ## Deserialise JSON arguments to CopyResponse (RFC 8620 section 5.4).
  ## Merges created/notCreated wire maps into unified Result map (section 8).
  discard $R
  let coreResult = parseCopyResponseCore(node)
  if coreResult.isErr:
    return initResultErr[CopyResponse[T], ValidationError](coreResult.error)
  let core = coreResult.get()
  let createRes = mergeCreateResults(node)
  if createRes.isErr:
    return initResultErr[CopyResponse[T], ValidationError](createRes.error)
  ok(
    CopyResponse[T](
      fromAccountId: core[0],
      accountId: core[1],
      newState: core[2],
      oldState: core[3],
      createResults: createRes.get(),
    )
  )

func fromJson*[T](
    R: typedesc[QueryResponse[T]], node: JsonNode
): Result[QueryResponse[T], ValidationError] =
  ## Deserialise JSON arguments to QueryResponse (RFC 8620 section 5.5).
  ## ``total`` and ``limit`` use lenient Opt handling (absent -> none).
  discard $R
  let coreResult = parseQueryResponseCore(node)
  if coreResult.isErr:
    return initResultErr[QueryResponse[T], ValidationError](coreResult.error)
  let core = coreResult.get()
  ok(
    QueryResponse[T](
      accountId: core[0],
      queryState: core[1],
      canCalculateChanges: core[2],
      position: core[3],
      ids: core[4],
      total: core[5],
      limit: core[6],
    )
  )

func fromJson*[T](
    R: typedesc[QueryChangesResponse[T]], node: JsonNode
): Result[QueryChangesResponse[T], ValidationError] =
  ## Deserialise JSON arguments to QueryChangesResponse (RFC 8620 section 5.6).
  ## ``total`` uses lenient Opt handling (absent -> none). ``added`` elements
  ## parsed via AddedItem.fromJson (Layer 2).
  discard $R
  let coreResult = parseQueryChangesResponseCore(node)
  if coreResult.isErr:
    return initResultErr[QueryChangesResponse[T], ValidationError](coreResult.error)
  let core = coreResult.get()
  ok(
    QueryChangesResponse[T](
      accountId: core[0],
      oldQueryState: core[1],
      newQueryState: core[2],
      total: core[3],
      removed: core[4],
      added: core[5],
    )
  )
