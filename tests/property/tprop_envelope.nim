# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for JMAP envelope types: Request, Response,
## Invocation, and Referencable.

import std/json
import std/random
import std/tables

import jmap_client/internal/types/primitives
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/envelope
import jmap_client/internal/types/methods_enum
import jmap_client/internal/types/validation
# H10-permitted direct leaf import for the envelope SerDe — ``Invocation.toJson``
# / ``Invocation.fromJson`` are hub-internal (A16/A30b), so the round-trip
# property reaches them here rather than through ``import jmap_client``.
import jmap_client/internal/serialisation/serde_envelope

import ../mproperty
import ../mtestblock

testCase propRequestPreservesMethodCallOrder:
  checkProperty "propRequestPreservesMethodCallOrder":
    ## Request.methodCalls preserves insertion order and count.
    let n = rng.rand(1 .. 10)
    lastInput = $n
    var calls: seq[Invocation] = @[]
    for i in 0 ..< n:
      calls.add genInvocation(rng)
    let req = initRequest(
      @["urn:ietf:params:jmap:core"], calls, Opt.none(Table[CreationId, Id])
    )
    doAssert req.methodCalls.len == n
    for i in 0 ..< n:
      doAssert req.methodCalls[i].name == calls[i].name

testCase propResponsePreservesInvocationOrder:
  checkProperty "propResponsePreservesInvocationOrder":
    ## Response.methodResponses preserves insertion order and count.
    let n = rng.rand(1 .. 10)
    lastInput = $n
    var responses: seq[Invocation] = @[]
    for i in 0 ..< n:
      responses.add genInvocation(rng)
    let state = parseJmapState("s" & $trial).get()
    let resp = initResponse(responses, Opt.none(Table[CreationId, Id]), state)
    doAssert resp.methodResponses.len == n
    for i in 0 ..< n:
      doAssert resp.methodResponses[i].name == responses[i].name

testCase propReferencableDirectPreservesValue:
  checkProperty "propReferencableDirectPreservesValue":
    ## direct(v).asDirect == Some(v) for random Id sequences.
    let ids = @[parseIdFromServer("id" & $trial).get()]
    lastInput = $trial
    let d = direct(ids)
    doAssert d.kind == rkDirect
    doAssert d.asDirect.get().len == ids.len

testCase propReferencableReferencePreservesRef:
  checkProperty "propReferencableReferencePreservesRef":
    ## referenceTo preserves the ResultReference.
    let mcid = parseMethodCallId("c" & $trial).get()
    lastInput = $trial
    let rr = initResultReference(resultOf = mcid, name = mnEmailQuery, path = rpIds)
    let r = referenceTo[seq[Id]](rr)
    doAssert r.kind == rkReference
    doAssert r.asReference.get().resultOf == mcid
    doAssert r.asReference.get().path == rpIds

testCase propReferencableExclusivity:
  checkProperty "propReferencableExclusivity":
    ## A Referencable is either direct or reference, never ambiguous.
    let ids = @[parseIdFromServer("id" & $trial).get()]
    lastInput = $trial
    let d = direct(ids)
    doAssert d.kind == rkDirect
    doAssert not (d.kind == rkReference)

    let mcid = parseMethodCallId("c" & $trial).get()
    let rr = initResultReference(resultOf = mcid, name = mnMailboxGet, path = rpIds)
    let r = referenceTo[seq[Id]](rr)
    doAssert r.kind == rkReference
    doAssert not (r.kind == rkDirect)

testCase propInvocationPreservesFields:
  checkProperty "propInvocationPreservesFields":
    ## Invocation construction preserves all three fields.
    let inv = genInvocation(rng)
    lastInput = inv.rawName
    doAssert inv.rawName.len > 0
    doAssert inv.arguments.kind == JObject
    # methodCallId was set by genInvocation

testCase propInvocationRoundTrip:
  checkProperty "Invocation round-trip: fromJson(toJson(inv)) == inv":
    ## A2b: every ``MethodName`` variant — the 27 named ones plus the
    ## ``mnUnknown`` catch-all (exercised via a synthesised vendor wire name) —
    ## round-trips losslessly through the wire form. ``Invocation`` is a flat
    ## (non-case) object, so its auto-generated structural ``==`` compares all
    ## three fields, including the ``JsonNode`` arguments (std/json's structural
    ## ``==``).
    let mcid = parseMethodCallId("c" & $rng.rand(0 .. 99)).get()
    let args = %*{"k": rng.rand(0 .. 1000), "flag": rng.rand(0 .. 1) == 0}
    # Named variants: ``initInvocation`` stores the wire name (``$name``).
    for name in MethodName:
      if name == mnUnknown:
        continue
      let inv = initInvocation(name, args, mcid)
      let rt = Invocation.fromJson(inv.toJson()).get()
      doAssert rt == inv, "round-trip mismatch for " & $name
    # ``mnUnknown``: a vendor wire name preserved verbatim via ``parseInvocation``
    # (``initInvocation`` would store the symbol "mnUnknown", which is lossy —
    # A11 forward-compat carries the raw bytes instead).
    let vendorName = "Vendor/customThing" & $trial
    let vendorInv = parseInvocation(vendorName, args, mcid).get()
    doAssert vendorInv.name == mnUnknown
    let vendorRt = Invocation.fromJson(vendorInv.toJson()).get()
    doAssert vendorRt == vendorInv
    doAssert vendorRt.rawName == vendorName

testCase propRequestCreatedIdsTablePreserved:
  checkPropertyN "propRequestCreatedIdsTablePreserved", QuickTrials:
    ## When createdIds is present, the table mapping is preserved.
    let n = rng.rand(1 .. 5)
    lastInput = $n
    var cids = initTable[CreationId, Id]()
    for i in 0 ..< n:
      let cid = parseCreationId("k" & $i).get()
      let id = parseIdFromServer("sid" & $i).get()
      cids[cid] = id
    let req = initRequest(@[], @[], Opt.some(cids))
    doAssert req.createdIds.isSome
    doAssert req.createdIds.get().len == n
    for i in 0 ..< n:
      let cid = parseCreationId("k" & $i).get()
      doAssert req.createdIds.get()[cid] == parseIdFromServer("sid" & $i).get()

# --- Referencable properties ---

testCase propReferencableDirectInjectivity:
  checkProperty "propReferencableDirectInjectivity":
    ## direct(v1) == direct(v2) implies v1 == v2 for comparable types.
    let v1 = rng.rand(int)
    let v2 = rng.rand(int)
    lastInput = $v1 & ", " & $v2
    let d1 = direct(v1)
    let d2 = direct(v2)
    ## Compare via kind + asDirect since Referencable is a sealed case
    ## object without a custom == operator.
    if d1.kind == d2.kind and d1.asDirect.get() == d2.asDirect.get():
      doAssert v1 == v2

testCase propReferencableKindDisjointness:
  checkProperty "propReferencableKindDisjointness":
    ## direct(v).kind != referenceTo(r).kind for any v and r.
    let v = rng.rand(int)
    lastInput = $v
    let mcid = parseMethodCallId("c" & $trial).get()
    let rr = initResultReference(resultOf = mcid, name = mnMailboxGet, path = rpIds)
    let d = direct(v)
    let r = referenceTo[int](rr)
    doAssert d.kind != r.kind

testCase propRefPathUnknownPreservesRaw:
  checkProperty "propRefPathUnknownPreservesRaw":
    ## Forward-compat invariant: unknown wire paths surface as
    ## ``rpUnknown`` while ``rawPath`` preserves the verbatim wire
    ## bytes (A11 contract).
    let mcid = parseMethodCallId("c" & $trial).get()
    lastInput = "/vendor/path/" & $trial
    let rr = parseResultReference(
        resultOf = mcid, name = "Mailbox/get", path = "/vendor/path/" & $trial
      )
      .get()
    doAssert rr.path == rpUnknown
    doAssert rr.rawPath == "/vendor/path/" & $trial
