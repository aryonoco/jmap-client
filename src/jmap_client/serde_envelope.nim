# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}
{.experimental: "strictCaseObjects".}

## Serialisation for JMAP envelope types: Invocation, Request, Response,
## ResultReference, and Referencable[T] helpers (RFC 8620 sections 3.2-3.4, 3.7).

import std/json
import std/tables

import results

import ./serde
import ./types

# =============================================================================
# Invocation
# =============================================================================

func toJson*(inv: Invocation): JsonNode =
  ## Serialise Invocation as 3-element JSON array (RFC 8620 section 3.2).
  {.cast(noSideEffect).}:
    result = %*[inv.name, inv.arguments, string(inv.methodCallId)]

func fromJson*(
    T: typedesc[Invocation], node: JsonNode
): Result[Invocation, ValidationError] =
  ## Deserialise a 3-element JSON array to Invocation (RFC 8620 section 3.2).
  checkJsonKind(node, JArray, $T)
  if node.len != 3:
    return err(parseError($T, "expected exactly 3 elements"))
  let elems = node.getElems(@[])
  let nameNode = elems[0]
  checkJsonKind(nameNode, JString, $T, "method name must be string")
  let name = nameNode.getStr("")
  let arguments = elems[1]
  let callIdNode = elems[2]
  checkJsonKind(callIdNode, JString, $T, "method call ID must be string")
  let callIdRaw = callIdNode.getStr("")
  checkJsonKind(arguments, JObject, $T, "arguments must be JSON object")
  if name.len == 0:
    return err(parseError($T, "method name must not be empty"))
  if callIdRaw.len == 0:
    return err(parseError($T, "method call ID must not be empty"))
  let mcid = ?parseMethodCallId(callIdRaw)
  ok(initInvocation(name, arguments, mcid))

# =============================================================================
# createdIds helper
# =============================================================================

func parseCreatedIds(
    node: JsonNode, typeName: string
): Result[Opt[Table[CreationId, Id]], ValidationError] =
  ## Parse optional createdIds from a Request or Response JSON object.
  ## Container-strict: wrong container kind returns err (design doc section 9).
  let cnode = node{"createdIds"}
  if cnode.isNil:
    return ok(default(Opt[Table[CreationId, Id]]))
  if cnode.kind == JNull:
    return ok(default(Opt[Table[CreationId, Id]]))
  if cnode.kind != JObject:
    return err(parseError(typeName, "createdIds must be object or null"))
  var tbl = initTable[CreationId, Id]()
  for k, v in cnode.pairs: # kind == JObject verified above
    let cid = ?parseCreationId(k)
    checkJsonKind(v, JString, typeName, "createdIds value must be string")
    let id = ?parseIdFromServer(v.getStr(""))
    tbl[cid] = id
  ok(Opt.some(tbl))

# =============================================================================
# Request
# =============================================================================

func toJson*(r: Request): JsonNode =
  ## Serialise Request to JSON (RFC 8620 section 3.3).
  {.cast(noSideEffect).}:
    result = newJObject()
    result["using"] = %r.`using`
    var calls = newJArray()
    for _, inv in r.methodCalls:
      calls.add(inv.toJson())
    result["methodCalls"] = calls
    if r.createdIds.isSome:
      var ids = newJObject()
      for k, v in r.createdIds.get():
        ids[string(k)] = %string(v)
      result["createdIds"] = ids

func fromJson*(T: typedesc[Request], node: JsonNode): Result[Request, ValidationError] =
  ## Deserialise JSON to Request (RFC 8620 section 3.3).
  checkJsonKind(node, JObject, $T)
  let usingNode = node{"using"}
  checkJsonKind(usingNode, JArray, $T, "missing or invalid using")
  var usingSeq: seq[string] = @[]
  for _, elem in usingNode.getElems(@[]):
    checkJsonKind(elem, JString, $T, "using element must be string")
    usingSeq.add(elem.getStr(""))
  let callsNode = node{"methodCalls"}
  checkJsonKind(callsNode, JArray, $T, "missing or invalid methodCalls")
  var methodCalls: seq[Invocation] = @[]
  for _, callNode in callsNode.getElems(@[]):
    let inv = ?Invocation.fromJson(callNode)
    methodCalls.add(inv)
  let createdIds = ?parseCreatedIds(node, $T)
  ok(Request(`using`: usingSeq, methodCalls: methodCalls, createdIds: createdIds))

# =============================================================================
# Response
# =============================================================================

func toJson*(r: Response): JsonNode =
  ## Serialise Response to JSON (RFC 8620 section 3.4).
  {.cast(noSideEffect).}:
    result = newJObject()
    var responses = newJArray()
    for _, inv in r.methodResponses:
      responses.add(inv.toJson())
    result["methodResponses"] = responses
    result["sessionState"] = %string(r.sessionState)
    if r.createdIds.isSome:
      var ids = newJObject()
      for k, v in r.createdIds.get():
        ids[string(k)] = %string(v)
      result["createdIds"] = ids

func parseResponseCore(
    node: JsonNode
): Result[(seq[Invocation], JmapState), ValidationError] =
  ## Parse methodResponses and sessionState from a Response JSON object.
  ## Separated from Response.fromJson to avoid the requiresInit + Opt[Table]
  ## interaction that prevents err()/? on Result[Response, ValidationError].
  checkJsonKind(node, JObject, "Response")
  let responsesNode = node{"methodResponses"}
  checkJsonKind(responsesNode, JArray, "Response", "missing or invalid methodResponses")
  var methodResponses: seq[Invocation] = @[]
  for _, respNode in responsesNode.getElems(@[]):
    let inv = ?Invocation.fromJson(respNode)
    methodResponses.add(inv)
  let sessionStateNode = node{"sessionState"}
  checkJsonKind(
    sessionStateNode, JString, "Response", "missing or invalid sessionState"
  )
  let sessionState = ?parseJmapState(sessionStateNode.getStr(""))
  ok((methodResponses, sessionState))

func fromJson*(
    T: typedesc[Response], node: JsonNode
): Result[Response, ValidationError] =
  ## Deserialise JSON to Response (RFC 8620 section 3.4).
  ## Uses initResultErr and helper funcs instead of err()/? because
  ## Result[Response, ValidationError] triggers a nim-results requiresInit
  ## limitation (Response has both Opt[Table[requiresInit,...]] and bare
  ## requiresInit fields).
  let coreResult = parseResponseCore(node)
  if coreResult.isErr:
    return initResultErr[Response, ValidationError](coreResult.error)
  let core = coreResult.get()
  let createdIdsResult = parseCreatedIds(node, $T)
  if createdIdsResult.isErr:
    return initResultErr[Response, ValidationError](createdIdsResult.error)
  let createdIds = createdIdsResult.get()
  ok(Response(methodResponses: core[0], createdIds: createdIds, sessionState: core[1]))

# =============================================================================
# ResultReference
# =============================================================================

func toJson*(r: ResultReference): JsonNode =
  ## Serialise ResultReference to JSON (RFC 8620 section 3.7).
  {.cast(noSideEffect).}:
    result = %*{"resultOf": string(r.resultOf), "name": r.name, "path": r.path}

func fromJson*(
    T: typedesc[ResultReference], node: JsonNode
): Result[ResultReference, ValidationError] =
  ## Deserialise JSON to ResultReference (RFC 8620 section 3.7).
  checkJsonKind(node, JObject, $T)
  let resultOfNode = node{"resultOf"}
  checkJsonKind(resultOfNode, JString, $T, "missing or invalid resultOf")
  let resultOfRaw = resultOfNode.getStr("")
  let nameNode = node{"name"}
  checkJsonKind(nameNode, JString, $T, "missing or invalid name")
  let name = nameNode.getStr("")
  let pathNode = node{"path"}
  checkJsonKind(pathNode, JString, $T, "missing or invalid path")
  let path = pathNode.getStr("")
  if name.len == 0:
    return err(parseError($T, "name must not be empty"))
  if path.len == 0:
    return err(parseError($T, "path must not be empty"))
  let resultOf = ?parseMethodCallId(resultOfRaw)
  ok(ResultReference(resultOf: resultOf, name: name, path: path))

# =============================================================================
# Referencable[T] helpers
# =============================================================================

func referencableKey*[T](fieldName: string, r: Referencable[T]): string =
  ## Returns the JSON key: plain for direct, #-prefixed for reference.
  case r.kind
  of rkDirect:
    fieldName
  of rkReference:
    "#" & fieldName

func fromJsonField*[T](
    fieldName: string,
    node: JsonNode,
    fromDirect:
      proc(n: JsonNode): Result[T, ValidationError] {.noSideEffect, raises: [].},
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
  let value = ?fromDirect(directNode)
  ok(direct[T](value))
