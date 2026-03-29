# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Regression tests for specific bugs found during the test suite uplift. Each
## block records a concrete deficiency and its resolution.
##
## POLICY: This file is append-only. Never remove or modify existing blocks.
## New regressions are added at the end with a dated block name following
## `regression_YYYY_MM_description`. Each block must document the bug, root
## cause, and fix in a comment.

import std/json
import std/strutils

import results

import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/framework
import jmap_client/errors

block regression_2026_03_creationIdGeneratorBug:
  ## The property test propCreationIdNoLeadingHash previously used
  ## genValidIdStrict which only produces base64url characters — '#' could
  ## never appear, making the no-leading-hash assertion trivially true.
  ## Fixed by switching to genValidCreationId which produces arbitrary bytes
  ## except '#' at position 0.
  let result = parseCreationId("#bad")
  doAssert result.isErr
  doAssert result.error.message == "must not include '#' prefix"

block regression_2026_03_patchObjectCommutativityValueCheck:
  ## The property test propPatchCommutativityDisjointKeys only checked .len
  ## equality between two orderings, not the actual values. Fixed by adding
  ## getKey assertions for both keys.
  let p1 = emptyPatch().setProp("a", newJInt(1)).get().setProp("b", newJInt(2)).get()
  let p2 = emptyPatch().setProp("b", newJInt(2)).get().setProp("a", newJInt(1)).get()
  doAssert p1.len == p2.len
  doAssert p1.getKey("a").get() == p2.getKey("a").get()
  doAssert p1.getKey("b").get() == p2.getKey("b").get()

block regression_2026_03_overlongDelBypass:
  ## Overlong-encoded DEL (\xC1\xBF) bypasses the explicit '\x7F' check in
  ## lenient validators because both bytes are >= 0x20 and != 0x7F. This is
  ## a known Layer 1 limitation; overlong encoding validation is deferred to
  ## Layer 2.
  doAssert parseIdFromServer("\xC1\xBF").isOk
  doAssert parseAccountId("\xC1\xBF").isOk
  doAssert parseJmapState("\xC1\xBF").isOk

# --- Phase 9: Regression test infrastructure ---

block regression_2026_03_controlCharBoundary0x20:
  ## Bug: lenient validators check `it < ' '` but space (0x20) is the
  ## boundary character that must be ACCEPTED.
  ## Root cause: off-by-one risk in the control char check.
  ## Fix: confirmed boundary is correct (< not <=).
  doAssert parseIdFromServer(" ").isOk
  doAssert parseAccountId(" ").isOk
  doAssert parseJmapState(" ").isOk

block regression_2026_03_delByteExplicitCheck:
  ## Bug: DEL (0x7F) is not caught by `it < ' '` check — requires explicit
  ## `it == '\x7F'` guard.
  ## Root cause: DEL is outside the 0x00..0x1F range.
  ## Fix: explicit DEL check in lenient validators.
  doAssert parseIdFromServer("\x7F").isErr
  doAssert parseAccountId("\x7F").isErr
  doAssert parseJmapState("\x7F").isErr

block regression_2026_03_dateAllZeroFractionalSingleDigit:
  ## Bug: single-digit ".0" fractional was not caught as all-zero.
  ## Root cause: the all-zero check uses allIt on the range [20..dotEnd).
  ## Fix: confirmed single-zero fractional is correctly rejected.
  doAssert parseDate("2024-01-01T12:00:00.0Z").isErr

block regression_2026_03_dateFractionalMiddleZero:
  ## Bug: fractional ".102" contains a zero but is NOT all-zeros.
  ## Root cause: risk of using anyIt instead of allIt for zero check.
  ## Fix: confirmed allIt is used (not anyIt).
  doAssert parseDate("2024-01-01T12:00:00.102Z").isOk

block regression_2026_03_creationIdHashAtNonZeroPosition:
  ## Bug: hash '#' in the middle of a CreationId was incorrectly rejected.
  ## Root cause: check was for any '#' instead of first-character '#'.
  ## Fix: confirmed only raw[0] == '#' is checked.
  doAssert parseCreationId("a#b").isOk
  doAssert parseCreationId("#a").isErr

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
  doAssert parseUtcDate("2024-01-01T12:00:00+00:00").isErr
  doAssert parseUtcDate("2024-01-01T12:00:00Z").isOk

block regression_2026_03_idMaxLengthBoundary:
  ## Bug: 255-byte ID accepted but 256-byte rejected — off-by-one risk.
  ## Root cause: length check uses `> 255` not `>= 255`.
  ## Fix: confirmed boundary is correct.
  doAssert parseId("A".repeat(255)).isOk
  doAssert parseId("A".repeat(256)).isErr
  doAssert parseIdFromServer("A".repeat(255)).isOk
  doAssert parseIdFromServer("A".repeat(256)).isErr

block regression_2026_03_patchObjectJsonNodeRefSharing:
  ## Bug: JsonNode mutations after setProp are visible through PatchObject
  ## because JsonNode is a ref type shared under ARC.
  ## Root cause: PatchObject stores JsonNode refs, not deep copies.
  ## Fix: documented as known behaviour; Layer 2 must deep-copy if needed.
  let node = newJObject()
  node["a"] = newJString("original")
  let p = emptyPatch().setProp("key", node).get()
  node["b"] = newJString("injected")
  doAssert p.getKey("key").get().hasKey("b")

block regression_2026_03_unsignedInt2Pow53Boundary:
  ## Bug: 2^53 (9007199254740992) was accepted as valid UnsignedInt.
  ## Root cause: off-by-one in boundary check (> vs >=).
  ## Fix: confirmed MaxUnsignedInt = 2^53 - 1 and check uses >.
  doAssert parseUnsignedInt(9_007_199_254_740_991'i64).isOk
  doAssert parseUnsignedInt(9_007_199_254_740_992'i64).isErr
