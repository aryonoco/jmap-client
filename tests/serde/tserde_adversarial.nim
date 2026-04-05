# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Adversarial input tests for Layer 2 serialisation. Tests malformed JSON,
## boundary inputs, deep nesting, large collections, type confusion, and
## resource pressure scenarios. Every test verifies graceful handling
## (success or ValidationError, never crash).

import std/json
import std/options
import std/strutils
import std/tables

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
import ../mserde_fixtures

# Valid JSON fixtures are in mfixtures.nim:
# validSessionJson(), validRequestJson(), validResponseJson()

# =============================================================================
# A. Session adversarial
# =============================================================================

block sessionCapabilitiesAsArray:
  ## capabilities as JArray instead of JObject -> assertErr
  var j = validSessionJson()
  j["capabilities"] = %*[1, 2, 3]
  assertErr Session.fromJson(j)

block sessionLargeCapabilities:
  ## 1000 vendor extension keys, each with empty JObject data -> should succeed.
  var j = validSessionJson()
  let caps = newJObject()
  caps["urn:ietf:params:jmap:core"] = j["capabilities"]["urn:ietf:params:jmap:core"]
  for i in 0 ..< 1000:
    caps["https://vendor.example/ext/" & $i] = newJObject()
  j["capabilities"] = caps
  let r = Session.fromJson(j).get()
  assertGe r.capabilities.len, 1001

block sessionLongCapabilityUri:
  ## Capability URI of 10,000 chars -> should succeed (URIs stored as-is).
  var j = validSessionJson()
  let longUri = "https://vendor.example/" & 'a'.repeat(10000)
  let caps = newJObject()
  caps["urn:ietf:params:jmap:core"] = j["capabilities"]["urn:ietf:params:jmap:core"]
  caps[longUri] = newJObject()
  j["capabilities"] = caps
  assertOk Session.fromJson(j)

block sessionUnicodeAccountName:
  ## Account with Unicode name (Japanese, emoji) -> should succeed.
  var j = validSessionJson()
  j["accounts"] = %*{
    "A1": {
      "name": "\u65E5\u672C\u8A9E\u30E6\u30FC\u30B6\u30FC \U0001F600",
      "isPersonal": true,
      "isReadOnly": false,
      "accountCapabilities": {},
    }
  }
  assertOk Session.fromJson(j)

block sessionPrimaryAccountsMissedID:
  ## primaryAccounts pointing to non-existent accountId -> should succeed
  ## (referential integrity not validated at Layer 2).
  var j = validSessionJson()
  j["primaryAccounts"] = %*{"urn:ietf:params:jmap:mail": "nonExistentId"}
  assertOk Session.fromJson(j)

block sessionDuplicateCapabilityUris:
  ## JSON with duplicate "urn:ietf:params:jmap:mail" keys in capabilities.
  ## JSON last-wins semantics apply; should succeed.
  var j = validSessionJson()
  let caps = newJObject()
  caps["urn:ietf:params:jmap:core"] = j["capabilities"]["urn:ietf:params:jmap:core"]
  caps["urn:ietf:params:jmap:mail"] = %*{"first": true}
  caps["urn:ietf:params:jmap:mail"] = %*{"second": true}
  j["capabilities"] = caps
  assertOk Session.fromJson(j)

block sessionCoreCapabilityAsFloat:
  ## maxSizeUpload as JFloat (3.14) instead of JInt -> assertErr.
  var j = validSessionJson()
  j["capabilities"]["urn:ietf:params:jmap:core"]["maxSizeUpload"] = newJFloat(3.14)
  assertErr Session.fromJson(j)

block sessionMissingCoreCapability:
  ## capabilities without ckCore -> assertErr.
  var j = validSessionJson()
  j["capabilities"] = %*{"urn:ietf:params:jmap:mail": {}}
  assertErr Session.fromJson(j)

block sessionEmptyApiUrl:
  ## apiUrl is empty string -> assertErr.
  var j = validSessionJson()
  j["apiUrl"] = %""
  assertErr Session.fromJson(j)

# =============================================================================
# B. Envelope adversarial
# =============================================================================

block invocationNullElements:
  ## ["method", null, "c0"] -> assertErr (null is not JObject for arguments).
  var arr = newJArray()
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
    methodCalls.add(%*["Method/" & $i, {}, "c" & $i])
  var j = newJObject()
  j["using"] = %*["urn:ietf:params:jmap:core"]
  j["methodCalls"] = methodCalls
  assertOk Request.fromJson(j)

block requestLargeCreatedIds:
  ## Request with 1000 createdIds entries -> should succeed.
  var j = validRequestJson()
  var ids = newJObject()
  for i in 0 ..< 1000:
    ids["k" & $i] = newJString("id" & $i)
  j["createdIds"] = ids
  let r = Request.fromJson(j).get()
  doAssert r.createdIds.isSome
  assertEq r.createdIds.get().len, 1000

block responseDeeplyNestedArguments:
  ## Response invocation with 50-level nested arguments object -> should succeed.
  var inner = newJObject()
  for i in 0 ..< 50:
    let outer = newJObject()
    outer["level" & $i] = inner
    inner = outer
  var inv = newJArray()
  inv.add(newJString("Method/deeply"))
  inv.add(inner)
  inv.add(newJString("c0"))
  var j = newJObject()
  j["methodResponses"] = %*[inv]
  j["sessionState"] = %"s1"
  assertOk Response.fromJson(j)

block createdIdsDuplicateKeys:
  ## createdIds with duplicate key (JSON last-wins) -> should succeed.
  var j = validRequestJson()
  var ids = newJObject()
  ids["k1"] = newJString("first")
  ids["k1"] = newJString("second")
  j["createdIds"] = ids
  assertOk Request.fromJson(j)

block createdIdsEmptyKey:
  ## createdIds with "" key -> assertErr (empty CreationId).
  var j = validRequestJson()
  var ids = newJObject()
  ids[""] = newJString("id1")
  j["createdIds"] = ids
  assertErr Request.fromJson(j)

block createdIdsEmptyValue:
  ## createdIds with value "" -> assertErr (empty Id).
  var j = validRequestJson()
  var ids = newJObject()
  ids["k1"] = newJString("")
  j["createdIds"] = ids
  assertErr Request.fromJson(j)

block responseEmptySessionState:
  ## sessionState as "" -> assertErr (JmapState requires non-empty).
  let j = %*{"methodResponses": [["Mailbox/get", {}, "c0"]], "sessionState": ""}
  assertErr Response.fromJson(j)

# =============================================================================
# C. Framework adversarial
# =============================================================================

block filterDeepNesting50Levels:
  ## 50-level deep filter via fromJson -> should succeed.
  var inner = newJObject()
  inner["value"] = %42
  for i in 0 ..< 50:
    var conds = newJArray()
    conds.add(inner)
    inner = newJObject()
    inner["operator"] = %"AND"
    inner["conditions"] = conds
  let r = Filter[int].fromJson(inner, fromIntCondition).get()
  discard r

block filterWideOperator1000Children:
  ## AND operator with 1000 leaf conditions -> should succeed.
  var conds = newJArray()
  for i in 0 ..< 1000:
    var leaf = newJObject()
    leaf["value"] = %i
    conds.add(leaf)
  var j = newJObject()
  j["operator"] = %"AND"
  j["conditions"] = conds
  let r = Filter[int].fromJson(j, fromIntCondition).get()
  doAssert r.kind == fkOperator
  assertEq r.conditions.len, 1000

block filterNullInConditions:
  ## {"operator":"AND","conditions":[null]} -> assertErr.
  var conds = newJArray()
  conds.add(newJNull())
  var j = newJObject()
  j["operator"] = %"AND"
  j["conditions"] = conds
  assertErr Filter[int].fromJson(j, fromIntCondition)

block filterStringInConditions:
  ## {"operator":"AND","conditions":["not-object"]} -> assertErr.
  var conds = newJArray()
  conds.add(%"not-object")
  var j = newJObject()
  j["operator"] = %"AND"
  j["conditions"] = conds
  assertErr Filter[int].fromJson(j, fromIntCondition)

block filterOperatorWhitespacePadded:
  ## "  AND  " -> assertErr (not trimmed).
  let j = %*{"operator": "  AND  ", "conditions": []}
  assertErr Filter[int].fromJson(j, fromIntCondition)

block filterOperatorMixedCase:
  ## "AnD" -> assertErr.
  let j = %*{"operator": "AnD", "conditions": []}
  assertErr Filter[int].fromJson(j, fromIntCondition)

block comparatorNullProperty:
  ## {"property":null} -> assertErr.
  var j = newJObject()
  j["property"] = newJNull()
  assertErr Comparator.fromJson(j)

block comparatorEmptyCollation:
  ## {"property":"x","collation":""} -> assertOk (empty collation is just a string).
  let j = %*{"property": "x", "collation": ""}
  let r = Comparator.fromJson(j).get()
  doAssert r.collation.isSome
  assertEq r.collation.get(), ""

block patchObjectLargePathCount:
  ## PatchObject with 1000 paths -> should succeed.
  var j = newJObject()
  for i in 0 ..< 1000:
    j["path/" & $i] = %i
  let r = PatchObject.fromJson(j).get()
  assertEq r.len, 1000

block patchObjectLongPathString:
  ## Path with 10,000 char key -> should succeed.
  var j = newJObject()
  let longKey = 'a'.repeat(10000)
  j[longKey] = %42
  let r = PatchObject.fromJson(j).get()
  assertEq r.len, 1

# =============================================================================
# D. Error adversarial
# =============================================================================

block requestErrorExtrasKeyCollision:
  ## Extras with key "type" (same as required field) -> verify "type" in
  ## serialised output is the error type, not the extras value.
  let j =
    %*{"type": "urn:ietf:params:jmap:error:limit", "custom": "data", "type": "evil"}
  # JSON last-wins: "type" will be "evil", which is a valid type string.
  # The parser reads whatever "type" resolves to.
  let r = RequestError.fromJson(j).get()
  let j2 = r.toJson()
  doAssert j2{"type"} != nil
  assertEq j2{"type"}.getStr(""), r.rawType
block methodErrorExtrasKeyCollision:
  ## Extras with key "description" -> extras should NOT override the real
  ## description. In the parsed result the description field is extracted
  ## separately from extras.
  let j = %*{"type": "serverFail", "description": "real desc", "vendorField": "vendor"}
  let r = MethodError.fromJson(j).get()
  doAssert r.description.isSome
  assertEq r.description.get(), "real desc"

block setErrorLargeProperties:
  ## invalidProperties with 1000 property strings -> should succeed.
  var propsArr = newJArray()
  for i in 0 ..< 1000:
    propsArr.add(%("prop" & $i))
  var j = newJObject()
  j["type"] = %"invalidProperties"
  j["properties"] = propsArr
  let r = SetError.fromJson(j).get()
  doAssert r.errorType == setInvalidProperties
  assertEq r.properties.len, 1000

block setErrorDeeplyNestedExtras:
  ## Extras with 50-level nested JSON -> should succeed (extras stored as-is).
  var inner = newJObject()
  for i in 0 ..< 50:
    let outer = newJObject()
    outer["level" & $i] = inner
    inner = outer
  var j = newJObject()
  j["type"] = %"forbidden"
  j["deepField"] = inner
  let r = SetError.fromJson(j).get()
  doAssert r.extras.isSome

block setErrorAlreadyExistsNullId:
  ## {"type":"alreadyExists","existingId":null} -> defensive fallback to setUnknown.
  var j = newJObject()
  j["type"] = %"alreadyExists"
  j["existingId"] = newJNull()
  let r = SetError.fromJson(j).get()
  doAssert r.errorType == setUnknown

block requestErrorFloatStatus:
  ## status as 429.5 (JFloat not JInt) -> lenient: status becomes None.
  var j = newJObject()
  j["type"] = %"urn:ietf:params:jmap:error:limit"
  j["status"] = newJFloat(429.5)
  let r = RequestError.fromJson(j).get()
  doAssert r.status.isNone

block requestErrorEmptyExtras:
  ## No unknown fields -> extras is None.
  let j = %*{"type": "urn:ietf:params:jmap:error:notJSON"}
  let r = RequestError.fromJson(j).get()
  doAssert r.extras.isNone

block setErrorInvalidPropertiesEmptyElement:
  ## Properties array with "" -> assertOk (empty strings allowed in array).
  let j = %*{"type": "invalidProperties", "properties": [""]}
  let r = SetError.fromJson(j).get()
  doAssert r.errorType == setInvalidProperties
  assertEq r.properties[0], ""

# =============================================================================
# E. Scale / resource tests
# =============================================================================

block sessionManyAccounts:
  ## Session with 100 accounts, each with 3 capabilities -> should succeed.
  var j = validSessionJson()
  var accts = newJObject()
  for i in 0 ..< 100:
    var acctCaps = newJObject()
    acctCaps["urn:ietf:params:jmap:mail"] = newJObject()
    acctCaps["urn:ietf:params:jmap:contacts"] = newJObject()
    acctCaps["https://vendor.example/ext"] = newJObject()
    var acct = newJObject()
    acct["name"] = %("user" & $i & "@example.com")
    acct["isPersonal"] = %true
    acct["isReadOnly"] = %false
    acct["accountCapabilities"] = acctCaps
    accts["acct" & $i] = acct
  j["accounts"] = accts
  let r = Session.fromJson(j).get()
  assertEq r.accounts.len, 100

block requestManyInvocations:
  ## Request with 500 invocations -> should succeed.
  var methodCalls = newJArray()
  for i in 0 ..< 500:
    methodCalls.add(%*["Email/get", {}, "c" & $i])
  var j = newJObject()
  j["using"] = %*["urn:ietf:params:jmap:core"]
  j["methodCalls"] = methodCalls
  let r = Request.fromJson(j).get()
  assertEq r.methodCalls.len, 500

block responseManyCreatedIds:
  ## Response with 500 createdIds -> should succeed.
  var j = validResponseJson()
  var ids = newJObject()
  for i in 0 ..< 500:
    ids["k" & $i] = newJString("id" & $i)
  j["createdIds"] = ids
  let r = Response.fromJson(j).get()
  doAssert r.createdIds.isSome
  assertEq r.createdIds.get().len, 500

block filterBranchingFactor:
  ## Filter tree with branching factor 10, depth 3 (1000 leaves) -> should succeed.
  # Build depth-0 leaves
  var leaves = newJArray()
  for i in 0 ..< 10:
    var leaf = newJObject()
    leaf["value"] = %i
    leaves.add(leaf)

  # Build depth-1: 10 AND operators, each with 10 leaves
  var mid = newJArray()
  for i in 0 ..< 10:
    var innerLeaves = newJArray()
    for k in 0 ..< 10:
      var leaf = newJObject()
      leaf["value"] = %(i * 10 + k)
      innerLeaves.add(leaf)
    var node = newJObject()
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
        leaf["value"] = %(i * 100 + k * 10 + m)
        innerLeaves.add(leaf)
      var andNode = newJObject()
      andNode["operator"] = %"AND"
      andNode["conditions"] = innerLeaves
      midChildren.add(andNode)
    var orNode = newJObject()
    orNode["operator"] = %"OR"
    orNode["conditions"] = midChildren
    top.add(orNode)

  # Build root: AND with 10 OR children
  var root = newJObject()
  root["operator"] = %"AND"
  root["conditions"] = top
  let r = Filter[int].fromJson(root, fromIntCondition).get()
  doAssert r.kind == fkOperator
  assertEq r.conditions.len, 10

# =============================================================================
# I. Null bytes and large strings
# =============================================================================

block nullBytesInStringField:
  ## Null byte (\x00) in account name — must parse or reject, never crash.
  var j = validSessionJson()
  j["username"] = %("test\x00evil")
  discard Session.fromJson(j)
block largeMethodName:
  ## 1MB method name — must not crash.
  let longName = 'A'.repeat(1_000_000)
  let j = newJArray()
  j.add(%longName)
  j.add(newJObject())
  j.add(%"c1")
  # Accept (method name is unvalidated string) or reject, never crash
  discard Invocation.fromJson(j)
# =============================================================================
# J. Duplicate JSON object keys
# =============================================================================

block duplicateJsonObjectKeys:
  ## JSON with duplicate keys — std/json last-wins behaviour. The serde layer
  ## must handle this gracefully regardless of which value wins.
  # std/json's %*{} does not allow duplicates, so build manually
  let j = parseJson("""{"type": "serverFail", "type": "invalidArguments"}""")
  let r = MethodError.fromJson(j).get()
  # Last wins — the rawType should be one of the two values
  doAssert r.rawType == "serverFail" or r.rawType == "invalidArguments"

# =============================================================================
# K. Empty JSON object for each type
# =============================================================================

block emptyObjectForAllTypes:
  ## %*{} passed to every fromJson — must return error, not crash.
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
  assertOk PatchObject.fromJson(newJObject())

# =============================================================================
# L. ARC shared-ref stress (validates Phase 1A fix)
# =============================================================================

block arcSharedRefMultipleCapabilities:
  ## Multiple capabilities referencing the same JsonNode — must not double-free.
  let shared = %*{"limit": 1000, "nested": {"a": [1, 2, 3]}}
  # Parse 10 capabilities all from the same shared ref
  var caps: seq[ServerCapability] = @[]
  const uris = [
    "urn:ietf:params:jmap:mail", "urn:ietf:params:jmap:submission",
    "urn:ietf:params:jmap:contacts", "urn:ietf:params:jmap:calendars",
    "urn:ietf:params:jmap:sieve",
  ]
  for uri in uris:
    let r = ServerCapability.fromJson(uri, shared).get()
    caps.add(r)
  # All should be independent copies
  for cap in caps:
    let j = cap.toJson()
    doAssert j{"limit"} != nil
    assertEq j{"limit"}.getBiggestInt(0), 1000
  # Dropping caps should not cause ARC issues — if we reach here, we are safe

# =============================================================================
# M. Duplicate JSON keys (Phase 4A)
# =============================================================================

block duplicateCreatedIdsKey:
  ## Build Request JSON with duplicate key in createdIds object:
  ## {"createdIds": {"abc":"id1","abc":"id2"}}. std/json uses last-wins
  ## semantics for duplicate object keys — the second value overwrites the
  ## first. Verify Request.fromJson succeeds under this behaviour.
  const raw =
    """{"using":["urn:ietf:params:jmap:core"],"methodCalls":[["Mailbox/get",{},"c0"]],"createdIds":{"abc":"id1","abc":"id2"}}"""
  let j = parseJson(raw)
  let r = Request.fromJson(j).get()
  # std/json last-wins: "abc" -> "id2"
  doAssert r.createdIds.isSome

block duplicateCapabilityUri:
  ## Build Session JSON with duplicate capability URI key. std/json last-wins
  ## semantics apply — the second value replaces the first. Verify Session
  ## deserialisation handles this gracefully.
  var j = validSessionJson()
  # Manually build capabilities with a duplicate vendor URI
  let caps = newJObject()
  caps["urn:ietf:params:jmap:core"] = j["capabilities"]["urn:ietf:params:jmap:core"]
  caps["urn:ietf:params:jmap:mail"] = %*{"first": true}
  caps["urn:ietf:params:jmap:mail"] = %*{"second": true}
  j["capabilities"] = caps
  # Last-wins: only one "urn:ietf:params:jmap:mail" entry with {"second": true}
  assertOk Session.fromJson(j)

# =============================================================================
# N. Numeric precision at JSON boundary (Phase 4B)
# =============================================================================

block jmapIntExponentNotation:
  ## parseJson("1e2") produces a JFloat node (kind == JFloat), not JInt.
  ## JmapInt.fromJson checks for JInt kind, so this must return err (wrong
  ## kind). Documents the std/json behaviour at the serde boundary.
  let j = parseJson("1e2")
  # std/json parses 1e2 as JFloat, not JInt
  doAssert j.kind == JFloat, "expected JFloat for 1e2, got " & $j.kind
  assertErr JmapInt.fromJson(j)

block unsignedIntJsonPrecisionBoundary:
  ## 2^53 = 9007199254740992 exceeds the UnsignedInt maximum (2^53-1).
  ## Verify the smart constructor rejects this value.
  const boundary: int64 = 9_007_199_254_740_992'i64 # 2^53
  assertErr parseUnsignedInt(boundary)

# =============================================================================
# O. BOM propagation across identifier types (Phase 4C)
# =============================================================================

block bomInAccountIdValue:
  ## BOM bytes (0xEF, 0xBB, 0xBF) at the start of an AccountId string via
  ## fromJson. All BOM bytes are >= 0x20 so the lenient parser (no control
  ## characters below 0x20) should accept them.
  const bomStr = "\xEF\xBB\xBFaccount1"
  let j = %bomStr
  assertOk AccountId.fromJson(j)
  # BOM bytes are 0xEF=239, 0xBB=187, 0xBF=191, all >= 0x20 -> accepted

block bomInJmapStateValue:
  ## BOM bytes at the start of a JmapState value. BOM bytes are >= 0x20
  ## so the lenient parser should accept them.
  const bomStr = "\xEF\xBB\xBFstate1"
  let j = %bomStr
  assertOk JmapState.fromJson(j)

block bomInJsonObjectKey:
  ## BOM bytes in a MethodError extras field key. Verify the BOM is preserved
  ## in the extras object verbatim.
  const bomKey = "\xEF\xBB\xBFvendor"
  let j = newJObject()
  j["type"] = %"serverFail"
  j[bomKey] = %"data"
  let r = MethodError.fromJson(j).get()
  doAssert r.extras.isSome
  doAssert r.extras.get(){bomKey} != nil
  assertEq r.extras.get(){bomKey}.getStr(""), "data"

# =============================================================================
# P. Unicode normalisation documentation (Phase 4D)
# =============================================================================

block unicodeNormalizationPropertyName:
  ## Create PropertyName with NFC ("caf\u00E9") and NFD ("cafe\u0301").
  ## Both should parse Ok because PropertyName only checks non-empty, but they
  ## are byte-distinct (different UTF-8 sequences). This documents that the
  ## library uses byte comparison, not Unicode-normalised comparison.
  const nfc = "caf\xC3\xA9" # U+00E9 (LATIN SMALL LETTER E WITH ACUTE)
  const nfd = "cafe\xCC\x81" # U+0065 + U+0301 (e + COMBINING ACUTE ACCENT)
  let rNfc = parsePropertyName(nfc).get()
  let rNfd = parsePropertyName(nfd).get()
  # They represent the same character visually but are byte-distinct
  doAssert string(rNfc) != string(rNfd),
    "NFC and NFD forms must be byte-distinct (no normalisation)"

# =============================================================================
# Q. Hash collision resilience (Phase 4E)
# =============================================================================

block capabilitiesLargeVendorSet:
  ## Build Session JSON with 10,000 vendor capability URIs. Verify parses
  ## without crash or hash table degeneration issues.
  var j = validSessionJson()
  let caps = newJObject()
  caps["urn:ietf:params:jmap:core"] = j["capabilities"]["urn:ietf:params:jmap:core"]
  for i in 0 ..< 10_000:
    caps["https://vendor.example/ext/" & $i] = newJObject()
  j["capabilities"] = caps
  let r = Session.fromJson(j).get()
  # Core + 10,000 vendor capabilities
  assertGe r.capabilities.len, 10_001

# =============================================================================
# R. Control character explicit boundary tests (Phase 4G)
# =============================================================================

block controlCharsInIdViaSerde:
  ## Id.fromJson with JSON strings containing control characters.
  ## The strict parser (parseIdFromServer) rejects characters < 0x20
  ## and 0x7F.
  # Null byte
  assertErr Id.fromJson(%("test\x00id"))
  # Newline
  assertErr Id.fromJson(%("test\nid"))
  # Tab
  assertErr Id.fromJson(%("test\tid"))
  # SOH (0x01)
  assertErr Id.fromJson(%("test\x01id"))

block controlCharsInAccountIdViaSerde:
  ## AccountId.fromJson with control characters. The lenient parser also
  ## rejects characters < 0x20 and 0x7F.
  assertErr AccountId.fromJson(%("acct\x00id"))
  assertErr AccountId.fromJson(%("acct\nid"))
  assertErr AccountId.fromJson(%("acct\tid"))
  assertErr AccountId.fromJson(%("acct\x01id"))

# =============================================================================
# S. JSON parser boundary documentation tests (Phase 4H)
# =============================================================================

{.push ruleOff: "trystatements".}

block jsonTrailingGarbage:
  ## Document std/json behaviour with trailing garbage: parseJson("42 extra")
  ## raises JsonParsingError because the parser expects end of input after
  ## the first value.
  var raised = false
  try:
    discard parseJson("42 extra")
  except JsonParsingError:
    raised = true
  doAssert raised, "std/json should raise JsonParsingError for trailing garbage"

block jsonUtf16Surrogates:
  ## Document std/json behaviour with lone UTF-16 surrogates.
  ## parseJson("""{"x": "\uD800"}""") — std/json may accept or reject this.
  ## We document whichever behaviour occurs.
  var parsed = false
  var raised = false
  try:
    discard parseJson("""{"x": "\uD800"}""")
    parsed = true
  except JsonParsingError:
    raised = true
  except ValueError:
    raised = true
  # Document: exactly one of these must be true (no crash)
  doAssert parsed xor raised,
    "std/json must either parse or raise for lone surrogate, never crash"

block jsonLeadingZeroNumber:
  ## Document std/json behaviour with leading zeros in numbers.
  ## JSON RFC 7159 forbids leading zeros (e.g. 0123), but std/json may or
  ## may not enforce this.
  var parsed = false
  var raised = false
  try:
    discard parseJson("""{"x": 0123}""")
    parsed = true
  except JsonParsingError:
    raised = true
  except ValueError:
    raised = true
  # Document: exactly one of these must be true (no crash)
  doAssert parsed xor raised,
    "std/json must either parse or raise for leading zero, never crash"

block jsonExtremeNestingDepth5000:
  ## Build a 5000-level nested JSON string and attempt to parse.
  ## Document whether std/json crashes, raises, or succeeds. The parser
  ## may hit a stack overflow for extreme nesting.
  var jsonStr = ""
  for i in 0 ..< 5000:
    jsonStr.add("""{"x":""")
  jsonStr.add("0")
  for i in 0 ..< 5000:
    jsonStr.add("}")
  var parsed = false
  var raised = false
  try:
    discard parseJson(jsonStr)
    parsed = true
  except JsonParsingError:
    raised = true
  except ValueError:
    raised = true
  except CatchableError:
    raised = true
  # Either succeeds or raises — never a silent corruption
  doAssert parsed xor raised,
    "std/json must either parse or raise for 5000-level nesting, never crash silently"

{.pop.} # ruleOff: "trystatements"

# =============================================================================
# T. Empty identifier serde tests (Phase 4I)
# =============================================================================

block emptyMethodCallIdViaSerde:
  ## MethodCallId.fromJson(%"") must return err — empty method call IDs
  ## are rejected by parseMethodCallId.
  assertErr MethodCallId.fromJson(%"")

block emptyCreationIdViaSerde:
  ## CreationId.fromJson(%"") must return err — empty creation IDs
  ## are rejected by parseCreationId.
  assertErr CreationId.fromJson(%"")

block emptyJmapStateViaSerde:
  ## JmapState.fromJson(%"") must return err — empty state tokens
  ## are rejected by parseJmapState.
  assertErr JmapState.fromJson(%"")

block emptyAccountIdViaSerde:
  ## AccountId.fromJson(%"") must return err — empty account IDs
  ## are rejected by parseAccountId.
  assertErr AccountId.fromJson(%"")

# =============================================================================
# U. Unicode in CreationId (Phase 4J)
# =============================================================================

block creationIdWithEmoji:
  ## Parse CreationId with emoji characters. CreationId.parseCreationId
  ## only rejects empty strings and '#' prefix — emoji characters are
  ## accepted because no charset restriction is imposed beyond those rules.
  let r = CreationId.fromJson(%"\xF0\x9F\x98\x80key") # U+1F600 GRINNING FACE
  # Emoji bytes are all >= 0x80, well above the '#' (0x23) check
  discard r

block creationIdWithCjk:
  ## Parse CreationId with CJK characters. Like emoji, CJK characters are
  ## accepted because parseCreationId has no charset restriction beyond
  ## non-empty and no '#' prefix.
  let r = CreationId.fromJson(%"\xE6\x97\xA5\xE6\x9C\xAC") # U+65E5 U+672C (Japanese)
  discard r

# =============================================================================
# V. Phase 3G: Extra fields ignored (Postel's law) tests
# For each type, parse JSON with an unknown extra field and assert isOk.
# Verifies the library follows Postel's law: be liberal in what you accept.
# =============================================================================

block extraFieldsIgnoredRequest:
  ## Request JSON with an extra unknown field must parse successfully.
  var j = validRequestJson()
  j["vendorExtension"] = %"test"
  let r = Request.fromJson(j).get()
  assertEq r.`using`.len, 1
  assertEq r.methodCalls.len, 1

block extraFieldsIgnoredResponse:
  ## Response JSON with an extra unknown field must parse successfully.
  var j = validResponseJson()
  j["vendorExtension"] = %"test"
  let r = Response.fromJson(j).get()
  assertEq r.methodResponses.len, 1

block extraFieldsIgnoredCoreCapabilities:
  ## CoreCapabilities JSON with an extra unknown field must parse successfully.
  var j = %*{
    "maxSizeUpload": 1,
    "maxConcurrentUpload": 1,
    "maxSizeRequest": 1,
    "maxConcurrentRequests": 1,
    "maxCallsInRequest": 1,
    "maxObjectsInGet": 1,
    "maxObjectsInSet": 1,
    "collationAlgorithms": [],
    "vendorExtension": "test",
  }
  assertOk CoreCapabilities.fromJson(j)

block extraFieldsIgnoredAccount:
  ## Account JSON with an extra unknown field must parse successfully.
  let j = %*{
    "name": "test@example.com",
    "isPersonal": true,
    "isReadOnly": false,
    "accountCapabilities": {},
    "vendorExtension": "test",
  }
  let r = Account.fromJson(j).get()
  assertEq r.name, "test@example.com"

block extraFieldsIgnoredComparator:
  ## Comparator JSON with an extra unknown field must parse successfully.
  let j = %*{"property": "subject", "isAscending": true, "vendorExtension": "test"}
  let r = Comparator.fromJson(j).get()
  assertEq string(r.property), "subject"

block extraFieldsIgnoredResultReference:
  ## ResultReference JSON with an extra unknown field must parse successfully.
  let j = %*{
    "resultOf": "c0", "name": "Mailbox/get", "path": "/ids", "vendorExtension": "test"
  }
  let r = ResultReference.fromJson(j).get()
  assertEq r.name, "Mailbox/get"

block extraFieldsIgnoredAddedItem:
  ## AddedItem JSON with an extra unknown field must parse successfully.
  let j = %*{"id": "item1", "index": 0, "vendorExtension": "test"}
  let r = AddedItem.fromJson(j).get()
  assertEq string(r.id), "item1"

# =============================================================================
# W. Phase 3H: Wrong-cased field name rejection tests
# Verifies that PascalCase or snake_case required field names fail parsing.
# Note: Nim's std/json uses exact string matching for object keys (unlike
# nimIdentNormalize for identifiers), so wrong-cased keys are simply absent.
# =============================================================================

block wrongCasedFieldRequestMethodCalls:
  ## "MethodCalls" (PascalCase) instead of "methodCalls" — treated as
  ## missing field since JSON keys are case-sensitive.
  let j = %*{
    "using": ["urn:ietf:params:jmap:core"], "MethodCalls": [["Mailbox/get", {}, "c0"]]
  }
  assertErrContains Request.fromJson(j), "missing or invalid methodCalls"

block wrongCasedFieldRequestUsing:
  ## "Using" (PascalCase) instead of "using".
  let j = %*{
    "Using": ["urn:ietf:params:jmap:core"], "methodCalls": [["Mailbox/get", {}, "c0"]]
  }
  assertErrContains Request.fromJson(j), "missing or invalid using"

block wrongCasedFieldResponseMethodResponses:
  ## "method_responses" (snake_case) instead of "methodResponses".
  let j = %*{"method_responses": [["Mailbox/get", {}, "c0"]], "sessionState": "s1"}
  assertErrContains Response.fromJson(j), "missing or invalid methodResponses"

block wrongCasedFieldResponseSessionState:
  ## "SessionState" (PascalCase) instead of "sessionState".
  let j = %*{"methodResponses": [["Mailbox/get", {}, "c0"]], "SessionState": "s1"}
  assertErrContains Response.fromJson(j), "missing or invalid sessionState"

block wrongCasedFieldSessionCapabilities:
  ## "Capabilities" (PascalCase) instead of "capabilities" in Session JSON.
  var j = validSessionJson()
  let caps = j["capabilities"]
  # Rebuild with wrong-cased key
  let j2 = %*{
    "Capabilities": caps,
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
  assertErrContains Session.fromJson(j2), "missing or invalid capabilities"

block wrongCasedFieldSessionUsername:
  ## "user_name" (snake_case) instead of "username" in Session JSON.
  var j = validSessionJson()
  let j2 = %*{
    "capabilities": j["capabilities"],
    "accounts": {},
    "primaryAccounts": {},
    "user_name": "",
    "apiUrl": "https://jmap.example.com/api/",
    "downloadUrl": j["downloadUrl"],
    "uploadUrl": j["uploadUrl"],
    "eventSourceUrl": j["eventSourceUrl"],
    "state": "s1",
  }
  assertErrContains Session.fromJson(j2), "missing or invalid username"

# =============================================================================
# Phase 5C: Path injection tests (PatchObject and ResultReference)
# =============================================================================

block patchObjectPathTraversal:
  ## Directory traversal path -> accepted (Layer 1 does not interpret paths).
  var j = newJObject()
  j["../../etc/passwd"] = %"malicious"
  let r = PatchObject.fromJson(j).get()
  doAssert r.getKey("../../etc/passwd").isSome

block patchObjectPathTildeZeroEscape:
  ## RFC 6901 tilde escape ~0 -> accepted and preserved as-is.
  var j = newJObject()
  j["/a~0b"] = %"val"
  let r = PatchObject.fromJson(j).get()
  doAssert r.getKey("/a~0b").isSome

block patchObjectPathTildeOneEscape:
  ## RFC 6901 tilde escape ~1 -> accepted and preserved as-is.
  var j = newJObject()
  j["/a~1b"] = %"val"
  let r = PatchObject.fromJson(j).get()
  doAssert r.getKey("/a~1b").isSome

block patchObjectPathNulByte:
  ## NUL byte in PatchObject path -> accepted. Documents FFI truncation risk.
  var j = newJObject()
  j["/a\x00b"] = %"val"
  assertOk PatchObject.fromJson(j)

block patchObjectPathVeryLong:
  ## 10,000-character path -> accepted (no length restriction on paths).
  var j = newJObject()
  let longPath = 'a'.repeat(10000)
  j[longPath] = %42
  let r = PatchObject.fromJson(j).get()
  assertEq r.len, 1

block patchObjectTraversalRoundTrip:
  ## Directory traversal path survives toJson -> fromJson round-trip.
  var j = newJObject()
  j["../../etc/passwd"] = %"malicious"
  let r = PatchObject.fromJson(j).get()
  let j2 = r.toJson()
  let r2 = PatchObject.fromJson(j2).get()
  doAssert r2.getKey("../../etc/passwd").isSome

block resultReferencePathWildcard:
  ## ResultReference with wildcard in path -> accepted.
  let j = %*{"resultOf": "c0", "name": "Email/get", "path": "/list/*/id"}
  let r = ResultReference.fromJson(j).get()
  assertEq r.path, "/list/*/id"

block resultReferencePathDeeplyNested:
  ## Deeply nested JSON Pointer path -> accepted.
  let j = %*{"resultOf": "c0", "name": "Email/get", "path": "/a/b/c/d/e/f/g"}
  let r = ResultReference.fromJson(j).get()
  assertEq r.path, "/a/b/c/d/e/f/g"

block resultReferencePathControlChars:
  ## Control characters in ResultReference path -> accepted.
  let j = %*{"resultOf": "c0", "name": "Email/get", "path": "/ids\x01\x02"}
  assertOk ResultReference.fromJson(j)

block resultReferencePathEmpty:
  ## Empty path in ResultReference -> returns err (path must be non-empty).
  let j = %*{"resultOf": "c0", "name": "Email/get", "path": ""}
  assertErr ResultReference.fromJson(j)

# =============================================================================
# Phase 5D: JSON numbers outside int64 range
# =============================================================================

{.push ruleOff: "trystatements".}

block jsonNumberAboveInt64Max:
  ## JSON number 2^63 exceeds int64.high. Documents std/json behaviour.
  var parsed = false
  var raised = false
  try:
    let j = parseJson("9223372036854775808")
    parsed = true
    if j.kind == JInt:
      discard UnsignedInt.fromJson(j)
    elif j.kind == JFloat:
      assertErr UnsignedInt.fromJson(j)
  except JsonParsingError:
    raised = true
  except ValueError:
    raised = true
  doAssert parsed xor raised, "std/json must either parse or raise, never crash"

block jsonNumberBelowInt64Min:
  ## JSON number below int64.low. Documents std/json behaviour.
  var parsed = false
  var raised = false
  try:
    let j = parseJson("-9223372036854775809")
    parsed = true
    if j.kind == JInt:
      discard JmapInt.fromJson(j)
    elif j.kind == JFloat:
      assertErr JmapInt.fromJson(j)
  except JsonParsingError:
    raised = true
  except ValueError:
    raised = true
  doAssert parsed xor raised, "std/json must either parse or raise, never crash"

{.pop.} # ruleOff: "trystatements"

# =============================================================================
# Phase 5E: Encoding edge cases
# =============================================================================

{.push ruleOff: "trystatements".}

block encodingBomPrefixInJson:
  ## BOM prefix before JSON. Documents std/json behaviour.
  var parsed = false
  var raised = false
  let j = parseJson("\xEF\xBB\xBF" & """{"type": "serverFail"}""")
  parsed = true
  try:
    discard MethodError.fromJson(j)
  except JsonParsingError:
    raised = true
  except ValueError:
    raised = true
  doAssert parsed xor raised, "std/json must either parse or raise, never crash"

{.pop.} # ruleOff: "trystatements"
