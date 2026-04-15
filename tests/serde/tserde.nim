# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for Layer 2 serialisation: shared helpers and primitive/identifier
## round-trip serialisation.

import std/json
import std/strutils

import jmap_client/serde
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/session
import jmap_client/framework {.all.}
import jmap_client/validation

import ../massertions
import ../mfixtures
import ../mproperty

# =============================================================================
# A. Shared helpers
# =============================================================================

block parseErrorFields:
  let e = parseError("Id", "expected JSON JString")
  assertEq e.typeName, "Id"
  assertEq e.message, "expected JSON JString"
  assertEq e.value, ""

block checkJsonKindAcceptsCorrect:
  doAssert checkJsonKind(%"hello", JString, "Test").isOk

block checkJsonKindRejectsNil:
  const nilNode: JsonNode = nil
  doAssert checkJsonKind(nilNode, JString, "Test").isErr

block checkJsonKindRejectsJNull:
  doAssert checkJsonKind(newJNull(), JString, "Test").isErr

block checkJsonKindRejectsWrongKind:
  doAssert checkJsonKind(%42, JString, "Test").isErr

block checkJsonKindCustomMessage:
  let r = checkJsonKind(%42, JString, "Test", "custom error message")
  doAssert r.isErr
  doAssert r.error.message == "custom error message"

block checkJsonKindDefaultMessage:
  let r = checkJsonKind(%42, JString, "Test")
  doAssert r.isErr
  doAssert r.error.message.contains("expected JSON")

block collectExtrasNone:
  let node = %*{"a": 1, "b": 2}
  let extras = collectExtras(node, ["a", "b"])
  assertNone extras

block collectExtrasSome:
  let node = %*{"a": 1, "b": 2, "c": 3}
  let extras = collectExtras(node, ["a"])
  assertSome extras
  doAssert extras.get(){"b"} != nil
  doAssert extras.get(){"c"} != nil

block collectExtrasEmptyObject:
  let node = newJObject()
  let extras = collectExtras(node, ["a", "b"])
  assertNone extras

# =============================================================================
# B. Round-trip tests
# =============================================================================

block roundTripId:
  let original = makeId()
  assertOkEq Id.fromJson(original.toJson()), original

block roundTripAccountId:
  let original = makeAccountId()
  assertOkEq AccountId.fromJson(original.toJson()), original

block roundTripJmapState:
  let original = makeState()
  assertOkEq JmapState.fromJson(original.toJson()), original

block roundTripMethodCallId:
  let original = makeMcid()
  assertOkEq MethodCallId.fromJson(original.toJson()), original

block roundTripCreationId:
  let original = makeCreationId()
  assertOkEq CreationId.fromJson(original.toJson()), original

block roundTripUriTemplate:
  let original = makeUriTemplate()
  assertOkEq UriTemplate.fromJson(original.toJson()), original

block roundTripPropertyName:
  let original = makePropertyName()
  assertOkEq PropertyName.fromJson(original.toJson()), original

block roundTripDate:
  let original = parseDate("2014-10-30T14:12:00+08:00").get()
  assertOkEq Date.fromJson(original.toJson()), original

block roundTripUtcDate:
  let original = parseUtcDate("2014-10-30T06:12:00Z").get()
  assertOkEq UTCDate.fromJson(original.toJson()), original

block roundTripUnsignedInt:
  let original = zeroUint()
  assertOkEq UnsignedInt.fromJson(original.toJson()), original

block roundTripJmapInt:
  let original = parseJmapInt(42).get()
  assertOkEq JmapInt.fromJson(original.toJson()), original

block roundTripUnsignedIntMax:
  let original = parseUnsignedInt(9007199254740991'i64).get()
  assertOkEq UnsignedInt.fromJson(original.toJson()), original

block roundTripJmapIntMin:
  let original = parseJmapInt(-9007199254740991'i64).get()
  assertOkEq JmapInt.fromJson(original.toJson()), original

block roundTripIdMaxLen:
  let original = parseIdFromServer('a'.repeat(255)).get()
  assertOkEq Id.fromJson(original.toJson()), original

# --- Phase 3A: Numeric boundary off-by-one tests ---

block unsignedIntDeserMaxMinus1:
  ## Off-by-one below the maximum: 2^53-2 must be accepted.
  assertOk UnsignedInt.fromJson(%9007199254740990'i64)

block unsignedIntDeserMaxPlus1:
  ## Off-by-one above the maximum: 2^53 must be rejected.
  assertErr UnsignedInt.fromJson(%9007199254740992'i64)

block jmapIntDeserMinPlus1:
  ## Off-by-one above the minimum: -(2^53-2) must be accepted.
  assertOk JmapInt.fromJson(%(-9007199254740990'i64))

block jmapIntDeserMaxMinus1:
  ## Off-by-one below the maximum: 2^53-2 must be accepted.
  assertOk JmapInt.fromJson(%9007199254740990'i64)

block jmapIntDeserMaxPlus1:
  ## Off-by-one above the maximum: 2^53 must be rejected.
  assertErr JmapInt.fromJson(%9007199254740992'i64)

block jmapIntDeserMinMinus1:
  ## Off-by-one below the minimum: -(2^53) must be rejected.
  assertErr JmapInt.fromJson(%(-9007199254740992'i64))

# --- Phase 3B: String length boundary tests ---

block propertyNameDeser255:
  ## PropertyName has no upper length limit; 255 chars is valid.
  assertOk PropertyName.fromJson(%("x".repeat(255)))

block jmapStateDeser255:
  ## JmapState has no upper length limit (non-empty, no control chars);
  ## 255 chars is valid.
  assertOk JmapState.fromJson(%("s".repeat(255)))

block methodCallIdDeser255:
  ## MethodCallId has no upper length limit (non-empty); 255 chars is valid.
  assertOk MethodCallId.fromJson(%("m".repeat(255)))

block idDeser254:
  ## Off-by-one below Id's maximum of 255: 254 chars must be accepted.
  assertOk Id.fromJson(%("a".repeat(254)))

# =============================================================================
# C. Edge-case deserialization
# =============================================================================

# --- Id ---

block idDeserValidBase64url:
  assertOk Id.fromJson(%"abc123-_XYZ")

block idDeserWrongKindInt:
  assertErr Id.fromJson(%42)

block idDeserNil:
  const node: JsonNode = nil
  assertErr Id.fromJson(node)

block idDeserNull:
  assertErr Id.fromJson(newJNull())

block idDeserArray:
  assertErr Id.fromJson(%*[1, 2, 3])

block idDeserEmpty:
  assertErr Id.fromJson(%"")

# --- UnsignedInt ---

block unsignedIntDeserZero:
  assertOk UnsignedInt.fromJson(%0)

block unsignedIntDeserMax:
  assertOk UnsignedInt.fromJson(%9007199254740991)

block unsignedIntDeserNegative:
  assertErr UnsignedInt.fromJson(%(-1))

block unsignedIntDeserWrongKindString:
  assertErr UnsignedInt.fromJson(%"42")

block unsignedIntDeserNil:
  const node: JsonNode = nil
  assertErr UnsignedInt.fromJson(node)

block unsignedIntDeserNull:
  assertErr UnsignedInt.fromJson(newJNull())

# --- JmapInt ---

block jmapIntDeserMin:
  assertOk JmapInt.fromJson(%(-9007199254740991))

block jmapIntDeserMax:
  assertOk JmapInt.fromJson(%9007199254740991)

block jmapIntDeserWrongKindString:
  assertErr JmapInt.fromJson(%"hello")

# --- Date ---

block dateDeserValid:
  assertOk Date.fromJson(%"2014-10-30T14:12:00+08:00")

block dateDeserWrongKindInt:
  assertErr Date.fromJson(%42)

block dateDeserLowercaseT:
  assertErr Date.fromJson(%"2014-10-30t14:12:00Z")

# --- UTCDate ---

block utcDateDeserValid:
  assertOk UTCDate.fromJson(%"2014-10-30T06:12:00Z")

block utcDateDeserNotZ:
  assertErr UTCDate.fromJson(%"2014-10-30T06:12:00+00:00")

# --- AccountId ---

block accountIdDeserValid:
  assertOk AccountId.fromJson(%"A13824")

block accountIdDeserEmpty:
  assertErr AccountId.fromJson(%"")

block accountIdDeserWrongKindInt:
  assertErr AccountId.fromJson(%42)

# --- JmapState ---

block jmapStateDeserValid:
  assertOk JmapState.fromJson(%"75128aab4b1b")

block jmapStateDeserEmpty:
  assertErr JmapState.fromJson(%"")

# --- MethodCallId ---

block methodCallIdDeserValid:
  assertOk MethodCallId.fromJson(%"c1")

block methodCallIdDeserEmpty:
  assertErr MethodCallId.fromJson(%"")

# --- CreationId ---

block creationIdDeserValid:
  assertOk CreationId.fromJson(%"abc")

block creationIdDeserHashPrefix:
  assertErr CreationId.fromJson(%"#abc")

# --- PropertyName ---

block propertyNameDeserValid:
  assertOk PropertyName.fromJson(%"name")

block propertyNameDeserEmpty:
  assertErr PropertyName.fromJson(%"")

# =============================================================================
# D. toJson value correctness
# =============================================================================

block toJsonIdValue:
  let id = makeId("test123")
  assertEq id.toJson().getStr(""), "test123"

block toJsonUnsignedIntValue:
  let ui = parseUnsignedInt(42).get()
  assertEq ui.toJson().getBiggestInt(0), 42'i64

block toJsonStringKinds:
  doAssert makeId().toJson().kind == JString
  doAssert makeAccountId().toJson().kind == JString
  doAssert makeState().toJson().kind == JString
  doAssert makeMcid().toJson().kind == JString
  doAssert makeCreationId().toJson().kind == JString
  doAssert makeUriTemplate().toJson().kind == JString
  doAssert makePropertyName().toJson().kind == JString
  doAssert parseDate("2014-10-30T14:12:00+08:00").get().toJson().kind == JString
  doAssert parseUtcDate("2014-10-30T06:12:00Z").get().toJson().kind == JString

block toJsonIntKinds:
  doAssert zeroUint().toJson().kind == JInt
  doAssert parseJmapInt(0).get().toJson().kind == JInt

# =============================================================================
# E. Property-based round-trip tests
# =============================================================================

checkProperty "Id round-trip":
  let s = rng.genValidLenientString(trial, 1, 255)
  let id = parseIdFromServer(s).get()
  assertOkEq Id.fromJson(id.toJson()), id

checkProperty "AccountId round-trip":
  let s = rng.genValidAccountId(trial)
  let aid = parseAccountId(s).get()
  assertOkEq AccountId.fromJson(aid.toJson()), aid

checkProperty "JmapState round-trip":
  let s = rng.genValidJmapState(trial)
  let state = parseJmapState(s).get()
  assertOkEq JmapState.fromJson(state.toJson()), state

checkProperty "MethodCallId round-trip":
  let s = rng.genValidMethodCallId(trial)
  let mcid = parseMethodCallId(s).get()
  assertOkEq MethodCallId.fromJson(mcid.toJson()), mcid

checkProperty "CreationId round-trip":
  let s = rng.genValidCreationId(trial)
  let cid = parseCreationId(s).get()
  assertOkEq CreationId.fromJson(cid.toJson()), cid

checkProperty "UriTemplate round-trip":
  let s = rng.genValidUriTemplateParametric()
  let tmpl = parseUriTemplate(s).get()
  assertOkEq UriTemplate.fromJson(tmpl.toJson()), tmpl

checkProperty "PropertyName round-trip":
  let s = rng.genValidPropertyName(trial)
  let pn = parsePropertyName(s).get()
  assertOkEq PropertyName.fromJson(pn.toJson()), pn

checkProperty "Date round-trip":
  let s = rng.genValidDate()
  let d = parseDate(s).get()
  assertOkEq Date.fromJson(d.toJson()), d

checkProperty "UTCDate round-trip":
  let s = rng.genValidUtcDate()
  let d = parseUtcDate(s).get()
  assertOkEq UTCDate.fromJson(d.toJson()), d

checkProperty "UnsignedInt round-trip":
  let n = rng.genValidUnsignedInt(trial)
  let ui = parseUnsignedInt(n).get()
  assertOkEq UnsignedInt.fromJson(ui.toJson()), ui

checkProperty "JmapInt round-trip":
  let n = rng.genValidJmapInt(trial)
  let ji = parseJmapInt(n).get()
  assertOkEq JmapInt.fromJson(ji.toJson()), ji

# =============================================================================
# F. Additional edge-case tests
# =============================================================================

block checkJsonKindMcdcKindMismatchNonNil:
  ## MC/DC: node is non-nil but has wrong kind — proves kind mismatch alone
  ## triggers error without relying on nil check.
  let node = %42 # JInt, not JString
  doAssert not node.isNil, "precondition: node must not be nil"
  assertErr Id.fromJson(node)

block collectExtrasMixedKnownUnknown:
  ## Three known + two unknown keys: only the two unknown are collected.
  let obj = %*{"a": 1, "b": 2, "c": 3, "x": 4, "y": 5}
  let extras = collectExtras(obj, ["a", "b", "c"])
  assertSome extras
  let e = extras.get()
  doAssert e{"x"} != nil
  doAssert e{"y"} != nil
  doAssert e{"a"}.isNil, "known key 'a' must not be in extras"
  doAssert e{"b"}.isNil, "known key 'b' must not be in extras"

block parseErrorEmptyMessage:
  ## parseError with empty message produces a valid ValidationError.
  let err = parseError("TestType", "")
  assertEq err.typeName, "TestType"
  assertEq err.message, ""
  assertEq err.value, ""

# --- MaxChanges serde ---

block maxChangesRoundTrip:
  let mc = makeMaxChanges(42)
  assertOkEq MaxChanges.fromJson(mc.toJson()), mc

block maxChangesSerValue:
  let mc = makeMaxChanges(100)
  assertEq mc.toJson().getBiggestInt(0), 100

block maxChangesDeserRejectsZero:
  assertErr MaxChanges.fromJson(%0)

block maxChangesDeserRejectsNegative:
  assertErr MaxChanges.fromJson(%(-1))

block maxChangesDeserRejectsWrongKind:
  assertErr MaxChanges.fromJson(%"42")

block maxChangesDeserNil:
  const nilNode: JsonNode = nil
  assertErr MaxChanges.fromJson(nilNode)

block maxChangesDeserNull:
  assertErr MaxChanges.fromJson(newJNull())
