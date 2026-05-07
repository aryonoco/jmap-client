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
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ../../types
import ../../serialisation

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

type SetRequest*[T, C, U] = object
  ## Request arguments for Foo/set (RFC 8620 section 5.3).
  ## Creates, updates, and/or destroys records of type T in a single method
  ## call. Each operation is atomic; the method as a whole is NOT atomic.
  ##
  ## ``C`` is the typed create-entry value (e.g. ``MailboxCreate``,
  ## ``EmailBlueprint``). ``U`` is the whole-container update algebra
  ## (e.g. ``NonEmptyMailboxUpdates``, ``NonEmptyEmailUpdates``). Both
  ## ``C.toJson`` and ``U.toJson`` resolve at instantiation via ``mixin``.
  accountId*: AccountId ## The identifier of the account to use.
  ifInState*: Opt[JmapState]
    ## If supplied, must match the current state; otherwise the method is
    ## aborted with a "stateMismatch" error.
  create*: Opt[Table[CreationId, C]]
    ## A map of creation identifiers to typed creation-model values.
    ## ``C.toJson`` is resolved via ``mixin`` by the serialiser.
  update*: Opt[U]
    ## Typed whole-container update algebra. ``Opt.none`` omits the
    ## ``update`` key from the wire; ``Opt.some(u)`` emits ``u.toJson()``
    ## verbatim as the wire ``"update"`` value.
  destroy*: Opt[Referencable[seq[Id]]]
    ## A list of identifiers for records to permanently delete. Referencable:
    ## may be a direct seq or a result reference.

type CopyDestroyModeKind* = enum
  ## Discriminator for ``CopyDestroyMode``. Names the two RFC 8620 §5.4
  ## post-copy dispositions: ``cdmKeep`` leaves the originals in place;
  ## ``cdmDestroyAfterSuccess`` triggers an implicit Foo/set destroy of
  ## the originals in the from-account after a successful copy.
  cdmKeep
  cdmDestroyAfterSuccess

type CopyDestroyMode* {.ruleOff: "objects".} = object
  ## Typed post-copy disposition for ``CopyRequest`` (RFC 8620 §5.4).
  ##
  ## Closes the illegal-state hole left by the prior flat representation
  ## (``onSuccessDestroyOriginal: bool`` + ``destroyFromIfInState:
  ## Opt[JmapState]``), where a non-empty ``destroyFromIfInState`` alongside
  ## ``onSuccessDestroyOriginal: false`` was structurally expressible but
  ## semantically meaningless -- the server would silently ignore the
  ## ``ifInState`` because no implicit destroy was issued. The case object
  ## makes the two legitimate combinations the only representable ones.
  ##
  ## Construction via the smart constructors ``keepOriginals`` and
  ## ``destroyAfterSuccess``; direct case-object construction is acceptable
  ## because the discriminator is module-public (the illegal state is gone).
  case kind*: CopyDestroyModeKind
  of cdmKeep:
    discard
  of cdmDestroyAfterSuccess:
    destroyIfInState*: Opt[JmapState]
      ## Passed as ``ifInState`` to the implicit Foo/set call. ``Opt.none``
      ## disables the state guard on the implicit destroy.

func keepOriginals*(): CopyDestroyMode =
  ## Constructs the ``cdmKeep`` variant — the server leaves originals in
  ## place after a successful copy. ``CopyRequest.toJson`` omits
  ## ``onSuccessDestroyOriginal`` entirely (spec default ``false`` per
  ## RFC 8620 §5.4), matching the RFC default-omission convention.
  return CopyDestroyMode(kind: cdmKeep)

func destroyAfterSuccess*(
    ifInState: Opt[JmapState] = Opt.none(JmapState)
): CopyDestroyMode =
  ## Constructs the ``cdmDestroyAfterSuccess`` variant -- the server issues
  ## an implicit Foo/set destroy of the originals after a successful copy.
  ## ``ifInState`` is the optional state guard passed through to that
  ## implicit destroy call.
  return CopyDestroyMode(kind: cdmDestroyAfterSuccess, destroyIfInState: ifInState)

type CopyRequest*[T, CopyItem] = object
  ## Request arguments for Foo/copy (RFC 8620 section 5.4).
  ## Copies records from one account to another.
  ##
  ## ``CopyItem`` is the typed create-entry value (e.g. ``EmailCopyItem``
  ## for Email/copy). ``CopyItem.toJson`` resolves at instantiation via
  ## ``mixin``.
  fromAccountId*: AccountId ## The identifier of the account to copy records from.
  ifFromInState*: Opt[JmapState]
    ## If supplied, must match the current state of the from-account.
  accountId*: AccountId ## The identifier of the account to copy records to.
  ifInState*: Opt[JmapState]
    ## If supplied, must match the current state of the destination account.
  create*: Table[CreationId, CopyItem]
    ## A map of creation identifiers to typed copy-item values. Required
    ## (not optional). Each copy item must carry an "id" property referencing
    ## the record in the from-account.
  destroyMode*: CopyDestroyMode
    ## Post-copy disposition of the originals. Case object — the illegal
    ## combination "state-guard supplied with no implicit destroy" is
    ## structurally unrepresentable.

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
  ##
  ## ``T`` is the typed ``created`` entry payload: the generic ``fromJson``
  ## resolves ``T.fromJson`` via ``mixin`` at instantiation to parse wire
  ## ``created[cid]`` into ``T``. ``updateResults`` stays ``Opt[JsonNode]``
  ## because update payloads are open-ended partial entities; typing them
  ## needs per-entity partial types which are out of scope for this pass.
  accountId*: AccountId ## The identifier of the account used for the call.
  oldState*: Opt[JmapState]
    ## The state before making the requested changes, or none if the server
    ## does not know the previous state.
  newState*: Opt[JmapState]
    ## Server state after the call. ``Opt.none`` when the server omits the
    ## field — Stalwart 0.15.5 empirically omits ``newState`` for /set
    ## responses with only failure rails populated. RFC 8620 §5.3 mandates
    ## the field; the library is lenient on receive per Postel's law.
    ## Consumers needing the post-call state fall back to ``oldState`` or
    ## to a fresh ``Foo/get``.
  createResults*: Table[CreationId, Result[T, SetError]]
    ## Merged create outcomes. Wire ``created`` entries become
    ## ``Result.ok(entity)`` via ``T.fromJson``; wire ``notCreated`` entries
    ## become ``Result.err(setError)``. Last-writer-wins on duplicate keys.
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
  ## Uses unified Result maps (Decision 3.9B). Shares the typed-``T``
  ## semantics of ``SetResponse[T]`` — ``T.fromJson`` resolves at
  ## instantiation via ``mixin``.
  fromAccountId*: AccountId ## The identifier of the account records were copied from.
  accountId*: AccountId ## The identifier of the account records were copied to.
  oldState*: Opt[JmapState] ## The state of the destination account before the copy.
  newState*: Opt[JmapState]
    ## Server state after the call. ``Opt.none`` when the server omits the
    ## field — Stalwart 0.15.5 empirically omits ``newState`` for /copy
    ## responses with only failure rails populated. RFC 8620 §5.4 mandates
    ## the field; the library is lenient on receive per Postel's law.
  createResults*: Table[CreationId, Result[T, SetError]]
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

func serializeOptFilter*[C](filter: Opt[Filter[C]]): Opt[SerializedFilter] =
  ## Pre-serialise an optional filter tree. ``Filter[C].toJson`` resolves
  ## the leaf condition's ``toJson`` via ``mixin`` at the builder's
  ## instantiation scope — the entity's filter condition type must have
  ## a visible ``toJson`` at that scope.
  mixin toJson
  for f in filter:
    return Opt.some(SerializedFilter(f.toJson()))
  Opt.none(SerializedFilter)

func serializeFilter*[C](filter: Filter[C]): SerializedFilter =
  ## Pre-serialise a required filter tree. Non-Opt variant for builders
  ## where the filter is mandatory (e.g. SearchSnippet/get).
  ## ``Filter[C].toJson`` resolves the leaf condition's ``toJson`` via
  ## ``mixin`` at the caller's instantiation scope.
  mixin toJson
  SerializedFilter(filter.toJson())

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
    # ``anchorOffset`` is meaningful only when ``anchor`` is set (RFC 8620
    # §5.5: the offset is from the anchor's position). Emitting it
    # alongside an absent anchor is wasteful on lenient servers (Stalwart)
    # and a hard reject on strict ones (Apache James 3.9 returns
    # ``invalidArguments`` "anchorOffset is syntactically valid, but is
    # not supported by the server"). Tying emission to anchor presence
    # keeps the wire request RFC-conformant against both.
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

func toJson*[T, C, U](req: SetRequest[T, C, U]): JsonNode =
  ## Serialise SetRequest to JSON arguments object (RFC 8620 section 5.3).
  ## Wire key order: ``accountId, ifInState, create, destroy, update``.
  ## ``C.toJson`` serialises each create entry; ``U.toJson`` serialises
  ## the whole update container. Both resolve at instantiation via
  ## ``mixin``. Entity-specific extension keys (e.g. ``onDestroyRemoveEmails``)
  ## are appended by the builder after this function returns.
  mixin toJson
  var node = newJObject()
  node["accountId"] = req.accountId.toJson()
  for s in req.ifInState:
    node["ifInState"] = s.toJson()
  for createMap in req.create:
    var createObj = newJObject()
    for k, v in createMap:
      createObj[string(k)] = v.toJson()
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
  for updateContainer in req.update:
    node["update"] = updateContainer.toJson()
  return node

func toJson*[T, CopyItem](req: CopyRequest[T, CopyItem]): JsonNode =
  ## Serialise CopyRequest to JSON arguments object (RFC 8620 section 5.4).
  ## ``create`` is required (always emitted). ``onSuccessDestroyOriginal``
  ## is emitted only when non-default (``true``); ``cdmKeep`` omits the key
  ## per RFC 8620 §5.4's default-omission convention. ``CopyItem.toJson``
  ## resolves at instantiation via ``mixin``.
  mixin toJson
  var node = newJObject()
  node["fromAccountId"] = req.fromAccountId.toJson()
  for s in req.ifFromInState:
    node["ifFromInState"] = s.toJson()
  node["accountId"] = req.accountId.toJson()
  for s in req.ifInState:
    node["ifInState"] = s.toJson()
  var createObj = newJObject()
  for k, v in req.create:
    createObj[string(k)] = v.toJson()
  node["create"] = createObj
  case req.destroyMode.kind
  of cdmKeep:
    discard
  of cdmDestroyAfterSuccess:
    node["onSuccessDestroyOriginal"] = %true
    for s in req.destroyMode.destroyIfInState:
      node["destroyFromIfInState"] = s.toJson()
  return node

# =============================================================================
# Response toJson — split merged Result tables back to the wire shape
# =============================================================================
# Round-trip helpers used primarily by tests and fixtures: ``fromJson``
# merges parallel wire maps into typed Result tables; these helpers
# reverse the projection. Production code consumes responses, never
# emits them — but the round-trip is load-bearing for serde tests.

func emitSplitCreateResults[T](
    createResults: Table[CreationId, Result[T, SetError]], node: JsonNode
) =
  ## Splits a merged ``createResults`` table into the wire ``created`` and
  ## ``notCreated`` maps; either key is omitted when its bucket is empty.
  ## ``T.toJson`` resolves at instantiation via ``mixin``.
  mixin toJson
  var created = newJObject()
  var notCreated = newJObject()
  for cid, r in createResults:
    if r.isOk:
      created[string(cid)] = r.get().toJson()
    else:
      notCreated[string(cid)] = r.error().toJson()
  if created.len > 0:
    node["created"] = created
  if notCreated.len > 0:
    node["notCreated"] = notCreated

func emitSplitUpdateResults(
    updateResults: Table[Id, Result[Opt[JsonNode], SetError]], node: JsonNode
) =
  ## Splits a merged ``updateResults`` table into ``updated`` and
  ## ``notUpdated`` wire maps. ``Opt.none`` projects to JSON null;
  ## ``Opt.some(n)`` projects to the inner node verbatim.
  var updated = newJObject()
  var notUpdated = newJObject()
  for id, r in updateResults:
    if r.isOk:
      let inner = r.get()
      updated[string(id)] =
        if inner.isSome:
          inner.get()
        else:
          newJNull()
    else:
      notUpdated[string(id)] = r.error().toJson()
  if updated.len > 0:
    node["updated"] = updated
  if notUpdated.len > 0:
    node["notUpdated"] = notUpdated

func emitSplitDestroyResults(
    destroyResults: Table[Id, Result[void, SetError]], node: JsonNode
) =
  ## Splits a merged ``destroyResults`` table into the wire ``destroyed``
  ## array and ``notDestroyed`` map. Empty buckets omit their key.
  var destroyed = newJArray()
  var notDestroyed = newJObject()
  for id, r in destroyResults:
    if r.isOk:
      destroyed.add(id.toJson())
    else:
      notDestroyed[string(id)] = r.error().toJson()
  if destroyed.len > 0:
    node["destroyed"] = destroyed
  if notDestroyed.len > 0:
    node["notDestroyed"] = notDestroyed

func toJson*[T](resp: SetResponse[T]): JsonNode =
  ## Serialise SetResponse[T] back to the RFC 8620 §5.3 wire shape:
  ## merged Result tables split into parallel created/notCreated,
  ## updated/notUpdated, destroyed/notDestroyed maps.
  mixin toJson
  var node = newJObject()
  node["accountId"] = resp.accountId.toJson()
  for s in resp.oldState:
    node["oldState"] = s.toJson()
  for s in resp.newState:
    node["newState"] = s.toJson()
  emitSplitCreateResults(resp.createResults, node)
  emitSplitUpdateResults(resp.updateResults, node)
  emitSplitDestroyResults(resp.destroyResults, node)
  return node

func toJson*[T](resp: CopyResponse[T]): JsonNode =
  ## Serialise CopyResponse[T] back to the RFC 8620 §5.4 wire shape.
  ## Only ``createResults`` to split; copy has no update/destroy branches.
  mixin toJson
  var node = newJObject()
  node["fromAccountId"] = resp.fromAccountId.toJson()
  node["accountId"] = resp.accountId.toJson()
  for s in resp.oldState:
    node["oldState"] = s.toJson()
  for s in resp.newState:
    node["newState"] = s.toJson()
  emitSplitCreateResults(resp.createResults, node)
  return node

# =============================================================================
# SetResponse merging helpers (section 8)
# =============================================================================

func mergeCreateResults*[T](
    node: JsonNode, path: JsonPath
): Result[Table[CreationId, Result[T, SetError]], SerdeViolation] =
  ## Merge wire ``created``/``notCreated`` maps into a unified Result table
  ## (RFC 8620 section 5.3, Decision 3.9B). Used by both SetResponse and
  ## CopyResponse. Last-writer-wins for duplicate keys (section 8.5).
  ##
  ## ``T.fromJson`` resolves at instantiation via ``mixin`` — every ``T``
  ## that ends up in ``SetResponse[T]`` / ``CopyResponse[T]`` MUST define
  ## ``fromJson(_: typedesc[T], JsonNode, JsonPath): Result[T,
  ## SerdeViolation]``.
  mixin fromJson
  var tbl = initTable[CreationId, Result[T, SetError]]()
  let createdNode = node{"created"}
  if not createdNode.isNil and createdNode.kind == JObject:
    for k, v in createdNode.pairs:
      let cid = ?wrapInner(parseCreationId(k), path / "created" / k)
      let entity = ?T.fromJson(v, path / "created" / k)
      tbl[cid] = Result[T, SetError].ok(entity)
  let notCreatedNode = node{"notCreated"}
  if not notCreatedNode.isNil and notCreatedNode.kind == JObject:
    for k, v in notCreatedNode.pairs:
      let cid = ?wrapInner(parseCreationId(k), path / "notCreated" / k)
      let se = ?SetError.fromJson(v, path / "notCreated" / k)
      tbl[cid] = Result[T, SetError].err(se)
  return ok(tbl)

func mergeUpdateResults(
    node: JsonNode, path: JsonPath
): Result[Table[Id, Result[Opt[JsonNode], SetError]], SerdeViolation] =
  ## Merge wire ``updated``/``notUpdated`` maps into a unified Result table
  ## (RFC 8620 section 5.3, Decision 3.9B). Null value in ``updated`` maps
  ## to ``ok(Opt.none)`` (server made no property changes the client
  ## doesn't already know); any non-null value maps to ``ok(Opt.some(v))``
  ## verbatim — RFC 8620 specifies ``PatchObject`` for this slot, but the
  ## library intentionally passes the raw node through because the entity-
  ## specific PatchObject shape is unknown at this layer. Postel on
  ## receive: defer the structural check to callers who know their
  ## entity. ``notUpdated`` entries go through ``SetError.fromJson`` and
  ## are therefore strict — a typed sum must parse. Last-writer-wins for
  ## duplicate keys (section 8.5).
  var tbl = initTable[Id, Result[Opt[JsonNode], SetError]]()
  let updatedNode = node{"updated"}
  if not updatedNode.isNil and updatedNode.kind == JObject:
    for k, v in updatedNode.pairs:
      let id = ?wrapInner(parseIdFromServer(k), path / "updated" / k)
      if v.isNil or v.kind == JNull:
        tbl[id] = Result[Opt[JsonNode], SetError].ok(Opt.none(JsonNode))
      else:
        tbl[id] = Result[Opt[JsonNode], SetError].ok(Opt.some(v))
  let notUpdatedNode = node{"notUpdated"}
  if not notUpdatedNode.isNil and notUpdatedNode.kind == JObject:
    for k, v in notUpdatedNode.pairs:
      let id = ?wrapInner(parseIdFromServer(k), path / "notUpdated" / k)
      let se = ?SetError.fromJson(v, path / "notUpdated" / k)
      tbl[id] = Result[Opt[JsonNode], SetError].err(se)
  return ok(tbl)

func mergeDestroyResults(
    node: JsonNode, path: JsonPath
): Result[Table[Id, Result[void, SetError]], SerdeViolation] =
  ## Merge wire ``destroyed``/``notDestroyed`` into a unified Result table
  ## (RFC 8620 section 5.3, Decision 3.9B). ``destroyed`` is a flat array
  ## on the wire; each ID becomes ``Result.ok()``. ``notDestroyed`` entries
  ## become ``Result.err(setError)``. Last-writer-wins on duplicate keys.
  var tbl = initTable[Id, Result[void, SetError]]()
  let destroyedNode = node{"destroyed"}
  if not destroyedNode.isNil and destroyedNode.kind == JArray:
    for i, elem in destroyedNode.getElems(@[]):
      let id = ?wrapInner(parseIdFromServer(elem.getStr("")), path / "destroyed" / i)
      tbl[id] = Result[void, SetError].ok()
  let notDestroyedNode = node{"notDestroyed"}
  if not notDestroyedNode.isNil and notDestroyedNode.kind == JObject:
    for k, v in notDestroyedNode.pairs:
      let id = ?wrapInner(parseIdFromServer(k), path / "notDestroyed" / k)
      let se = ?SetError.fromJson(v, path / "notDestroyed" / k)
      tbl[id] = Result[void, SetError].err(se)
  return ok(tbl)

# =============================================================================
# Response fromJson (Pattern L3-B)
# =============================================================================

func fromJson*[T](
    R: typedesc[GetResponse[T]], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[GetResponse[T], SerdeViolation] =
  ## Deserialise JSON arguments to GetResponse (RFC 8620 section 5.1).
  ## Uses lenient constructors for server-assigned identifiers. ``list``
  ## contains raw JsonNode entities -- entity-specific parsing is the
  ## caller's responsibility.
  discard $R # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let accountIdNode = ?fieldJString(node, "accountId", path)
  let accountId =
    ?wrapInner(parseAccountId(accountIdNode.getStr("")), path / "accountId")
  let stateNode = ?fieldJString(node, "state", path)
  let state = ?wrapInner(parseJmapState(stateNode.getStr("")), path / "state")
  let listNode = ?fieldJArray(node, "list", path)
  let list = listNode.getElems(@[])
  let notFound = ?parseOptIdArray(node{"notFound"}, path / "notFound")
  return ok(
    GetResponse[T](accountId: accountId, state: state, list: list, notFound: notFound)
  )

func fromJson*[T](
    R: typedesc[ChangesResponse[T]], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[ChangesResponse[T], SerdeViolation] =
  ## Deserialise JSON arguments to ChangesResponse (RFC 8620 section 5.2).
  discard $R # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let accountIdNode = ?fieldJString(node, "accountId", path)
  let accountId =
    ?wrapInner(parseAccountId(accountIdNode.getStr("")), path / "accountId")
  let oldStateNode = ?fieldJString(node, "oldState", path)
  let oldState = ?wrapInner(parseJmapState(oldStateNode.getStr("")), path / "oldState")
  let newStateNode = ?fieldJString(node, "newState", path)
  let newState = ?wrapInner(parseJmapState(newStateNode.getStr("")), path / "newState")
  let hmcNode = ?fieldJBool(node, "hasMoreChanges", path)
  let hasMoreChanges = hmcNode.getBool(false)
  let created = ?parseIdArrayField(node, "created", path)
  let updated = ?parseIdArrayField(node, "updated", path)
  let destroyed = ?parseIdArrayField(node, "destroyed", path)
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
    R: typedesc[SetResponse[T]], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[SetResponse[T], SerdeViolation] =
  ## Deserialise JSON arguments to SetResponse (RFC 8620 section 5.3).
  ## Merges parallel wire maps into separate success/failure tables (section 8).
  ## ``T.fromJson`` is resolved at instantiation via ``mixin``.
  mixin fromJson
  discard $R # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let accountIdNode = ?fieldJString(node, "accountId", path)
  let accountId =
    ?wrapInner(parseAccountId(accountIdNode.getStr("")), path / "accountId")
  let newState = optState(node, "newState")
  let oldState = optState(node, "oldState")
  let createResults = ?mergeCreateResults[T](node, path)
  let updateResults = ?mergeUpdateResults(node, path)
  let destroyResults = ?mergeDestroyResults(node, path)
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
    R: typedesc[CopyResponse[T]], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[CopyResponse[T], SerdeViolation] =
  ## Deserialise JSON arguments to CopyResponse (RFC 8620 section 5.4).
  ## Merges created/notCreated wire maps into separate success/failure
  ## tables (section 8). ``T.fromJson`` resolves at instantiation via
  ## ``mixin``.
  mixin fromJson
  discard $R # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let fromAccountIdNode = ?fieldJString(node, "fromAccountId", path)
  let fromAccountId =
    ?wrapInner(parseAccountId(fromAccountIdNode.getStr("")), path / "fromAccountId")
  let accountIdNode = ?fieldJString(node, "accountId", path)
  let accountId =
    ?wrapInner(parseAccountId(accountIdNode.getStr("")), path / "accountId")
  let newState = optState(node, "newState")
  let oldState = optState(node, "oldState")
  let createResults = ?mergeCreateResults[T](node, path)
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
    R: typedesc[QueryResponse[T]], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[QueryResponse[T], SerdeViolation] =
  ## Deserialise JSON arguments to QueryResponse (RFC 8620 section 5.5).
  ## ``total`` and ``limit`` use lenient Option handling (absent -> none).
  discard $R # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let accountIdNode = ?fieldJString(node, "accountId", path)
  let accountId =
    ?wrapInner(parseAccountId(accountIdNode.getStr("")), path / "accountId")
  let queryStateNode = ?fieldJString(node, "queryState", path)
  let queryState =
    ?wrapInner(parseJmapState(queryStateNode.getStr("")), path / "queryState")
  let cccNode = ?fieldJBool(node, "canCalculateChanges", path)
  let canCalculateChanges = cccNode.getBool(false)
  let posNode = ?fieldJInt(node, "position", path)
  let position =
    ?wrapInner(parseUnsignedInt(posNode.getBiggestInt(0)), path / "position")
  let ids = ?parseIdArrayField(node, "ids", path)
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
    R: typedesc[QueryChangesResponse[T]],
    node: JsonNode,
    path: JsonPath = emptyJsonPath(),
): Result[QueryChangesResponse[T], SerdeViolation] =
  ## Deserialise JSON arguments to QueryChangesResponse (RFC 8620 section 5.6).
  ## ``total`` uses lenient Option handling (absent -> none). ``added`` elements
  ## parsed via AddedItem.fromJson (Layer 2).
  discard $R # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let accountIdNode = ?fieldJString(node, "accountId", path)
  let accountId =
    ?wrapInner(parseAccountId(accountIdNode.getStr("")), path / "accountId")
  let oldQueryStateNode = ?fieldJString(node, "oldQueryState", path)
  let oldQueryState =
    ?wrapInner(parseJmapState(oldQueryStateNode.getStr("")), path / "oldQueryState")
  let newQueryStateNode = ?fieldJString(node, "newQueryState", path)
  let newQueryState =
    ?wrapInner(parseJmapState(newQueryStateNode.getStr("")), path / "newQueryState")
  let total = optUnsignedInt(node, "total")
  let removed = ?parseIdArrayField(node, "removed", path)
  let addedNode = ?fieldJArray(node, "added", path)
  var added: seq[AddedItem] = @[]
  for i, elem in addedNode.getElems(@[]):
    let item = ?AddedItem.fromJson(elem, path / "added" / i)
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
