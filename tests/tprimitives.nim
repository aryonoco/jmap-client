# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for Id, UnsignedInt, JmapInt, Date, and UTCDate smart constructors.

import std/hashes
import std/strutils

import pkg/results

import jmap_client/primitives

import ./massertions

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

# --- Error content assertions ---

block parseIdErrorContentEmpty:
  assertErrFields parseId(""), "Id", "length must be 1-255 octets", ""

block parseIdErrorContentTooLong:
  assertErrFields parseId('a'.repeat(256)),
    "Id", "length must be 1-255 octets", 'a'.repeat(256)

block parseIdErrorContentBadChar:
  assertErrFields parseId("abc=def"),
    "Id", "contains characters outside base64url alphabet", "abc=def"

block parseIdErrorContentSpace:
  assertErrFields parseId("abc def"),
    "Id", "contains characters outside base64url alphabet", "abc def"

block parseIdFromServerErrorContentControl:
  assertErrFields parseIdFromServer("\x00abc"),
    "Id", "contains control characters", "\x00abc"

block parseUnsignedIntErrorContentNegative:
  assertErrFields parseUnsignedInt(-1), "UnsignedInt", "must be non-negative", "-1"

block parseUnsignedIntErrorContentOverflow:
  assertErrFields parseUnsignedInt(MaxUnsignedInt + 1),
    "UnsignedInt", "exceeds 2^53-1", $(MaxUnsignedInt + 1)

block parseJmapIntErrorContentUnder:
  assertErrFields parseJmapInt(MinJmapInt - 1),
    "JmapInt", "outside JSON-safe integer range", $(MinJmapInt - 1)

block parseJmapIntErrorContentOver:
  assertErrFields parseJmapInt(MaxJmapInt + 1),
    "JmapInt", "outside JSON-safe integer range", $(MaxJmapInt + 1)

block parseDateErrorContentTooShort:
  assertErrFields parseDate("2024-01-01"),
    "Date", "too short for RFC 3339 date-time", "2024-01-01"

block parseDateErrorContentBadDate:
  assertErrFields parseDate("20X4-01-01T12:00:00Z"),
    "Date", "invalid date portion", "20X4-01-01T12:00:00Z"

block parseDateErrorContentTSep:
  assertErrFields parseDate("2024-01-01t12:00:00Z"),
    "Date", "'T' separator must be uppercase", "2024-01-01t12:00:00Z"

block parseDateErrorContentBadTime:
  assertErrFields parseDate("2024-01-01T1X:00:00Z"),
    "Date", "invalid time portion", "2024-01-01T1X:00:00Z"

block parseDateErrorContentZeroFrac:
  assertErrFields parseDate("2024-01-01T12:00:00.000Z"),
    "Date", "zero fractional seconds must be omitted", "2024-01-01T12:00:00.000Z"

block parseDateErrorContentEmptyFrac:
  assertErrFields parseDate("2024-01-01T12:00:00.Z"),
    "Date",
    "fractional seconds must contain at least one digit",
    "2024-01-01T12:00:00.Z"

block parseUtcDateErrorContentNotZ:
  assertErrFields parseUtcDate("2024-01-01T12:00:00+05:00"),
    "UTCDate", "time-offset must be 'Z'", "2024-01-01T12:00:00+05:00"

# --- Adversarial edge cases ---

block parseIdNullByte:
  doAssert parseId("abc\x00def").isErr

block parseIdFromServerNullByte:
  doAssert parseIdFromServer("abc\x00def").isErr

block parseIdMultibyteUtf8:
  let result = parseIdFromServer("\xC3\xA9\xC3\xA9")
  doAssert result.isOk
  doAssert result.get().len == 4

block parseDateInvalidCalendarAccepted:
  doAssert parseDate("2024-02-30T12:00:00Z").isOk

block parseDateInvalidTimeAccepted:
  doAssert parseDate("2024-01-01T25:99:99Z").isOk

block parseDateVeryLongFractional:
  doAssert parseDate("2024-01-01T12:00:00.123456789012345Z").isOk

block parseUtcDateFractionalThenZ:
  doAssert parseUtcDate("2024-01-01T12:00:00.123Z").isOk

block parseDateNullByteInOffset:
  doAssert parseDate("2024-01-01T12:00:00\x00").isErr

block parseDateDoubleZ:
  doAssert parseDate("2024-01-01T12:00:00ZZ").isErr

block parseUtcDateOffsetNotZ:
  doAssert parseUtcDate("2024-01-01T12:00:00+00:00").isErr

# --- Missing paths and boundary values ---

block parseIdFromServerEmpty:
  doAssert parseIdFromServer("").isErr

block parseIdFromServerTooLong:
  doAssert parseIdFromServer('a'.repeat(256)).isErr

block parseIdFromServerMaxLength:
  doAssert parseIdFromServer('a'.repeat(255)).isOk

block parseIdFromServerMinLength:
  doAssert parseIdFromServer("x").isOk

block parseIdFromServerSpaceAccepted:
  doAssert parseIdFromServer("abc def").isOk

block parseIdFromServerEqualsAccepted:
  doAssert parseIdFromServer("abc=def").isOk

block parseIdFromServerDelRejected:
  doAssert parseIdFromServer("abc\x7Fdef").isErr

block parseIdPlusRejectedStrict:
  doAssert parseId("abc+def").isErr

block parseJmapIntZero:
  doAssert parseJmapInt(0).isOk

block parseJmapIntUnderflow:
  doAssert parseJmapInt(MinJmapInt - 1).isErr

block parseJmapIntOverflow:
  doAssert parseJmapInt(MaxJmapInt + 1).isErr

block parseUnsignedIntInt64Max:
  doAssert parseUnsignedInt(int64.high).isErr

block parseJmapIntInt64Min:
  doAssert parseJmapInt(int64.low).isErr

block parseJmapIntInt64Max:
  doAssert parseJmapInt(int64.high).isErr

block maxUnsignedIntIsCorrect:
  doAssert MaxUnsignedInt == (1'i64 shl 53) - 1
  doAssert MinJmapInt == -((1'i64 shl 53) - 1)
  doAssert MaxJmapInt == (1'i64 shl 53) - 1

# --- Date/UTCDate structural edge cases ---

block parseDateLeapSecond:
  # Leap second: structural validation only, accepted
  assertOk parseDate("2016-12-31T23:59:60Z")

block parseDateMonthZero:
  # Month 00: structural validation only, accepted (no calendar check)
  assertOk parseDate("2024-00-15T12:00:00Z")

block parseDateDayZero:
  assertOk parseDate("2024-01-00T12:00:00Z")

block parseDateYearZero:
  assertOk parseDate("0000-01-01T12:00:00Z")

block parseDateNegativeYear:
  # Negative year: non-digit at position 0
  assertErr parseDate("-001-01-01T12:00:00Z")

block parseUtcDateNegativeZeroOffset:
  # -00:00 must be rejected for UTCDate (must end with Z)
  assertErr parseUtcDate("2024-01-01T12:00:00-00:00")

block parseDateTrailingAfterNumericOffset:
  assertErr parseDate("2024-01-01T12:00:00+05:00X")

block parseDateInvalidOffsetValues:
  # Invalid offset values accepted (structural only, no range check)
  assertOk parseDate("2024-01-01T12:00:00+24:00")
  assertOk parseDate("2024-01-01T12:00:00-99:99")
  assertOk parseDate("2024-01-01T12:00:00+00:60")

block parseDateVeryLongFractionalSeconds:
  # Long fractional seconds: accepted, no crash
  let frac = "1".repeat(1000)
  assertOk parseDate("2024-01-01T12:00:00." & frac & "Z")

block parseDateTwoZeroFractional:
  assertErr parseDate("2024-01-01T12:00:00.00Z")

# --- Integer boundary completions ---

block unsignedIntDollarAtMax:
  assertEq $(parseUnsignedInt(MaxUnsignedInt).get()), "9007199254740991"

block jmapIntDollarAtMin:
  assertEq $(parseJmapInt(MinJmapInt).get()), "-9007199254740991"

block jmapIntDollarAtMax:
  assertEq $(parseJmapInt(MaxJmapInt).get()), "9007199254740991"

block jmapIntNegationAtMinEqualsMax:
  let minVal = parseJmapInt(MinJmapInt).get()
  let maxVal = parseJmapInt(MaxJmapInt).get()
  assertEq -minVal, maxVal

# --- Date parser: untested code paths ---

block parseDateBadTimezoneChar:
  # Non-Z/+/- at timezone position
  assertErr parseDate("2024-01-01T12:00:00X08:00")
  assertErrContains parseDate("2024-01-01T12:00:00X08:00"), "timezone offset"

block parseDateTruncatedNumericOffset:
  # Truncated numeric offset: only +HH
  assertErr parseDate("2024-01-01T12:00:00+08")
  assertErrContains parseDate("2024-01-01T12:00:00+08"), "timezone offset"

block parseDateShortNumericOffset:
  # Short numeric offset: +HH:M
  assertErr parseDate("2024-01-01T12:00:00+08:0")
  assertErrContains parseDate("2024-01-01T12:00:00+08:0"), "timezone offset"

block parseDateNonDigitInOffset:
  # Non-digit in offset hours
  assertErr parseDate("2024-01-01T12:00:00+0X:00")
  assertErrContains parseDate("2024-01-01T12:00:00+0X:00"), "timezone offset"

block parseDateMissingColonInOffset:
  # Missing colon in offset: +HHMMSS
  assertErr parseDate("2024-01-01T12:00:00+080000")
  assertErrContains parseDate("2024-01-01T12:00:00+080000"), "timezone offset"

block parseDateNonDigitAfterFracDot:
  # Non-digit immediately after fractional dot
  assertErr parseDate("2024-01-01T12:00:00.1X")
  assertErrContains parseDate("2024-01-01T12:00:00.1X"), "timezone offset"

block parseDateWrongSeparators:
  # Wrong separators in date/time portion
  assertErr parseDate("2024:01:01T12-00-00Z")
  assertErrMsg parseDate("2024:01:01T12-00-00Z"), "invalid date portion"

block parseDateNoSeparators:
  # Compact format without separators
  assertErr parseDate("20240101T120000Z")
  assertErrMsg parseDate("20240101T120000Z"), "too short for RFC 3339 date-time"

# --- Integer boundary completeness ---

block parseUnsignedIntInt64High:
  # int64.high is well above 2^53-1
  assertErr parseUnsignedInt(int64.high)

block parseUnsignedIntInt64Low:
  # int64.low is massively negative
  assertErr parseUnsignedInt(int64.low)

block parseJmapIntInt64High:
  assertErr parseJmapInt(int64.high)

block parseJmapIntInt64Low:
  assertErr parseJmapInt(int64.low)

block parseUnsignedIntOne:
  assertOk parseUnsignedInt(1)

block parseIdLength254:
  # 254-char base64url string should be accepted
  assertOk parseId('a'.repeat(254))

block parseUnsignedIntMaxMinusOne:
  assertOk parseUnsignedInt(MaxUnsignedInt - 1)

block parseJmapIntMinPlusOne:
  assertOk parseJmapInt(MinJmapInt + 1)

block parseJmapIntMaxMinusOne:
  assertOk parseJmapInt(MaxJmapInt - 1)
