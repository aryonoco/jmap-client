# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Request builder for constructing JMAP method call batches (RFC 8620
## section 3.3). Accumulates typed method invocations and capability URIs,
## producing a sealed ``BuiltRequest`` via ``freeze()``. Each ``add*``
## function returns a phantom-typed ``ResponseHandle[T]`` for type-safe
## response extraction via ``dispatch.get[T]``.
##
## **Lifecycle.** ``RequestBuilder`` (mutable accumulator) → ``BuiltRequest``
## (frozen, branded carrier) → ``DispatchedResponse`` (received, branded
## artifact) → ``T`` (typed value). Each phase is a distinct type; the
## brand carried on every handle and every dispatched response makes
## cross-builder and cross-client misuse a programming error caught at
## extraction time (``gekHandleMismatch``).
##
## **Pure functional core.** Each ``add*`` returns a new
## ``(RequestBuilder, ResponseHandle[T])`` tuple.
##
## **Capability auto-collection.** Each ``add*`` registers its entity's
## capability URI. The ``using`` array in the built Request is automatically
## deduplicated.
##
## **Call ID generation.** Auto-incrementing "c0", "c1", "c2"... (Decision
## 3.2A). Call IDs are scoped to a single builder instance; the
## ``BuilderId`` brand distinguishes builder instances.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/sequtils
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
  ## section 3.3). Each builder carries a ``BuilderId`` brand minted at
  ## construction; that brand travels into every handle the builder
  ## issues and into the ``BuiltRequest`` produced by ``freeze``, so
  ## extraction can detect cross-builder / cross-client misuse.
  id: BuilderId ## per-builder dispatch brand
  nextCallId: int ## monotonic counter for "c0", "c1", ...
  invocations: seq[Invocation] ## accumulated method calls
  callLimits: seq[CallLimitMeta]
    ## per-call object-count metadata, parallel to invocations
  capabilityUris: seq[CapabilityUri] ## deduplicated capability URIs

type BuiltRequest* = object
  ## Frozen, dispatch-ready request. Produced by ``RequestBuilder.freeze``;
  ## consumed by ``JmapClient.send``. Carries the builder's brand so the
  ## ``DispatchedResponse`` returned from ``send`` carries the same
  ## brand, allowing handles issued by the same builder to match at
  ## extraction.
  rawRequest: Request
  rawBuilderId: BuilderId
  rawCallLimits: seq[CallLimitMeta]

{.pop.}

func initRequestBuilder*(id: BuilderId): RequestBuilder =
  ## Module-private surface — exported with ``*`` so ``client.nim`` and
  ## tests under ``tests/`` can construct, filtered from the protocol
  ## hub. Creates a fresh builder branded with ``id``, counter at zero,
  ## no invocations, and ``urn:ietf:params:jmap:core`` pre-declared in
  ## ``using``. RFC 8620 §3.2 obliges clients to declare every
  ## capability they need to use; ``core`` is the foundational namespace
  ## that every JMAP method implicitly relies on (Result-Reference,
  ## sessionState, etc.). Lenient servers (Stalwart 0.15.5) accept
  ## requests with ``core`` omitted; strict servers (Apache James 3.9)
  ## reject them with ``unknownMethod (Missing capability(ies):
  ## urn:ietf:params:jmap:core)``. Pre-declaring it makes the client
  ## portable across both.
  return RequestBuilder(
    id: id,
    nextCallId: 0,
    invocations: @[],
    callLimits: @[],
    # literal IETF URN, always parses Ok
    capabilityUris: @[parseCapabilityUri("urn:ietf:params:jmap:core").get()],
  )

func builderId*(b: RequestBuilder): BuilderId =
  ## Hub-private accessor — the builder's brand. Reachable via direct
  ## ``import jmap_client/internal/protocol/builder``; filtered from
  ## the protocol hub so application developers never see brands.
  b.id

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
  ## Returned as ``seq[string]`` for API parity with ``Request.using``
  ## (RFC 8620 §3.3 wire format).
  return b.capabilityUris.mapIt(string(it))

# =============================================================================
# Freeze — sealed snapshot into a branded BuiltRequest
# =============================================================================

func freeze*(b: RequestBuilder): BuiltRequest =
  ## Snapshots the builder's accumulated state into a sealed, branded
  ## carrier. The builder remains immutable (the codebase's existing
  ## accumulator pattern) — ``freeze`` does NOT consume the builder;
  ## callers may continue accumulating into a fresh branch off ``b`` if
  ## they wish, though each new accumulation must eventually ``freeze``
  ## for dispatch. ``createdIds`` is always ``none`` — proxy splitting
  ## is a Layer 4 concern.
  BuiltRequest(
    rawRequest: Request(
      `using`: b.capabilityUris.mapIt(string(it)),
      methodCalls: b.invocations,
      createdIds: Opt.none(Table[CreationId, Id]),
    ),
    rawBuilderId: b.id,
    rawCallLimits: b.callLimits,
  )

func request*(br: BuiltRequest): Request =
  ## Hub-private accessor (filtered from the protocol hub). Reachable
  ## via direct ``import jmap_client/internal/protocol/builder``.
  br.rawRequest

func builderId*(br: BuiltRequest): BuilderId =
  ## Hub-private accessor — the brand of the issuing builder.
  br.rawBuilderId

func callLimits*(br: BuiltRequest): seq[CallLimitMeta] =
  ## Hub-private accessor — per-call object-count metadata, parallel to
  ## ``br.request.methodCalls``. Used by ``client.validateLimits`` to
  ## enforce server-declared ``maxObjectsInGet`` and ``maxObjectsInSet``
  ## from typed counts rather than raw JSON traversal of
  ## ``inv.arguments``.
  br.rawCallLimits

func builtRequestForTest*(
    request: Request, builderId: BuilderId, callLimits: seq[CallLimitMeta] = @[]
): BuiltRequest =
  ## Test-only escape hatch — constructs a ``BuiltRequest`` from raw
  ## components without routing through ``RequestBuilder``. Hub-private
  ## (filtered out of ``protocol.nim``'s re-export). Reachable only via
  ## whitebox internal imports under ``tests/``. Production code MUST
  ## use ``RequestBuilder.freeze()``.
  BuiltRequest(rawRequest: request, rawBuilderId: builderId, rawCallLimits: callLimits)

# =============================================================================
# Internal helpers (not exported)
# =============================================================================

func nextId(b: RequestBuilder): MethodCallId =
  ## Computes the next call ID from the current counter without mutation.
  ## Bypasses parseMethodCallId because the format is provably valid (D3.9).
  MethodCallId("c" & $b.nextCallId)

func withCapability(caps: seq[CapabilityUri], cap: CapabilityUri): seq[CapabilityUri] =
  ## Returns a new capability list with ``cap`` added if not already present.
  if cap in caps:
    caps
  else:
    caps & @[cap]

func addInvocation*(
    b: RequestBuilder,
    name: MethodName,
    args: JsonNode,
    capability: CapabilityUri,
    meta: CallLimitMeta = CallLimitMeta(kind: clmOther),
): (RequestBuilder, MethodCallId) =
  ## Constructs an Invocation and returns a new builder with it accumulated.
  ## ``name`` is typed — illegal (empty) names are structurally impossible.
  ## ``meta`` records the per-call object-count signature for
  ## ``client.validateLimits``; defaults to ``clmOther`` (no per-call
  ## object-count limit applies). The accumulated builder preserves the
  ## brand of ``b`` (``b.id``), so every handle minted from this point
  ## carries the same ``BuilderId``.
  let callId = b.nextId()
  let inv = initInvocation(name, args, callId)
  return (
    RequestBuilder(
      id: b.id,
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
  (newBuilder, initResponseHandle[RespType](callId, b.id))

# =============================================================================
# addEcho — Core/echo (RFC 8620 section 4)
# =============================================================================

func addEcho*(
    b: RequestBuilder, args: JsonNode
): (RequestBuilder, ResponseHandle[JsonNode]) =
  ## Adds a Core/echo invocation (RFC 8620 section 4). The server echoes
  ## the arguments back unchanged. Useful for connectivity testing.
  let (newBuilder, callId) = b.addInvocation(
    mnCoreEcho,
    args,
    # literal IETF URN, always parses Ok
    parseCapabilityUri("urn:ietf:params:jmap:core").get(),
  )
  return (newBuilder, initResponseHandle[JsonNode](callId, b.id))

# =============================================================================
# addCapabilityInvocation — RFC 8620 §2.5 vendor capability escape
# =============================================================================

func addRawInvocation(
    b: RequestBuilder,
    rawName: string,
    args: JsonNode,
    capability: CapabilityUri,
    meta: CallLimitMeta = CallLimitMeta(kind: clmOther),
): Result[(RequestBuilder, MethodCallId), ValidationError] =
  ## Module-private helper. Constructs an ``Invocation`` via
  ## ``parseInvocation`` so the verbatim wire name is preserved (the
  ## typed-enum ``addInvocation`` writes ``$name``, which is symbol-
  ## valued for ``mnUnknown`` and therefore lossy for vendor methods).
  ## Returns Result because ``parseInvocation`` validates non-empty
  ## rawName; the sole caller ``addCapabilityInvocation`` pre-validates
  ## via the ``MethodNameLiteral`` smart constructor, so the err arm is
  ## unreachable in practice.
  let callId = b.nextId()
  let inv = ?parseInvocation(rawName, args, callId)
  ok(
    (
      RequestBuilder(
        id: b.id,
        nextCallId: b.nextCallId + 1,
        invocations: b.invocations & @[inv],
        callLimits: b.callLimits & @[meta],
        capabilityUris: withCapability(b.capabilityUris, capability),
      ),
      callId,
    )
  )

func addCapabilityInvocation*(
    b: RequestBuilder,
    capability: CapabilityUri,
    methodName: MethodNameLiteral,
    args: JsonNode,
): Result[(RequestBuilder, ResponseHandle[JsonNode]), ValidationError] =
  ## RFC 8620 §2.5 vendor-capability escape — 2nd documented send-side
  ## P19 exception (alongside ``addEcho``).
  ##
  ## **Vendor capabilities only.** Vendor URN namespaces
  ## (``urn:com:vendor:*``, ``urn:io:vendor:*``, …) are reserved per
  ## RFC 8620 §2.5 for capabilities the library cannot enumerate.
  ##
  ## **Standard IETF capabilities** (``urn:ietf:params:jmap:*``) MUST
  ## use the typed ``add<Entity><Method>`` family. That family is fully
  ## ``JsonNode``-free; this proc is the only public send-side
  ## ``JsonNode`` escape (other than ``addEcho``). H11 lint
  ## mechanically blocks the typed family from re-acquiring
  ## ``JsonNode`` parameters.
  ##
  ## ``capability`` auto-threads into ``Request.using[]`` via the
  ## linear-scan dedup shared with the typed family. ``methodName``
  ## arrives as a typed ``MethodNameLiteral`` — the wire-shape check
  ## (1..255 octets, no control chars, contains ``/``) lives in
  ## ``parseMethodNameLiteral`` (P15). ``args`` must be a non-nil
  ## JObject (RFC 8620 §3.2); a nil or non-JObject node fails on the
  ## Result rail before reaching ``parseInvocation`` (which does not
  ## validate ``arguments``). Returns ``ResponseHandle[JsonNode]``
  ## because the response shape is vendor-defined.
  if args.isNil:
    return err(validationError("VendorInvocation", "args must be a JSON object", "nil"))
  if args.kind != JObject:
    return
      err(validationError("VendorInvocation", "args must be a JSON object", $args.kind))
  let (b1, callId) = ?addRawInvocation(b, string(methodName), args, capability)
  ok((b1, initResponseHandle[JsonNode](callId, b.id)))

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
  ## returning only a subset of properties. Hub-private — exposed via
  ## per-entity wrappers in ``mail_builders.nim``.
  mixin getMethodName, capabilityUri
  let req = GetRequest[T](accountId: accountId, ids: ids, properties: properties)
  let args = req.toJson()
  let meta = getMeta(ids)
  let (newBuilder, callId) =
    addInvocation(b, getMethodName(T), args, capabilityUri(T), meta)
  (newBuilder, initResponseHandle[GetResponse[T]](callId, b.id))

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
): (RequestBuilder, ResponseHandle[R]) =
  ## Foo/set (RFC 8620 section 5.3). ``T`` = entity, ``C`` = typed create
  ## value, ``U`` = whole-container update algebra, ``R`` = response type.
  ## Hub-private — exposed via per-entity wrappers in ``mail_builders.nim``.
  ## ``setMethodName``, ``capabilityUri``, ``C.toJson``, and ``U.toJson``
  ## all resolve at instantiation via ``mixin``.
  mixin setMethodName, capabilityUri, toJson
  let req = SetRequest[T, C, U](
    accountId: accountId,
    ifInState: ifInState,
    create: create,
    update: update,
    destroy: destroy,
  )
  let args = req.toJson()
  let meta = setMeta(create, update, destroy)
  let (newBuilder, callId) =
    addInvocation(b, setMethodName(T), args, capabilityUri(T), meta)
  (newBuilder, initResponseHandle[R](callId, b.id))

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
): (RequestBuilder, ResponseHandle[R]) =
  ## Foo/copy (RFC 8620 section 5.4). ``T`` = entity, ``CopyItem`` = typed
  ## per-entry create-value, ``R`` = response type. ``destroyMode`` defaults
  ## to ``keepOriginals()``. Hub-private — exposed via per-entity wrappers
  ## in ``mail_builders.nim``. ``copyMethodName``, ``capabilityUri``, and
  ## ``CopyItem.toJson`` resolve at instantiation via ``mixin``. Per RFC
  ## 8620 §5.4, /copy is a /set-class operation; the meta carries
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
  let args = req.toJson()
  let meta = CallLimitMeta(kind: clmSet, objectCount: Opt.some(create.len))
  let (newBuilder, callId) =
    addInvocation(b, copyMethodName(T), args, capabilityUri(T), meta)
  (newBuilder, initResponseHandle[R](callId, b.id))

# =============================================================================
# addQuery — Foo/query (RFC 8620 section 5.5)
# =============================================================================

func addQuery*[T, C, SortT](
    b: RequestBuilder,
    accountId: AccountId,
    filter: Opt[Filter[C]] = default(Opt[Filter[C]]),
    sort: Opt[seq[SortT]] = default(Opt[seq[SortT]]),
    queryParams: QueryParams = QueryParams(),
): (RequestBuilder, ResponseHandle[QueryResponse[T]]) =
  ## Foo/query. ``T`` = entity, ``C`` = filter-condition type, ``SortT`` =
  ## sort-element type. Hub-private — exposed via per-entity wrappers in
  ## ``mail_builders.nim``. ``C.toJson`` resolves via ``mixin`` at the
  ## caller's instantiation scope through the ``serializeOptFilter`` →
  ## ``Filter[C].toJson`` cascade.
  mixin queryMethodName, capabilityUri, toJson
  let args = assembleQueryArgs(
    accountId, serializeOptFilter(filter), serializeOptSort(sort), queryParams
  )
  let (newBuilder, callId) =
    addInvocation(b, queryMethodName(T), args, capabilityUri(T))
  (newBuilder, initResponseHandle[QueryResponse[T]](callId, b.id))

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
): (RequestBuilder, ResponseHandle[QueryChangesResponse[T]]) =
  ## Foo/queryChanges. Takes ``calculateTotal`` directly — RFC 8620
  ## section 5.6 defines no window fields for /queryChanges. Hub-private
  ## — exposed via per-entity wrappers in ``mail_builders.nim``.
  ## ``C.toJson`` resolves via ``mixin`` at the caller's instantiation
  ## scope.
  mixin queryChangesMethodName, capabilityUri, toJson
  let args = assembleQueryChangesArgs(
    accountId,
    sinceQueryState,
    serializeOptFilter(filter),
    serializeOptSort(sort),
    maxChanges,
    upToId,
    calculateTotal,
  )
  let (newBuilder, callId) =
    addInvocation(b, queryChangesMethodName(T), args, capabilityUri(T))
  (newBuilder, initResponseHandle[QueryChangesResponse[T]](callId, b.id))

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
  ## / ``destroy`` (the common case), invoke the four-parameter form
  ## directly — the template deliberately takes only ``b`` and
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
  ## ``destroyMode``, invoke the three-parameter form directly.
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
