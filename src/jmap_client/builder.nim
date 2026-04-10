# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Request builder for constructing JMAP method call batches (RFC 8620
## section 3.3). Accumulates typed method invocations and capability URIs,
## producing a complete Request envelope via ``build()``. Each ``add*``
## function returns a phantom-typed ``ResponseHandle[T]`` for type-safe
## response extraction via ``dispatch.get[T]``.
##
## **Pure functional core.** Each ``add*`` returns a new
## ``(RequestBuilder, ResponseHandle[T])`` tuple — no mutation.
## Under ``--mm:arc``, dead bindings are moved in place (zero copy).
## ``build()`` is a pure snapshot projection. The effect boundary is at
## Layer 4's ``proc send()``.
##
## **Capability auto-collection.** Each ``add*`` registers its entity's
## capability URI. The ``using`` array in the built Request is automatically
## deduplicated — no manual management required.
##
## **Call ID generation.** Auto-incrementing "c0", "c1", "c2"... (Decision
## 3.2A). Call IDs are scoped to a single builder instance.

{.push raises: [], noSideEffect.}

import std/json
import std/tables

import ./types
import ./serialisation
import ./methods
import ./dispatch

# =============================================================================
# RequestBuilder type
# =============================================================================

{.push ruleOff: "objects".}

type RequestBuilder* = object
  ## Immutable accumulator for constructing a JMAP Request (RFC 8620
  ## section 3.3). All fields are private — each ``add*`` returns a new
  ## builder with the addition applied.
  nextCallId: int ## monotonic counter for "c0", "c1", ...
  invocations: seq[Invocation] ## accumulated method calls
  capabilityUris: seq[string] ## deduplicated capability URIs

{.pop.}

func initRequestBuilder*(): RequestBuilder =
  ## Creates a fresh builder with counter at zero, no invocations, no
  ## capabilities.
  return RequestBuilder(nextCallId: 0, invocations: @[], capabilityUris: @[])

# =============================================================================
# Read-only accessors (immutability by default)
# =============================================================================

func methodCallCount*(b: RequestBuilder): int =
  ## Number of method calls accumulated so far.
  return b.invocations.len

func isEmpty*(b: RequestBuilder): bool =
  ## True if no method calls have been added.
  return b.invocations.len == 0

func capabilities*(b: RequestBuilder): seq[string] =
  ## Snapshot of the deduplicated capability URIs registered so far.
  return b.capabilityUris

# =============================================================================
# Build — pure snapshot
# =============================================================================

func build*(b: RequestBuilder): Request =
  ## Pure snapshot of the current builder state. Does not mutate the builder.
  ## ``createdIds`` is always none — proxy splitting is a Layer 4 concern.
  ## The builder can continue accumulating after ``build()`` for sequential
  ## requests.
  return Request(
    `using`: b.capabilityUris,
    methodCalls: b.invocations,
    createdIds: Opt.none(Table[CreationId, Id]),
  )

# =============================================================================
# Internal helpers (not exported)
# =============================================================================

func nextId(b: RequestBuilder): MethodCallId =
  ## Computes the next call ID from the current counter without mutation.
  ## Bypasses parseMethodCallId because the format is provably valid (D3.9).
  MethodCallId("c" & $b.nextCallId)

func withCapability(caps: seq[string], cap: string): seq[string] =
  ## Returns a new capability list with ``cap`` added if not already present.
  if cap in caps:
    caps
  else:
    caps & @[cap]

func addInvocation*(
    b: RequestBuilder, name: string, args: JsonNode, capability: string
): (RequestBuilder, MethodCallId) =
  ## Constructs an Invocation and returns a new builder with it accumulated.
  let callId = b.nextId()
  let inv = initInvocationUnchecked(name, args, callId)
  return (
    RequestBuilder(
      nextCallId: b.nextCallId + 1,
      invocations: b.invocations & @[inv],
      capabilityUris: withCapability(b.capabilityUris, capability),
    ),
    callId,
  )

# =============================================================================
# DRY template for non-query add* methods
# =============================================================================

template addMethodImpl(
    b: RequestBuilder, T: typedesc, suffix: string, req: typed, RespType: typedesc
): untyped =
  ## Shared boilerplate for non-query add* functions: mixin resolution,
  ## toJson serialisation, invocation accumulation, handle wrapping.
  mixin methodNamespace, capabilityUri
  let args = req.toJson()
  let (newBuilder, callId) =
    addInvocation(b, methodNamespace(T) & "/" & suffix, args, capabilityUri(T))
  (newBuilder, ResponseHandle[RespType](callId))

# =============================================================================
# addEcho — Core/echo (RFC 8620 section 4)
# =============================================================================

func addEcho*(
    b: RequestBuilder, args: JsonNode
): (RequestBuilder, ResponseHandle[JsonNode]) =
  ## Adds a Core/echo invocation (RFC 8620 section 4). The server echoes
  ## the arguments back unchanged. Useful for connectivity testing.
  let (newBuilder, callId) =
    b.addInvocation("Core/echo", args, "urn:ietf:params:jmap:core")
  return (newBuilder, ResponseHandle[JsonNode](callId))

# =============================================================================
# addGet — Foo/get (RFC 8620 section 5.1)
# =============================================================================

func addGet*[T](
    b: RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ResponseHandle[GetResponse[T]]) =
  ## Adds a Foo/get invocation. Fetches objects by identifiers, optionally
  ## returning only a subset of properties.
  let req = GetRequest[T](accountId: accountId, ids: ids, properties: properties)
  addMethodImpl(b, T, "get", req, GetResponse[T])

# =============================================================================
# addChanges — Foo/changes (RFC 8620 section 5.2)
# =============================================================================

func addChanges*[T](
    b: RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, ResponseHandle[ChangesResponse[T]]) =
  ## Adds a Foo/changes invocation. Retrieves identifiers for records that
  ## have changed since a given state.
  let req = ChangesRequest[T](
    accountId: accountId, sinceState: sinceState, maxChanges: maxChanges
  )
  addMethodImpl(b, T, "changes", req, ChangesResponse[T])

# =============================================================================
# addSet — Foo/set (RFC 8620 section 5.3)
# =============================================================================

func addSet*[T](
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, JsonNode]] = Opt.none(Table[CreationId, JsonNode]),
    update: Opt[Table[Id, PatchObject]] = Opt.none(Table[Id, PatchObject]),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): (RequestBuilder, ResponseHandle[SetResponse[T]]) =
  ## Adds a Foo/set invocation. Creates, updates, and/or destroys records
  ## in a single method call.
  let req = SetRequest[T](
    accountId: accountId,
    ifInState: ifInState,
    create: create,
    update: update,
    destroy: destroy,
  )
  addMethodImpl(b, T, "set", req, SetResponse[T])

# =============================================================================
# addCopy — Foo/copy (RFC 8620 section 5.4)
# =============================================================================

func addCopy*[T](
    b: RequestBuilder,
    fromAccountId: AccountId,
    accountId: AccountId,
    create: Table[CreationId, JsonNode],
    ifFromInState: Opt[JmapState] = Opt.none(JmapState),
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    onSuccessDestroyOriginal: bool = false,
    destroyFromIfInState: Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, ResponseHandle[CopyResponse[T]]) =
  ## Adds a Foo/copy invocation. Copies records from one account to another.
  let req = CopyRequest[T](
    fromAccountId: fromAccountId,
    ifFromInState: ifFromInState,
    accountId: accountId,
    ifInState: ifInState,
    create: create,
    onSuccessDestroyOriginal: onSuccessDestroyOriginal,
    destroyFromIfInState: destroyFromIfInState,
  )
  addMethodImpl(b, T, "copy", req, CopyResponse[T])

# =============================================================================
# addQuery — Foo/query (RFC 8620 section 5.5)
# =============================================================================

func addQuery*[T, C](
    b: RequestBuilder,
    accountId: AccountId,
    filterConditionToJson: proc(c: C): JsonNode {.noSideEffect, raises: [].},
    filter: Opt[Filter[C]] = Opt.none(Filter[C]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    queryParams: QueryParams = QueryParams(),
): (RequestBuilder, ResponseHandle[QueryResponse[T]]) =
  ## Adds a Foo/query invocation. Searches, sorts, and windows entity data
  ## on the server. ``C`` is the filter condition type, resolved from
  ## ``filterType(T)`` by the caller.
  mixin methodNamespace, capabilityUri
  let req = QueryRequest[T, C](
    accountId: accountId,
    filter: filter,
    sort: sort,
    position: queryParams.position,
    anchor: queryParams.anchor,
    anchorOffset: queryParams.anchorOffset,
    limit: queryParams.limit,
    calculateTotal: queryParams.calculateTotal,
  )
  let args = req.toJson(filterConditionToJson)
  let (newBuilder, callId) =
    addInvocation(b, methodNamespace(T) & "/query", args, capabilityUri(T))
  (newBuilder, ResponseHandle[QueryResponse[T]](callId))

# =============================================================================
# addQueryChanges — Foo/queryChanges (RFC 8620 section 5.6)
# =============================================================================

func addQueryChanges*[T, C](
    b: RequestBuilder,
    accountId: AccountId,
    sinceQueryState: JmapState,
    filterConditionToJson: proc(c: C): JsonNode {.noSideEffect, raises: [].},
    filter: Opt[Filter[C]] = Opt.none(Filter[C]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    upToId: Opt[Id] = Opt.none(Id),
    queryParams: QueryParams = QueryParams(),
): (RequestBuilder, ResponseHandle[QueryChangesResponse[T]]) =
  ## Adds a Foo/queryChanges invocation. Efficiently updates a cached query
  ## to match the new server state. ``C`` is the filter condition type.
  ##
  ## Only ``queryParams.calculateTotal`` is used — the remaining four
  ## query window fields (position, anchor, anchorOffset, limit) are
  ## not applicable to /queryChanges (RFC 8620 section 5.6) and are
  ## ignored.
  mixin methodNamespace, capabilityUri
  let req = QueryChangesRequest[T, C](
    accountId: accountId,
    filter: filter,
    sort: sort,
    sinceQueryState: sinceQueryState,
    maxChanges: maxChanges,
    upToId: upToId,
    calculateTotal: queryParams.calculateTotal,
  )
  let args = req.toJson(filterConditionToJson)
  let (newBuilder, callId) =
    addInvocation(b, methodNamespace(T) & "/queryChanges", args, capabilityUri(T))
  (newBuilder, ResponseHandle[QueryChangesResponse[T]](callId))

# =============================================================================
# Single-type-parameter query overloads (resolve filter via template expansion)
# =============================================================================
#
# These are templates (not procs) because filterType(T) must appear in type
# positions that are resolved at the call site. Nim's `mixin` only affects
# the function body, not the parameter signature. Templates expand at the
# call site where filterType is visible, avoiding this limitation.
#
# The two-parameter `addQuery[T, C]` func remains as an escape hatch for
# custom filter types not registered via the entity framework.

template addQuery*[T](
    b: RequestBuilder, accountId: AccountId
): (RequestBuilder, ResponseHandle[QueryResponse[T]]) =
  ## Single-type-parameter Foo/query. Resolves the filter condition type
  ## from ``filterType(T)`` and the serialisation callback from
  ## ``filterConditionToJson`` at the call site (template expansion).
  ##
  ## This closes a type-safety gap: the two-parameter ``addQuery[T, C]``
  ## allows ``C != filterType(T)``, which compiles but produces semantically
  ## wrong JSON. This overload makes that impossible.
  ##
  ## For queries with filters or custom ``QueryParams``, use the
  ## two-parameter ``addQuery[T, C]`` overload which accepts both.
  addQuery[T, filterType(T)](
    b,
    accountId,
    proc(c: filterType(T)): JsonNode {.noSideEffect, raises: [].} =
      filterConditionToJson(c),
  )

template addQueryChanges*[T](
    b: RequestBuilder, accountId: AccountId, sinceQueryState: JmapState
): (RequestBuilder, ResponseHandle[QueryChangesResponse[T]]) =
  ## Single-type-parameter Foo/queryChanges. Same resolution as ``addQuery[T]``.
  ## For custom ``QueryParams``, use the two-parameter
  ## ``addQueryChanges[T, C]`` overload.
  addQueryChanges[T, filterType(T)](
    b,
    accountId,
    sinceQueryState,
    proc(c: filterType(T)): JsonNode {.noSideEffect, raises: [].} =
      filterConditionToJson(c),
  )

# =============================================================================
# Argument-construction helpers (reduce Opt.some/direct nesting at call sites)
# =============================================================================

func directIds*(ids: openArray[Id]): Opt[Referencable[seq[Id]]] =
  ## Wraps a sequence of IDs into ``Opt[Referencable[seq[Id]]]`` for direct
  ## (non-reference) use. Eliminates the ``Opt.some(direct(@[...]))`` nesting
  ## at call sites.
  ##
  ## **Before:** ``addGet[T](b, acctId, ids = Opt.some(direct(@[id1, id2])))``
  ## **After:** ``addGet[T](b, acctId, ids = directIds(@[id1, id2]))``
  return Opt.some(direct(@ids))

func initCreates*(
    pairs: openArray[(CreationId, JsonNode)]
): Opt[Table[CreationId, JsonNode]] =
  ## Builds an Opt-wrapped create table from CreationId/JsonNode pairs.
  ## Keys must be validated ``CreationId`` values — preserves smart-constructor
  ## discipline. Use ``parseCreationId`` or test helper ``makeCreationId``
  ## to obtain keys.
  var tbl = initTable[CreationId, JsonNode](pairs.len)
  for (k, v) in pairs:
    tbl[k] = v
  return Opt.some(tbl)

func initUpdates*(pairs: openArray[(Id, PatchObject)]): Opt[Table[Id, PatchObject]] =
  ## Builds an Opt-wrapped update table from Id/PatchObject pairs.
  ## Keys must be validated ``Id`` values.
  var tbl = initTable[Id, PatchObject](pairs.len)
  for (k, v) in pairs:
    tbl[k] = v
  return Opt.some(tbl)
