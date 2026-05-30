# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP Request/Response envelope types (RFC 8620 sections 3.2-3.4, 3.7).
## Covers Invocation, Request, Response, ResultReference, and the
## Referencable[T] variant for back-reference support.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/tables
from std/json import JsonNode

import results

import ./identifiers
import ./methods_enum
import ./primitives
import ./validation

# nimalyzer: Invocation intentionally has no public fields.
# arguments / rawName / rawMethodCallId are module-private so construction
# flows through ``initInvocation`` (typed, infallible) or ``parseInvocation``
# (string-taking, fallible at the wire). Public accessor funcs below provide
# read access for internal consumers (serde, dispatch, builder), which import
# this leaf module directly. The whole envelope wire surface — Invocation,
# Request, Response, ResultReference, and their accessors/constructors — is
# hub-internal (A30b): the hub (``internal/types.nim``) demotes them all, so
# ``import jmap_client`` exposes only the ``BuiltRequest`` / ``DispatchedResponse``
# handles and ``Referencable[T]``. Apps never reach a raw wire instance (P5/P8).
type Invocation* {.ruleOff: "objects".} = object
  ## A method call or response tuple (RFC 8620 section 3.2). Serialised as a
  ## 3-element JSON array by Layer 2.
  arguments: JsonNode ## module-private; named arguments — always a JObject
  rawMethodCallId: MethodCallId ## module-private; validated MethodCallId
  rawName: string ## module-private; always a non-empty wire-format name

func methodCallId*(inv: Invocation): MethodCallId =
  ## Returns the validated method call ID.
  return inv.rawMethodCallId

func name*(inv: Invocation): MethodName =
  ## Typed method-name accessor. Returns ``mnUnknown`` for wire names the
  ## library doesn't recognise (forward compatibility — ``rawName`` preserves
  ## the verbatim string for lossless round-trip).
  return parseMethodName(inv.rawName)

func arguments*(inv: Invocation): JsonNode =
  ## Returns the named arguments JsonNode for this invocation (always
  ## a JObject per RFC 8620 §3.2). Read by the dispatcher, serde, and
  ## builder internals, which import this leaf module directly; the whole
  ## ``Invocation`` type is hub-internal (A30b), so application developers
  ## never reach raw JsonNode args via ``import jmap_client``. They consume
  ## typed responses through the dispatcher and ``RequestBuilder``.
  return inv.arguments

func rawName*(inv: Invocation): string =
  ## Verbatim wire name. Always non-empty (enforced at construction).
  ## Prefer ``name`` for comparison against a known variant; use ``rawName``
  ## for wire emission and for forward-compatible inspection of unknown
  ## method names (e.g. the literal ``"error"`` response tag).
  return inv.rawName

func initInvocation*(
    name: MethodName, arguments: JsonNode, methodCallId: MethodCallId
): Invocation =
  ## Total, typed constructor. ``MethodName`` is a string-backed enum;
  ## the wire name is ``$name`` — empty is structurally unrepresentable.
  ## Stores the backing string verbatim in ``rawName`` so round-trip is
  ## identity-functional.
  return Invocation(arguments: arguments, rawMethodCallId: methodCallId, rawName: $name)

func parseInvocation*(
    rawName: string, arguments: JsonNode, methodCallId: MethodCallId
): Result[Invocation, ValidationError] =
  ## Wire-boundary constructor: accepts any non-empty string so unknown
  ## method names round-trip losslessly (Postel's law). Used only by
  ## ``serde_envelope.fromJson``.
  if rawName.len == 0:
    return err(validationError("Invocation", "name must not be empty", rawName))
  return ok(
    Invocation(arguments: arguments, rawMethodCallId: methodCallId, rawName: rawName)
  )

# nimalyzer: Request and Response intentionally have no public fields.
# rawUsing / rawMethodCalls / rawCreatedIds (Request) and
# rawMethodResponses / rawCreatedIds / rawSessionState (Response) are
# module-private so construction flows through ``initRequest`` (total,
# build path) or ``parseRequest`` (fallible, wire boundary — non-empty
# ``using`` per RFC 8620 §3.3) for Request, and ``initResponse`` (total
# — all field-level invariants are enforced upstream by the field-level
# parsers) for Response. Public accessor funcs below provide read
# access; UFCS preserves the ``r.using`` / ``r.methodCalls`` /
# ``r.methodResponses`` / ``r.sessionState`` spellings unchanged for the
# internal consumers that import this leaf directly. Both types are
# hub-internal (A30b): application developers construct Requests via
# ``RequestBuilder.freeze`` and never see Responses raw;
# ``DispatchedResponse.get`` is the typed read path.
type Request* {.ruleOff: "objects".} = object
  ## Top-level JMAP request envelope (RFC 8620 section 3.3). Contains
  ## the capability URIs, method calls, and optional creation-ID map.
  ## Pattern-A: private fields, smart constructors, public accessors.
  rawUsing: seq[string] ## module-private; capability URIs the client wishes to use
  rawMethodCalls: seq[Invocation] ## module-private; processed sequentially by server
  rawCreatedIds: Opt[Table[CreationId, Id]]
    ## module-private; optional, enables proxy splitting

func `using`*(r: Request): seq[string] =
  ## Capability URIs the client wishes to use (RFC 8620 §3.3).
  return r.rawUsing

func methodCalls*(r: Request): seq[Invocation] =
  ## Method calls in order; the server processes them sequentially.
  return r.rawMethodCalls

func createdIds*(r: Request): Opt[Table[CreationId, Id]] =
  ## Optional creation-ID map; enables RFC 8620 §5.7 proxy splitting.
  return r.rawCreatedIds

func initRequest*(
    `using`: seq[string],
    methodCalls: seq[Invocation],
    createdIds: Opt[Table[CreationId, Id]],
): Request =
  ## Total, infallible constructor. Used by the build path
  ## (``RequestBuilder.freeze``). The RFC 8620 §3.3 invariant — non-
  ## empty ``using`` — is proved upstream: ``initRequestBuilder``
  ## seeds ``urn:ietf:params:jmap:core`` into the builder's capability
  ## list, and ``freeze`` materialises that list directly into
  ## ``using``. The parse path validates via ``parseRequest`` before
  ## delegating here.
  return
    Request(rawUsing: `using`, rawMethodCalls: methodCalls, rawCreatedIds: createdIds)

func parseRequest*(
    `using`: seq[string],
    methodCalls: seq[Invocation],
    createdIds: Opt[Table[CreationId, Id]],
): Result[Request, ValidationError] =
  ## Wire-boundary constructor: enforces RFC 8620 §3.3 (``using`` must
  ## not be empty). Used only by ``serde_envelope.Request.fromJson``
  ## via ``wrapInner``. ``methodCalls`` is accepted empty so adversarial
  ## wire-shape tests can express the zero-call case; the server
  ## surfaces it through its own ``maxCallsInRequest`` path, not the
  ## parser.
  if `using`.len == 0:
    return err(validationError("Request", "using must not be empty", ""))
  return ok(initRequest(`using`, methodCalls, createdIds))

type Response* {.ruleOff: "objects".} = object
  ## Top-level JMAP response envelope (RFC 8620 section 3.4). Contains
  ## method responses, optional creation-ID map, and the current
  ## session state. Pattern-A: private fields, smart constructor,
  ## public accessors. Application code never constructs Responses —
  ## they arrive through ``client.send`` and are consumed via
  ## ``DispatchedResponse``.
  rawMethodResponses: seq[Invocation]
    ## module-private; same format as Request.methodCalls
  rawCreatedIds: Opt[Table[CreationId, Id]]
    ## module-private; only present if given in request
  rawSessionState: JmapState ## module-private; server's current Session.state

func methodResponses*(r: Response): seq[Invocation] =
  ## Method responses in the order the server processed the calls.
  return r.rawMethodResponses

func createdIds*(r: Response): Opt[Table[CreationId, Id]] =
  ## Only present if the request supplied a ``createdIds`` map.
  return r.rawCreatedIds

func sessionState*(r: Response): JmapState =
  ## Current Session.state value. After every response, compare with
  ## ``Session.state``; if they differ, the session is stale and
  ## should be re-fetched (RFC 8620 §3.4). The RFC uses permissive
  ## language ("may") for this check — it is not a MUST-level
  ## requirement.
  return r.rawSessionState

func initResponse*(
    methodResponses: seq[Invocation],
    createdIds: Opt[Table[CreationId, Id]],
    sessionState: JmapState,
): Response =
  ## Total, infallible constructor. The only callers are inside the
  ## library (the wire-boundary ``Response.fromJson`` in
  ## ``serde_envelope.nim``); application code does not construct
  ## Responses. Per-field invariants are enforced upstream:
  ## ``sessionState`` arrives validated by ``parseJmapState`` at the
  ## wire boundary; ``methodResponses`` carries already-parsed
  ## ``Invocation`` values; ``createdIds`` is structurally validated
  ## by ``parseCreatedIds``.
  return Response(
    rawMethodResponses: methodResponses,
    rawCreatedIds: createdIds,
    rawSessionState: sessionState,
  )

# nimalyzer: ResultReference intentionally has no public fields.
# rawResultOf / rawName / rawPath are module-private so construction flows
# through ``initResultReference`` (typed, infallible) or
# ``parseResultReference`` (string-taking, fallible at the wire). The UFCS
# accessors below provide read access; ``rr.resultOf`` reads unchanged.
type ResultReference* {.ruleOff: "objects".} = object
  ## Back-reference to a previous method call's result (RFC 8620 section 3.7).
  ## The server resolves the JSON Pointer path against the referenced response.
  rawResultOf: MethodCallId ## module-private; method call ID of the previous call
  rawName: string ## module-private; expected response name (non-empty)
  rawPath: string ## module-private; JSON Pointer (RFC 6901) with JMAP '*'

func resultOf*(rr: ResultReference): MethodCallId =
  ## Method call ID of the referenced previous call (RFC 8620 §3.7).
  return rr.rawResultOf

func name*(rr: ResultReference): MethodName =
  ## Typed response-name accessor. Returns ``mnUnknown`` for forward-compat
  ## wire names — ``rawName`` preserves the verbatim string.
  return parseMethodName(rr.rawName)

func rawName*(rr: ResultReference): string =
  ## Verbatim wire name of the referenced response.
  return rr.rawName

func path*(rr: ResultReference): RefPath =
  ## Typed result-reference path. Forward-compatible: unknown wire
  ## paths surface as ``rpUnknown``; ``rr.rawPath`` preserves the
  ## verbatim wire bytes for lossless inspection.
  return parseRefPath(rr.rawPath)

func rawPath*(rr: ResultReference): string =
  ## Verbatim wire path — e.g. ``"/ids"`` or ``"/list/*/id"``.
  return rr.rawPath

func initResultReference*(
    resultOf: MethodCallId, name: MethodName, path: RefPath
): ResultReference =
  ## Total, typed constructor. Both enum parameters are string-backed;
  ## stored verbatim as ``$name`` / ``$path`` for lossless wire emission.
  return ResultReference(rawResultOf: resultOf, rawName: $name, rawPath: $path)

func parseResultReference*(
    resultOf: MethodCallId, name: string, path: string
): Result[ResultReference, ValidationError] =
  ## Wire-boundary constructor. Accepts any non-empty strings so forward-
  ## compatible references (unknown method names, unknown paths) round-trip
  ## losslessly. Used only by ``serde_envelope.fromJson``.
  if name.len == 0:
    return err(validationError("ResultReference", "name must not be empty", name))
  if path.len == 0:
    return err(validationError("ResultReference", "path must not be empty", path))
  return ok(ResultReference(rawResultOf: resultOf, rawName: name, rawPath: path))

type
  ReferencableKind* = enum
    ## Discriminator for Referencable: direct value or back-reference.
    rkDirect
    rkReference

  Referencable*[T] {.ruleOff: "objects".} = object
    ## Either a direct value or a result reference (RFC 8620 section 3.7).
    ## Isomorphic to Haskell's Either T ResultReference. Sealed: the
    ## discriminator and both arms are module-private so construction flows
    ## only through ``direct`` / ``referenceTo`` (and the typed ``reference``
    ## primitive in ``protocol/dispatch.nim``). Consumers read via ``kind``
    ## plus the ``asDirect`` / ``asReference`` Opt-accessors — never a raw
    ## arm field.
    case rawKind: ReferencableKind
    of rkDirect:
      rawValue: T
    of rkReference:
      rawReference: ResultReference

func kind*[T](r: Referencable[T]): ReferencableKind =
  ## Discriminator: ``rkDirect`` or ``rkReference``.
  return r.rawKind

func asDirect*[T](r: Referencable[T]): Opt[T] =
  ## The direct value when this is a ``rkDirect``; ``Opt.none`` otherwise.
  case r.rawKind
  of rkDirect:
    Opt.some(r.rawValue)
  of rkReference:
    Opt.none(T)

func asReference*[T](r: Referencable[T]): Opt[ResultReference] =
  ## The back-reference when this is a ``rkReference``; ``Opt.none`` otherwise.
  case r.rawKind
  of rkReference:
    Opt.some(r.rawReference)
  of rkDirect:
    Opt.none(ResultReference)

func direct*[T](value: T): Referencable[T] =
  ## Wraps a direct value into a Referencable.
  return Referencable[T](rawKind: rkDirect, rawValue: value)

func referenceTo*[T](reference: ResultReference): Referencable[T] =
  ## Wraps a result reference into a Referencable.
  return Referencable[T](rawKind: rkReference, rawReference: reference)
