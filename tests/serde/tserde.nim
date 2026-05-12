# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for Layer 2 serialisation: shared helpers and primitive/identifier
## round-trip serialisation.

import std/json
import std/strutils

import jmap_client/internal/serialisation/serde
import jmap_client/internal/types/primitives
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/session
import jmap_client/internal/types/framework
import jmap_client/internal/types/validation

import ../massertions
import ../mfixtures
import ../mproperty
import ../mtestblock

# =============================================================================
# A. Shared helpers
# =============================================================================

testCase expectKindAcceptsCorrect:
  doAssert expectKind(%"hello", JString, emptyJsonPath()).isOk

testCase expectKindRejectsNilAsNilNode:
  const nilNode: JsonNode = nil
  let r = expectKind(nilNode, JString, emptyJsonPath())
  doAssert r.isErr
  doAssert r.error.kind == svkNilNode

testCase expectKindRejectsJNullAsWrongKind:
  let r = expectKind(newJNull(), JString, emptyJsonPath())
  doAssert r.isErr
  doAssert r.error.kind == svkWrongKind
  doAssert r.error.actualKind == JNull

testCase expectKindRejectsWrongKind:
  let r = expectKind(%42, JString, emptyJsonPath())
  doAssert r.isErr
  doAssert r.error.kind == svkWrongKind
  doAssert r.error.expectedKind == JString
  doAssert r.error.actualKind == JInt

testCase fieldOfKindMissing:
  ## Missing field yields svkMissingField anchored at the parent path.
  let obj = %*{"a": 1}
  let r = fieldOfKind(obj, "b", JInt, emptyJsonPath())
  doAssert r.isErr
  doAssert r.error.kind == svkMissingField
  doAssert r.error.missingFieldName == "b"

testCase fieldOfKindWrongKindPath:
  ## Wrong-kind on a field anchors the path at parent/key.
  let obj = %*{"a": "not-int"}
  let r = fieldOfKind(obj, "a", JInt, emptyJsonPath())
  doAssert r.isErr
  doAssert r.error.kind == svkWrongKind
  doAssert $r.error.path == "/a"

testCase jsonPathConcat:
  ## Path concatenation yields RFC 6901 shape.
  let p = emptyJsonPath() / "methodResponses" / 0 / "arguments" / "accountId"
  assertEq $p, "/methodResponses/0/arguments/accountId"

testCase jsonPathEscapes:
  ## Tilde and slash in reference tokens escape per RFC 6901 §3.
  let p = emptyJsonPath() / "a/b" / "c~d"
  assertEq $p, "/a~1b/c~0d"

testCase collectExtrasNone:
  let node = %*{"a": 1, "b": 2}
  let extras = collectExtras(node, ["a", "b"])
  assertNone extras

testCase collectExtrasSome:
  let node = %*{"a": 1, "b": 2, "c": 3}
  let extras = collectExtras(node, ["a"])
  assertSome extras
  doAssert extras.get(){"b"} != nil
  doAssert extras.get(){"c"} != nil

testCase collectExtrasEmptyObject:
  let node = newJObject()
  let extras = collectExtras(node, ["a", "b"])
  assertNone extras

# =============================================================================
# B. Round-trip tests
# =============================================================================

testCase roundTripId:
  let original = makeId()
  assertOkEq Id.fromJson(original.toJson()), original

testCase roundTripAccountId:
  let original = makeAccountId()
  assertOkEq AccountId.fromJson(original.toJson()), original

testCase roundTripJmapState:
  let original = makeState()
  assertOkEq JmapState.fromJson(original.toJson()), original

testCase roundTripMethodCallId:
  let original = makeMcid()
  assertOkEq MethodCallId.fromJson(original.toJson()), original

testCase roundTripCreationId:
  let original = makeCreationId()
  assertOkEq CreationId.fromJson(original.toJson()), original

testCase roundTripUriTemplate:
  let original = makeUriTemplate()
  assertOkEq UriTemplate.fromJson(original.toJson()), original

testCase roundTripPropertyName:
  let original = makePropertyName()
  assertOkEq PropertyName.fromJson(original.toJson()), original

testCase roundTripDate:
  let original = parseDate("2014-10-30T14:12:00+08:00").get()
  assertOkEq Date.fromJson(original.toJson()), original

testCase roundTripUtcDate:
  let original = parseUtcDate("2014-10-30T06:12:00Z").get()
  assertOkEq UTCDate.fromJson(original.toJson()), original

testCase roundTripUnsignedInt:
  let original = zeroUint()
  assertOkEq UnsignedInt.fromJson(original.toJson()), original

testCase roundTripJmapInt:
  let original = parseJmapInt(42).get()
  assertOkEq JmapInt.fromJson(original.toJson()), original

testCase roundTripUnsignedIntMax:
  let original = parseUnsignedInt(9007199254740991'i64).get()
  assertOkEq UnsignedInt.fromJson(original.toJson()), original

testCase roundTripJmapIntMin:
  let original = parseJmapInt(-9007199254740991'i64).get()
  assertOkEq JmapInt.fromJson(original.toJson()), original

testCase roundTripIdMaxLen:
  let original = parseIdFromServer('a'.repeat(255)).get()
  assertOkEq Id.fromJson(original.toJson()), original

# --- Phase 3A: Numeric boundary off-by-one tests ---

testCase unsignedIntDeserMaxMinus1:
  ## Off-by-one below the maximum: 2^53-2 must be accepted.
  assertOk UnsignedInt.fromJson(%9007199254740990'i64)

testCase unsignedIntDeserMaxPlus1:
  ## Off-by-one above the maximum: 2^53 must be rejected.
  assertErr UnsignedInt.fromJson(%9007199254740992'i64)

testCase jmapIntDeserMinPlus1:
  ## Off-by-one above the minimum: -(2^53-2) must be accepted.
  assertOk JmapInt.fromJson(%(-9007199254740990'i64))

testCase jmapIntDeserMaxMinus1:
  ## Off-by-one below the maximum: 2^53-2 must be accepted.
  assertOk JmapInt.fromJson(%9007199254740990'i64)

testCase jmapIntDeserMaxPlus1:
  ## Off-by-one above the maximum: 2^53 must be rejected.
  assertErr JmapInt.fromJson(%9007199254740992'i64)

testCase jmapIntDeserMinMinus1:
  ## Off-by-one below the minimum: -(2^53) must be rejected.
  assertErr JmapInt.fromJson(%(-9007199254740992'i64))

# --- Phase 3B: String length boundary tests ---

testCase propertyNameDeser255:
  ## PropertyName has no upper length limit; 255 chars is valid.
  assertOk PropertyName.fromJson(%("x".repeat(255)))

testCase jmapStateDeser255:
  ## JmapState has no upper length limit (non-empty, no control chars);
  ## 255 chars is valid.
  assertOk JmapState.fromJson(%("s".repeat(255)))

testCase methodCallIdDeser255:
  ## MethodCallId has no upper length limit (non-empty); 255 chars is valid.
  assertOk MethodCallId.fromJson(%("m".repeat(255)))

testCase idDeser254:
  ## Off-by-one below Id's maximum of 255: 254 chars must be accepted.
  assertOk Id.fromJson(%("a".repeat(254)))

# =============================================================================
# C. Edge-case deserialization
# =============================================================================

# --- Id ---

testCase idDeserValidBase64url:
  assertOk Id.fromJson(%"abc123-_XYZ")

testCase idDeserWrongKindInt:
  assertErr Id.fromJson(%42)

testCase idDeserNil:
  const node: JsonNode = nil
  assertErr Id.fromJson(node)

testCase idDeserNull:
  assertErr Id.fromJson(newJNull())

testCase idDeserArray:
  assertErr Id.fromJson(%*[1, 2, 3])

testCase idDeserEmpty:
  assertErr Id.fromJson(%"")

# --- UnsignedInt ---

testCase unsignedIntDeserZero:
  assertOk UnsignedInt.fromJson(%0)

testCase unsignedIntDeserMax:
  assertOk UnsignedInt.fromJson(%9007199254740991)

testCase unsignedIntDeserNegative:
  assertErr UnsignedInt.fromJson(%(-1))

testCase unsignedIntDeserWrongKindString:
  assertErr UnsignedInt.fromJson(%"42")

testCase unsignedIntDeserNil:
  const node: JsonNode = nil
  assertErr UnsignedInt.fromJson(node)

testCase unsignedIntDeserNull:
  assertErr UnsignedInt.fromJson(newJNull())

# --- JmapInt ---

testCase jmapIntDeserMin:
  assertOk JmapInt.fromJson(%(-9007199254740991))

testCase jmapIntDeserMax:
  assertOk JmapInt.fromJson(%9007199254740991)

testCase jmapIntDeserWrongKindString:
  assertErr JmapInt.fromJson(%"hello")

# --- Date ---

testCase dateDeserValid:
  assertOk Date.fromJson(%"2014-10-30T14:12:00+08:00")

testCase dateDeserWrongKindInt:
  assertErr Date.fromJson(%42)

testCase dateDeserLowercaseT:
  assertErr Date.fromJson(%"2014-10-30t14:12:00Z")

# --- UTCDate ---

testCase utcDateDeserValid:
  assertOk UTCDate.fromJson(%"2014-10-30T06:12:00Z")

testCase utcDateDeserNotZ:
  assertErr UTCDate.fromJson(%"2014-10-30T06:12:00+00:00")

# --- AccountId ---

testCase accountIdDeserValid:
  assertOk AccountId.fromJson(%"A13824")

testCase accountIdDeserEmpty:
  assertErr AccountId.fromJson(%"")

testCase accountIdDeserWrongKindInt:
  assertErr AccountId.fromJson(%42)

# --- JmapState ---

testCase jmapStateDeserValid:
  assertOk JmapState.fromJson(%"75128aab4b1b")

testCase jmapStateDeserEmpty:
  assertErr JmapState.fromJson(%"")

# --- MethodCallId ---

testCase methodCallIdDeserValid:
  assertOk MethodCallId.fromJson(%"c1")

testCase methodCallIdDeserEmpty:
  assertErr MethodCallId.fromJson(%"")

# --- CreationId ---

testCase creationIdDeserValid:
  assertOk CreationId.fromJson(%"abc")

testCase creationIdDeserHashPrefix:
  assertErr CreationId.fromJson(%"#abc")

# --- PropertyName ---

testCase propertyNameDeserValid:
  assertOk PropertyName.fromJson(%"name")

testCase propertyNameDeserEmpty:
  assertErr PropertyName.fromJson(%"")

# =============================================================================
# D. toJson value correctness
# =============================================================================

testCase toJsonIdValue:
  let id = makeId("test123")
  assertEq id.toJson().getStr(""), "test123"

testCase toJsonUnsignedIntValue:
  let ui = parseUnsignedInt(42).get()
  assertEq ui.toJson().getBiggestInt(0), 42'i64

testCase toJsonStringKinds:
  doAssert makeId().toJson().kind == JString
  doAssert makeAccountId().toJson().kind == JString
  doAssert makeState().toJson().kind == JString
  doAssert makeMcid().toJson().kind == JString
  doAssert makeCreationId().toJson().kind == JString
  doAssert makeUriTemplate().toJson().kind == JString
  doAssert makePropertyName().toJson().kind == JString
  doAssert parseDate("2014-10-30T14:12:00+08:00").get().toJson().kind == JString
  doAssert parseUtcDate("2014-10-30T06:12:00Z").get().toJson().kind == JString

testCase toJsonIntKinds:
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

testCase expectKindMcdcKindMismatchNonNil:
  ## MC/DC: node is non-nil but has wrong kind — proves kind mismatch alone
  ## triggers error without relying on nil check.
  let node = %42 # JInt, not JString
  doAssert not node.isNil, "precondition: node must not be nil"
  assertErr Id.fromJson(node)

testCase collectExtrasMixedKnownUnknown:
  ## Three known + two unknown keys: only the two unknown are collected.
  let obj = %*{"a": 1, "b": 2, "c": 3, "x": 4, "y": 5}
  let extras = collectExtras(obj, ["a", "b", "c"])
  assertSome extras
  let e = extras.get()
  doAssert e{"x"} != nil
  doAssert e{"y"} != nil
  doAssert e{"a"}.isNil, "known key 'a' must not be in extras"
  doAssert e{"b"}.isNil, "known key 'b' must not be in extras"

# --- MaxChanges serde ---

testCase maxChangesRoundTrip:
  let mc = makeMaxChanges(42)
  assertOkEq MaxChanges.fromJson(mc.toJson()), mc

testCase maxChangesSerValue:
  let mc = makeMaxChanges(100)
  assertEq mc.toJson().getBiggestInt(0), 100

testCase maxChangesDeserRejectsZero:
  assertErr MaxChanges.fromJson(%0)

testCase maxChangesDeserRejectsNegative:
  assertErr MaxChanges.fromJson(%(-1))

testCase maxChangesDeserRejectsWrongKind:
  assertErr MaxChanges.fromJson(%"42")

testCase maxChangesDeserNil:
  const nilNode: JsonNode = nil
  assertErr MaxChanges.fromJson(nilNode)

testCase maxChangesDeserNull:
  assertErr MaxChanges.fromJson(newJNull())
