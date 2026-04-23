# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phantom-typed response handles and dispatch extraction for JMAP method
## responses (RFC 8620 section 3.4). ``ResponseHandle[T]`` ties a method call
## ID to its expected response type at compile time. ``get[T]`` extracts typed
## responses from the Response envelope, detecting method errors and converting
## validation failures losslessly.
##
## **Two-level railway composition.** Layer 4's ``send`` returns
## ``JmapResult[Response]`` (Track 1: transport/request errors). ``get[T]``
## returns ``Result[T, MethodError]`` (Track 2: per-invocation errors). These
## are intentionally separate railways — transport failures and method errors
## require fundamentally different recovery actions.
##
## **Cross-request safety gap.** Call IDs repeat across requests (every
## request's first method call is "c0"). A handle from Request A, if used
## with Response B, will silently extract the wrong invocation. Use handles
## immediately within the scope where the request was built.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/json

import ./types
import ./serialisation
import ./methods

# =============================================================================
# ResponseHandle[T]
# =============================================================================

type ResponseHandle*[T] = distinct MethodCallId
  ## Phantom-typed handle tying a method call ID to its expected response
  ## type T. T is unused at runtime — it exists solely for compile-time
  ## type safety. At runtime, just a MethodCallId.

func `==`*[T](a, b: ResponseHandle[T]): bool =
  ## Equality comparison delegated to the underlying MethodCallId.
  return MethodCallId(a) == MethodCallId(b)

func `$`*[T](a: ResponseHandle[T]): string =
  ## String representation delegated to the underlying MethodCallId.
  return $MethodCallId(a)

func hash*[T](a: ResponseHandle[T]): Hash =
  ## Hash delegated to the underlying MethodCallId.
  return hash(MethodCallId(a))

func callId*[T](handle: ResponseHandle[T]): MethodCallId =
  ## Extracts the underlying MethodCallId from a ResponseHandle.
  return MethodCallId(handle)

# =============================================================================
# NameBoundHandle[T] — dispatch for compound overloads (RFC 8620 §5.4)
# =============================================================================

type NameBoundHandle*[T] = object
  ## Response handle whose wire invocation shares its call-id with a sibling
  ## invocation (RFC 8620 §5.4 compound overloads, e.g. the implicit Email/set
  ## destroy response accompanying Email/copy with onSuccessDestroyOriginal).
  ##
  ## The method-name fact travels with the handle — set once at the builder
  ## construction site, never at the extraction site. Dispatch resolves via
  ## call-id + method-name simultaneously, so UFCS extraction (resp.get(h))
  ## needs no filter argument. "Parse once at the boundary, trust forever"
  ## applied to dispatch: the constraint lives in the type, not in every
  ## caller's argument list.
  callId*: MethodCallId
  methodName*: MethodName

func `==`*[T](a, b: NameBoundHandle[T]): bool =
  ## Equality on both components.
  a.callId == b.callId and a.methodName == b.methodName

func `$`*[T](h: NameBoundHandle[T]): string =
  ## String form: "<callId>@<methodName>".
  $h.callId & "@" & $h.methodName

func hash*[T](h: NameBoundHandle[T]): Hash =
  ## Hash combining both components.
  !$(h.callId.hash !& h.methodName.hash)

# =============================================================================
# Railway bridge: serde (SerdeViolation) → per-invocation (MethodError)
# =============================================================================

func serdeToMethodError*(
    rootType: string
): proc(sv: SerdeViolation): MethodError {.noSideEffect, raises: [].} =
  ## Returns a closure that translates a ``SerdeViolation`` into a
  ## ``MethodError`` via the canonical ``toValidationError`` translator
  ## (with ``rootType``), then packs the resulting shape into a
  ## ``serverFail`` method error. Preserves ``typeName`` and ``value`` in
  ## ``extras`` so no diagnostic information is lost.
  return proc(sv: SerdeViolation): MethodError {.noSideEffect, raises: [].} =
    let ve = toValidationError(sv, rootType)
    let extras = %*{"typeName": ve.typeName, "value": ve.value}
    methodError(
      rawType = "serverFail",
      description = Opt.some(ve.message),
      extras = Opt.some(extras),
    )

# =============================================================================
# Internal helpers
# =============================================================================

func findInvocation(resp: Response, targetId: MethodCallId): Opt[Invocation] =
  ## Scans methodResponses for the first invocation matching targetId.
  for inv in resp.methodResponses:
    if inv.methodCallId == targetId:
      return Opt.some(inv)
  return Opt.none(Invocation)

func extractInvocation(
    resp: Response, targetId: MethodCallId
): Result[Invocation, MethodError] =
  ## Finds and validates an invocation: returns the invocation for normal
  ## responses, or an appropriate MethodError for missing/error responses.
  let matchOpt = findInvocation(resp, targetId)
  if matchOpt.isNone:
    return err(
      methodError(
        rawType = "serverFail",
        description = Opt.some("no response for call ID " & $targetId),
      )
    )
  let inv = matchOpt.get()
  if inv.rawName == "error":
    let meResult = MethodError.fromJson(inv.arguments)
    if meResult.isOk:
      return err(meResult.get())
    return err(
      methodError(
        rawType = "serverFail",
        description = Opt.some("malformed error response for call ID " & $targetId),
      )
    )
  return ok(inv)

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

func extractInvocationByName(
    resp: Response, targetId: MethodCallId, filterName: MethodName
): Result[Invocation, MethodError] =
  ## Name-filtered counterpart to ``extractInvocation``. Returns the first
  ## invocation matching both call-id and method-name, or an appropriate
  ## MethodError for missing/error responses.
  let matchOpt = findInvocationByName(resp, targetId, filterName)
  if matchOpt.isNone:
    return err(
      methodError(
        rawType = "serverFail",
        description =
          Opt.some("no " & $filterName & " response for call ID " & $targetId),
      )
    )
  let inv = matchOpt.get()
  if inv.rawName == "error":
    let meResult = MethodError.fromJson(inv.arguments)
    if meResult.isOk:
      return err(meResult.get())
    return err(
      methodError(
        rawType = "serverFail",
        description = Opt.some("malformed error response for call ID " & $targetId),
      )
    )
  return ok(inv)

# =============================================================================
# get[T] — default extraction via mixin fromJson
# =============================================================================

func get*[T](resp: Response, handle: ResponseHandle[T]): Result[T, MethodError] =
  ## Extracts a typed response from the Response envelope using ``mixin
  ## fromJson`` to resolve ``T.fromJson`` at the caller's scope.
  ##
  ## Algorithm:
  ## 1. Scan methodResponses for invocation matching handle's call ID.
  ## 2. Not found → err(serverFail).
  ## 3. If name == "error" → parse as MethodError, return err.
  ## 4. Otherwise → call T.fromJson(arguments) via mixin.
  ##    ok → return ok. err(SerdeViolation) → convert to MethodError
  ##    via ``serdeToMethodError($T)`` (translator with ``T``'s name as
  ##    root context).
  mixin fromJson
  let inv = ?extractInvocation(resp, callId(handle))
  return T.fromJson(inv.arguments).mapErr(serdeToMethodError($T))

# =============================================================================
# get[T] — callback overload (escape hatch)
# =============================================================================

func get*[T](
    resp: Response,
    handle: ResponseHandle[T],
    fromArgs:
      proc(node: JsonNode): Result[T, SerdeViolation] {.noSideEffect, raises: [].},
): Result[T, MethodError] =
  ## Extracts a typed response using a caller-supplied parsing callback.
  ## For custom parsing where ``T.fromJson`` is not discoverable via mixin
  ## (e.g., entity-specific extractors or JsonNode for Core/echo).
  let inv = ?extractInvocation(resp, callId(handle))
  return fromArgs(inv.arguments).mapErr(serdeToMethodError($T))

# =============================================================================
# get[T] — NameBoundHandle overload
# =============================================================================

func get*[T](resp: Response, h: NameBoundHandle[T]): Result[T, MethodError] =
  ## Extract a typed response using a NameBoundHandle. The method-name
  ## filter lives in the handle itself — no filter argument at the call
  ## site. Used by compound overloads where a sibling invocation shares
  ## the call-id (RFC 8620 §5.4).
  mixin fromJson
  let inv = ?extractInvocationByName(resp, h.callId, h.methodName)
  return T.fromJson(inv.arguments).mapErr(serdeToMethodError($T))

# =============================================================================
# Reference construction — generic escape hatch
# =============================================================================

func reference*[T](
    handle: ResponseHandle[T], name: MethodName, path: RefPath
): ResultReference =
  ## Constructs a ResultReference from a handle (RFC 8620 section 3.7).
  ## The ``name`` is the expected response method name (Decision D3.10:
  ## explicit, not auto-derived from T). The ``path`` is a typed
  ## ``RefPath`` whose backing string is the JSON Pointer with optional
  ## JMAP '*' wildcard — see ``methods_enum.RefPath``.
  return initResultReference(resultOf = callId(handle), name = name, path = path)

# =============================================================================
# Type-safe reference convenience functions (Make Illegal States Unrepresentable)
# =============================================================================

func idsRef*[T](handle: ResponseHandle[QueryResponse[T]]): Referencable[seq[Id]] =
  ## Convenience: reference to /ids from a /query response. Only compiles
  ## on ``ResponseHandle[QueryResponse[T]]`` — the compiler rejects this
  ## on get/set/changes handles. Auto-derives the response name from T via
  ## ``mixin queryMethodName``.
  mixin queryMethodName
  return referenceTo[seq[Id]](
    initResultReference(
      resultOf = callId(handle), name = queryMethodName(T), path = rpIds
    )
  )

func listIdsRef*[T](handle: ResponseHandle[GetResponse[T]]): Referencable[seq[Id]] =
  ## Convenience: reference to /list/*/id from a /get response. Only
  ## compiles on ``ResponseHandle[GetResponse[T]]``.
  mixin getMethodName
  return referenceTo[seq[Id]](
    initResultReference(
      resultOf = callId(handle), name = getMethodName(T), path = rpListIds
    )
  )

func addedIdsRef*[T](
    handle: ResponseHandle[QueryChangesResponse[T]]
): Referencable[seq[Id]] =
  ## Convenience: reference to /added/*/id from a /queryChanges response.
  ## Only compiles on ``ResponseHandle[QueryChangesResponse[T]]``.
  mixin queryChangesMethodName
  return referenceTo[seq[Id]](
    initResultReference(
      resultOf = callId(handle), name = queryChangesMethodName(T), path = rpAddedIds
    )
  )

func createdRef*[T](handle: ResponseHandle[ChangesResponse[T]]): Referencable[seq[Id]] =
  ## Convenience: reference to /created from a /changes response. Only
  ## compiles on ``ResponseHandle[ChangesResponse[T]]`` — the compiler
  ## rejects this on get/set/query handles.
  mixin changesMethodName
  return referenceTo[seq[Id]](
    initResultReference(
      resultOf = callId(handle), name = changesMethodName(T), path = rpCreated
    )
  )

func updatedRef*[T](handle: ResponseHandle[ChangesResponse[T]]): Referencable[seq[Id]] =
  ## Convenience: reference to /updated from a /changes response. Only
  ## compiles on ``ResponseHandle[ChangesResponse[T]]`` — the compiler
  ## rejects this on get/set/query handles.
  mixin changesMethodName
  return referenceTo[seq[Id]](
    initResultReference(
      resultOf = callId(handle), name = changesMethodName(T), path = rpUpdated
    )
  )
