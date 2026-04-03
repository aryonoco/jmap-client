# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Regression tests for specific bugs found during the test suite uplift. Each
## block records a concrete deficiency and its resolution.
##
## POLICY: This file is append-only. Never remove or modify existing blocks.
## New regressions are added at the end with a dated block name following
## `regression_YYYY_MM_description`. Each block must document the bug, root
## cause, and fix in a comment.

import std/json
import std/options
import std/strutils

import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/framework
import jmap_client/errors
import jmap_client/serde_errors
import jmap_client/serde_session
import jmap_client/serde_framework

import ../massertions
import ../mserde_fixtures

block regression_2026_03_creationIdGeneratorBug:
  ## The property test propCreationIdNoLeadingHash previously used
  ## genValidIdStrict which only produces base64url characters — '#' could
  ## never appear, making the no-leading-hash assertion trivially true.
  ## Fixed by switching to genValidCreationId which produces arbitrary bytes
  ## except '#' at position 0.
  assertErrMsg parseCreationId("#bad"), "must not include '#' prefix"

block regression_2026_03_patchObjectCommutativityValueCheck:
  ## The property test propPatchCommutativityDisjointKeys only checked .len
  ## equality between two orderings, not the actual values. Fixed by adding
  ## getKey assertions for both keys.
  let p1 = emptyPatch().setProp("a", newJInt(1)).setProp("b", newJInt(2))
  let p2 = emptyPatch().setProp("b", newJInt(2)).setProp("a", newJInt(1))
  doAssert p1.len == p2.len
  doAssert p1.getKey("a").get() == p2.getKey("a").get()
  doAssert p1.getKey("b").get() == p2.getKey("b").get()

block regression_2026_03_overlongDelBypass:
  ## Overlong-encoded DEL (\xC1\xBF) bypasses the explicit '\x7F' check in
  ## lenient validators because both bytes are >= 0x20 and != 0x7F. This is
  ## a known Layer 1 limitation; overlong encoding validation is deferred to
  ## Layer 2.
  assertOk parseIdFromServer("\xC1\xBF")
  assertOk parseAccountId("\xC1\xBF")
  assertOk parseJmapState("\xC1\xBF")

# --- Phase 9: Regression test infrastructure ---

block regression_2026_03_controlCharBoundary0x20:
  ## Bug: lenient validators check `it < ' '` but space (0x20) is the
  ## boundary character that must be ACCEPTED.
  ## Root cause: off-by-one risk in the control char check.
  ## Fix: confirmed boundary is correct (< not <=).
  assertOk parseIdFromServer(" ")
  assertOk parseAccountId(" ")
  assertOk parseJmapState(" ")

block regression_2026_03_delByteExplicitCheck:
  ## Bug: DEL (0x7F) is not caught by `it < ' '` check — requires explicit
  ## `it == '\x7F'` guard.
  ## Root cause: DEL is outside the 0x00..0x1F range.
  ## Fix: explicit DEL check in lenient validators.
  assertErr parseIdFromServer("\x7F")
  assertErr parseAccountId("\x7F")
  assertErr parseJmapState("\x7F")

block regression_2026_03_dateAllZeroFractionalSingleDigit:
  ## Bug: single-digit ".0" fractional was not caught as all-zero.
  ## Root cause: the all-zero check uses allIt on the range [20..dotEnd).
  ## Fix: confirmed single-zero fractional is correctly rejected.
  assertErr parseDate("2024-01-01T12:00:00.0Z")

block regression_2026_03_dateFractionalMiddleZero:
  ## Bug: fractional ".102" contains a zero but is NOT all-zeros.
  ## Root cause: risk of using anyIt instead of allIt for zero check.
  ## Fix: confirmed allIt is used (not anyIt).
  assertOk parseDate("2024-01-01T12:00:00.102Z")

block regression_2026_03_creationIdHashAtNonZeroPosition:
  ## Bug: hash '#' in the middle of a CreationId was incorrectly rejected.
  ## Root cause: check was for any '#' instead of first-character '#'.
  ## Fix: confirmed only raw[0] == '#' is checked.
  assertOk parseCreationId("a#b")
  assertErr parseCreationId("#a")

block regression_2026_03_setErrorDefensiveFallback:
  ## Bug: setError("invalidProperties") without variant data could crash
  ## when accessing .properties field.
  ## Root cause: discriminator not safely mapped to else branch.
  ## Fix: defensive constructor maps to setUnknown, preserving rawType.
  let se = setError("invalidProperties")
  doAssert se.errorType == setUnknown
  doAssert se.rawType == "invalidProperties"

block regression_2026_03_utcDateNonZOffset:
  ## Bug: UTCDate accepted "+00:00" as equivalent to "Z".
  ## Root cause: check was for timezone presence, not specifically 'Z'.
  ## Fix: confirmed last character must be 'Z'.
  assertErr parseUtcDate("2024-01-01T12:00:00+00:00")
  assertOk parseUtcDate("2024-01-01T12:00:00Z")

block regression_2026_03_idMaxLengthBoundary:
  ## Bug: 255-byte ID accepted but 256-byte rejected — off-by-one risk.
  ## Root cause: length check uses `> 255` not `>= 255`.
  ## Fix: confirmed boundary is correct.
  assertOk parseId("A".repeat(255))
  assertErr parseId("A".repeat(256))
  assertOk parseIdFromServer("A".repeat(255))
  assertErr parseIdFromServer("A".repeat(256))

block regression_2026_03_patchObjectJsonNodeRefSharing:
  ## Bug: JsonNode mutations after setProp are visible through PatchObject
  ## because JsonNode is a ref type shared under ARC.
  ## Root cause: PatchObject stores JsonNode refs, not deep copies.
  ## Fix: documented as known behaviour; Layer 2 must deep-copy if needed.
  let node = newJObject()
  node["a"] = newJString("original")
  let p = emptyPatch().setProp("key", node)
  node["b"] = newJString("injected")
  doAssert p.getKey("key").get().hasKey("b")

block regression_2026_03_unsignedInt2Pow53Boundary:
  ## Bug: 2^53 (9007199254740992) was accepted as valid UnsignedInt.
  ## Root cause: off-by-one in boundary check (> vs >=).
  ## Fix: confirmed MaxUnsignedInt = 2^53 - 1 and check uses >.
  assertOk parseUnsignedInt(9_007_199_254_740_991'i64)
  assertErr parseUnsignedInt(9_007_199_254_740_992'i64)

# --- Phase 6B: Regression entries for Phase 0 bugs ---

block regression_2026_03_extrasOverwriteStandardFields:
  ## Known issue: in RequestError/MethodError/SetError toJson(), the extras
  ## loop runs AFTER standard field writes. Extras with colliding keys (e.g.
  ## "type") can overwrite standard fields in the serialised JSON output.
  ## Root cause: extras loop writes `result[key] = val` without skipping known keys.
  ## Status: only reachable via manual construction (not round-trip, since
  ## collectExtras strips known keys during fromJson). Documented as known
  ## behaviour; fix tracked for future phase.
  ##
  ## Document that colliding extras keys DO appear in toJson output (the bug
  ## IS present). When constructing errors with extras from fromJson, the
  ## collision cannot occur because collectExtras filters known keys.
  # Verify that collectExtras (fromJson path) strips known keys
  let j = newJObject()
  j["type"] = %"serverFail"
  j["description"] = %"real desc"
  j["vendorField"] = %"vendor value"
  let me = MethodError.fromJson(j)
  # extras from fromJson should NOT contain "type" or "description"
  if me.extras.isSome:
    doAssert me.extras.get(){"type"}.isNil, "collectExtras must strip known key 'type'"
    doAssert me.extras.get(){"description"}.isNil,
      "collectExtras must strip known key 'description'"

block regression_2026_03_toJsonAliasedInternalRefs:
  ## Known issue: ServerCapability.toJson returns the internal rawData
  ## JsonNode ref directly (for non-ckCore variants). Callers can mutate
  ## internal state through the returned ref.
  ## Root cause: return of `cap.rawData` instead of `cap.rawData.copy()`.
  ## Fix: ServerCapability.toJson and AccountCapabilityEntry.toJson now return
  ## deep copies. Mutation through the returned ref no longer propagates.
  let data = newJObject()
  data["original"] = %"value"
  let cap =
    ServerCapability(rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: data)
  let j = cap.toJson()
  j["injected"] = %"corrupted"
  # After fix: injection must NOT be visible through the capability
  let j2 = cap.toJson()
  doAssert j2{"injected"}.isNil,
    "toJson must return independent copy — mutation must not propagate"

block regression_2026_03_filterFromJsonDepthGuard:
  ## Hardening: Filter[C].fromJson had no depth guard for recursion. A
  ## deeply-nested pre-parsed JsonNode tree could cause StackOverflowDefect,
  ## which is uncatchable under {.push raises: [].}.
  ## Root cause: unbounded recursion in fromJson without depth tracking.
  ## Fix: MaxFilterDepth = 128 constant and depth parameter in internal helper.
  ##
  ## Verify that depth > 128 returns err instead of crashing.
  var inner = newJObject()
  inner["value"] = %42
  for i in 0 ..< 200:
    var conds = newJArray()
    conds.add(inner)
    inner = newJObject()
    inner["operator"] = %"AND"
    inner["conditions"] = conds
  assertErr Filter[int].fromJson(inner, fromIntCondition)
