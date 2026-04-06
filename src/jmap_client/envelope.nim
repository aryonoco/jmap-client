# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP Request/Response envelope types (RFC 8620 sections 3.2-3.4, 3.7).
## Covers Invocation, Request, Response, ResultReference, and the
## Referencable[T] variant for back-reference support.

import std/tables
from std/json import JsonNode

import results

import ./identifiers
import ./primitives
import ./validation

{.push raises: [].}

type Invocation* = object
  ## A method call or response tuple (RFC 8620 section 3.2). Serialised as a
  ## 3-element JSON array by Layer 2.
  ##
  ## Construction sealed via Pattern A (architecture Limitation 5/6a):
  ## ``rawMethodCallId`` is module-private, blocking direct construction
  ## from outside this module. Use ``initInvocation`` to construct.
  name*: string ## method name (request) or response name
  arguments*: JsonNode ## named arguments — always a JObject at the wire level
  rawMethodCallId: string ## module-private; validated MethodCallId

func methodCallId*(inv: Invocation): MethodCallId =
  ## Returns the validated method call ID.
  MethodCallId(inv.rawMethodCallId)

func initInvocation*(
    name: string, arguments: JsonNode, methodCallId: MethodCallId
): Result[Invocation, ValidationError] =
  ## Constructs an Invocation. Validates that name is non-empty.
  if name.len == 0:
    return err(validationError("Invocation", "name must not be empty", name))
  ok(
    Invocation(name: name, arguments: arguments, rawMethodCallId: string(methodCallId))
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

type ResultReference* = object
  ## Back-reference to a previous method call's result (RFC 8620 section 3.7).
  ## The server resolves the JSON Pointer path against the referenced response.
  ##
  ## Construction sealed via private ``rawName`` field. Use
  ## ``parseResultReference`` to construct with validation, or
  ## ``initResultReference`` for infallible construction from pre-validated values.
  resultOf*: MethodCallId ## method call ID of the previous call
  rawName: string ## module-private; expected response name (non-empty)
  path*: string ## JSON Pointer (RFC 6901) with JMAP '*' array wildcard

func name*(rr: ResultReference): string =
  ## Returns the expected response name.
  rr.rawName

func parseResultReference*(
    resultOf: MethodCallId, name: string, path: string
): Result[ResultReference, ValidationError] =
  ## Validates and constructs a ResultReference. Rejects empty name or path.
  if name.len == 0:
    return err(validationError("ResultReference", "name must not be empty", name))
  if path.len == 0:
    return err(validationError("ResultReference", "path must not be empty", path))
  ok(ResultReference(resultOf: resultOf, rawName: name, path: path))

func initResultReference*(
    resultOf: MethodCallId, name: string, path: string
): ResultReference =
  ## Constructs a ResultReference without validation. For internal use where
  ## name and path are known to be valid (e.g., builder-produced references
  ## using path constants).
  doAssert name.len > 0, "ResultReference name must not be empty"
  doAssert path.len > 0, "ResultReference path must not be empty"
  ResultReference(resultOf: resultOf, rawName: name, path: path)

const
  RefPathIds* = "/ids" ## IDs from /query result
  RefPathListIds* = "/list/*/id" ## IDs from /get result
  RefPathAddedIds* = "/added/*/id" ## IDs from /queryChanges result
  RefPathCreated* = "/created" ## created map from /changes or /set result
  RefPathUpdated* = "/updated" ## updated IDs from /changes result
  RefPathUpdatedProperties* = "/updatedProperties"
    ## updatedProperties from Mailbox/changes (RFC 8621 section 2.2)

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
  Referencable[T](kind: rkDirect, value: value)

func referenceTo*[T](reference: ResultReference): Referencable[T] =
  ## Wraps a result reference into a Referencable.
  Referencable[T](kind: rkReference, reference: reference)
