# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for AccountId, JmapState, MethodCallId, and CreationId smart constructors.

import std/strutils

import jmap_client/internal/types/identifiers
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation

import ../massertions
import ../mtestblock

# --- parseAccountId ---

testCase parseAccountIdEmpty:
  assertErrFields parseAccountId(""), "AccountId", "length must be 1-255 octets", ""

testCase parseAccountIdValid:
  assertOk parseAccountId("A13824")

testCase parseAccountIdTooLong:
  assertErrFields parseAccountId('a'.repeat(256)),
    "AccountId", "length must be 1-255 octets", 'a'.repeat(256)

testCase parseAccountIdMaxLength:
  assertOk parseAccountId('a'.repeat(255))

testCase parseAccountIdMinLength:
  assertOk parseAccountId("x")

testCase parseAccountIdControlChar:
  assertErrFields parseAccountId("abc\x00def"),
    "AccountId", "contains control characters", "abc\x00def"

# --- parseJmapState ---

testCase parseJmapStateEmpty:
  assertErrFields parseJmapState(""), "JmapState", "must not be empty", ""

testCase parseJmapStateValid:
  assertOk parseJmapState("75128aab4b1b")

testCase parseJmapStateControlChar:
  assertErrFields parseJmapState("abc\x00def"),
    "JmapState", "contains control characters", "abc\x00def"

# --- parseMethodCallId ---

testCase parseMethodCallIdEmpty:
  assertErrFields parseMethodCallId(""), "MethodCallId", "must not be empty", ""

testCase parseMethodCallIdValid:
  assertOk parseMethodCallId("c1")

# --- parseCreationId ---

testCase parseCreationIdEmpty:
  assertErrFields parseCreationId(""), "CreationId", "must not be empty", ""

testCase parseCreationIdHashPrefix:
  assertErrFields parseCreationId("#abc"),
    "CreationId", "must not include '#' prefix", "#abc"

testCase parseCreationIdValid:
  assertOk parseCreationId("abc")

# --- Borrowed ops: AccountId ---

testCase accountIdBorrowedOps:
  let a = parseAccountId("A13824").get()
  let b = parseAccountId("A13824").get()
  let c = parseAccountId("B99921").get()

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "A13824"
  doAssert hash(a) == hash(b)
  doAssert a.len == 6

# --- Borrowed ops: JmapState, MethodCallId, CreationId ---

testCase jmapStateBorrowedOps:
  let a = parseJmapState("75128aab4b1b").get()
  let b = parseJmapState("75128aab4b1b").get()
  let c = parseJmapState("different").get()

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "75128aab4b1b"
  doAssert hash(a) == hash(b)
  doAssert not compiles(a.len)

testCase methodCallIdBorrowedOps:
  let a = parseMethodCallId("c1").get()
  let b = parseMethodCallId("c1").get()
  let c = parseMethodCallId("c2").get()

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "c1"
  doAssert hash(a) == hash(b)
  doAssert not compiles(a.len)

testCase creationIdBorrowedOps:
  let a = parseCreationId("abc").get()
  let b = parseCreationId("abc").get()
  let c = parseCreationId("xyz").get()

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "abc"
  doAssert hash(a) == hash(b)
  doAssert not compiles(a.len)

# --- Adversarial edge cases ---

testCase parseAccountIdBom:
  assertOk parseAccountId("\xEF\xBB\xBFabc")

testCase parseIdFromServerHighUnicode:
  let result = parseIdFromServer("\xF0\x9F\x98\x80").get()
  doAssert result.len == 4

# --- Missing boundaries ---

testCase parseAccountIdDelChar:
  assertErrFields parseAccountId("abc\x7Fdef"),
    "AccountId", "contains control characters", "abc\x7Fdef"

testCase parseAccountIdSpaceAccepted:
  assertOk parseAccountId("abc def")

testCase parseJmapStateDelChar:
  assertErrFields parseJmapState("abc\x7Fdef"),
    "JmapState", "contains control characters", "abc\x7Fdef"

testCase parseCreationIdHashMiddle:
  assertOk parseCreationId("ab#cd")

testCase parseMethodCallIdControlAccepted:
  assertOk parseMethodCallId("\x01abc")

testCase parseCreationIdLongString:
  assertOk parseCreationId('a'.repeat(1000))

# --- Phase 4: Identifier mutation resistance ---

testCase accountIdControlBoundaryReject:
  ## 0x1F (unit separator) is < 0x20, must be rejected.
  assertErr parseAccountId("\x1F")

testCase accountIdControlBoundaryAccept:
  ## 0x20 (space) is at boundary — must be accepted.
  assertOk parseAccountId(" ")

testCase accountIdDelRejected:
  ## DEL (0x7F) explicitly rejected by lenient validators.
  assertErr parseAccountId("\x7F")

testCase accountIdHighBytesAccepted:
  ## Bytes >= 0x80 are accepted by lenient validators.
  assertOk parseAccountId("\x80")
  assertOk parseAccountId("\xFF")

testCase jmapStateSingleChar:
  ## Single character is minimum valid length.
  assertOk parseJmapState("a")

testCase jmapStateControlBoundary:
  ## 0x1F rejected, space accepted.
  assertErr parseJmapState("\x1F")
  assertOk parseJmapState(" ")

testCase creationIdHashInMiddle:
  ## Hash at position != 0 is accepted.
  assertOk parseCreationId("a#b")
  assertOk parseCreationId("abc#def#ghi")

testCase methodCallIdAllBytesAccepted:
  ## MethodCallId has no charset restriction; all 256 byte values accepted.
  var s = newString(256)
  for i in 0 ..< 256:
    s[i] = char(i)
  assertOk parseMethodCallId(s)

# --- Phase 3: Boundary value tests ---

testCase parseAccountIdLen2:
  ## parseAccountId accepts a 2-character string (boundary above minimum).
  assertOk parseAccountId("AB")

testCase parseCreationIdHashAtEnd:
  ## parseCreationId accepts a hash at the end (only position 0 is rejected).
  assertOk parseCreationId("a#")
