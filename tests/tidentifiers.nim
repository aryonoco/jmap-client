# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for AccountId, JmapState, MethodCallId, and CreationId smart constructors.

import std/hashes
import std/strutils

import pkg/results

import jmap_client/identifiers
import jmap_client/primitives

import ./massertions

# --- parseAccountId ---

block parseAccountIdEmpty:
  doAssert parseAccountId("").isErr

block parseAccountIdValid:
  let result = parseAccountId("A13824")
  doAssert result.isOk

block parseAccountIdTooLong:
  doAssert parseAccountId('a'.repeat(256)).isErr

block parseAccountIdMaxLength:
  let result = parseAccountId('a'.repeat(255))
  doAssert result.isOk

block parseAccountIdMinLength:
  let result = parseAccountId("x")
  doAssert result.isOk

block parseAccountIdControlChar:
  doAssert parseAccountId("abc\x00def").isErr

# --- parseJmapState ---

block parseJmapStateEmpty:
  doAssert parseJmapState("").isErr

block parseJmapStateValid:
  let result = parseJmapState("75128aab4b1b")
  doAssert result.isOk

block parseJmapStateControlChar:
  doAssert parseJmapState("abc\x00def").isErr

# --- parseMethodCallId ---

block parseMethodCallIdEmpty:
  doAssert parseMethodCallId("").isErr

block parseMethodCallIdValid:
  let result = parseMethodCallId("c1")
  doAssert result.isOk

# --- parseCreationId ---

block parseCreationIdEmpty:
  doAssert parseCreationId("").isErr

block parseCreationIdHashPrefix:
  doAssert parseCreationId("#abc").isErr

block parseCreationIdValid:
  let result = parseCreationId("abc")
  doAssert result.isOk

# --- Borrowed ops: AccountId ---

block accountIdBorrowedOps:
  let a = parseAccountId("A13824").get()
  let b = parseAccountId("A13824").get()
  let c = parseAccountId("B99921").get()

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "A13824"
  doAssert hash(a) == hash(b)
  doAssert a.len == 6

# --- Borrowed ops: JmapState, MethodCallId, CreationId ---

block jmapStateBorrowedOps:
  let a = parseJmapState("75128aab4b1b").get()
  let b = parseJmapState("75128aab4b1b").get()
  let c = parseJmapState("different").get()

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "75128aab4b1b"
  doAssert hash(a) == hash(b)
  doAssert not compiles(a.len)

block methodCallIdBorrowedOps:
  let a = parseMethodCallId("c1").get()
  let b = parseMethodCallId("c1").get()
  let c = parseMethodCallId("c2").get()

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "c1"
  doAssert hash(a) == hash(b)
  doAssert not compiles(a.len)

block creationIdBorrowedOps:
  let a = parseCreationId("abc").get()
  let b = parseCreationId("abc").get()
  let c = parseCreationId("xyz").get()

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "abc"
  doAssert hash(a) == hash(b)
  doAssert not compiles(a.len)

# --- Error content assertions ---

block parseAccountIdErrorContentEmpty:
  assertErrFields parseAccountId(""), "AccountId", "length must be 1-255 octets", ""

block parseAccountIdErrorContentTooLong:
  assertErrFields parseAccountId('a'.repeat(256)),
    "AccountId", "length must be 1-255 octets", 'a'.repeat(256)

block parseAccountIdErrorContentControl:
  assertErrFields parseAccountId("abc\x00def"),
    "AccountId", "contains control characters", "abc\x00def"

block parseJmapStateErrorContentEmpty:
  assertErrFields parseJmapState(""), "JmapState", "must not be empty", ""

block parseJmapStateErrorContentControl:
  assertErrFields parseJmapState("abc\x00def"),
    "JmapState", "contains control characters", "abc\x00def"

block parseMethodCallIdErrorContentEmpty:
  assertErrFields parseMethodCallId(""), "MethodCallId", "must not be empty", ""

block parseCreationIdErrorContentEmpty:
  assertErrFields parseCreationId(""), "CreationId", "must not be empty", ""

block parseCreationIdErrorContentHash:
  assertErrFields parseCreationId("#abc"),
    "CreationId", "must not include '#' prefix", "#abc"

# --- Adversarial edge cases ---

block parseAccountIdBom:
  doAssert parseAccountId("\xEF\xBB\xBFabc").isOk

block parseIdFromServerHighUnicode:
  let result = parseIdFromServer("\xF0\x9F\x98\x80")
  doAssert result.isOk
  doAssert result.get().len == 4

# --- Missing boundaries ---

block parseAccountIdDelChar:
  doAssert parseAccountId("abc\x7Fdef").isErr

block parseAccountIdSpaceAccepted:
  doAssert parseAccountId("abc def").isOk

block parseJmapStateDelChar:
  doAssert parseJmapState("abc\x7Fdef").isErr

block parseCreationIdHashMiddle:
  doAssert parseCreationId("ab#cd").isOk

block parseMethodCallIdControlAccepted:
  doAssert parseMethodCallId("\x01abc").isOk

block parseCreationIdLongString:
  doAssert parseCreationId('a'.repeat(1000)).isOk
