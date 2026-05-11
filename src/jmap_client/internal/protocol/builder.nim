# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Request builder for constructing JMAP method call batches (RFC 8620
## section 3.3). Accumulates typed method invocations and capability URIs,
## producing a complete Request envelope via ``build()``. Each ``add*``
## function returns a phantom-typed ``ResponseHandle[T]`` for type-safe
## response extraction via ``dispatch.get[T]``.
##
## **Pure functional core.** Each ``add*`` returns a new
## ``(RequestBuilder, ResponseHandle[T])`` tuple.
##
## **Capability auto-collection.** Each ``add*`` registers its entity's
## capability URI. The ``using`` array in the built Request is automatically
## deduplicated.
##
## **Call ID generation.** Auto-incrementing "c0", "c1", "c2"... (Decision
## 3.2A). Call IDs are scoped to a single builder instance.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ../../types
import ../../serialisation
import ./methods
import ./dispatch
import ./call_meta

# =============================================================================
# RequestBuilder type
# =============================================================================

{.push ruleOff: "objects".}

type RequestBuilder* = object
  ## Immutable accumulator for constructing a JMAP Request (RFC 8620
  ## section 3.3).
  nextCallId: int ## monotonic counter for "c0", "c1", ...
  invocations: seq[Invocation] ## accumulated method calls
  callLimits: seq[CallLimitMeta]
    ## per-call object-count metadata, parallel to invocations
  capabilityUris: seq[string] ## deduplicated capability URIs

{.pop.}

func initRequestBuilder*(): RequestBuilder =
  ## Creates a fresh builder with counter at zero, no invocations, and
  ## ``urn:ietf:params:jmap:core`` pre-declared in ``using``. RFC 8620
  ## §3.2 obliges clients to declare every capability they need to use;
  ## ``core`` is the foundational namespace that every JMAP method
  ## implicitly relies on (Result-Reference, sessionState, etc.). Lenient
  ## servers (Stalwart 0.15.5) accept requests with ``core`` omitted;
  ## strict servers (Apache James 3.9) reject them with
  ## ``unknownMethod (Missing capability(ies): urn:ietf:params:jmap:core)``.
  ## Pre-declaring it makes the client portable across both.
  return RequestBuilder(
    nextCallId: 0,
    invocations: @[],
    callLimits: @[],
    capabilityUris: @["urn:ietf:params:jmap:core"],
  )

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

func callLimits*(b: RequestBuilder): seq[CallLimitMeta] =
  ## Per-call limit metadata, parallel to ``b.build().methodCalls``.
  ## Internal-only API — used by ``client.validateLimits(builder, caps)``
  ## to enforce server-declared ``maxObjectsInGet`` and
  ## ``maxObjectsInSet`` from typed counts rather than raw JSON
  ## traversal of ``inv.arguments``. Excluded from the hub re-export
  ## (``protocol.nim``); reachable only via direct internal import.
  return b.callLimits

# =============================================================================
# Build — pure snapshot
# =============================================================================

func build*(b: RequestBuilder): Request =
  ## Snapshot of the current builder state.
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
    b: RequestBuilder,
    name: MethodName,
    args: JsonNode,
    capability: string,
    meta: CallLimitMeta = CallLimitMeta(kind: clmOther),
): (RequestBuilder, MethodCallId) =
  ## Constructs an Invocation and returns a new builder with it accumulated.
  ## ``name`` is typed — illegal (empty) names are structurally impossible.
  ## ``meta`` records the per-call object-count signature for
  ## ``client.validateLimits``; defaults to ``clmOther`` (no per-call
  ## object-count limit applies).
  let callId = b.nextId()
  let inv = initInvocation(name, args, callId)
  return (
    RequestBuilder(
      nextCallId: b.nextCallId + 1,
      invocations: b.invocations & @[inv],
      callLimits: b.callLimits & @[meta],
      capabilityUris: withCapability(b.capabilityUris, capability),
    ),
    callId,
  )

# =============================================================================
# Template for non-query add* methods
# =============================================================================

template addMethodImpl(
    b: RequestBuilder,
    T: typedesc,
    methodNameResolver: untyped,
    req: typed,
    RespType: typedesc,
): untyped =
  ## Shared boilerplate for non-query add* functions: mixin resolution,
  ## toJson serialisation, invocation accumulation, handle wrapping.
  ## ``methodNameResolver`` is the per-verb resolver (e.g. ``getMethodName``),
  ## resolved via ``mixin`` at the caller's scope. Passing the wrong verb
  ## for an entity (e.g. ``setMethodName`` on Thread) is a compile error.
  mixin methodNameResolver, capabilityUri
  let args = req.toJson()
  let (newBuilder, callId) =
    addInvocation(b, methodNameResolver(T), args, capabilityUri(T))
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
    b.addInvocation(mnCoreEcho, args, "urn:ietf:params:jmap:core")
  return (newBuilder, ResponseHandle[JsonNode](callId))

# =============================================================================
# addGet — Foo/get (RFC 8620 section 5.1)
# =============================================================================

func addGet*[T](
    b: RequestBuilder,
    accountId: AccountId,
    ids: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
    extras: seq[(string, JsonNode)] = @[],
): (RequestBuilder, ResponseHandle[GetResponse[T]]) =
  ## Adds a Foo/get invocation. Fetches objects by identifiers, optionally
  ## returning only a subset of properties. Entity-specific extension keys
  ## (e.g. Email/get's body-fetch options) are supplied via ``extras`` and
  ## appended to the args after the standard frame (insertion order preserved).
  mixin getMethodName, capabilityUri
  let req = GetRequest[T](accountId: accountId, ids: ids, properties: properties)
  var args = req.toJson()
  for (k, v) in extras:
    args[k] = v
  var idCount = Opt.some(0)
  for r in ids:
    case r.kind
    of rkDirect:
      idCount = Opt.some(r.value.len)
    of rkReference:
      idCount = Opt.none(int)
  let meta = CallLimitMeta(kind: clmGet, idCount: idCount)
  let (newBuilder, callId) =
    addInvocation(b, getMethodName(T), args, capabilityUri(T), meta)
  (newBuilder, ResponseHandle[GetResponse[T]](callId))

# =============================================================================
# addChanges — Foo/changes (RFC 8620 section 5.2)
# =============================================================================

func addChanges*[T, RespT](
    b: RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): (RequestBuilder, ResponseHandle[RespT]) =
  ## Adds a Foo/changes invocation. Retrieves identifiers for records that
  ## have changed since a given state. ``RespT`` is the concrete response
  ## type the caller expects — ``ChangesResponse[T]`` for standard entities,
  ## or an extended composition type (e.g. ``MailboxChangesResponse`` with
  ## its RFC 8621 §2.2 ``updatedProperties`` field). Request wire shape is
  ## unchanged; only the typed response varies.
  let req = ChangesRequest[T](
    accountId: accountId, sinceState: sinceState, maxChanges: maxChanges
  )
  addMethodImpl(b, T, changesMethodName, req, RespT)

template addChanges*[T](
    b: RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
): untyped =
  ## Single-type-parameter Foo/changes alias. Resolves
  ## ``changesResponseType(T)`` at the call site via template expansion;
  ## delegates to the two-parameter ``addChanges[T, RespT]`` with that
  ## resolved response type. Every registered entity module supplies its
  ## own ``changesResponseType(T)`` template (see
  ## ``mail/mail_entities.nim`` for the five mail entities).
  addChanges[T, changesResponseType(T)](b, accountId, sinceState, maxChanges)

# =============================================================================
# addSet — Foo/set (RFC 8620 section 5.3)
# =============================================================================

func addSet*[T, C, U, R](
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, C]] = Opt.none(Table[CreationId, C]),
    update: Opt[U] = Opt.none(U),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    extras: seq[(string, JsonNode)] = @[],
): (RequestBuilder, ResponseHandle[R]) =
  ## Foo/set (RFC 8620 section 5.3). ``T`` = entity, ``C`` = typed create
  ## value, ``U`` = whole-container update algebra, ``R`` = response type.
  ## Entity-specific extension keys are supplied via ``extras`` and
  ## appended to the args after the standard frame (insertion order
  ## preserved). ``setMethodName``, ``capabilityUri``, ``C.toJson``,
  ## ``U.toJson``, and ``U.len`` all resolve at instantiation via
  ## ``mixin``.
  mixin setMethodName, capabilityUri, toJson, len
  let req = SetRequest[T, C, U](
    accountId: accountId,
    ifInState: ifInState,
    create: create,
    update: update,
    destroy: destroy,
  )
  var args = req.toJson()
  for (k, v) in extras:
    args[k] = v
  var n = 0
  var anyReference = false
  for c in create:
    n += c.len
  for u in update:
    n += u.len
  for d in destroy:
    case d.kind
    of rkDirect:
      n += d.value.len
    of rkReference:
      anyReference = true
  let objectCount: Opt[int] =
    if anyReference:
      Opt.none(int)
    else:
      Opt.some(n)
  let meta = CallLimitMeta(kind: clmSet, objectCount: objectCount)
  let (newBuilder, callId) =
    addInvocation(b, setMethodName(T), args, capabilityUri(T), meta)
  (newBuilder, ResponseHandle[R](callId))

# =============================================================================
# addCopy — Foo/copy (RFC 8620 section 5.4)
# =============================================================================

func addCopy*[T, CopyItem, R](
    b: RequestBuilder,
    fromAccountId: AccountId,
    accountId: AccountId,
    create: Table[CreationId, CopyItem],
    ifFromInState: Opt[JmapState] = Opt.none(JmapState),
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    destroyMode: CopyDestroyMode = keepOriginals(),
    extras: seq[(string, JsonNode)] = @[],
): (RequestBuilder, ResponseHandle[R]) =
  ## Foo/copy (RFC 8620 section 5.4). ``T`` = entity, ``CopyItem`` = typed
  ## per-entry create-value, ``R`` = response type. ``destroyMode`` defaults
  ## to ``keepOriginals()``; entity-specific extension keys arrive via
  ## ``extras`` and are appended to the args after the standard frame
  ## (insertion order preserved). ``copyMethodName``, ``capabilityUri``,
  ## and ``CopyItem.toJson`` resolve at instantiation via ``mixin``.
  ## Per RFC 8620 §5.4, /copy is a /set-class operation; the meta carries
  ## ``objectCount = Opt.some(create.len)``.
  mixin copyMethodName, capabilityUri, toJson
  let req = CopyRequest[T, CopyItem](
    fromAccountId: fromAccountId,
    ifFromInState: ifFromInState,
    accountId: accountId,
    ifInState: ifInState,
    create: create,
    destroyMode: destroyMode,
  )
  var args = req.toJson()
  for (k, v) in extras:
    args[k] = v
  let meta = CallLimitMeta(kind: clmSet, objectCount: Opt.some(create.len))
  let (newBuilder, callId) =
    addInvocation(b, copyMethodName(T), args, capabilityUri(T), meta)
  (newBuilder, ResponseHandle[R](callId))

# =============================================================================
# addQuery — Foo/query (RFC 8620 section 5.5)
# =============================================================================

func addQuery*[T, C, SortT](
    b: RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[C]] = default(Opt[Filter[C]]),
    sort: Opt[seq[SortT]] = default(Opt[seq[SortT]]),
    queryParams: QueryParams = QueryParams(),
    extras: seq[(string, JsonNode)] = @[],
): (RequestBuilder, ResponseHandle[QueryResponse[T]]) =
  ## Foo/query. ``T`` = entity, ``C`` = filter-condition type, ``SortT`` =
  ## sort-element type. Entity-specific extension keys are supplied via
  ## ``extras`` and merged into the args after the standard frame
  ## (insertion order preserved). ``C.toJson`` resolves via ``mixin`` at
  ## the caller's instantiation scope through the
  ## ``serializeOptFilter`` → ``Filter[C].toJson`` cascade.
  mixin queryMethodName, capabilityUri, toJson
  var args = assembleQueryArgs(
    accountId, serializeOptFilter(filter), serializeOptSort(sort), queryParams
  )
  for (k, v) in extras:
    args[k] = v
  let (newBuilder, callId) =
    addInvocation(b, queryMethodName(T), args, capabilityUri(T))
  (newBuilder, ResponseHandle[QueryResponse[T]](callId))

# =============================================================================
# addQueryChanges — Foo/queryChanges (RFC 8620 section 5.6)
# =============================================================================

func addQueryChanges*[T, C, SortT](
    b: RequestBuilder,
    accountId: AccountId,
    sinceQueryState: JmapState,
    filter: Opt[Filter[C]] = default(Opt[Filter[C]]),
    sort: Opt[seq[SortT]] = default(Opt[seq[SortT]]),
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    upToId: Opt[Id] = Opt.none(Id),
    calculateTotal: bool = false,
    extras: seq[(string, JsonNode)] = @[],
): (RequestBuilder, ResponseHandle[QueryChangesResponse[T]]) =
  ## Foo/queryChanges. Takes ``calculateTotal`` directly — RFC 8620
  ## section 5.6 defines no window fields for /queryChanges. ``C.toJson``
  ## resolves via ``mixin`` at the caller's instantiation scope.
  mixin queryChangesMethodName, capabilityUri, toJson
  var args = assembleQueryChangesArgs(
    accountId,
    sinceQueryState,
    serializeOptFilter(filter),
    serializeOptSort(sort),
    maxChanges,
    upToId,
    calculateTotal,
  )
  for (k, v) in extras:
    args[k] = v
  let (newBuilder, callId) =
    addInvocation(b, queryChangesMethodName(T), args, capabilityUri(T))
  (newBuilder, ResponseHandle[QueryChangesResponse[T]](callId))

# =============================================================================
# Single-type-parameter query overloads (resolve filter via template expansion)
# =============================================================================
#
# Templates because filterType(T) must appear in type positions that are
# resolved at the call site. For entity-typed sort, use the three-parameter
# addQuery[T, C, S] / addQueryChanges[T, C, S] forms directly.

template addQuery*[T](
    b: RequestBuilder, accountId: AccountId
): (RequestBuilder, ResponseHandle[QueryResponse[T]]) =
  ## Single-type-parameter Foo/query. Resolves the filter condition type
  ## from ``filterType(T)`` at the call site; uses the protocol-level
  ## ``Comparator`` for sort. For entity-typed sort, use the three-parameter
  ## ``addQuery[T, C, S]`` directly.
  addQuery[T, filterType(T), Comparator](b, accountId)

template addQueryChanges*[T](
    b: RequestBuilder, accountId: AccountId, sinceQueryState: JmapState
): (RequestBuilder, ResponseHandle[QueryChangesResponse[T]]) =
  ## Single-type-parameter Foo/queryChanges. Same resolution as ``addQuery[T]``.
  addQueryChanges[T, filterType(T), Comparator](b, accountId, sinceQueryState)

template addSet*[T](b: RequestBuilder, accountId: AccountId): untyped =
  ## Single-type-parameter Foo/set alias. Resolves ``createType(T)``,
  ## ``updateType(T)``, and ``setResponseType(T)`` at the call site via
  ## template expansion; delegates to the four-parameter
  ## ``addSet[T, C, U, R]``. For calls that supply ``create`` / ``update``
  ## / ``destroy`` / ``extras`` (the common case), invoke the four-parameter
  ## form directly — the template deliberately takes only ``b`` and
  ## ``accountId`` to avoid referencing template-returning-typedesc calls
  ## inside a template's own parameter-list default expressions (Nim limitation).
  addSet[T, createType(T), updateType(T), setResponseType(T)](b, accountId)

template addCopy*[T](
    b: RequestBuilder, fromAccountId: AccountId, accountId: AccountId, create: untyped
): untyped =
  ## Single-type-parameter Foo/copy alias. Resolves ``copyItemType(T)``
  ## and ``copyResponseType(T)`` at the call site via template expansion;
  ## delegates to the three-parameter ``addCopy[T, CopyItem, R]``.
  ## For calls that override ``ifFromInState`` / ``ifInState`` /
  ## ``destroyMode`` / ``extras``, invoke the three-parameter form directly.
  addCopy[T, copyItemType(T), copyResponseType(T)](b, fromAccountId, accountId, create)

# =============================================================================
# Argument-construction helpers (reduce Opt.some/direct nesting at call sites)
# =============================================================================

func directIds*(ids: openArray[Id]): Opt[Referencable[seq[Id]]] =
  ## Wraps a sequence of IDs into ``Opt[Referencable[seq[Id]]]`` for direct
  ## (non-reference) use. Eliminates the ``Opt.some(direct(@[...]))`` nesting
  ## at call sites.
  return Opt.some(direct(@ids))

func initCreates*(
    pairs: openArray[(CreationId, JsonNode)]
): Opt[Table[CreationId, JsonNode]] =
  ## Builds an Opt-wrapped create table from CreationId/JsonNode pairs.
  ## Keys must be validated ``CreationId`` values — preserves smart-constructor
  ## discipline. Use ``parseCreationId`` to obtain keys.
  var tbl = initTable[CreationId, JsonNode](pairs.len)
  for (k, v) in pairs:
    tbl[k] = v
  return Opt.some(tbl)
