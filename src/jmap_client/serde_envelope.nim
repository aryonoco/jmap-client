# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serialisation for JMAP envelope types: Invocation, Request, Response,
## ResultReference, and Referencable[T] helpers (RFC 8620 sections 3.2-3.4, 3.7).

{.push raises: [], noSideEffect.}

import std/json
import std/tables

import ./serde
import ./types

# =============================================================================
# Invocation
# =============================================================================

func toJson*(inv: Invocation): JsonNode =
  ## Serialise Invocation as 3-element JSON array (RFC 8620 section 3.2).
  return %*[inv.name, inv.arguments, string(inv.methodCallId)]

func fromJson*(
    T: typedesc[Invocation], node: JsonNode
): Result[Invocation, ValidationError] =
  ## Deserialise a 3-element JSON array to Invocation (RFC 8620 section 3.2).
  ?checkJsonKind(node, JArray, $T)
  if node.len != 3:
    return err(parseError($T, "expected exactly 3 elements"))
  let elems = node.getElems(@[])
  let nameNode = elems[0]
  ?checkJsonKind(nameNode, JString, $T, "method name must be string")
  let name = nameNode.getStr("")
  let arguments = elems[1]
  let callIdNode = elems[2]
  ?checkJsonKind(callIdNode, JString, $T, "method call ID must be string")
  let callIdRaw = callIdNode.getStr("")
  ?checkJsonKind(arguments, JObject, $T, "arguments must be JSON object")
  if name.len == 0:
    return err(parseError($T, "method name must not be empty"))
  if callIdRaw.len == 0:
    return err(parseError($T, "method call ID must not be empty"))
  let mcid = ?parseMethodCallId(callIdRaw)
  return initInvocation(name, arguments, mcid)

# =============================================================================
# createdIds helper
# =============================================================================

func parseCreatedIds(
    node: JsonNode, typeName: string
): Result[Opt[Table[CreationId, Id]], ValidationError] =
  ## Parse optional createdIds from a Request or Response JSON object.
  ## Container-strict: wrong container kind raises (design doc section 9).
  let cnode = node{"createdIds"}
  if cnode.isNil:
    return ok(Opt.none(Table[CreationId, Id]))
  if cnode.kind == JNull:
    return ok(Opt.none(Table[CreationId, Id]))
  if cnode.kind != JObject:
    return err(parseError(typeName, "createdIds must be object or null"))
  var tbl = initTable[CreationId, Id]()
  for k, v in cnode.pairs: # kind == JObject verified above
    let cid = ?parseCreationId(k)
    ?checkJsonKind(v, JString, typeName, "createdIds value must be string")
    let id = ?parseIdFromServer(v.getStr(""))
    tbl[cid] = id
  return ok(Opt.some(tbl))

# =============================================================================
# Request
# =============================================================================

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
      ids[string(k)] = %string(v)
    node["createdIds"] = ids
  return node

func fromJson*(T: typedesc[Request], node: JsonNode): Result[Request, ValidationError] =
  ## Deserialise JSON to Request (RFC 8620 section 3.3).
  ?checkJsonKind(node, JObject, $T)
  let usingNode = node{"using"}
  ?checkJsonKind(usingNode, JArray, $T, "missing or invalid using")
  var usingSeq: seq[string] = @[]
  for _, elem in usingNode.getElems(@[]):
    ?checkJsonKind(elem, JString, $T, "using element must be string")
    usingSeq.add(elem.getStr(""))
  let callsNode = node{"methodCalls"}
  ?checkJsonKind(callsNode, JArray, $T, "missing or invalid methodCalls")
  var methodCalls: seq[Invocation] = @[]
  for _, callNode in callsNode.getElems(@[]):
    let inv = ?Invocation.fromJson(callNode)
    methodCalls.add(inv)
  let createdIds = ?parseCreatedIds(node, $T)
  return
    ok(Request(`using`: usingSeq, methodCalls: methodCalls, createdIds: createdIds))

# =============================================================================
# Response
# =============================================================================

func toJson*(r: Response): JsonNode =
  ## Serialise Response to JSON (RFC 8620 section 3.4).
  var node = newJObject()
  var responses = newJArray()
  for _, inv in r.methodResponses:
    responses.add(inv.toJson())
  node["methodResponses"] = responses
  node["sessionState"] = %string(r.sessionState)
  for createdIds in r.createdIds:
    var ids = newJObject()
    for k, v in createdIds:
      ids[string(k)] = %string(v)
    node["createdIds"] = ids
  return node

func fromJson*(
    T: typedesc[Response], node: JsonNode
): Result[Response, ValidationError] =
  ## Deserialise JSON to Response (RFC 8620 section 3.4).
  ?checkJsonKind(node, JObject, "Response")
  let responsesNode = node{"methodResponses"}
  ?checkJsonKind(
    responsesNode, JArray, "Response", "missing or invalid methodResponses"
  )
  var methodResponses: seq[Invocation] = @[]
  for _, respNode in responsesNode.getElems(@[]):
    let inv = ?Invocation.fromJson(respNode)
    methodResponses.add(inv)
  let sessionStateNode = node{"sessionState"}
  ?checkJsonKind(
    sessionStateNode, JString, "Response", "missing or invalid sessionState"
  )
  let sessionState = ?parseJmapState(sessionStateNode.getStr(""))
  let createdIds = ?parseCreatedIds(node, $T)
  return ok(
    Response(
      methodResponses: methodResponses,
      createdIds: createdIds,
      sessionState: sessionState,
    )
  )

# =============================================================================
# ResultReference
# =============================================================================

func toJson*(r: ResultReference): JsonNode =
  ## Serialise ResultReference to JSON (RFC 8620 section 3.7).
  return %*{"resultOf": string(r.resultOf), "name": r.name, "path": r.path}

func fromJson*(
    T: typedesc[ResultReference], node: JsonNode
): Result[ResultReference, ValidationError] =
  ## Deserialise JSON to ResultReference (RFC 8620 section 3.7).
  ?checkJsonKind(node, JObject, $T)
  let resultOfNode = node{"resultOf"}
  ?checkJsonKind(resultOfNode, JString, $T, "missing or invalid resultOf")
  let resultOfRaw = resultOfNode.getStr("")
  let nameNode = node{"name"}
  ?checkJsonKind(nameNode, JString, $T, "missing or invalid name")
  let name = nameNode.getStr("")
  let pathNode = node{"path"}
  ?checkJsonKind(pathNode, JString, $T, "missing or invalid path")
  let path = pathNode.getStr("")
  let resultOf = ?parseMethodCallId(resultOfRaw)
  return parseResultReference(resultOf, name, path)

# =============================================================================
# Referencable[T] helpers
# =============================================================================

func referencableKey*[T](fieldName: string, r: Referencable[T]): string =
  ## Returns the JSON key: plain for direct, #-prefixed for reference.
  case r.kind
  of rkDirect:
    return fieldName
  of rkReference:
    return "#" & fieldName

func fromJsonField*[T](
    fieldName: string,
    node: JsonNode,
    fromDirect: proc(n: JsonNode): T {.noSideEffect, raises: [].},
): Result[Referencable[T], ValidationError] =
  ## Parse a Referencable field from a JSON object.
  ## Checks "#fieldName" (reference) first, then "fieldName" (direct).
  ## Rejects when both forms are present (RFC 8620 §3.7).
  let refKey = "#" & fieldName
  let refNode = node{refKey}
  let directNode = node{fieldName}
  # RFC 8620 §3.7: reject when both direct and referenced forms are present
  if not refNode.isNil and not directNode.isNil:
    return err(
      parseError(
        "Referencable",
        "cannot specify both " & fieldName & " and " & refKey & " (RFC 8620 §3.7)",
      )
    )
  if not refNode.isNil:
    if refNode.kind != JObject:
      return err(
        parseError("Referencable", refKey & " must be a JSON object (ResultReference)")
      )
    let resultRef = ?ResultReference.fromJson(refNode)
    return ok(referenceTo[T](resultRef))
  if directNode.isNil:
    return
      err(parseError("Referencable", "missing field: " & fieldName & " or " & refKey))
  let value = fromDirect(directNode)
  return ok(direct[T](value))
