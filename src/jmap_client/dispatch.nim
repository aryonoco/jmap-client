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

{.push raises: [].}

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
  MethodCallId(a) == MethodCallId(b)

func `$`*[T](a: ResponseHandle[T]): string =
  ## String representation delegated to the underlying MethodCallId.
  $MethodCallId(a)

func hash*[T](a: ResponseHandle[T]): Hash =
  ## Hash delegated to the underlying MethodCallId.
  hash(MethodCallId(a))

func callId*[T](handle: ResponseHandle[T]): MethodCallId =
  ## Extracts the underlying MethodCallId from a ResponseHandle.
  MethodCallId(handle)

# =============================================================================
# Railway bridge: Track 0 (ValidationError) → Track 2 (MethodError)
# =============================================================================

func validationToMethodError*(ve: ValidationError): MethodError =
  ## Lossless conversion from the construction railway (Track 0) to the
  ## per-invocation railway (Track 2). Preserves the full ValidationError
  ## structure in MethodError.extras as structured JSON so no diagnostic
  ## information is lost.
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
  Opt.none(Invocation)

# =============================================================================
# get[T] — default extraction via mixin fromJson
# =============================================================================

proc get*[T](resp: Response, handle: ResponseHandle[T]): Result[T, MethodError] =
  ## Extracts a typed response from the Response envelope using ``mixin
  ## fromJson`` to resolve ``T.fromJson`` at the caller's scope.
  ##
  ## Algorithm:
  ## 1. Scan methodResponses for invocation matching handle's call ID.
  ## 2. Not found → err(serverFail).
  ## 3. If name == "error" → parse as MethodError, return err.
  ## 4. Otherwise → call T.fromJson(arguments) via mixin.
  ##    ok → return ok. err(ValidationError) → convert to MethodError.
  mixin fromJson
  let targetId = callId(handle)
  let matchOpt = findInvocation(resp, targetId)
  if matchOpt.isNone:
    return err(
      methodError(
        rawType = "serverFail",
        description = Opt.some("no response for call ID " & $targetId),
      )
    )
  let matchedInv = matchOpt.get()
  # Detect method-level error response (RFC 8620 section 3.6.2)
  if matchedInv.name == "error":
    let meResult = MethodError.fromJson(matchedInv.arguments)
    if meResult.isOk:
      return err(meResult.get())
    return err(
      methodError(
        rawType = "serverFail",
        description = Opt.some("malformed error response for call ID " & $targetId),
      )
    )
  # Parse via mixin-resolved fromJson
  let parseResult = T.fromJson(matchedInv.arguments)
  if parseResult.isOk:
    return ok(parseResult.get())
  err(validationToMethodError(parseResult.error()))

# =============================================================================
# get[T] — callback overload (escape hatch)
# =============================================================================

proc get*[T](
    resp: Response,
    handle: ResponseHandle[T],
    fromArgs:
      proc(node: JsonNode): Result[T, ValidationError] {.noSideEffect, raises: [].},
): Result[T, MethodError] =
  ## Extracts a typed response using a caller-supplied parsing callback.
  ## For custom parsing where ``T.fromJson`` is not discoverable via mixin
  ## (e.g., entity-specific extractors or JsonNode for Core/echo).
  let targetId = callId(handle)
  let matchOpt = findInvocation(resp, targetId)
  if matchOpt.isNone:
    return err(
      methodError(
        rawType = "serverFail",
        description = Opt.some("no response for call ID " & $targetId),
      )
    )
  let matchedInv = matchOpt.get()
  if matchedInv.name == "error":
    let meResult = MethodError.fromJson(matchedInv.arguments)
    if meResult.isOk:
      return err(meResult.get())
    return err(
      methodError(
        rawType = "serverFail",
        description = Opt.some("malformed error response for call ID " & $targetId),
      )
    )
  let parseResult = fromArgs(matchedInv.arguments)
  if parseResult.isOk:
    return ok(parseResult.get())
  err(validationToMethodError(parseResult.error()))

# =============================================================================
# Reference construction — generic escape hatch
# =============================================================================

func reference*[T](
    handle: ResponseHandle[T], name: string, path: string
): ResultReference =
  ## Constructs a ResultReference from a handle (RFC 8620 section 3.7).
  ## The ``name`` is the expected response method name (Decision D3.10:
  ## explicit, not auto-derived from T). The ``path`` is a JSON Pointer
  ## string with optional JMAP '*' wildcard.
  initResultReference(resultOf = callId(handle), name = name, path = path)

# =============================================================================
# Type-safe reference convenience functions (Make Illegal States Unrepresentable)
# =============================================================================

func idsRef*[T](handle: ResponseHandle[QueryResponse[T]]): Referencable[seq[Id]] =
  ## Convenience: reference to /ids from a /query response. Only compiles
  ## on ``ResponseHandle[QueryResponse[T]]`` — the compiler rejects this
  ## on get/set/changes handles. Auto-derives the response name from T via
  ## ``mixin methodNamespace``.
  mixin methodNamespace
  let name = methodNamespace(T) & "/query"
  referenceTo[seq[Id]](
    initResultReference(resultOf = callId(handle), name = name, path = RefPathIds)
  )

func listIdsRef*[T](handle: ResponseHandle[GetResponse[T]]): Referencable[seq[Id]] =
  ## Convenience: reference to /list/*/id from a /get response. Only
  ## compiles on ``ResponseHandle[GetResponse[T]]``.
  mixin methodNamespace
  let name = methodNamespace(T) & "/get"
  referenceTo[seq[Id]](
    initResultReference(resultOf = callId(handle), name = name, path = RefPathListIds)
  )

func addedIdsRef*[T](
    handle: ResponseHandle[QueryChangesResponse[T]]
): Referencable[seq[Id]] =
  ## Convenience: reference to /added/*/id from a /queryChanges response.
  ## Only compiles on ``ResponseHandle[QueryChangesResponse[T]]``.
  mixin methodNamespace
  let name = methodNamespace(T) & "/queryChanges"
  referenceTo[seq[Id]](
    initResultReference(resultOf = callId(handle), name = name, path = RefPathAddedIds)
  )
