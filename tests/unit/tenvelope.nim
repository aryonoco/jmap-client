# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for JMAP Request/Response envelope types.

import std/json
import std/tables

import results

import jmap_client/identifiers
import jmap_client/primitives
import jmap_client/envelope

import ../massertions

# --- Invocation ---

block invocationConstruction:
  let mcid = parseMethodCallId("c1").get()
  let inv = Invocation(
    name: "Mailbox/get", arguments: %*{"accountId": "A1"}, methodCallId: mcid
  )
  doAssert inv.name == "Mailbox/get"
  doAssert inv.arguments == %*{"accountId": "A1"}
  doAssert inv.methodCallId == mcid

# --- Request ---

block requestRfcExample:
  let c1 = parseMethodCallId("c1").get()
  let c2 = parseMethodCallId("c2").get()
  let c3 = parseMethodCallId("c3").get()
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
    methodCalls: @[
      Invocation(
        name: "method1",
        arguments: %*{"arg1": "arg1data", "arg2": "arg2data"},
        methodCallId: c1,
      ),
      Invocation(name: "method2", arguments: %*{"arg1": "arg1data"}, methodCallId: c2),
      Invocation(name: "method3", arguments: %*{}, methodCallId: c3),
    ],
  )
  doAssert req.`using`.len == 2
  doAssert req.`using`[0] == "urn:ietf:params:jmap:core"
  doAssert req.`using`[1] == "urn:ietf:params:jmap:mail"
  doAssert req.methodCalls.len == 3
  doAssert req.methodCalls[0].name == "method1"
  doAssert req.methodCalls[0].methodCallId == c1
  doAssert req.methodCalls[1].name == "method2"
  doAssert req.methodCalls[2].name == "method3"
  doAssert req.methodCalls[2].methodCallId == c3
  doAssert req.createdIds.isNone

block requestWithCreatedIds:
  let cid = parseCreationId("k1").get()
  let id = parseId("abc").get()
  var tbl = initTable[CreationId, Id]()
  tbl[cid] = id
  let req = Request(`using`: @[], methodCalls: @[], createdIds: Opt.some(tbl))
  doAssert req.createdIds.isSome
  let extracted = req.createdIds.get()
  doAssert extracted.len == 1
  doAssert extracted[cid] == id

block requestEmptyMethodCalls:
  let req = Request(`using`: @[], methodCalls: @[])
  doAssert req.`using`.len == 0
  doAssert req.methodCalls.len == 0
  doAssert req.createdIds.isNone

# --- Response ---

block responseConstruction:
  let mcid = parseMethodCallId("c1").get()
  let state = parseJmapState("state1").get()
  let resp = Response(
    methodResponses:
      @[Invocation(name: "Mailbox/get", arguments: %*{"list": []}, methodCallId: mcid)],
    sessionState: state,
  )
  doAssert resp.methodResponses.len == 1
  doAssert resp.methodResponses[0].name == "Mailbox/get"
  doAssert resp.methodResponses[0].methodCallId == mcid
  doAssert resp.sessionState == state
  doAssert resp.createdIds.isNone

block responseRfcExample:
  let c1 = parseMethodCallId("c1").get()
  let c2 = parseMethodCallId("c2").get()
  let c3 = parseMethodCallId("c3").get()
  let state = parseJmapState("75128aab4b1b").get()
  let resp = Response(
    methodResponses: @[
      Invocation(
        name: "method1", arguments: %*{"arg1": 3, "arg2": "foo"}, methodCallId: c1
      ),
      Invocation(name: "method2", arguments: %*{"isBlah": true}, methodCallId: c2),
      Invocation(
        name: "anotherResponseFromMethod2",
        arguments: %*{"data": 10, "yetmoredata": "Hello"},
        methodCallId: c2,
      ),
      Invocation(
        name: "error", arguments: %*{"type": "unknownMethod"}, methodCallId: c3
      ),
    ],
    sessionState: state,
  )
  doAssert resp.methodResponses.len == 4
  doAssert resp.methodResponses[0].methodCallId == c1
  doAssert resp.methodResponses[1].methodCallId == c2
  doAssert resp.methodResponses[2].methodCallId == c2
  doAssert resp.methodResponses[3].name == "error"
  doAssert resp.methodResponses[3].methodCallId == c3
  doAssert resp.sessionState == state
  doAssert resp.createdIds.isNone

block responseWithCreatedIds:
  let cid = parseCreationId("k1").get()
  let id = parseId("abc").get()
  let state = parseJmapState("state2").get()
  var tbl = initTable[CreationId, Id]()
  tbl[cid] = id
  let resp =
    Response(methodResponses: @[], createdIds: Opt.some(tbl), sessionState: state)
  doAssert resp.createdIds.isSome
  let extracted = resp.createdIds.get()
  doAssert extracted.len == 1
  doAssert extracted[cid] == id

# --- ResultReference ---

block resultReferenceConstruction:
  let mcid = parseMethodCallId("c1").get()
  let rref = ResultReference(resultOf: mcid, name: "Mailbox/query", path: "/ids")
  doAssert rref.resultOf == mcid
  doAssert rref.name == "Mailbox/query"
  doAssert rref.path == "/ids"

# --- Path Constants ---

block pathConstantValues:
  doAssert RefPathIds == "/ids"
  doAssert RefPathListIds == "/list/*/id"
  doAssert RefPathAddedIds == "/added/*/id"
  doAssert RefPathCreated == "/created"
  doAssert RefPathUpdated == "/updated"
  doAssert RefPathUpdatedProperties == "/updatedProperties"

# --- Referencable[T] ---

block directReferencableInt:
  let r = direct(42)
  doAssert r.kind == rkDirect
  doAssert r.value == 42

block referenceReferencableSeqId:
  let mcid = parseMethodCallId("c1").get()
  let rref = ResultReference(resultOf: mcid, name: "Mailbox/query", path: "/ids")
  let r = referenceTo[seq[Id]](rref)
  doAssert r.kind == rkReference
  doAssert r.reference.resultOf == mcid
  doAssert r.reference.name == "Mailbox/query"
  doAssert r.reference.path == "/ids"

block referencableConcreteTypes:
  let strRef = direct("hello")
  doAssert strRef.kind == rkDirect
  doAssert strRef.value == "hello"

  let idSeq = direct(@[parseId("abc").get()])
  doAssert idSeq.kind == rkDirect
  doAssert idSeq.value.len == 1

  let optRef = direct(Opt.some("x"))
  doAssert optRef.kind == rkDirect
  doAssert optRef.value.isSome
  doAssert optRef.value.get() == "x"

# --- Referencable compile-time safety ---

block referencableVariantDiscrimination:
  # Direct and reference variants are distinguished by kind discriminator
  let id = parseId("test").get()
  let mcid = parseMethodCallId("c0").get()
  let d = direct[Id](id)
  let rr = ResultReference(resultOf: mcid, name: "Email/get", path: "/ids")
  let r = referenceTo[Id](rr)
  doAssert d.kind == rkDirect
  doAssert r.kind == rkReference
  doAssert d.value == id
  doAssert r.reference.resultOf == mcid
  doAssert r.reference.name == "Email/get"
  doAssert r.reference.path == "/ids"

# --- Request.using duplicate entries ---

block requestDuplicateUsing:
  ## Duplicate entries in Request.using are preserved (seq, not set).
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:core"],
    methodCalls: @[],
    createdIds: Opt.none(Table[CreationId, Id]),
  )
  doAssert req.`using`.len == 2
