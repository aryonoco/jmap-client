# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for AccountId, JmapState, MethodCallId, and CreationId smart constructors.

import std/strutils

import jmap_client/identifiers
import jmap_client/primitives

import ../massertions

# --- parseAccountId ---

block parseAccountIdEmpty:
  assertErrFields parseAccountId(""), "AccountId", "length must be 1-255 octets", ""

block parseAccountIdValid:
  assertOk parseAccountId("A13824")

block parseAccountIdTooLong:
  assertErrFields parseAccountId('a'.repeat(256)),
    "AccountId", "length must be 1-255 octets", 'a'.repeat(256)

block parseAccountIdMaxLength:
  assertOk parseAccountId('a'.repeat(255))

block parseAccountIdMinLength:
  assertOk parseAccountId("x")

block parseAccountIdControlChar:
  assertErrFields parseAccountId("abc\x00def"),
    "AccountId", "contains control characters", "abc\x00def"

# --- parseJmapState ---

block parseJmapStateEmpty:
  assertErrFields parseJmapState(""), "JmapState", "must not be empty", ""

block parseJmapStateValid:
  assertOk parseJmapState("75128aab4b1b")

block parseJmapStateControlChar:
  assertErrFields parseJmapState("abc\x00def"),
    "JmapState", "contains control characters", "abc\x00def"

# --- parseMethodCallId ---

block parseMethodCallIdEmpty:
  assertErrFields parseMethodCallId(""), "MethodCallId", "must not be empty", ""

block parseMethodCallIdValid:
  assertOk parseMethodCallId("c1")

# --- parseCreationId ---

block parseCreationIdEmpty:
  assertErrFields parseCreationId(""), "CreationId", "must not be empty", ""

block parseCreationIdHashPrefix:
  assertErrFields parseCreationId("#abc"),
    "CreationId", "must not include '#' prefix", "#abc"

block parseCreationIdValid:
  assertOk parseCreationId("abc")

# --- Borrowed ops: AccountId ---

block accountIdBorrowedOps:
  let a = parseAccountId("A13824")
  let b = parseAccountId("A13824")
  let c = parseAccountId("B99921")

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "A13824"
  doAssert hash(a) == hash(b)
  doAssert a.len == 6

# --- Borrowed ops: JmapState, MethodCallId, CreationId ---

block jmapStateBorrowedOps:
  let a = parseJmapState("75128aab4b1b")
  let b = parseJmapState("75128aab4b1b")
  let c = parseJmapState("different")

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "75128aab4b1b"
  doAssert hash(a) == hash(b)
  doAssert not compiles(a.len)

block methodCallIdBorrowedOps:
  let a = parseMethodCallId("c1")
  let b = parseMethodCallId("c1")
  let c = parseMethodCallId("c2")

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "c1"
  doAssert hash(a) == hash(b)
  doAssert not compiles(a.len)

block creationIdBorrowedOps:
  let a = parseCreationId("abc")
  let b = parseCreationId("abc")
  let c = parseCreationId("xyz")

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "abc"
  doAssert hash(a) == hash(b)
  doAssert not compiles(a.len)

# --- Adversarial edge cases ---

block parseAccountIdBom:
  assertOk parseAccountId("\xEF\xBB\xBFabc")

block parseIdFromServerHighUnicode:
  let result = parseIdFromServer("\xF0\x9F\x98\x80")
  doAssert result.len == 4

# --- Missing boundaries ---

block parseAccountIdDelChar:
  assertErrFields parseAccountId("abc\x7Fdef"),
    "AccountId", "contains control characters", "abc\x7Fdef"

block parseAccountIdSpaceAccepted:
  assertOk parseAccountId("abc def")

block parseJmapStateDelChar:
  assertErrFields parseJmapState("abc\x7Fdef"),
    "JmapState", "contains control characters", "abc\x7Fdef"

block parseCreationIdHashMiddle:
  assertOk parseCreationId("ab#cd")

block parseMethodCallIdControlAccepted:
  assertOk parseMethodCallId("\x01abc")

block parseCreationIdLongString:
  assertOk parseCreationId('a'.repeat(1000))

# --- Phase 4: Identifier mutation resistance ---

block accountIdControlBoundaryReject:
  ## 0x1F (unit separator) is < 0x20, must be rejected.
  assertErr parseAccountId("\x1F")

block accountIdControlBoundaryAccept:
  ## 0x20 (space) is at boundary — must be accepted.
  assertOk parseAccountId(" ")

block accountIdDelRejected:
  ## DEL (0x7F) explicitly rejected by lenient validators.
  assertErr parseAccountId("\x7F")

block accountIdHighBytesAccepted:
  ## Bytes >= 0x80 are accepted by lenient validators.
  assertOk parseAccountId("\x80")
  assertOk parseAccountId("\xFF")

block jmapStateSingleChar:
  ## Single character is minimum valid length.
  assertOk parseJmapState("a")

block jmapStateControlBoundary:
  ## 0x1F rejected, space accepted.
  assertErr parseJmapState("\x1F")
  assertOk parseJmapState(" ")

block creationIdHashInMiddle:
  ## Hash at position != 0 is accepted.
  assertOk parseCreationId("a#b")
  assertOk parseCreationId("abc#def#ghi")

block methodCallIdAllBytesAccepted:
  ## MethodCallId has no charset restriction; all 256 byte values accepted.
  var s = newString(256)
  for i in 0 ..< 256:
    s[i] = char(i)
  assertOk parseMethodCallId(s)

# --- Phase 3: Boundary value tests ---

block parseAccountIdLen2:
  ## parseAccountId accepts a 2-character string (boundary above minimum).
  assertOk parseAccountId("AB")

block parseCreationIdHashAtEnd:
  ## parseCreationId accepts a hash at the end (only position 0 is rejected).
  assertOk parseCreationId("a#")
