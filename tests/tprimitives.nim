# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for Id, UnsignedInt, JmapInt, Date, and UTCDate smart constructors.

import std/hashes
import std/strutils

import pkg/results

import jmap_client/primitives

# --- parseId (strict) ---

block parseIdEmpty:
  doAssert parseId("").isErr

block parseIdTooLong:
  doAssert parseId('a'.repeat(256)).isErr

block parseIdMaxLength:
  let result = parseId('a'.repeat(255))
  doAssert result.isOk

block parseIdMinLength:
  let result = parseId("x")
  doAssert result.isOk

block parseIdValidBase64url:
  let result = parseId("abc123-_XYZ")
  doAssert result.isOk

block parseIdPadChar:
  doAssert parseId("abc=def").isErr

block parseIdSpace:
  doAssert parseId("abc def").isErr

# --- parseIdFromServer (lenient) ---

block parseIdFromServerPlus:
  let result = parseIdFromServer("abc+def")
  doAssert result.isOk

block parseIdFromServerControlChar:
  doAssert parseIdFromServer("abc\x00def").isErr

# --- parseUnsignedInt ---

block parseUnsignedIntZero:
  let result = parseUnsignedInt(0'i64)
  doAssert result.isOk

block parseUnsignedIntMax:
  let result = parseUnsignedInt(MaxUnsignedInt)
  doAssert result.isOk

block parseUnsignedIntNegative:
  doAssert parseUnsignedInt(-1'i64).isErr

block parseUnsignedIntOverflow:
  doAssert parseUnsignedInt(MaxUnsignedInt + 1).isErr

# --- parseJmapInt ---

block parseJmapIntMin:
  let result = parseJmapInt(MinJmapInt)
  doAssert result.isOk

block parseJmapIntMax:
  let result = parseJmapInt(MaxJmapInt)
  doAssert result.isOk

# --- parseDate ---

block parseDateValidOffset:
  let result = parseDate("2014-10-30T14:12:00+08:00")
  doAssert result.isOk

block parseDateValidFrac:
  let result = parseDate("2014-10-30T14:12:00.123Z")
  doAssert result.isOk

block parseDateLowercaseT:
  doAssert parseDate("2014-10-30t14:12:00Z").isErr

block parseDateZeroFrac:
  doAssert parseDate("2014-10-30T14:12:00.000Z").isErr

block parseDateEmptyFrac:
  doAssert parseDate("2014-10-30T14:12:00.Z").isErr

block parseDateSingleZeroFrac:
  doAssert parseDate("2014-10-30T14:12:00.0Z").isErr

block parseDateTrailingZeroNonZeroFrac:
  let result = parseDate("2014-10-30T14:12:00.100Z")
  doAssert result.isOk

block parseDateLowercaseZ:
  doAssert parseDate("2014-10-30T14:12:00z").isErr

block parseDateTooShort:
  doAssert parseDate("2014-10-30").isErr

# --- parseUtcDate ---

block parseUtcDateValid:
  let result = parseUtcDate("2014-10-30T06:12:00Z")
  doAssert result.isOk

block parseUtcDateNotZ:
  doAssert parseUtcDate("2014-10-30T06:12:00+00:00").isErr

# --- Borrowed ops: string types (Id, Date, UTCDate) ---

block idBorrowedOps:
  let a = parseId("abc").get()
  let b = parseId("abc").get()
  let c = parseId("xyz").get()

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "abc"
  doAssert hash(a) == hash(b)
  doAssert a.len == 3

block dateBorrowedOps:
  let a = parseDate("2014-10-30T14:12:00+08:00").get()
  let b = parseDate("2014-10-30T14:12:00+08:00").get()

  doAssert a == b
  doAssert $a == "2014-10-30T14:12:00+08:00"
  doAssert hash(a) == hash(b)
  doAssert a.len == 25

block utcDateBorrowedOps:
  let a = parseUtcDate("2014-10-30T06:12:00Z").get()
  let b = parseUtcDate("2014-10-30T06:12:00Z").get()

  doAssert a == b
  doAssert $a == "2014-10-30T06:12:00Z"
  doAssert hash(a) == hash(b)
  doAssert a.len == 20

# --- Borrowed ops: int types (UnsignedInt, JmapInt) ---

block unsignedIntBorrowedOps:
  let x = parseUnsignedInt(10'i64).get()
  let y = parseUnsignedInt(10'i64).get()
  let z = parseUnsignedInt(20'i64).get()

  doAssert x == y
  doAssert not (x == z)
  doAssert x < z
  doAssert x <= y
  doAssert x <= z
  doAssert not (z <= x)
  doAssert $x == "10"
  doAssert hash(x) == hash(y)

block jmapIntBorrowedOps:
  let x = parseJmapInt(10'i64).get()
  let y = parseJmapInt(10'i64).get()
  let z = parseJmapInt(20'i64).get()

  doAssert x == y
  doAssert not (x == z)
  doAssert x < z
  doAssert x <= y
  doAssert x <= z
  doAssert not (z <= x)
  doAssert $x == "10"
  doAssert hash(x) == hash(y)

# --- Unary negation on JmapInt ---

block jmapIntUnaryNeg:
  let pos = parseJmapInt(100'i64).get()
  let neg = parseJmapInt(-100'i64).get()

  doAssert -pos == neg
  doAssert -neg == pos
