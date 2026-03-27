# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## JMAP Request/Response envelope types (RFC 8620 sections 3.2-3.4, 3.7).
## Covers Invocation, Request, Response, ResultReference, and the
## Referencable[T] variant for back-reference support.

import std/tables
from std/json import JsonNode

import pkg/results

import ./identifiers
import ./primitives

type Invocation* = object
  ## A method call or response tuple (RFC 8620 section 3.2). Serialised as a
  ## 3-element JSON array by Layer 2.
  name*: string ## method name (request) or response name
  arguments*: JsonNode ## named arguments — always a JObject at the wire level
  methodCallId*: MethodCallId ## correlates responses to requests

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
  sessionState*: JmapState ## current Session.state value

type ResultReference* = object
  ## Back-reference to a previous method call's result (RFC 8620 section 3.7).
  ## The server resolves the JSON Pointer path against the referenced response.
  resultOf*: MethodCallId ## method call ID of the previous call
  name*: string ## expected response name
  path*: string ## JSON Pointer (RFC 6901) with JMAP '*' array wildcard

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
