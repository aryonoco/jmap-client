# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parsing for JMAP envelope types (RFC 8620 §3.2-3.4, 3.7) plus the
## ``Referencable[T]`` field-extraction helpers. Hub-private — per P19
## ("diagnostic emission is fine; the reverse direction is not"), no
## application code constructs typed envelopes by parsing raw JSON. The
## library's auto-dispatch path consumes these internally.
##
## In-tree callers reach this module via direct H10 import. The companion
## ``serde_envelope_emit`` carries the user-facing toJson direction.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json
import std/tables

import ./serde
import ./serde_diagnostics
import ./serde_helpers
import ../types
import ../types/envelope

func fromJson*(
    T: typedesc[Invocation], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Invocation, SerdeViolation] =
  ## Deserialise a 3-element JSON array to Invocation (RFC 8620 section 3.2).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JArray, path)
  ?expectLen(node, 3, path)
  let elems = node.getElems(@[])
  let nameNode = elems[0]
  ?expectKind(nameNode, JString, path / 0)
  let name = nameNode.getStr("")
  let arguments = elems[1]
  let callIdNode = elems[2]
  ?expectKind(callIdNode, JString, path / 2)
  let callIdRaw = callIdNode.getStr("")
  ?expectKind(arguments, JObject, path / 1)
  ?nonEmptyStr(name, "method name", path / 0)
  ?nonEmptyStr(callIdRaw, "method call ID", path / 2)
  let mcid = ?wrapInner(parseMethodCallId(callIdRaw), path / 2)
  return wrapInner(parseInvocation(name, arguments, mcid), path)

func parseCreatedIds(
    node: JsonNode, path: JsonPath
): Result[Opt[Table[CreationId, Id]], SerdeViolation] =
  ## Parse optional createdIds from a Request or Response JSON object.
  ## Container-strict: wrong container kind raises (design doc section 9).
  let cnode = node{"createdIds"}
  if cnode.isNil:
    return ok(Opt.none(Table[CreationId, Id]))
  if cnode.kind == JNull:
    return ok(Opt.none(Table[CreationId, Id]))
  if cnode.kind != JObject:
    return err(
      SerdeViolation(
        kind: svkWrongKind,
        path: path / "createdIds",
        expectedKind: JObject,
        actualKind: cnode.kind,
      )
    )
  var tbl = initTable[CreationId, Id]()
  for k, v in cnode.pairs:
    let cid = ?wrapInner(parseCreationId(k), path / "createdIds" / k)
    ?expectKind(v, JString, path / "createdIds" / k)
    let id = ?wrapInner(parseIdFromServer(v.getStr("")), path / "createdIds" / k)
    tbl[cid] = id
  return ok(Opt.some(tbl))

func fromJson*(
    T: typedesc[Request], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Request, SerdeViolation] =
  ## Deserialise JSON to Request (RFC 8620 section 3.3).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let usingNode = ?fieldJArray(node, "using", path)
  var usingSeq: seq[string] = @[]
  for i, elem in usingNode.getElems(@[]):
    ?expectKind(elem, JString, path / "using" / i)
    usingSeq.add(elem.getStr(""))
  let callsNode = ?fieldJArray(node, "methodCalls", path)
  var methodCalls: seq[Invocation] = @[]
  for i, callNode in callsNode.getElems(@[]):
    let inv = ?Invocation.fromJson(callNode, path / "methodCalls" / i)
    methodCalls.add(inv)
  let createdIds = ?parseCreatedIds(node, path)
  return
    ok(Request(`using`: usingSeq, methodCalls: methodCalls, createdIds: createdIds))

func fromJson*(
    T: typedesc[Response], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[Response, SerdeViolation] =
  ## Deserialise JSON to Response (RFC 8620 section 3.4).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let responsesNode = ?fieldJArray(node, "methodResponses", path)
  var methodResponses: seq[Invocation] = @[]
  for i, respNode in responsesNode.getElems(@[]):
    let inv = ?Invocation.fromJson(respNode, path / "methodResponses" / i)
    methodResponses.add(inv)
  let sessionStateNode = ?fieldJString(node, "sessionState", path)
  let sessionState =
    ?wrapInner(parseJmapState(sessionStateNode.getStr("")), path / "sessionState")
  let createdIds = ?parseCreatedIds(node, path)
  return ok(
    Response(
      methodResponses: methodResponses,
      createdIds: createdIds,
      sessionState: sessionState,
    )
  )

func fromJson*(
    T: typedesc[ResultReference], node: JsonNode, path: JsonPath = emptyJsonPath()
): Result[ResultReference, SerdeViolation] =
  ## Deserialise JSON to ResultReference (RFC 8620 section 3.7).
  discard $T # consumed for nimalyzer params rule
  ?expectKind(node, JObject, path)
  let resultOfNode = ?fieldJString(node, "resultOf", path)
  let resultOfRaw = resultOfNode.getStr("")
  let nameNode = ?fieldJString(node, "name", path)
  let name = nameNode.getStr("")
  let pathNode = ?fieldJString(node, "path", path)
  let pathValue = pathNode.getStr("")
  let resultOf = ?wrapInner(parseMethodCallId(resultOfRaw), path / "resultOf")
  return wrapInner(parseResultReference(resultOf, name, pathValue), path)

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
    path: JsonPath = emptyJsonPath(),
): Result[Referencable[T], SerdeViolation] =
  ## Parse a Referencable field from a JSON object.
  ## Checks "#fieldName" (reference) first, then "fieldName" (direct).
  ## Rejects when both forms are present (RFC 8620 §3.7).
  let refKey = "#" & fieldName
  let refNode = node{refKey}
  let directNode = node{fieldName}
  # RFC 8620 §3.7: reject when both direct and referenced forms are present
  if not refNode.isNil and not directNode.isNil:
    return err(
      SerdeViolation(
        kind: svkConflictingFields,
        path: path,
        conflictKeyA: fieldName,
        conflictKeyB: refKey,
        conflictRule: "RFC 8620 §3.7",
      )
    )
  if not refNode.isNil:
    ?expectKind(refNode, JObject, path / refKey)
    let resultRef = ?ResultReference.fromJson(refNode, path / refKey)
    return ok(referenceTo[T](resultRef))
  if directNode.isNil:
    return err(
      SerdeViolation(
        kind: svkMissingField, path: path, missingFieldName: fieldName & " or " & refKey
      )
    )
  let value = fromDirect(directNode)
  return ok(direct[T](value))
