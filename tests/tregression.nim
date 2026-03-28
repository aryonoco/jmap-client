# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Regression tests for specific bugs found during the test suite uplift. Each
## block records a concrete deficiency and its resolution.

import std/json

import pkg/results

import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/framework

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
