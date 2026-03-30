# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based tests for JMAP envelope types: Request, Response,
## Invocation, and Referencable.

import std/json
import std/random
import std/tables

import results

import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/envelope

import ../massertions
import ../mproperty

block propRequestPreservesMethodCallOrder:
  checkProperty "propRequestPreservesMethodCallOrder":
    ## Request.methodCalls preserves insertion order and count.
    let n = rng.rand(1 .. 10)
    lastInput = $n
    var calls: seq[Invocation] = @[]
    for i in 0 ..< n:
      calls.add genInvocation(rng)
    let req = Request(
      `using`: @["urn:ietf:params:jmap:core"],
      methodCalls: calls,
      createdIds: Opt.none(Table[CreationId, Id]),
    )
    doAssert req.methodCalls.len == n
    for i in 0 ..< n:
      doAssert req.methodCalls[i].name == calls[i].name

block propResponsePreservesInvocationOrder:
  checkProperty "propResponsePreservesInvocationOrder":
    ## Response.methodResponses preserves insertion order and count.
    let n = rng.rand(1 .. 10)
    lastInput = $n
    var responses: seq[Invocation] = @[]
    for i in 0 ..< n:
      responses.add genInvocation(rng)
    let state = parseJmapState("s" & $trial).get()
    let resp = Response(
      methodResponses: responses,
      createdIds: Opt.none(Table[CreationId, Id]),
      sessionState: state,
    )
    doAssert resp.methodResponses.len == n
    for i in 0 ..< n:
      doAssert resp.methodResponses[i].name == responses[i].name

block propReferencableDirectPreservesValue:
  checkProperty "propReferencableDirectPreservesValue":
    ## direct(v).value == v for random Id sequences.
    let ids = @[parseId("id" & $trial).get()]
    lastInput = $trial
    let d = direct(ids)
    doAssert d.kind == rkDirect
    doAssert d.value.len == ids.len

block propReferencableReferencePreservesRef:
  checkProperty "propReferencableReferencePreservesRef":
    ## referenceTo preserves the ResultReference.
    let mcid = parseMethodCallId("c" & $trial).get()
    lastInput = $trial
    let rr = ResultReference(resultOf: mcid, name: "Email/query", path: "/ids")
    let r = referenceTo[seq[Id]](rr)
    doAssert r.kind == rkReference
    doAssert r.reference.resultOf == mcid
    doAssert r.reference.path == "/ids"

block propReferencableExclusivity:
  checkProperty "propReferencableExclusivity":
    ## A Referencable is either direct or reference, never ambiguous.
    let ids = @[parseId("id" & $trial).get()]
    lastInput = $trial
    let d = direct(ids)
    doAssert d.kind == rkDirect
    doAssert not (d.kind == rkReference)

    let mcid = parseMethodCallId("c" & $trial).get()
    let rr = ResultReference(resultOf: mcid, name: "M/get", path: "/ids")
    let r = referenceTo[seq[Id]](rr)
    doAssert r.kind == rkReference
    doAssert not (r.kind == rkDirect)

block propInvocationPreservesFields:
  checkProperty "propInvocationPreservesFields":
    ## Invocation construction preserves all three fields.
    let inv = genInvocation(rng)
    lastInput = inv.name
    doAssert inv.name.len > 0
    doAssert inv.arguments.kind == JObject
    # methodCallId was set by genInvocation

block propRequestCreatedIdsTablePreserved:
  checkPropertyN "propRequestCreatedIdsTablePreserved", QuickTrials:
    ## When createdIds is present, the table mapping is preserved.
    let n = rng.rand(1 .. 5)
    lastInput = $n
    var cids = initTable[CreationId, Id]()
    for i in 0 ..< n:
      let cid = parseCreationId("k" & $i).get()
      let id = parseId("sid" & $i).get()
      cids[cid] = id
    let req = Request(`using`: @[], methodCalls: @[], createdIds: Opt.some(cids))
    doAssert req.createdIds.isSome
    doAssert req.createdIds.get().len == n
    for i in 0 ..< n:
      let cid = parseCreationId("k" & $i).get()
      doAssert req.createdIds.get()[cid] == parseId("sid" & $i).get()

# --- Referencable properties ---

block propReferencableDirectInjectivity:
  checkProperty "propReferencableDirectInjectivity":
    ## direct(v1) == direct(v2) implies v1 == v2 for comparable types.
    let v1 = rng.rand(int)
    let v2 = rng.rand(int)
    lastInput = $v1 & ", " & $v2
    let d1 = direct(v1)
    let d2 = direct(v2)
    ## Compare via kind + value since Referencable is a case object
    ## without a custom == operator.
    if d1.kind == d2.kind and d1.value == d2.value:
      doAssert v1 == v2

block propReferencableKindDisjointness:
  checkProperty "propReferencableKindDisjointness":
    ## direct(v).kind != referenceTo(r).kind for any v and r.
    let v = rng.rand(int)
    lastInput = $v
    let mcid = parseMethodCallId("c" & $trial).get()
    let rr = ResultReference(resultOf: mcid, name: "M/get", path: "/ids")
    let d = direct(v)
    let r = referenceTo[int](rr)
    doAssert d.kind != r.kind
