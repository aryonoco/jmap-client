# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Diagnostic emission for JMAP envelope types (RFC 8620 §3.2-3.4, 3.7):
## ``Invocation``, ``Request``, ``Response``, ``ResultReference``.
##
## Per P19 ("schema-driven types, not stringly-typed signatures"),
## diagnostic emission is a user-facing concern — application code uses
## ``inv.toJson`` to print a parsed invocation, ``req.toJson`` to log a
## constructed batch, and so on. The reverse direction (parsing typed
## envelopes from raw JSON) is library plumbing and lives in the sibling
## ``serde_envelope_parse`` module, which is hub-private.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ../types
import ../types/envelope

func toJson*(inv: Invocation): JsonNode =
  ## Serialise Invocation as 3-element JSON array (RFC 8620 section 3.2).
  ## Uses ``rawName`` so forward-compatible unknown method names round-trip
  ## losslessly — ``$inv.name`` would collapse them to the ``mnUnknown``
  ## symbol name.
  return %*[inv.rawName, inv.arguments, $inv.methodCallId]

func toJson*(r: Request): JsonNode =
  ## Serialise Request to JSON (RFC 8620 section 3.3).
  var node = newJObject()
  node["using"] = %r.`using`
  var calls = newJArray()
  for _, inv in r.methodCalls:
    calls.add(inv.toJson())
  node["methodCalls"] = calls
  for createdIds in r.createdIds:
    var ids = newJObject()
    for k, v in createdIds:
      ids[$k] = %($v)
    node["createdIds"] = ids
  return node

func toJson*(r: Response): JsonNode =
  ## Serialise Response to JSON (RFC 8620 section 3.4).
  var node = newJObject()
  var responses = newJArray()
  for _, inv in r.methodResponses:
    responses.add(inv.toJson())
  node["methodResponses"] = responses
  node["sessionState"] = %($r.sessionState)
  for createdIds in r.createdIds:
    var ids = newJObject()
    for k, v in createdIds:
      ids[$k] = %($v)
    node["createdIds"] = ids
  return node

func toJson*(r: ResultReference): JsonNode =
  ## Serialise ResultReference to JSON (RFC 8620 section 3.7).
  ## Uses ``rawName`` / ``rawPath`` to preserve verbatim wire strings,
  ## including any forward-compatible unknown variants.
  return %*{"resultOf": $r.resultOf, "name": r.rawName, "path": r.rawPath}
