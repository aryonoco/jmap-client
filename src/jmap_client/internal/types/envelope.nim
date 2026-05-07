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
# rawName / rawMethodCallId are module-private so construction flows
# through ``initInvocation`` (typed, infallible) or ``parseInvocation``
# (string-taking, fallible at the wire). Public accessor funcs below
# provide read access; UFCS keeps the ``inv.name`` spelling unchanged.
type Invocation* {.ruleOff: "objects".} = object
  ## A method call or response tuple (RFC 8620 section 3.2). Serialised as a
  ## 3-element JSON array by Layer 2.
  arguments*: JsonNode ## named arguments — always a JObject at the wire level
  rawMethodCallId: string ## module-private; always a validated MethodCallId
  rawName: string ## module-private; always a non-empty wire-format name

func methodCallId*(inv: Invocation): MethodCallId =
  ## Returns the validated method call ID.
  return MethodCallId(inv.rawMethodCallId)

func name*(inv: Invocation): MethodName =
  ## Typed method-name accessor. Returns ``mnUnknown`` for wire names the
  ## library doesn't recognise (forward compatibility — ``rawName`` preserves
  ## the verbatim string for lossless round-trip).
  return parseMethodName(inv.rawName)

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
  return Invocation(
    arguments: arguments, rawMethodCallId: string(methodCallId), rawName: $name
  )

func parseInvocation*(
    rawName: string, arguments: JsonNode, methodCallId: MethodCallId
): Result[Invocation, ValidationError] =
  ## Wire-boundary constructor: accepts any non-empty string so unknown
  ## method names round-trip losslessly (Postel's law). Used only by
  ## ``serde_envelope.fromJson``.
  if rawName.len == 0:
    return err(validationError("Invocation", "name must not be empty", rawName))
  return ok(
    Invocation(
      arguments: arguments, rawMethodCallId: string(methodCallId), rawName: rawName
    )
  )

type Request* = object
  ## Top-level JMAP request envelope (RFC 8620 section 3.3). Contains the
  ## capability URIs, method calls, and optional creation ID map.
  `using`*: seq[string] ## capability URIs the client wishes to use
  methodCalls*: seq[Invocation] ## processed sequentially by server
  createdIds*: Opt[Table[CreationId, Id]] ## optional; enables proxy splitting

type Response* = object
  ## Top-level JMAP response envelope (RFC 8620 section 3.4). Contains method
  ## responses, optional creation ID map, and the current session state.
  methodResponses*: seq[Invocation] ## same format as methodCalls
  createdIds*: Opt[Table[CreationId, Id]] ## only present if given in request
  sessionState*: JmapState
    ## Current Session.state value. After every response, compare with
    ## ``Session.state``; if they differ, the session is stale and should
    ## be re-fetched (RFC 8620 §3.4). The RFC uses permissive language
    ## ("may") for this check — it is not a MUST-level requirement.

# nimalyzer: ResultReference intentionally has no public fields.
# rawName / rawPath are module-private so construction flows through
# ``initResultReference`` (typed, infallible) or ``parseResultReference``
# (string-taking, fallible at the wire).
type ResultReference* {.ruleOff: "objects".} = object
  ## Back-reference to a previous method call's result (RFC 8620 section 3.7).
  ## The server resolves the JSON Pointer path against the referenced response.
  resultOf*: MethodCallId ## method call ID of the previous call
  rawName: string ## module-private; expected response name (non-empty)
  rawPath: string ## module-private; JSON Pointer (RFC 6901) with JMAP '*'

func name*(rr: ResultReference): MethodName =
  ## Typed response-name accessor. Returns ``mnUnknown`` for forward-compat
  ## wire names — ``rawName`` preserves the verbatim string.
  return parseMethodName(rr.rawName)

func rawName*(rr: ResultReference): string =
  ## Verbatim wire name of the referenced response.
  return rr.rawName

func path*(rr: ResultReference): RefPath =
  ## Typed result-reference path. Unknown paths fall back to ``rpIds`` —
  ## but this never fires in practice because the server only echoes
  ## paths we sent, which are always drawn from the enum.
  for p in RefPath:
    if $p == rr.rawPath:
      return p
  return rpIds

func rawPath*(rr: ResultReference): string =
  ## Verbatim wire path — e.g. ``"/ids"`` or ``"/list/*/id"``.
  return rr.rawPath

func initResultReference*(
    resultOf: MethodCallId, name: MethodName, path: RefPath
): ResultReference =
  ## Total, typed constructor. Both enum parameters are string-backed;
  ## stored verbatim as ``$name`` / ``$path`` for lossless wire emission.
  return ResultReference(resultOf: resultOf, rawName: $name, rawPath: $path)

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
  return ok(ResultReference(resultOf: resultOf, rawName: name, rawPath: path))

type
  ReferencableKind* = enum
    ## Discriminator for Referencable: direct value or back-reference.
    rkDirect
    rkReference

  Referencable*[T] = object
    ## Either a direct value or a result reference (RFC 8620 section 3.7).
    ## Isomorphic to Haskell's Either T ResultReference.
    case kind*: ReferencableKind
    of rkDirect:
      value*: T
    of rkReference:
      reference*: ResultReference

func direct*[T](value: T): Referencable[T] =
  ## Wraps a direct value into a Referencable.
  return Referencable[T](kind: rkDirect, value: value)

func referenceTo*[T](reference: ResultReference): Referencable[T] =
  ## Wraps a result reference into a Referencable.
  return Referencable[T](kind: rkReference, reference: reference)
