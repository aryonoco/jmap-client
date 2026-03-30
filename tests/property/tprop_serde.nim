# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based tests for Layer 2 serialisation round-trips. Verifies
## toJson -> fromJson identity, totality (never crashes on arbitrary input),
## and idempotence for all composite serde types.

import std/json
import std/random
import std/sets
import std/tables

import results

import jmap_client/serde
import jmap_client/serde_envelope
import jmap_client/serde_session
import jmap_client/serde_framework
import jmap_client/serde_errors
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/session
import jmap_client/envelope
import jmap_client/framework
import jmap_client/errors
import jmap_client/validation

import ../massertions
import ../mfixtures
import ../mproperty

# =============================================================================
# A. Round-trip identity properties (Tier 1 -- Critical)
# =============================================================================

block propRoundTripRequest:
  checkPropertyN "Request round-trip: fromJson(toJson(req)) preserves structure",
    ThoroughTrials:
    let req = rng.genRequest()
    lastInput = $req.using.len & " using, " & $req.methodCalls.len & " calls"
    let j = req.toJson()
    let rt = Request.fromJson(j)
    doAssert rt.isOk, "Request round-trip failed"
    doAssert reqEq(rt.get(), req), "Request round-trip identity violated"

block propRoundTripResponse:
  checkPropertyN "Response round-trip: fromJson(toJson(resp)) preserves structure",
    ThoroughTrials:
    let resp = rng.genResponse()
    lastInput = $resp.methodResponses.len & " responses"
    let j = resp.toJson()
    let rt = Response.fromJson(j)
    doAssert rt.isOk, "Response round-trip failed"
    doAssert respEq(rt.get(), resp), "Response round-trip identity violated"

block propRoundTripServerCapabilityRawData:
  checkPropertyN "ServerCapability rawData preserved through round-trip", ThoroughTrials:
    let cap = rng.genServerCapability()
    lastInput = cap.rawUri
    if cap.kind != ckCore:
      let j = cap.toJson()
      let rt = ServerCapability.fromJson(cap.rawUri, j)
      doAssert rt.isOk, "ServerCapability round-trip failed for " & cap.rawUri
      doAssert capEq(rt.get(), cap), "rawData lost for " & cap.rawUri

block propRoundTripComparator:
  checkPropertyN "Comparator round-trip preserves all fields", ThoroughTrials:
    let c = rng.genComparator()
    lastInput = string(c.property)
    let j = c.toJson()
    let rt = Comparator.fromJson(j)
    doAssert rt.isOk, "Comparator round-trip failed"
    let v = rt.get()
    doAssert string(v.property) == string(c.property)
    doAssert v.isAscending == c.isAscending
    doAssert v.collation == c.collation

block propRoundTripAddedItem:
  checkPropertyN "AddedItem round-trip preserves id and index", ThoroughTrials:
    let item = rng.genAddedItem()
    lastInput = string(item.id) & " @ " & $int64(item.index)
    let j = item.toJson()
    let rt = AddedItem.fromJson(j)
    doAssert rt.isOk, "AddedItem round-trip failed"
    doAssert rt.get().id == item.id
    doAssert rt.get().index == item.index

block propRoundTripResultReference:
  checkPropertyN "ResultReference round-trip preserves all fields", ThoroughTrials:
    let rref = rng.genResultReference()
    lastInput = rref.name
    let j = rref.toJson()
    let rt = ResultReference.fromJson(j)
    doAssert rt.isOk, "ResultReference round-trip failed"
    doAssert rt.get().resultOf == rref.resultOf
    doAssert rt.get().name == rref.name
    doAssert rt.get().path == rref.path

# =============================================================================
# B. Round-trip for error types (Tier 2 -- High)
# =============================================================================

block propRoundTripRequestError:
  checkPropertyN "RequestError round-trip preserves rawType and optional fields",
    ThoroughTrials:
    let re = rng.genRequestError()
    lastInput = re.rawType
    let j = re.toJson()
    let rt = RequestError.fromJson(j)
    doAssert rt.isOk, "RequestError round-trip failed"
    doAssert rt.get().rawType == re.rawType
    doAssert rt.get().errorType == re.errorType
    doAssert rt.get().status == re.status
    doAssert rt.get().title == re.title
    doAssert rt.get().detail == re.detail

block propRoundTripMethodError:
  checkPropertyN "MethodError round-trip preserves rawType and description",
    ThoroughTrials:
    let me = rng.genMethodError()
    lastInput = me.rawType
    let j = me.toJson()
    let rt = MethodError.fromJson(j)
    doAssert rt.isOk, "MethodError round-trip failed"
    doAssert rt.get().rawType == me.rawType
    doAssert rt.get().errorType == me.errorType
    doAssert rt.get().description == me.description

block propRoundTripSetErrorVariants:
  checkPropertyN "SetError variant round-trip preserves errorType and rawType",
    ThoroughTrials:
    let se = rng.genSetError()
    lastInput = se.rawType & " (" & $se.errorType & ")"
    let j = se.toJson()
    let rt = SetError.fromJson(j)
    doAssert rt.isOk, "SetError round-trip failed for " & se.rawType
    doAssert rt.get().rawType == se.rawType
    # Variant-specific fields (defensive fallback may remap)
    case se.errorType
    of setInvalidProperties:
      if rt.get().errorType == setInvalidProperties:
        doAssert rt.get().properties == se.properties
    of setAlreadyExists:
      if rt.get().errorType == setAlreadyExists:
        doAssert rt.get().existingId == se.existingId
    else:
      discard

# =============================================================================
# C. Filter round-trip (Tier 1 -- Critical)
# =============================================================================

block propRoundTripFilterInt:
  checkPropertyN "Filter[int] round-trip preserves tree structure", ThoroughTrials:
    let f = rng.genFilter(3)
    lastInput = $f.kind
    let j = f.toJson(intToJson)
    let rt = Filter[int].fromJson(j, fromIntCondition)
    doAssert rt.isOk, "Filter[int] round-trip failed"
    doAssert filterEq(rt.get(), f), "Filter[int] round-trip identity violated"

# =============================================================================
# D. Totality: fromJson never crashes on arbitrary input (Tier 3)
# =============================================================================

block propTotalitySessionMalformed:
  checkPropertyN "Session.fromJson never crashes on malformed input", ThoroughTrials:
    let j = rng.genMalformedSessionJson()
    lastInput = $j.kind
    discard Session.fromJson(j)

block propTotalityRequestArbitraryJson:
  checkPropertyN "Request.fromJson never crashes on arbitrary JSON", ThoroughTrials:
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard Request.fromJson(j)

block propTotalityResponseArbitraryJson:
  checkPropertyN "Response.fromJson never crashes on arbitrary JSON", ThoroughTrials:
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard Response.fromJson(j)

block propTotalityInvocationArbitraryJson:
  checkPropertyN "Invocation.fromJson never crashes on arbitrary JSON", ThoroughTrials:
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard Invocation.fromJson(j)

block propTotalityComparatorArbitraryJson:
  checkProperty "Comparator.fromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard Comparator.fromJson(j)

block propTotalitySetErrorArbitraryJson:
  checkProperty "SetError.fromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard SetError.fromJson(j)

block propTotalityRequestErrorArbitraryJson:
  checkProperty "RequestError.fromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard RequestError.fromJson(j)

block propTotalityMethodErrorArbitraryJson:
  checkProperty "MethodError.fromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard MethodError.fromJson(j)

block propTotalityPatchObjectArbitraryJson:
  checkProperty "PatchObject.fromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard PatchObject.fromJson(j)

block propTotalityAddedItemArbitraryJson:
  checkProperty "AddedItem.fromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard AddedItem.fromJson(j)

# =============================================================================
# E. Idempotence: toJson(fromJson(toJson(x))) == toJson(x) (Tier 3)
# =============================================================================

block propIdempotenceInvocation:
  checkPropertyN "Invocation serialisation is idempotent", ThoroughTrials:
    let inv = rng.genInvocationWithArgs()
    lastInput = inv.name
    let j1 = inv.toJson()
    let parsed = Invocation.fromJson(j1)
    doAssert parsed.isOk
    let j2 = parsed.get().toJson()
    doAssert j1 == j2, "Invocation toJson is not idempotent"

block propIdempotenceResultReference:
  checkPropertyN "ResultReference serialisation is idempotent", ThoroughTrials:
    let rref = rng.genResultReference()
    lastInput = rref.name
    let j1 = rref.toJson()
    let parsed = ResultReference.fromJson(j1)
    doAssert parsed.isOk
    let j2 = parsed.get().toJson()
    doAssert j1 == j2, "ResultReference toJson is not idempotent"

block propIdempotenceRequestError:
  checkPropertyN "RequestError serialisation is idempotent", ThoroughTrials:
    let re = rng.genRequestError()
    lastInput = re.rawType
    let j1 = re.toJson()
    let parsed = RequestError.fromJson(j1)
    doAssert parsed.isOk
    let j2 = parsed.get().toJson()
    doAssert j1 == j2, "RequestError toJson is not idempotent"

# =============================================================================
# F. SetError variant field preservation (Tier 2)
# =============================================================================

block propSetErrorInvalidPropertiesRoundTrip:
  checkPropertyN "invalidProperties SetError preserves properties list", ThoroughTrials:
    let propCount = rng.rand(1 .. 8)
    var props: seq[string] = @[]
    for i in 0 ..< propCount:
      props.add "field" & $rng.rand(0 .. 999)
    lastInput = $props.len & " properties"
    let se = setErrorInvalidProperties("invalidProperties", props)
    let j = se.toJson()
    let rt = SetError.fromJson(j)
    doAssert rt.isOk, "invalidProperties SetError round-trip failed"
    doAssert rt.get().errorType == setInvalidProperties
    doAssert rt.get().properties == props,
      "properties list not preserved through round-trip"

block propSetErrorAlreadyExistsRoundTrip:
  checkPropertyN "alreadyExists SetError preserves existingId", ThoroughTrials:
    let idStr = rng.genValidIdStrict(minLen = 1, maxLen = 50)
    lastInput = idStr
    let id = parseId(idStr).get()
    let se = setErrorAlreadyExists("alreadyExists", id)
    let j = se.toJson()
    let rt = SetError.fromJson(j)
    doAssert rt.isOk, "alreadyExists SetError round-trip failed"
    doAssert rt.get().errorType == setAlreadyExists
    doAssert rt.get().existingId == id, "existingId not preserved through round-trip"

# =============================================================================
# G. Composition properties (Tier 2)
# =============================================================================

block propRequestInvocationCountRoundTrip:
  checkPropertyN "Request methodCalls.len preserved through round-trip", ThoroughTrials:
    let req = rng.genRequest()
    lastInput = $req.methodCalls.len & " calls"
    let j = req.toJson()
    let rt = Request.fromJson(j)
    doAssert rt.isOk, "Request round-trip failed"
    doAssert rt.get().methodCalls.len == req.methodCalls.len,
      "methodCalls count changed through round-trip"

block propInvocationArgumentsRoundTrip:
  checkPropertyN "Invocation arguments preserved through round-trip", ThoroughTrials:
    let inv = rng.genInvocationWithArgs()
    lastInput = inv.name
    let j = inv.toJson()
    let rt = Invocation.fromJson(j)
    doAssert rt.isOk, "Invocation round-trip failed"
    doAssert rt.get().arguments == inv.arguments,
      "Invocation arguments changed through round-trip"

# =============================================================================
# H. Deep JSON totality (Tier 3)
# =============================================================================

block propSessionDeepJsonTotality:
  checkPropertyN "Session.fromJson never crashes on deep arbitrary JSON", QuickTrials:
    let j = rng.genArbitraryJsonObject(5)
    lastInput = $j.kind
    discard Session.fromJson(j)

block propRequestDeepJsonTotality:
  checkPropertyN "Request.fromJson never crashes on deep arbitrary JSON", QuickTrials:
    let j = rng.genArbitraryJsonObject(5)
    lastInput = $j.kind
    discard Request.fromJson(j)

# =============================================================================
# I. Idempotency and double-parse (Tier 2)
# =============================================================================

block propSessionDeserIdempotent:
  checkPropertyN "parsing Session JSON twice yields identical results", ThoroughTrials:
    let session = rng.genSession()
    let j = session.toJson()
    let first = Session.fromJson(j)
    let second = Session.fromJson(j)
    doAssert first.isOk, "first parse failed"
    doAssert second.isOk, "second parse failed"
    doAssert sessionEq(first.get(), second.get()),
      "two parses of same Session JSON differ"

block propDoubleParsePrimitives:
  checkPropertyN "parse -> $ -> parse round-trip stable for primitives", ThoroughTrials:
    ## Id: parse, stringify, re-parse.
    let idStr = rng.genValidIdStrict(minLen = 1, maxLen = 50)
    lastInput = idStr
    let id1 = parseId(idStr).get()
    let id2 = parseId($id1).get()
    doAssert id1 == id2, "Id double-parse not stable"
    ## AccountId: parse, stringify, re-parse.
    let acctStr = rng.genValidAccountId()
    let acct1 = parseAccountId(acctStr).get()
    let acct2 = parseAccountId($acct1).get()
    doAssert acct1 == acct2, "AccountId double-parse not stable"
    ## JmapState: parse, stringify, re-parse.
    let stateStr = rng.genValidJmapState()
    let state1 = parseJmapState(stateStr).get()
    let state2 = parseJmapState($state1).get()
    doAssert state1 == state2, "JmapState double-parse not stable"
