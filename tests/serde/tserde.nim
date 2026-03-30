# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for Layer 2 serialisation: shared helpers and primitive/identifier
## round-trip serialisation.

import std/json
import std/strutils

import results

import jmap_client/serde
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/session
import jmap_client/framework
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

func tryCheckString(node: JsonNode): Result[string, ValidationError] =
  ## Wrapper to test checkJsonKind with JString expectation.
  checkJsonKind(node, JString, "Test")
  ok(node.getStr(""))

func tryCheckStringCustomMsg(node: JsonNode): Result[string, ValidationError] =
  ## Wrapper to test checkJsonKind with a custom error message.
  checkJsonKind(node, JString, "Test", "custom error message")
  ok(node.getStr(""))

block checkJsonKindAcceptsCorrect:
  {.cast(noSideEffect).}:
    assertOk tryCheckString(%"hello")

block checkJsonKindRejectsNil:
  const nilNode: JsonNode = nil
  assertErr tryCheckString(nilNode)

block checkJsonKindRejectsJNull:
  assertErr tryCheckString(newJNull())

block checkJsonKindRejectsWrongKind:
  {.cast(noSideEffect).}:
    assertErr tryCheckString(%42)

block checkJsonKindCustomMessage:
  {.cast(noSideEffect).}:
    let r = tryCheckStringCustomMsg(%42)
    assertErrMsg r, "custom error message"

block checkJsonKindDefaultMessage:
  {.cast(noSideEffect).}:
    let r = tryCheckString(%42)
    assertErrContains r, "expected JSON"

block collectExtrasNone:
  {.cast(noSideEffect).}:
    let node = %*{"a": 1, "b": 2}
    let extras = collectExtras(node, ["a", "b"])
    assertNone extras

block collectExtrasSome:
  {.cast(noSideEffect).}:
    let node = %*{"a": 1, "b": 2, "c": 3}
    let extras = collectExtras(node, ["a"])
    assertSome extras
    doAssert extras.get(){"b"} != nil
    doAssert extras.get(){"c"} != nil

block collectExtrasEmptyObject:
  {.cast(noSideEffect).}:
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

# =============================================================================
# C. Edge-case deserialization
# =============================================================================

# --- Id ---

block idDeserValidBase64url:
  {.cast(noSideEffect).}:
    assertOk Id.fromJson(%"abc123-_XYZ")

block idDeserWrongKindInt:
  {.cast(noSideEffect).}:
    assertErr Id.fromJson(%42)

block idDeserNil:
  const node: JsonNode = nil
  assertErr Id.fromJson(node)

block idDeserNull:
  assertErr Id.fromJson(newJNull())

block idDeserArray:
  {.cast(noSideEffect).}:
    assertErr Id.fromJson(%*[1, 2, 3])

block idDeserEmpty:
  {.cast(noSideEffect).}:
    assertErr Id.fromJson(%"")

# --- UnsignedInt ---

block unsignedIntDeserZero:
  {.cast(noSideEffect).}:
    assertOk UnsignedInt.fromJson(%0)

block unsignedIntDeserMax:
  {.cast(noSideEffect).}:
    assertOk UnsignedInt.fromJson(%9007199254740991)

block unsignedIntDeserNegative:
  {.cast(noSideEffect).}:
    assertErr UnsignedInt.fromJson(%(-1))

block unsignedIntDeserWrongKindString:
  {.cast(noSideEffect).}:
    assertErr UnsignedInt.fromJson(%"42")

block unsignedIntDeserNil:
  const node: JsonNode = nil
  assertErr UnsignedInt.fromJson(node)

block unsignedIntDeserNull:
  assertErr UnsignedInt.fromJson(newJNull())

# --- JmapInt ---

block jmapIntDeserMin:
  {.cast(noSideEffect).}:
    assertOk JmapInt.fromJson(%(-9007199254740991))

block jmapIntDeserMax:
  {.cast(noSideEffect).}:
    assertOk JmapInt.fromJson(%9007199254740991)

block jmapIntDeserWrongKindString:
  {.cast(noSideEffect).}:
    assertErr JmapInt.fromJson(%"hello")

block jmapIntDeserNil:
  const node: JsonNode = nil
  assertErr JmapInt.fromJson(node)

block jmapIntDeserNull:
  assertErr JmapInt.fromJson(newJNull())

block jmapIntDeserOverflowPositive:
  ## One above the 2^53-1 maximum.
  {.cast(noSideEffect).}:
    assertErr JmapInt.fromJson(%9007199254740992'i64)

block jmapIntDeserOverflowNegative:
  ## One below the -(2^53-1) minimum.
  {.cast(noSideEffect).}:
    assertErr JmapInt.fromJson(%(-9007199254740992'i64))

block unsignedIntDeserOverflowMax:
  ## One above the 2^53-1 maximum.
  {.cast(noSideEffect).}:
    assertErr UnsignedInt.fromJson(%9007199254740992'i64)

# --- Date ---

block dateDeserValid:
  {.cast(noSideEffect).}:
    assertOk Date.fromJson(%"2014-10-30T14:12:00+08:00")

block dateDeserWrongKindInt:
  {.cast(noSideEffect).}:
    assertErr Date.fromJson(%42)

block dateDeserLowercaseT:
  {.cast(noSideEffect).}:
    assertErr Date.fromJson(%"2014-10-30t14:12:00Z")

block dateDeserNil:
  const node: JsonNode = nil
  assertErr Date.fromJson(node)

block dateDeserNull:
  assertErr Date.fromJson(newJNull())

block dateDeserEmptyString:
  {.cast(noSideEffect).}:
    assertErr Date.fromJson(%"")

# --- UTCDate ---

block utcDateDeserValid:
  {.cast(noSideEffect).}:
    assertOk UTCDate.fromJson(%"2014-10-30T06:12:00Z")

block utcDateDeserNotZ:
  {.cast(noSideEffect).}:
    assertErr UTCDate.fromJson(%"2014-10-30T06:12:00+00:00")

block utcDateDeserNil:
  const node: JsonNode = nil
  assertErr UTCDate.fromJson(node)

block utcDateDeserNull:
  assertErr UTCDate.fromJson(newJNull())

block utcDateDeserEmptyString:
  {.cast(noSideEffect).}:
    assertErr UTCDate.fromJson(%"")

# --- AccountId ---

block accountIdDeserValid:
  {.cast(noSideEffect).}:
    assertOk AccountId.fromJson(%"A13824")

block accountIdDeserEmpty:
  {.cast(noSideEffect).}:
    assertErr AccountId.fromJson(%"")

block accountIdDeserWrongKindInt:
  {.cast(noSideEffect).}:
    assertErr AccountId.fromJson(%42)

# --- JmapState ---

block jmapStateDeserValid:
  {.cast(noSideEffect).}:
    assertOk JmapState.fromJson(%"75128aab4b1b")

block jmapStateDeserEmpty:
  {.cast(noSideEffect).}:
    assertErr JmapState.fromJson(%"")

# --- MethodCallId ---

block methodCallIdDeserValid:
  {.cast(noSideEffect).}:
    assertOk MethodCallId.fromJson(%"c1")

block methodCallIdDeserEmpty:
  {.cast(noSideEffect).}:
    assertErr MethodCallId.fromJson(%"")

# --- CreationId ---

block creationIdDeserValid:
  {.cast(noSideEffect).}:
    assertOk CreationId.fromJson(%"abc")

block creationIdDeserHashPrefix:
  {.cast(noSideEffect).}:
    assertErr CreationId.fromJson(%"#abc")

# --- PropertyName ---

block propertyNameDeserValid:
  {.cast(noSideEffect).}:
    assertOk PropertyName.fromJson(%"name")

block propertyNameDeserEmpty:
  {.cast(noSideEffect).}:
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
