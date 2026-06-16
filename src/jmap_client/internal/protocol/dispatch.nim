# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phantom-typed response handles and dispatch extraction for JMAP method
## responses (RFC 8620 section 3.4). ``ResponseHandle[T]`` ties a method call
## ID to its expected response type at compile time and carries a
## ``BuilderId`` that brands it to the issuing ``RequestBuilder``. ``get[T]``
## extracts typed responses from a sealed ``DispatchedResponse`` returned by
## ``JmapClient.send``.
##
## **One rail, method errors as data.** ``send`` returns
## ``JmapResult[DispatchedResponse]``; ``get[T]`` / ``getBoth`` return
## ``Result[MethodOutcome[T], JmapError]`` — the same rail. A handle issued by
## a different builder is ``jeMisuse``; a missing / malformed / undecodable
## response is ``jeProtocol``. A server-reported method-level error is NOT a
## rail error: it rides the ok branch as ``MethodOutcome.mokMethodError`` so a
## batch's successful siblings survive (RFC 8620 §3.6.2).

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/json
import std/tables

import ../types
import ../types/errors
import ../serialisation/serde
import ../serialisation/serde_errors
import ../types/envelope
import ./methods
import ./jmap_error

# =============================================================================
# ResponseHandle[T] — sealed, brand-carrying (Pattern A)
# =============================================================================

type
  ParseProc*[T] =
    proc(args: JsonNode): Result[T, SerdeViolation] {.noSideEffect, raises: [].}
    ## Sole resolver for ``T`` from a JMAP invocation's ``arguments``
    ## object. Captured at handle-construction time inside the builder
    ## where ``T.fromJson`` is lexically in scope. ``dispatch.get``
    ## invokes the captured proc directly — no user-scope mixin chain.

  ResponseHandle*[T] {.ruleOff: "objects".} = object
    ## Phantom-typed dispatch handle tying a compile-time response type
    ## ``T`` to a runtime ``(callId, builderId)`` pair plus the resolver
    ## that parses ``T`` from the invocation's ``arguments`` field.
    ## Construction is gated — ``initResponseHandle`` is hub-private
    ## surface so handles can only be minted by builder modules where
    ## the resolver chain is in scope (P5/P19).
    rawCallId: MethodCallId
    rawBuilderId: BuilderId
    rawParseProc: ParseProc[T]

template initResponseHandle*[T](
    callId: MethodCallId, builderId: BuilderId
): ResponseHandle[T] =
  ## Sole construction path for ``ResponseHandle[T]``. Expands at the
  ## builder's call site so ``T.fromJson`` resolves at the builder's
  ## scope via ``mixin``. The resulting closure is stored on the
  ## handle and invoked by ``dispatch.get`` without further mixin.
  mixin fromJson
  block:
    proc parse(args: JsonNode): Result[T, SerdeViolation] {.noSideEffect, raises: [].} =
      ## Captured resolver for ``T`` from the invocation's ``arguments``.
      T.fromJson(args)

    ResponseHandle[T](rawCallId: callId, rawBuilderId: builderId, rawParseProc: parse)

func callId*[T](h: ResponseHandle[T]): MethodCallId =
  ## Public accessor — the underlying ``MethodCallId``. Stays public
  ## (no hub filter) because back-reference construction via
  ## ``reference`` needs to read the callId without exposing the brand.
  h.rawCallId

func builderId*[T](h: ResponseHandle[T]): BuilderId =
  ## Hub-private accessor — the brand of the issuing ``RequestBuilder``.
  ## Internal cross-module reach only (consumed by ``get``/``getBoth``
  ## for the mismatch check).
  h.rawBuilderId

func `==`*[T](a, b: ResponseHandle[T]): bool =
  ## Structural equality across both components.
  a.rawCallId == b.rawCallId and a.rawBuilderId == b.rawBuilderId

func `$`*[T](h: ResponseHandle[T]): string =
  ## String form delegates to the underlying ``MethodCallId``.
  $h.rawCallId

func hash*[T](h: ResponseHandle[T]): Hash =
  ## Hash combining both components via ``std/hashes`` mixer.
  !$(hash(h.rawCallId) !& hash(h.rawBuilderId))

# =============================================================================
# NameBoundHandle[T] — dispatch for compound overloads (RFC 8620 §5.4)
# =============================================================================

type NameBoundHandle*[T] {.ruleOff: "objects".} = object
  ## Response handle whose wire invocation shares its call-id with a
  ## sibling invocation (RFC 8620 §5.4 compound overloads, e.g. the
  ## implicit ``Email/set`` destroy response accompanying ``Email/copy``
  ## with ``onSuccessDestroyOriginal``).
  ##
  ## The method-name fact travels with the handle — set once at the
  ## builder construction site, never at the extraction site. Dispatch
  ## resolves via call-id + method-name simultaneously, so UFCS
  ## extraction (``dr.get(h)``) needs no filter argument. The brand
  ## (``rawBuilderId``) lets the extraction validate the handle was
  ## issued by the builder that produced the dispatched response.
  rawCallId: MethodCallId
  rawMethodName: MethodName
  rawBuilderId: BuilderId
  rawParseProc: ParseProc[T]

template initNameBoundHandle*[T](
    callId: MethodCallId, methodName: MethodName, builderId: BuilderId
): NameBoundHandle[T] =
  ## Sole construction path for ``NameBoundHandle[T]``. Template form
  ## — mirrors ``initResponseHandle``: expands at the builder's call
  ## site so ``T.fromJson`` resolves at the builder's scope.
  mixin fromJson
  block:
    proc parse(args: JsonNode): Result[T, SerdeViolation] {.noSideEffect, raises: [].} =
      ## Captured resolver for ``T`` from the invocation's ``arguments``.
      T.fromJson(args)

    NameBoundHandle[T](
      rawCallId: callId,
      rawMethodName: methodName,
      rawBuilderId: builderId,
      rawParseProc: parse,
    )

func callId*[T](h: NameBoundHandle[T]): MethodCallId =
  ## Public accessor — the underlying ``MethodCallId``.
  h.rawCallId

func methodName*[T](h: NameBoundHandle[T]): MethodName =
  ## Public accessor — the bound method name.
  h.rawMethodName

func builderId*[T](h: NameBoundHandle[T]): BuilderId =
  ## Hub-private accessor — see ``builderId*(ResponseHandle)``.
  h.rawBuilderId

func `==`*[T](a, b: NameBoundHandle[T]): bool =
  ## Structural equality across all three components.
  a.rawCallId == b.rawCallId and a.rawMethodName == b.rawMethodName and
    a.rawBuilderId == b.rawBuilderId

func `$`*[T](h: NameBoundHandle[T]): string =
  ## String form: ``"<callId>@<methodName>"``.
  $h.rawCallId & "@" & $h.rawMethodName

func hash*[T](h: NameBoundHandle[T]): Hash =
  ## Hash combining all three components.
  !$(hash(h.rawCallId) !& hash(h.rawMethodName) !& hash(h.rawBuilderId))

# =============================================================================
# Internal helpers
# =============================================================================

func findInvocation(resp: Response, targetId: MethodCallId): Opt[Invocation] =
  ## Scans methodResponses for the first invocation matching targetId.
  for inv in resp.methodResponses:
    if inv.methodCallId == targetId:
      return Opt.some(inv)
  return Opt.none(Invocation)

# =============================================================================
# Name-filtered dispatch helpers (private)
# =============================================================================

func findInvocationByName(
    resp: Response, targetId: MethodCallId, filterName: MethodName
): Opt[Invocation] =
  ## Scans methodResponses for the first invocation matching BOTH call-id
  ## AND method-name. Used by compound overload dispatch where multiple
  ## invocations share a call-id (RFC 8620 §5.4).
  for inv in resp.methodResponses:
    if inv.methodCallId == targetId and inv.rawName == $filterName:
      return Opt.some(inv)
  return Opt.none(Invocation)

func classifyInvocation[T](
    found: Opt[Invocation], callId: MethodCallId, parseProc: ParseProc[T]
): Result[MethodOutcome[T], JmapError] =
  ## Classifies a located invocation into the rail/data split (the brand check
  ## is the caller's job):
  ##   * no invocation for the call id          → err(jeProtocol pfMissingCall)
  ##   * an "error" invocation that parses       → ok(mokMethodError) — the
  ##     server ran the method and reported a domain error, which is DATA
  ##   * an "error" invocation that does not     → err(jeProtocol pfMalformedError)
  ##   * a normal invocation that decodes        → ok(mokValue)
  ##   * a normal invocation that fails to decode → err(jeProtocol pfDecode)
  ## The former synthetic ``serverFail`` MethodErrors for missing / malformed
  ## responses were library/protocol faults masquerading as server method
  ## errors; they now ride the rail honestly.
  let inv = found.valueOr:
    return err(jmapProtocol(protocolMissingCall(callId)))
  if inv.rawName == "error":
    let me = MethodError.fromJson(inv.arguments).valueOr:
      return err(jmapProtocol(protocolMalformedError(callId)))
    return ok(methodFailure[T](me))
  let value = parseProc(inv.arguments).valueOr:
    return err(jmapProtocol(protocolDecode(callId, error)))
  ok(methodValue[T](value))

# =============================================================================
# DispatchedResponse — sealed dispatch artifact
# =============================================================================

type DispatchedResponse* {.ruleOff: "objects".} = object
  ## Dispatch artifact pairing a wire-data ``Response`` with the
  ## ``BuilderId`` of the builder that issued the originating request.
  ## Returned only by ``JmapClient.send``; consumed by ``handle.get`` to
  ## validate that the handle was issued by the same builder.
  ##
  ## Modelled after SQLite's ``sqlite3_stmt*`` (compiled artifact) vs
  ## row data, and libcurl's ``CURL*`` (easy handle) vs response bytes:
  ## dispatch artifact and wire data live in separate types.
  rawResponse: Response
  rawBuilderId: BuilderId

func initDispatchedResponse*(
    response: Response, builderId: BuilderId
): DispatchedResponse =
  ## Module-private surface — exported with ``*`` for ``client.nim`` to
  ## call, filtered from the protocol hub. Sole construction path.
  DispatchedResponse(rawResponse: response, rawBuilderId: builderId)

func response*(dr: DispatchedResponse): Response =
  ## Hub-private accessor — the underlying wire-data ``Response``.
  ## Internal callers, tests, and diagnostic code reach this via direct
  ## ``import jmap_client/internal/protocol/dispatch``. Application
  ## developers use ``handle.get(dr)`` for typed extraction.
  dr.rawResponse

func builderId*(dr: DispatchedResponse): BuilderId =
  ## Hub-private accessor — brand of the builder that issued the
  ## originating request. Used by ``handle.get`` for the brand check.
  dr.rawBuilderId

func sessionState*(dr: DispatchedResponse): JmapState =
  ## Hub-public convenience accessor — the response's
  ## ``sessionState``. Compare with the cached ``Session.state`` to
  ## detect a stale session (RFC 8620 §3.4).
  dr.rawResponse.sessionState

func createdIds*(dr: DispatchedResponse): Opt[Table[CreationId, Id]] =
  ## Hub-public convenience accessor — server-confirmed creation IDs.
  dr.rawResponse.createdIds

# =============================================================================
# get[T] — default extraction via mixin fromJson
# =============================================================================

func get*[T](
    dr: DispatchedResponse, handle: ResponseHandle[T]
): Result[MethodOutcome[T], JmapError] =
  ## Extracts a typed response from the dispatched response by invoking the
  ## resolver closure stored on the handle (bound at builder time — no mixin at
  ## this site). A handle issued by a different builder is ``jeMisuse``; the
  ## invocation is then classified into the rail/data split by
  ## ``classifyInvocation`` (see there): a server method error rides the ok
  ## branch as data, a missing/malformed/undecodable response rides ``jeProtocol``.
  if handle.rawBuilderId != dr.rawBuilderId:
    return err(jmapMisuse(dr.rawBuilderId, handle.rawBuilderId, handle.rawCallId))
  classifyInvocation[T](
    findInvocation(dr.rawResponse, handle.rawCallId),
    handle.rawCallId,
    handle.rawParseProc,
  )

# =============================================================================
# get[T] — NameBoundHandle overload
# =============================================================================

func get*[T](
    dr: DispatchedResponse, h: NameBoundHandle[T]
): Result[MethodOutcome[T], JmapError] =
  ## Extract a typed response using a ``NameBoundHandle``. The method-name
  ## filter lives in the handle itself — no filter argument at the call site.
  ## Used by compound overloads where a sibling invocation shares the call-id
  ## (RFC 8620 §5.4). Same brand check and rail/data classification as the
  ## ``ResponseHandle`` overload.
  if h.rawBuilderId != dr.rawBuilderId:
    return err(jmapMisuse(dr.rawBuilderId, h.rawBuilderId, h.rawCallId))
  classifyInvocation[T](
    findInvocationByName(dr.rawResponse, h.rawCallId, h.rawMethodName),
    h.rawCallId,
    h.rawParseProc,
  )

# =============================================================================
# Compound method dispatch (RFC 8620 §5.4)
# =============================================================================

type CompoundHandles*[A, B] {.ruleOff: "objects".} = object
  ## Paired handles for RFC 8620 §5.4 implicit-call compound methods.
  ## ``primary`` is the declared method's response (type ``A``);
  ## ``implicit`` is the server-emitted follow-up response (type ``B``),
  ## carrying a method-name filter because it shares the primary's
  ## call-id per RFC 8620 §5.4. The implicit handle is present
  ## (``Opt.some``) only when the builder requested the implicit call (an
  ## ``onSuccess*`` / ``onSuccessDestroyOriginal`` argument); it is
  ## ``Opt.none`` when no implicit was requested, so ``getBoth`` extracts
  ## the implicit only when one is expected rather than faulting on its
  ## by-design absence.
  primary*: ResponseHandle[A]
  implicit*: Opt[NameBoundHandle[B]]

type CompoundResults*[A, B] {.ruleOff: "objects".} = object
  ## Paired extraction target for ``getBoth(CompoundHandles[A, B])``. The
  ## ``primary`` outcome carries the declared method's result as data (a server
  ## method error rides it as ``mokMethodError``, not the rail — §3.6.2). The
  ## ``implicit`` outcome is ``Opt``: RFC 8620 §5.4 emits the implicit call only
  ## when the primary method *succeeds*, so it is absent (``none``) when
  ## ``primary`` is a method error OR when the builder did not request the
  ## implicit call, and present (``some``) — itself a ``MethodOutcome`` — only
  ## when the implicit was requested and the primary ran. ``getBoth`` is the sole
  ## producer and never emits a contradictory pair; the ``Opt`` is kept rather
  ## than collapsed into the discriminator because its *payload* — the implicit
  ## response — is not derivable from ``primary``.
  primary*: MethodOutcome[A]
  implicit*: Opt[MethodOutcome[B]]

func getBoth*[A, B](
    dr: DispatchedResponse, handles: CompoundHandles[A, B]
): Result[CompoundResults[A, B], JmapError] =
  ## Extract both responses from a §5.4 implicit-call compound. The ``primary``
  ## handle dispatches through the default ``get[T]`` overload; both share the
  ## brand-check semantics (the inner handles must have been issued by the
  ## builder that produced ``dr``). Total over all three §5.4 shapes: a primary
  ## method error means the server never ran the implicit (``none``); a value
  ## primary with no requested implicit means none was expected (``none``); only
  ## a value primary with a requested implicit extracts it. When the implicit was
  ## requested but is absent from the response, that is a genuine §5.4 dispatch
  ## fault and rides the rail.
  let primary = ?dr.get(handles.primary)
  case primary.kind
  of mokMethodError:
    ok(CompoundResults[A, B](primary: primary, implicit: Opt.none(MethodOutcome[B])))
  of mokValue:
    # The implicit handle is present only when the builder requested the
    # implicit call (RFC 8620 §5.4). When requested, an absent response is a
    # genuine fault; when not requested, no implicit is expected.
    for h in handles.implicit:
      let implicit = ?dr.get(h)
      return ok(CompoundResults[A, B](primary: primary, implicit: Opt.some(implicit)))
    ok(CompoundResults[A, B](primary: primary, implicit: Opt.none(MethodOutcome[B])))

template registerCompoundMethod*(Primary, Implicit: typedesc) =
  ## Compile-checks that ``Primary`` parametrises ``ResponseHandle``
  ## and that ``Implicit`` parametrises ``NameBoundHandle``. Call at
  ## module scope in ``mail_entities.nim`` for each compound
  ## participant. Regression (e.g. a non-type argument or a typedesc
  ## that breaks generic instantiation) surfaces as a ``{.error.}``
  ## at module load, not at first builder invocation.
  static:
    when not compiles(ResponseHandle[Primary]):
      {.
        error: "registerCompoundMethod: " & $Primary & " cannot back a ResponseHandle"
      .}
    when not compiles(NameBoundHandle[Implicit]):
      {.
        error:
          "registerCompoundMethod: " & $Implicit & " not NameBoundHandle-compatible"
      .}

# RFC 8620 §3.7 back-reference chains carry no generic context type. A
# back-reference chain is two independent invocations with distinct call-ids,
# so its paired extraction is exactly two ``dr.get`` calls — a parametric
# ``ChainedHandles[A, B]`` earns nothing the call sites do not already have
# (contrast ``CompoundHandles`` at §5.4, whose ``implicit`` ``NameBoundHandle``
# can only be minted by a builder). Each chain is therefore a bespoke record
# co-located with its builder (``EmailQuerySnippetChain`` in ``mail_methods``,
# ``EmailQueryThreadChain`` in ``mail_builders``), keeping the hub at exactly
# two paired-handle context types — ``CompoundHandles`` / ``CompoundResults``
# (P9, B9).

# =============================================================================
# Reference construction — generic escape hatch
# =============================================================================

func reference*[U](
    handle: ResponseHandle[auto], name: MethodName, path: RefPath
): Referencable[U] =
  ## Typed back-reference (RFC 8620 §3.7). ``U`` is the referenced value's
  ## type (e.g. ``seq[Id]`` for an ``ids`` back-ref) and is bound explicitly
  ## at the call site (``reference[seq[Id]](h, ...)``); the handle's response
  ## type is inferred via ``ResponseHandle[auto]`` (``U`` appears only in the
  ## return type, so it cannot be inferred from the arguments and must lead).
  ## The ``name`` is the expected response method name (Decision D3.10:
  ## explicit, not auto-derived). The ``path`` is a typed ``RefPath`` whose
  ## backing string is the JSON Pointer with optional JMAP '*' wildcard — see
  ## ``methods_enum.RefPath``. This is the sole public constructor of a
  ## reference-shaped ``Referencable``; ``ResultReference`` is hub-internal
  ## (A30b).
  referenceTo[U](
    initResultReference(resultOf = callId(handle), name = name, path = path)
  )
