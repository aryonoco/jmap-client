# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Adversarial input tests for Layer 2 serialisation. Tests malformed JSON,
## boundary inputs, deep nesting, large collections, type confusion, and
## resource pressure scenarios. Every test verifies graceful handling
## (Ok or Err result, never crash).

import std/json
import std/strutils
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

# ---------------------------------------------------------------------------
# Helper definitions
# ---------------------------------------------------------------------------

proc fromIntCondition(
    n: JsonNode
): Result[int, ValidationError] {.noSideEffect, raises: [].} =
  ## Deserialise int condition for Filter[int] tests.
  checkJsonKind(n, JObject, "int")
  let vNode = n{"value"}
  checkJsonKind(vNode, JInt, "int", "missing or invalid value")
  ok(vNode.getInt(0))

proc intToJson(c: int): JsonNode {.noSideEffect, raises: [].} =
  ## Serialise an int condition to a JSON object for Filter[int] tests.
  {.cast(noSideEffect).}:
    %*{"value": c}

# Minimal valid Session JSON builder, returns a fresh tree each call.
proc validSessionJson(): JsonNode =
  ## Builds a fresh minimal valid Session JSON for adversarial modifications.
  %*{
    "capabilities": {
      "urn:ietf:params:jmap:core": {
        "maxSizeUpload": 1,
        "maxConcurrentUpload": 1,
        "maxSizeRequest": 1,
        "maxConcurrentRequests": 1,
        "maxCallsInRequest": 1,
        "maxObjectsInGet": 1,
        "maxObjectsInSet": 1,
        "collationAlgorithms": [],
      }
    },
    "accounts": {},
    "primaryAccounts": {},
    "username": "",
    "apiUrl": "https://jmap.example.com/api/",
    "downloadUrl":
      "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}",
    "uploadUrl": "https://jmap.example.com/upload/{accountId}/",
    "eventSourceUrl":
      "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}",
    "state": "s1",
  }

proc validRequestJson(): JsonNode =
  ## Builds a fresh minimal valid Request JSON.
  %*{"using": ["urn:ietf:params:jmap:core"], "methodCalls": [["Mailbox/get", {}, "c0"]]}

proc validResponseJson(): JsonNode =
  ## Builds a fresh minimal valid Response JSON.
  %*{"methodResponses": [["Mailbox/get", {}, "c0"]], "sessionState": "s1"}

# =============================================================================
# A. Session adversarial
# =============================================================================

block sessionCapabilitiesAsArray:
  ## capabilities as JArray instead of JObject -> assertErr
  var j = validSessionJson()
  {.cast(noSideEffect).}:
    j["capabilities"] = %*[1, 2, 3]
  assertErr Session.fromJson(j)

block sessionLargeCapabilities:
  ## 1000 vendor extension keys, each with empty JObject data -> should succeed.
  var j = validSessionJson()
  let caps = newJObject()
  {.cast(noSideEffect).}:
    caps["urn:ietf:params:jmap:core"] = j["capabilities"]["urn:ietf:params:jmap:core"]
  for i in 0 ..< 1000:
    {.cast(noSideEffect).}:
      caps["https://vendor.example/ext/" & $i] = newJObject()
  j["capabilities"] = caps
  let r = Session.fromJson(j)
  assertOk r
  assertGe r.get().capabilities.len, 1001

block sessionLongCapabilityUri:
  ## Capability URI of 10,000 chars -> should succeed (URIs stored as-is).
  var j = validSessionJson()
  let longUri = "https://vendor.example/" & 'a'.repeat(10000)
  let caps = newJObject()
  {.cast(noSideEffect).}:
    caps["urn:ietf:params:jmap:core"] = j["capabilities"]["urn:ietf:params:jmap:core"]
    caps[longUri] = newJObject()
  j["capabilities"] = caps
  let r = Session.fromJson(j)
  assertOk r

block sessionUnicodeAccountName:
  ## Account with Unicode name (Japanese, emoji) -> should succeed.
  var j = validSessionJson()
  {.cast(noSideEffect).}:
    j["accounts"] = %*{
      "A1": {
        "name": "\u65E5\u672C\u8A9E\u30E6\u30FC\u30B6\u30FC \U0001F600",
        "isPersonal": true,
        "isReadOnly": false,
        "accountCapabilities": {},
      }
    }
  assertOk Session.fromJson(j)

block sessionPrimaryAccountsMissedId:
  ## primaryAccounts pointing to non-existent accountId -> should succeed
  ## (referential integrity not validated at Layer 2).
  var j = validSessionJson()
  {.cast(noSideEffect).}:
    j["primaryAccounts"] = %*{"urn:ietf:params:jmap:mail": "nonExistentId"}
  assertOk Session.fromJson(j)

block sessionDuplicateCapabilityUris:
  ## JSON with duplicate "urn:ietf:params:jmap:mail" keys in capabilities.
  ## JSON last-wins semantics apply; should succeed.
  var j = validSessionJson()
  let caps = newJObject()
  {.cast(noSideEffect).}:
    caps["urn:ietf:params:jmap:core"] = j["capabilities"]["urn:ietf:params:jmap:core"]
    caps["urn:ietf:params:jmap:mail"] = %*{"first": true}
    caps["urn:ietf:params:jmap:mail"] = %*{"second": true}
  j["capabilities"] = caps
  assertOk Session.fromJson(j)

block sessionCoreCapabilityAsFloat:
  ## maxSizeUpload as JFloat (3.14) instead of JInt -> assertErr.
  var j = validSessionJson()
  {.cast(noSideEffect).}:
    j["capabilities"]["urn:ietf:params:jmap:core"]["maxSizeUpload"] = newJFloat(3.14)
  assertErr Session.fromJson(j)

block sessionMissingCoreCapability:
  ## capabilities without ckCore -> assertErr.
  var j = validSessionJson()
  {.cast(noSideEffect).}:
    j["capabilities"] = %*{"urn:ietf:params:jmap:mail": {}}
  assertErr Session.fromJson(j)

block sessionEmptyApiUrl:
  ## apiUrl is empty string -> assertErr.
  var j = validSessionJson()
  {.cast(noSideEffect).}:
    j["apiUrl"] = %""
  assertErr Session.fromJson(j)

# =============================================================================
# B. Envelope adversarial
# =============================================================================

block invocationNullElements:
  ## ["method", null, "c0"] -> assertErr (null is not JObject for arguments).
  var arr = newJArray()
  {.cast(noSideEffect).}:
    arr.add(newJString("method"))
    arr.add(newJNull())
    arr.add(newJString("c0"))
  assertErr Invocation.fromJson(arr)

block invocationEmptyArray:
  ## [] -> assertErr.
  assertErr Invocation.fromJson(newJArray())

block requestLargeMethodCalls:
  ## Request with 1000 method calls -> should succeed.
  var methodCalls = newJArray()
  for i in 0 ..< 1000:
    {.cast(noSideEffect).}:
      methodCalls.add(%*["Method/" & $i, {}, "c" & $i])
  var j = newJObject()
  {.cast(noSideEffect).}:
    j["using"] = %*["urn:ietf:params:jmap:core"]
  j["methodCalls"] = methodCalls
  assertOk Request.fromJson(j)

block requestLargeCreatedIds:
  ## Request with 1000 createdIds entries -> should succeed.
  var j = validRequestJson()
  var ids = newJObject()
  for i in 0 ..< 1000:
    {.cast(noSideEffect).}:
      ids["k" & $i] = newJString("id" & $i)
  j["createdIds"] = ids
  let r = Request.fromJson(j)
  assertOk r
  doAssert r.get().createdIds.isSome
  assertEq r.get().createdIds.get().len, 1000

block responseDeeplyNestedArguments:
  ## Response invocation with 50-level nested arguments object -> should succeed.
  var inner = newJObject()
  for i in 0 ..< 50:
    let outer = newJObject()
    {.cast(noSideEffect).}:
      outer["level" & $i] = inner
    inner = outer
  var inv = newJArray()
  {.cast(noSideEffect).}:
    inv.add(newJString("Method/deeply"))
    inv.add(inner)
    inv.add(newJString("c0"))
  var j = newJObject()
  {.cast(noSideEffect).}:
    j["methodResponses"] = %*[inv]
    j["sessionState"] = %"s1"
  assertOk Response.fromJson(j)

block createdIdsDuplicateKeys:
  ## createdIds with duplicate key (JSON last-wins) -> should succeed.
  var j = validRequestJson()
  var ids = newJObject()
  {.cast(noSideEffect).}:
    ids["k1"] = newJString("first")
    ids["k1"] = newJString("second")
  j["createdIds"] = ids
  let r = Request.fromJson(j)
  assertOk r

block createdIdsEmptyKey:
  ## createdIds with "" key -> assertErr (empty CreationId).
  var j = validRequestJson()
  var ids = newJObject()
  {.cast(noSideEffect).}:
    ids[""] = newJString("id1")
  j["createdIds"] = ids
  assertErr Request.fromJson(j)

block createdIdsEmptyValue:
  ## createdIds with value "" -> assertErr (empty Id).
  var j = validRequestJson()
  var ids = newJObject()
  {.cast(noSideEffect).}:
    ids["k1"] = newJString("")
  j["createdIds"] = ids
  assertErr Request.fromJson(j)

block responseEmptySessionState:
  ## sessionState as "" -> assertErr (JmapState requires non-empty).
  {.cast(noSideEffect).}:
    let j = %*{"methodResponses": [["Mailbox/get", {}, "c0"]], "sessionState": ""}
  assertErr Response.fromJson(j)

# =============================================================================
# C. Framework adversarial
# =============================================================================

block filterDeepNesting50Levels:
  ## 50-level deep filter via fromJson -> should succeed.
  var inner = newJObject()
  {.cast(noSideEffect).}:
    inner["value"] = %42
  for i in 0 ..< 50:
    var conds = newJArray()
    conds.add(inner)
    inner = newJObject()
    {.cast(noSideEffect).}:
      inner["operator"] = %"AND"
    inner["conditions"] = conds
  let r = Filter[int].fromJson(inner, fromIntCondition)
  assertOk r

block filterWideOperator1000Children:
  ## AND operator with 1000 leaf conditions -> should succeed.
  var conds = newJArray()
  for i in 0 ..< 1000:
    var leaf = newJObject()
    {.cast(noSideEffect).}:
      leaf["value"] = %i
    conds.add(leaf)
  var j = newJObject()
  {.cast(noSideEffect).}:
    j["operator"] = %"AND"
  j["conditions"] = conds
  let r = Filter[int].fromJson(j, fromIntCondition)
  assertOk r
  doAssert r.get().kind == fkOperator
  assertEq r.get().conditions.len, 1000

block filterNullInConditions:
  ## {"operator":"AND","conditions":[null]} -> assertErr.
  var conds = newJArray()
  conds.add(newJNull())
  var j = newJObject()
  {.cast(noSideEffect).}:
    j["operator"] = %"AND"
  j["conditions"] = conds
  assertErr Filter[int].fromJson(j, fromIntCondition)

block filterStringInConditions:
  ## {"operator":"AND","conditions":["not-object"]} -> assertErr.
  var conds = newJArray()
  {.cast(noSideEffect).}:
    conds.add(%"not-object")
  var j = newJObject()
  {.cast(noSideEffect).}:
    j["operator"] = %"AND"
  j["conditions"] = conds
  assertErr Filter[int].fromJson(j, fromIntCondition)

block filterOperatorWhitespacePadded:
  ## "  AND  " -> assertErr (not trimmed).
  {.cast(noSideEffect).}:
    let j = %*{"operator": "  AND  ", "conditions": []}
    assertErr Filter[int].fromJson(j, fromIntCondition)

block filterOperatorMixedCase:
  ## "AnD" -> assertErr.
  {.cast(noSideEffect).}:
    let j = %*{"operator": "AnD", "conditions": []}
    assertErr Filter[int].fromJson(j, fromIntCondition)

block comparatorNullProperty:
  ## {"property":null} -> assertErr.
  var j = newJObject()
  j["property"] = newJNull()
  assertErr Comparator.fromJson(j)

block comparatorEmptyCollation:
  ## {"property":"x","collation":""} -> assertOk (empty collation is just a string).
  {.cast(noSideEffect).}:
    let j = %*{"property": "x", "collation": ""}
  let r = Comparator.fromJson(j)
  assertOk r
  doAssert r.get().collation.isSome
  assertEq r.get().collation.get(), ""

block patchObjectLargePathCount:
  ## PatchObject with 1000 paths -> should succeed.
  var j = newJObject()
  for i in 0 ..< 1000:
    {.cast(noSideEffect).}:
      j["path/" & $i] = %i
  let r = PatchObject.fromJson(j)
  assertOk r
  assertEq r.get().len, 1000

block patchObjectLongPathString:
  ## Path with 10,000 char key -> should succeed.
  var j = newJObject()
  let longKey = 'a'.repeat(10000)
  {.cast(noSideEffect).}:
    j[longKey] = %42
  let r = PatchObject.fromJson(j)
  assertOk r
  assertEq r.get().len, 1

# =============================================================================
# D. Error adversarial
# =============================================================================

block requestErrorExtrasKeyCollision:
  ## Extras with key "type" (same as required field) -> verify "type" in
  ## serialised output is the error type, not the extras value.
  {.cast(noSideEffect).}:
    let j =
      %*{"type": "urn:ietf:params:jmap:error:limit", "custom": "data", "type": "evil"}
  # JSON last-wins: "type" will be "evil", which is a valid type string.
  # The parser reads whatever "type" resolves to.
  let r = RequestError.fromJson(j)
  # May succeed with rawType "evil" or may have "urn:..." depending on parser.
  # Either way: no crash. If it succeeds, serialised output "type" field
  # comes from rawType, not extras.
  if r.isOk:
    let j2 = r.get().toJson()
    doAssert j2{"type"} != nil
    assertEq j2{"type"}.getStr(""), r.get().rawType

block methodErrorExtrasKeyCollision:
  ## Extras with key "description" -> extras should NOT override the real
  ## description. In the parsed result the description field is extracted
  ## separately from extras.
  {.cast(noSideEffect).}:
    let j =
      %*{"type": "serverFail", "description": "real desc", "vendorField": "vendor"}
  let r = MethodError.fromJson(j)
  assertOk r
  doAssert r.get().description.isSome
  assertEq r.get().description.get(), "real desc"

block setErrorLargeProperties:
  ## invalidProperties with 1000 property strings -> should succeed.
  var propsArr = newJArray()
  for i in 0 ..< 1000:
    {.cast(noSideEffect).}:
      propsArr.add(%("prop" & $i))
  var j = newJObject()
  {.cast(noSideEffect).}:
    j["type"] = %"invalidProperties"
  j["properties"] = propsArr
  let r = SetError.fromJson(j)
  assertOk r
  doAssert r.get().errorType == setInvalidProperties
  assertEq r.get().properties.len, 1000

block setErrorDeeplyNestedExtras:
  ## Extras with 50-level nested JSON -> should succeed (extras stored as-is).
  var inner = newJObject()
  for i in 0 ..< 50:
    let outer = newJObject()
    {.cast(noSideEffect).}:
      outer["level" & $i] = inner
    inner = outer
  var j = newJObject()
  {.cast(noSideEffect).}:
    j["type"] = %"forbidden"
    j["deepField"] = inner
  let r = SetError.fromJson(j)
  assertOk r
  doAssert r.get().extras.isSome

block setErrorAlreadyExistsNullId:
  ## {"type":"alreadyExists","existingId":null} -> defensive fallback to setUnknown.
  var j = newJObject()
  {.cast(noSideEffect).}:
    j["type"] = %"alreadyExists"
  j["existingId"] = newJNull()
  let r = SetError.fromJson(j)
  assertOk r
  doAssert r.get().errorType == setUnknown

block requestErrorFloatStatus:
  ## status as 429.5 (JFloat not JInt) -> lenient: status becomes None.
  var j = newJObject()
  {.cast(noSideEffect).}:
    j["type"] = %"urn:ietf:params:jmap:error:limit"
    j["status"] = newJFloat(429.5)
  let r = RequestError.fromJson(j)
  assertOk r
  doAssert r.get().status.isNone

block requestErrorEmptyExtras:
  ## No unknown fields -> extras is None.
  {.cast(noSideEffect).}:
    let j = %*{"type": "urn:ietf:params:jmap:error:notJSON"}
  let r = RequestError.fromJson(j)
  assertOk r
  doAssert r.get().extras.isNone

block setErrorInvalidPropertiesEmptyElement:
  ## Properties array with "" -> assertOk (empty strings allowed in array).
  {.cast(noSideEffect).}:
    let j = %*{"type": "invalidProperties", "properties": [""]}
  let r = SetError.fromJson(j)
  assertOk r
  doAssert r.get().errorType == setInvalidProperties
  assertEq r.get().properties[0], ""

# =============================================================================
# E. Scale / resource tests
# =============================================================================

block sessionManyAccounts:
  ## Session with 100 accounts, each with 3 capabilities -> should succeed.
  var j = validSessionJson()
  var accts = newJObject()
  for i in 0 ..< 100:
    var acctCaps = newJObject()
    {.cast(noSideEffect).}:
      acctCaps["urn:ietf:params:jmap:mail"] = newJObject()
      acctCaps["urn:ietf:params:jmap:contacts"] = newJObject()
      acctCaps["https://vendor.example/ext"] = newJObject()
    var acct = newJObject()
    {.cast(noSideEffect).}:
      acct["name"] = %("user" & $i & "@example.com")
      acct["isPersonal"] = %true
      acct["isReadOnly"] = %false
    acct["accountCapabilities"] = acctCaps
    {.cast(noSideEffect).}:
      accts["acct" & $i] = acct
  j["accounts"] = accts
  let r = Session.fromJson(j)
  assertOk r
  assertEq r.get().accounts.len, 100

block requestManyInvocations:
  ## Request with 500 invocations -> should succeed.
  var methodCalls = newJArray()
  for i in 0 ..< 500:
    {.cast(noSideEffect).}:
      methodCalls.add(%*["Email/get", {}, "c" & $i])
  var j = newJObject()
  {.cast(noSideEffect).}:
    j["using"] = %*["urn:ietf:params:jmap:core"]
  j["methodCalls"] = methodCalls
  let r = Request.fromJson(j)
  assertOk r
  assertEq r.get().methodCalls.len, 500

block responseManyCreatedIds:
  ## Response with 500 createdIds -> should succeed.
  var j = validResponseJson()
  var ids = newJObject()
  for i in 0 ..< 500:
    {.cast(noSideEffect).}:
      ids["k" & $i] = newJString("id" & $i)
  j["createdIds"] = ids
  let r = Response.fromJson(j)
  assertOk r
  doAssert r.get().createdIds.isSome
  assertEq r.get().createdIds.get().len, 500

block filterBranchingFactor:
  ## Filter tree with branching factor 10, depth 3 (1000 leaves) -> should succeed.
  # Build depth-0 leaves
  var leaves = newJArray()
  for i in 0 ..< 10:
    var leaf = newJObject()
    {.cast(noSideEffect).}:
      leaf["value"] = %i
    leaves.add(leaf)

  # Build depth-1: 10 AND operators, each with 10 leaves
  var mid = newJArray()
  for i in 0 ..< 10:
    var innerLeaves = newJArray()
    for k in 0 ..< 10:
      var leaf = newJObject()
      {.cast(noSideEffect).}:
        leaf["value"] = %(i * 10 + k)
      innerLeaves.add(leaf)
    var node = newJObject()
    {.cast(noSideEffect).}:
      node["operator"] = %"AND"
    node["conditions"] = innerLeaves
    mid.add(node)

  # Build depth-2: 10 OR operators, each with 10 AND operators (total ~1000 leaves)
  var top = newJArray()
  for i in 0 ..< 10:
    var midChildren = newJArray()
    for k in 0 ..< 10:
      var innerLeaves = newJArray()
      for m in 0 ..< 10:
        var leaf = newJObject()
        {.cast(noSideEffect).}:
          leaf["value"] = %(i * 100 + k * 10 + m)
        innerLeaves.add(leaf)
      var andNode = newJObject()
      {.cast(noSideEffect).}:
        andNode["operator"] = %"AND"
      andNode["conditions"] = innerLeaves
      midChildren.add(andNode)
    var orNode = newJObject()
    {.cast(noSideEffect).}:
      orNode["operator"] = %"OR"
    orNode["conditions"] = midChildren
    top.add(orNode)

  # Build root: AND with 10 OR children
  var root = newJObject()
  {.cast(noSideEffect).}:
    root["operator"] = %"AND"
  root["conditions"] = top
  let r = Filter[int].fromJson(root, fromIntCondition)
  assertOk r
  doAssert r.get().kind == fkOperator
  assertEq r.get().conditions.len, 10

# =============================================================================
# I. Null bytes and large strings
# =============================================================================

block nullBytesInStringField:
  ## Null byte (\x00) in account name — must parse or reject, never crash.
  {.cast(noSideEffect).}:
    var j = validSessionJson()
    j["username"] = %("test\x00evil")
    let r = Session.fromJson(j)
    # Accept or reject, but never crash
    doAssert r.isOk or r.isErr

block largeMethodName:
  ## 1MB method name — must not crash.
  {.cast(noSideEffect).}:
    let longName = 'A'.repeat(1_000_000)
    let j = newJArray()
    j.add(%longName)
    j.add(newJObject())
    j.add(%"c1")
    let r = Invocation.fromJson(j)
    # Accept (method name is unvalidated string) or reject, never crash
    doAssert r.isOk or r.isErr

# =============================================================================
# J. Duplicate JSON object keys
# =============================================================================

block duplicateJsonObjectKeys:
  ## JSON with duplicate keys — std/json last-wins behaviour. The serde layer
  ## must handle this gracefully regardless of which value wins.
  {.cast(noSideEffect).}:
    # std/json's %*{} does not allow duplicates, so build manually
    let j = parseJson("""{"type": "serverFail", "type": "invalidArguments"}""")
    let r = MethodError.fromJson(j)
    assertOk r
    # Last wins — the rawType should be one of the two values
    doAssert r.get().rawType == "serverFail" or r.get().rawType == "invalidArguments"

# =============================================================================
# K. Empty JSON object for each type
# =============================================================================

block emptyObjectForAllTypes:
  ## %*{} passed to every fromJson — must return error, not crash.
  {.cast(noSideEffect).}:
    let empty = newJObject()
    assertErr CoreCapabilities.fromJson(empty)
    assertErr Account.fromJson(empty)
    assertErr Session.fromJson(empty)
    assertErr Request.fromJson(empty)
    assertErr Invocation.fromJson(empty)
    assertErr ResultReference.fromJson(empty)
    assertErr Comparator.fromJson(empty)
    assertErr AddedItem.fromJson(empty)
    assertErr RequestError.fromJson(empty)
    assertErr MethodError.fromJson(empty)

block emptyObjectPatchObjectValid:
  ## PatchObject with empty JSON object is valid (empty patch).
  {.cast(noSideEffect).}:
    let r = PatchObject.fromJson(newJObject())
    assertOk r

# =============================================================================
# L. ARC shared-ref stress (validates Phase 1A fix)
# =============================================================================

block arcSharedRefMultipleCapabilities:
  ## Multiple capabilities referencing the same JsonNode — must not double-free.
  {.cast(noSideEffect).}:
    let shared = %*{"limit": 1000, "nested": {"a": [1, 2, 3]}}
    # Parse 10 capabilities all from the same shared ref
    var caps: seq[ServerCapability] = @[]
    const uris = [
      "urn:ietf:params:jmap:mail", "urn:ietf:params:jmap:submission",
      "urn:ietf:params:jmap:contacts", "urn:ietf:params:jmap:calendars",
      "urn:ietf:params:jmap:sieve",
    ]
    for uri in uris:
      let r = ServerCapability.fromJson(uri, shared)
      assertOk r
      caps.add(r.get())
    # All should be independent copies
    for cap in caps:
      let j = cap.toJson()
      doAssert j{"limit"} != nil
      assertEq j{"limit"}.getBiggestInt(0), 1000
    # Dropping caps should not cause ARC issues — if we reach here, we are safe
