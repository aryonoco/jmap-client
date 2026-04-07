# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Request builder for constructing JMAP method call batches (RFC 8620
## section 3.3). Accumulates typed method invocations and capability URIs,
## producing a complete Request envelope via ``build()``. Each ``add*``
## function returns a phantom-typed ``ResponseHandle[T]`` for type-safe
## response extraction via ``dispatch.get[T]``.
##
## **Functional core.** The builder uses owned ``var`` mutation under
## ``func`` — the Nim equivalent of a State computation. ``build()`` is a
## pure snapshot projection. The effect boundary is at Layer 4's
## ``proc send()``.
##
## **Capability auto-collection.** Each ``add*`` registers its entity's
## capability URI. The ``using`` array in the built Request is automatically
## deduplicated — no manual management required.
##
## **Call ID generation.** Auto-incrementing "c0", "c1", "c2"... (Decision
## 3.2A). Call IDs are scoped to a single builder instance.

{.push raises: [].}

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
  ## Accumulates method calls and capabilities for constructing a JMAP
  ## Request (RFC 8620 section 3.3). All fields are private — the builder
  ## is the sole construction and mutation path.
  nextCallId: int ## monotonic counter for "c0", "c1", ...
  invocations: seq[Invocation] ## accumulated method calls
  capabilityUris: seq[string] ## deduplicated capability URIs

{.pop.}

func initRequestBuilder*(): RequestBuilder =
  ## Creates a fresh builder with counter at zero, no invocations, no
  ## capabilities.
  RequestBuilder(nextCallId: 0, invocations: @[], capabilityUris: @[])

# =============================================================================
# Read-only accessors (immutability by default)
# =============================================================================

func methodCallCount*(b: RequestBuilder): int =
  ## Number of method calls accumulated so far.
  b.invocations.len

func isEmpty*(b: RequestBuilder): bool =
  ## True if no method calls have been added.
  b.invocations.len == 0

func capabilities*(b: RequestBuilder): seq[string] =
  ## Snapshot of the deduplicated capability URIs registered so far.
  b.capabilityUris

# =============================================================================
# Build — pure snapshot
# =============================================================================

func build*(b: RequestBuilder): Request =
  ## Pure snapshot of the current builder state. Does not mutate the builder.
  ## ``createdIds`` is always none — proxy splitting is a Layer 4 concern.
  ## The builder can continue accumulating after ``build()`` for sequential
  ## requests.
  Request(
    `using`: b.capabilityUris,
    methodCalls: b.invocations,
    createdIds: Opt.none(Table[CreationId, Id]),
  )

# =============================================================================
# Internal helpers (not exported)
# =============================================================================

func nextId(b: var RequestBuilder): MethodCallId =
  ## Generates "c0", "c1", ... via direct MethodCallId construction.
  ## Bypasses parseMethodCallId because the format is provably valid (D3.9).
  let callId = MethodCallId("c" & $b.nextCallId)
  b.nextCallId += 1
  callId

func addCapability(b: var RequestBuilder, cap: string) =
  ## Adds a capability URI if not already present.
  if cap notin b.capabilityUris:
    b.capabilityUris.add(cap)

func addInvocation(
    b: var RequestBuilder, name: string, args: JsonNode, capability: string
): MethodCallId =
  ## Constructs an Invocation, accumulates it, and registers the capability.
  let callId = b.nextId()
  let inv = initInvocationUnchecked(name, args, callId)
  b.invocations.add(inv)
  b.addCapability(capability)
  callId

# =============================================================================
# DRY template for non-query add* methods
# =============================================================================

template addMethodImpl(
    b: var RequestBuilder, T: typedesc, suffix: string, req: typed, RespType: typedesc
): untyped =
  ## Shared boilerplate for non-query add* functions: mixin resolution,
  ## toJson serialisation, invocation accumulation, handle wrapping.
  mixin methodNamespace, capabilityUri
  let args = req.toJson()
  let callId =
    addInvocation(b, methodNamespace(T) & "/" & suffix, args, capabilityUri(T))
  ResponseHandle[RespType](callId)

# =============================================================================
# addEcho — Core/echo (RFC 8620 section 4)
# =============================================================================

func addEcho*(b: var RequestBuilder, args: JsonNode): ResponseHandle[JsonNode] =
  ## Adds a Core/echo invocation (RFC 8620 section 4). The server echoes
  ## the arguments back unchanged. Useful for connectivity testing.
  let callId = b.addInvocation("Core/echo", args, "urn:ietf:params:jmap:core")
  ResponseHandle[JsonNode](callId)

# =============================================================================
# addGet — Foo/get (RFC 8620 section 5.1)
# =============================================================================

func addGet*[T](
    b: var RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): ResponseHandle[GetResponse[T]] =
  ## Adds a Foo/get invocation. Fetches objects by identifiers, optionally
  ## returning only a subset of properties.
  let req = GetRequest[T](accountId: accountId, ids: ids, properties: properties)
  addMethodImpl(b, T, "get", req, GetResponse[T])

# =============================================================================
# addChanges — Foo/changes (RFC 8620 section 5.2)
# =============================================================================

func addChanges*[T](
    b: var RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): ResponseHandle[ChangesResponse[T]] =
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
    b: var RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, JsonNode]] = Opt.none(Table[CreationId, JsonNode]),
    update: Opt[Table[Id, PatchObject]] = Opt.none(Table[Id, PatchObject]),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
): ResponseHandle[SetResponse[T]] =
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
    b: var RequestBuilder,
    fromAccountId: AccountId,
    accountId: AccountId,
    create: Table[CreationId, JsonNode],
    ifFromInState: Opt[JmapState] = Opt.none(JmapState),
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    onSuccessDestroyOriginal: bool = false,
    destroyFromIfInState: Opt[JmapState] = Opt.none(JmapState),
): ResponseHandle[CopyResponse[T]] =
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

proc addQuery*[T, C](
    b: var RequestBuilder,
    accountId: AccountId,
    filterConditionToJson: proc(c: C): JsonNode {.noSideEffect, raises: [].},
    filter: Opt[Filter[C]] = Opt.none(Filter[C]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    position: JmapInt = JmapInt(0),
    anchor: Opt[Id] = Opt.none(Id),
    anchorOffset: JmapInt = JmapInt(0),
    limit: Opt[UnsignedInt] = Opt.none(UnsignedInt),
    calculateTotal: bool = false,
): ResponseHandle[QueryResponse[T]] =
  ## Adds a Foo/query invocation. Searches, sorts, and windows entity data
  ## on the server. ``C`` is the filter condition type, resolved from
  ## ``filterType(T)`` by the caller.
  ##
  ## Must be ``proc`` (not ``func``) because ``filterConditionToJson`` is a
  ## ``proc`` callback parameter.
  mixin methodNamespace, capabilityUri
  let req = QueryRequest[T, C](
    accountId: accountId,
    filter: filter,
    sort: sort,
    position: position,
    anchor: anchor,
    anchorOffset: anchorOffset,
    limit: limit,
    calculateTotal: calculateTotal,
  )
  let args = req.toJson(filterConditionToJson)
  let callId = addInvocation(b, methodNamespace(T) & "/query", args, capabilityUri(T))
  ResponseHandle[QueryResponse[T]](callId)

# =============================================================================
# addQueryChanges — Foo/queryChanges (RFC 8620 section 5.6)
# =============================================================================

proc addQueryChanges*[T, C](
    b: var RequestBuilder,
    accountId: AccountId,
    sinceQueryState: JmapState,
    filterConditionToJson: proc(c: C): JsonNode {.noSideEffect, raises: [].},
    filter: Opt[Filter[C]] = Opt.none(Filter[C]),
    sort: Opt[seq[Comparator]] = Opt.none(seq[Comparator]),
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    upToId: Opt[Id] = Opt.none(Id),
    calculateTotal: bool = false,
): ResponseHandle[QueryChangesResponse[T]] =
  ## Adds a Foo/queryChanges invocation. Efficiently updates a cached query
  ## to match the new server state. ``C`` is the filter condition type.
  mixin methodNamespace, capabilityUri
  let req = QueryChangesRequest[T, C](
    accountId: accountId,
    filter: filter,
    sort: sort,
    sinceQueryState: sinceQueryState,
    maxChanges: maxChanges,
    upToId: upToId,
    calculateTotal: calculateTotal,
  )
  let args = req.toJson(filterConditionToJson)
  let callId =
    addInvocation(b, methodNamespace(T) & "/queryChanges", args, capabilityUri(T))
  ResponseHandle[QueryChangesResponse[T]](callId)

# =============================================================================
# Single-type-parameter query overloads (resolve filter via template expansion)
# =============================================================================
#
# These are templates (not procs) because filterType(T) must appear in type
# positions that are resolved at the call site. Nim's `mixin` only affects
# the function body, not the parameter signature. Templates expand at the
# call site where filterType is visible, avoiding this limitation.
#
# The two-parameter `addQuery[T, C]` proc remains as an escape hatch for
# custom filter types not registered via the entity framework.

template addQuery*[T](
    b: var RequestBuilder, accountId: AccountId
): ResponseHandle[QueryResponse[T]] =
  ## Single-type-parameter Foo/query. Resolves the filter condition type
  ## from ``filterType(T)`` and the serialisation callback from
  ## ``filterConditionToJson`` at the call site (template expansion).
  ##
  ## This closes a type-safety gap: the two-parameter ``addQuery[T, C]``
  ## allows ``C != filterType(T)``, which compiles but produces semantically
  ## wrong JSON. This overload makes that impossible.
  ##
  ## For queries with filters, use the two-parameter ``addQuery[T, C]``
  ## overload which accepts a filter parameter, or use ``addQuery[T]`` for
  ## filterless queries and add filters via the pipeline combinators.
  addQuery[T, filterType(T)](
    b,
    accountId,
    proc(c: filterType(T)): JsonNode {.noSideEffect, raises: [].} =
      filterConditionToJson(c),
  )

template addQueryChanges*[T](
    b: var RequestBuilder, accountId: AccountId, sinceQueryState: JmapState
): ResponseHandle[QueryChangesResponse[T]] =
  ## Single-type-parameter Foo/queryChanges. Same resolution as ``addQuery[T]``.
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
  Opt.some(direct(@ids))

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
  Opt.some(tbl)

func initUpdates*(pairs: openArray[(Id, PatchObject)]): Opt[Table[Id, PatchObject]] =
  ## Builds an Opt-wrapped update table from Id/PatchObject pairs.
  ## Keys must be validated ``Id`` values.
  var tbl = initTable[Id, PatchObject](pairs.len)
  for (k, v) in pairs:
    tbl[k] = v
  Opt.some(tbl)
