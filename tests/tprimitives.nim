# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for Id, UnsignedInt, JmapInt, Date, and UTCDate smart constructors.

import std/hashes
import std/strutils

import results

import jmap_client/primitives

import ./massertions

# --- parseId (strict) ---

block parseIdEmpty:
  assertErrFields parseId(""), "Id", "length must be 1-255 octets", ""

block parseIdTooLong:
  assertErrFields parseId('a'.repeat(256)),
    "Id", "length must be 1-255 octets", 'a'.repeat(256)

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
  assertErrFields parseId("abc=def"),
    "Id", "contains characters outside base64url alphabet", "abc=def"

block parseIdSpace:
  assertErrFields parseId("abc def"),
    "Id", "contains characters outside base64url alphabet", "abc def"

# --- parseIdFromServer (lenient) ---

block parseIdFromServerPlus:
  let result = parseIdFromServer("abc+def")
  doAssert result.isOk

block parseIdFromServerControlChar:
  assertErrFields parseIdFromServer("abc\x00def"),
    "Id", "contains control characters", "abc\x00def"

# --- parseUnsignedInt ---

block parseUnsignedIntZero:
  let result = parseUnsignedInt(0'i64)
  doAssert result.isOk

block parseUnsignedIntMax:
  let result = parseUnsignedInt(MaxUnsignedInt)
  doAssert result.isOk

block parseUnsignedIntNegative:
  assertErrFields parseUnsignedInt(-1'i64), "UnsignedInt", "must be non-negative", "-1"

block parseUnsignedIntOverflow:
  assertErrFields parseUnsignedInt(MaxUnsignedInt + 1),
    "UnsignedInt", "exceeds 2^53-1", $(MaxUnsignedInt + 1)

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
  assertErrFields parseDate("2014-10-30t14:12:00Z"),
    "Date", "'T' separator must be uppercase", "2014-10-30t14:12:00Z"

block parseDateZeroFrac:
  assertErrFields parseDate("2014-10-30T14:12:00.000Z"),
    "Date", "zero fractional seconds must be omitted", "2014-10-30T14:12:00.000Z"

block parseDateEmptyFrac:
  assertErrFields parseDate("2014-10-30T14:12:00.Z"),
    "Date",
    "fractional seconds must contain at least one digit",
    "2014-10-30T14:12:00.Z"

block parseDateSingleZeroFrac:
  assertErrFields parseDate("2014-10-30T14:12:00.0Z"),
    "Date", "zero fractional seconds must be omitted", "2014-10-30T14:12:00.0Z"

block parseDateTrailingZeroNonZeroFrac:
  let result = parseDate("2014-10-30T14:12:00.100Z")
  doAssert result.isOk

block parseDateLowercaseZ:
  assertErrFields parseDate("2014-10-30T14:12:00z"),
    "Date", "'T' and 'Z' must be uppercase (RFC 3339)", "2014-10-30T14:12:00z"

block parseDateTooShort:
  assertErrFields parseDate("2014-10-30"),
    "Date", "too short for RFC 3339 date-time", "2014-10-30"

# --- parseUtcDate ---

block parseUtcDateValid:
  let result = parseUtcDate("2014-10-30T06:12:00Z")
  doAssert result.isOk

block parseUtcDateNotZ:
  assertErrFields parseUtcDate("2014-10-30T06:12:00+00:00"),
    "UTCDate", "time-offset must be 'Z'", "2014-10-30T06:12:00+00:00"

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

block parseIdFromServerErrorContentControl:
  assertErrFields parseIdFromServer("\x00abc"),
    "Id", "contains control characters", "\x00abc"

block parseDateErrorContentBadDate:
  assertErrFields parseDate("20X4-01-01T12:00:00Z"),
    "Date", "invalid date portion", "20X4-01-01T12:00:00Z"

block parseDateErrorContentBadTime:
  assertErrFields parseDate("2024-01-01T1X:00:00Z"),
    "Date", "invalid time portion", "2024-01-01T1X:00:00Z"

# --- Adversarial edge cases ---

block parseIdNullByte:
  assertErrFields parseId("abc\x00def"),
    "Id", "contains characters outside base64url alphabet", "abc\x00def"

block parseIdFromServerNullByte:
  assertErrFields parseIdFromServer("abc\x00def"),
    "Id", "contains control characters", "abc\x00def"

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
  assertErrFields parseDate("2024-01-01T12:00:00\x00"),
    "Date", "timezone offset must be 'Z' or '+/-HH:MM'", "2024-01-01T12:00:00\x00"

block parseDateDoubleZ:
  assertErrFields parseDate("2024-01-01T12:00:00ZZ"),
    "Date", "trailing characters after 'Z'", "2024-01-01T12:00:00ZZ"

block parseUtcDateOffsetNotZ:
  assertErrFields parseUtcDate("2024-01-01T12:00:00+00:00"),
    "UTCDate", "time-offset must be 'Z'", "2024-01-01T12:00:00+00:00"

# --- Missing paths and boundary values ---

block parseIdFromServerEmpty:
  assertErrFields parseIdFromServer(""), "Id", "length must be 1-255 octets", ""

block parseIdFromServerTooLong:
  assertErrFields parseIdFromServer('a'.repeat(256)),
    "Id", "length must be 1-255 octets", 'a'.repeat(256)

block parseIdFromServerMaxLength:
  doAssert parseIdFromServer('a'.repeat(255)).isOk

block parseIdFromServerMinLength:
  doAssert parseIdFromServer("x").isOk

block parseIdFromServerSpaceAccepted:
  doAssert parseIdFromServer("abc def").isOk

block parseIdFromServerEqualsAccepted:
  doAssert parseIdFromServer("abc=def").isOk

block parseIdFromServerDelRejected:
  assertErrFields parseIdFromServer("abc\x7Fdef"),
    "Id", "contains control characters", "abc\x7Fdef"

block parseIdPlusRejectedStrict:
  assertErrFields parseId("abc+def"),
    "Id", "contains characters outside base64url alphabet", "abc+def"

block parseJmapIntZero:
  doAssert parseJmapInt(0).isOk

block parseJmapIntUnderflow:
  assertErrFields parseJmapInt(MinJmapInt - 1),
    "JmapInt", "outside JSON-safe integer range", $(MinJmapInt - 1)

block parseJmapIntOverflow:
  assertErrFields parseJmapInt(MaxJmapInt + 1),
    "JmapInt", "outside JSON-safe integer range", $(MaxJmapInt + 1)

block parseUnsignedIntInt64Max:
  assertErrFields parseUnsignedInt(int64.high),
    "UnsignedInt", "exceeds 2^53-1", $(int64.high)

block parseJmapIntInt64Min:
  assertErrFields parseJmapInt(int64.low),
    "JmapInt", "outside JSON-safe integer range", $(int64.low)

block parseJmapIntInt64Max:
  assertErrFields parseJmapInt(int64.high),
    "JmapInt", "outside JSON-safe integer range", $(int64.high)

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
  assertErrFields parseDate("-001-01-01T12:00:00Z"),
    "Date", "invalid date portion", "-001-01-01T12:00:00Z"

block parseUtcDateNegativeZeroOffset:
  # -00:00 must be rejected for UTCDate (must end with Z)
  assertErrFields parseUtcDate("2024-01-01T12:00:00-00:00"),
    "UTCDate", "time-offset must be 'Z'", "2024-01-01T12:00:00-00:00"

block parseDateTrailingAfterNumericOffset:
  assertErrFields parseDate("2024-01-01T12:00:00+05:00X"),
    "Date", "timezone offset must be 'Z' or '+/-HH:MM'", "2024-01-01T12:00:00+05:00X"

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
  assertErrFields parseDate("2024-01-01T12:00:00.00Z"),
    "Date", "zero fractional seconds must be omitted", "2024-01-01T12:00:00.00Z"

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
  assertErrFields parseDate("2024-01-01T12:00:00X08:00"),
    "Date", "timezone offset must be 'Z' or '+/-HH:MM'", "2024-01-01T12:00:00X08:00"

block parseDateTruncatedNumericOffset:
  # Truncated numeric offset: only +HH
  assertErrFields parseDate("2024-01-01T12:00:00+08"),
    "Date", "timezone offset must be 'Z' or '+/-HH:MM'", "2024-01-01T12:00:00+08"

block parseDateShortNumericOffset:
  # Short numeric offset: +HH:M
  assertErrFields parseDate("2024-01-01T12:00:00+08:0"),
    "Date", "timezone offset must be 'Z' or '+/-HH:MM'", "2024-01-01T12:00:00+08:0"

block parseDateNonDigitInOffset:
  # Non-digit in offset hours
  assertErrFields parseDate("2024-01-01T12:00:00+0X:00"),
    "Date", "timezone offset must be 'Z' or '+/-HH:MM'", "2024-01-01T12:00:00+0X:00"

block parseDateMissingColonInOffset:
  # Missing colon in offset: +HHMMSS
  assertErrFields parseDate("2024-01-01T12:00:00+080000"),
    "Date", "timezone offset must be 'Z' or '+/-HH:MM'", "2024-01-01T12:00:00+080000"

block parseDateNonDigitAfterFracDot:
  # Non-digit immediately after fractional dot
  assertErrFields parseDate("2024-01-01T12:00:00.1X"),
    "Date", "timezone offset must be 'Z' or '+/-HH:MM'", "2024-01-01T12:00:00.1X"

block parseDateWrongSeparators:
  # Wrong separators in date/time portion
  assertErrFields parseDate("2024:01:01T12-00-00Z"),
    "Date", "invalid date portion", "2024:01:01T12-00-00Z"

block parseDateNoSeparators:
  # Compact format without separators
  assertErrFields parseDate("20240101T120000Z"),
    "Date", "too short for RFC 3339 date-time", "20240101T120000Z"

block parseUnsignedIntInt64Low:
  # int64.low is massively negative
  assertErrFields parseUnsignedInt(int64.low),
    "UnsignedInt", "must be non-negative", $(int64.low)

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

# --- Phase 4: Date parsing mutation resistance ---

block dateWrongSeparatorSlash:
  ## Catches slash-for-dash mutation in date portion.
  assertErr parseDate("2024/01/01T12:00:00Z")

block dateWrongSeparatorInTime:
  ## Catches dash-for-colon mutation in time portion.
  assertErr parseDate("2024-01-01T12-00:00Z")

block dateExactMinimumLength:
  ## Exactly 20 chars is minimum valid — catches < vs <= mutation.
  const input = "2024-01-01T12:00:00Z"
  doAssert input.len == 20
  assertOk parseDate(input)

block dateFractionalZeroInMiddle:
  ## ".102" contains zero but is not all zeros — catches allIt vs anyIt mutation.
  assertOk parseDate("2024-01-01T12:00:00.102Z")

block dateOffsetWithoutColon:
  ## "+0500" is malformed offset — must be "+HH:MM".
  assertErr parseDate("2024-01-01T12:00:00+0500")

block dateNegativeOffset:
  ## "-05:00" is valid — catches accept-only-plus mutation.
  assertOk parseDate("2024-01-01T12:00:00-05:00")

block dateMonth13:
  ## Month 13 is structurally valid (Layer 1 does not validate calendar).
  assertOk parseDate("2024-13-01T12:00:00Z")

block dateNanosecondFractional:
  ## 9-digit fractional seconds (nanosecond precision) is valid.
  assertOk parseDate("2024-01-01T12:00:00.123456789Z")

block dateDay32:
  ## Day 32 is structurally valid in Layer 1.
  assertOk parseDate("2024-01-32T12:00:00Z")

block dateMaxYear:
  ## Year 9999 is structurally valid.
  assertOk parseDate("9999-12-28T23:59:59Z")

block dateMidnightBoundary:
  ## Midnight boundary (00:00:00) is valid.
  assertOk parseDate("2024-01-01T00:00:00Z")

block dateEndOfDayBoundary:
  ## End-of-day boundary (23:59:59) is valid.
  assertOk parseDate("2024-01-01T23:59:59Z")

# --- Phase 4: Id parsing mutation resistance ---

block idInvalidCharAtPosition254:
  ## Invalid char at near-end position in max-length string.
  var s = "A".repeat(255)
  s[254] = '+'
  assertErr parseId(s)

block idFromServerControlCharAtEnd:
  ## Control char at last position of lenient Id.
  assertErr parseIdFromServer("A".repeat(254) & "\x1F")

block idAllUnderscoresMaxLength:
  ## 255 underscores — all valid base64url.
  assertOk parseId("_".repeat(255))

block idFromServerSpaceSingle:
  ## Space (0x20) is the boundary between control and printable — accepted.
  assertOk parseIdFromServer(" ")

block idStrictRejectsSpace:
  ## Space is NOT in base64url charset — rejected by strict parser.
  assertErr parseId(" ")

block idFromServerDelAtStart:
  ## DEL (0x7F) at position 0.
  assertErr parseIdFromServer("\x7Fabc")

block idFromServerDelAtMiddle:
  ## DEL at middle position.
  assertErr parseIdFromServer("ab\x7Fcd")

block idFromServerDelAtEnd:
  ## DEL at last position.
  assertErr parseIdFromServer("abc\x7F")

# --- Phase 4: Integer boundary off-by-one ---

block unsignedIntExactly2Pow53:
  ## 2^53 = 9007199254740992 exceeds MaxUnsignedInt — must reject.
  assertErr parseUnsignedInt(9_007_199_254_740_992'i64)

block unsignedInt2Pow53Minus2:
  ## 2^53 - 2 = 9007199254740990 — must accept.
  assertOk parseUnsignedInt(9_007_199_254_740_990'i64)

block jmapIntExactlyNeg2Pow53:
  ## -(2^53) = -9007199254740992 — below MinJmapInt, must reject.
  assertErr parseJmapInt(-9_007_199_254_740_992'i64)

block jmapIntExactlyMinJmapInt:
  ## -(2^53 - 1) = -9007199254740991 — exactly MinJmapInt, must accept.
  assertOk parseJmapInt(-9_007_199_254_740_991'i64)

# --- Phase 2: Boundary value tests ---

block parseIdLen2:
  ## parseId accepts a 2-character base64url string (boundary above minimum).
  assertOk parseId("AB")

block parseIdFromServerLen2:
  ## parseIdFromServer accepts a 2-character string (boundary above minimum).
  assertOk parseIdFromServer("AB")

block parseIdFromServerLen255:
  ## parseIdFromServer accepts a 255-character string (maximum length).
  assertOk parseIdFromServer("A".repeat(255))

block parseIdFromServerLen256:
  ## parseIdFromServer rejects a 256-character string (one over maximum).
  assertErr parseIdFromServer("A".repeat(256))

# --- Phase 3: Equivalence class gaps ---

block parseIdStrictRejectsDel:
  ## Strict Id rejects DEL character (0x7F).
  assertErr parseId("abc\x7Fdef")

block parseIdStrictRejectsHighByte80:
  ## Strict Id rejects high byte 0x80.
  assertErr parseId("abc\x80def")

block parseIdStrictRejectsHighByteFF:
  ## Strict Id rejects high byte 0xFF.
  assertErr parseId("abc\xFFdef")

# --- Phase 3: MC/DC tests for Date compound conditions ---

block dateMcdcMonthNonDigit:
  ## MC/DC: non-digit in month position triggers date portion rejection.
  assertErrFields parseDate("2024-X1-01T12:00:00Z"),
    "Date", "invalid date portion", "2024-X1-01T12:00:00Z"

block dateMcdcSecondDashWrong:
  ## MC/DC: wrong separator (slash) at second dash position.
  assertErrFields parseDate("2024-01/01T12:00:00Z"),
    "Date", "invalid date portion", "2024-01/01T12:00:00Z"

block dateMcdcDayNonDigit:
  ## MC/DC: non-digit in day position triggers date portion rejection.
  assertErrFields parseDate("2024-01-X1T12:00:00Z"),
    "Date", "invalid date portion", "2024-01-X1T12:00:00Z"

block dateMcdcMinuteNonDigit:
  ## MC/DC: non-digit in minute position triggers time portion rejection.
  assertErrFields parseDate("2024-01-01T12:X0:00Z"),
    "Date", "invalid time portion", "2024-01-01T12:X0:00Z"

block dateMcdcSecondColonWrong:
  ## MC/DC: wrong separator (dash) at second colon position.
  assertErrFields parseDate("2024-01-01T12:00-00Z"),
    "Date", "invalid time portion", "2024-01-01T12:00-00Z"

block dateMcdcSecondNonDigit:
  ## MC/DC: non-digit in second position triggers time portion rejection.
  assertErrFields parseDate("2024-01-01T12:00:X0Z"),
    "Date", "invalid time portion", "2024-01-01T12:00:X0Z"

block dateMcdcOffsetMinuteFirstNonDigit:
  ## MC/DC: non-digit at offset minute first position.
  assertErrFields parseDate("2024-01-01T12:00:00+08:X0"),
    "Date", "timezone offset must be 'Z' or '+/-HH:MM'", "2024-01-01T12:00:00+08:X0"

block dateMcdcOffsetMinuteSecondNonDigit:
  ## MC/DC: non-digit at offset minute second position.
  assertErrFields parseDate("2024-01-01T12:00:00+08:0X"),
    "Date", "timezone offset must be 'Z' or '+/-HH:MM'", "2024-01-01T12:00:00+08:0X"

# --- Phase 7: Table-driven date validation ---

block dateTableDrivenValid:
  ## Comprehensive table of valid date formats — easy to extend.
  const validCases = [
    ("2024-01-01T12:00:00Z", "basic UTC"),
    ("2024-01-01T12:00:00+05:30", "positive offset with half-hour"),
    ("2024-01-01T12:00:00-12:00", "maximum negative offset"),
    ("2024-01-01T12:00:00+14:00", "maximum positive offset"),
    ("2024-01-01T12:00:00.1Z", "1-digit fractional"),
    ("2024-01-01T12:00:00.12Z", "2-digit fractional"),
    ("2024-01-01T12:00:00.123Z", "3-digit fractional"),
    ("2024-01-01T12:00:00.123456Z", "6-digit fractional"),
    ("2024-01-01T12:00:00.123456789Z", "9-digit fractional"),
    ("0000-01-01T00:00:00Z", "year zero"),
    ("9999-12-28T23:59:59Z", "near-max year"),
    ("2024-01-01T00:00:00Z", "midnight"),
    ("2024-01-01T23:59:59Z", "end of day"),
    ("2024-02-30T12:00:00Z", "calendar-invalid Feb 30 (structural only)"),
    ("2024-13-01T12:00:00Z", "calendar-invalid month 13 (structural only)"),
  ]
  for (input, reason) in validCases:
    doAssert parseDate(input).isOk, "expected Ok for: " & reason & " (" & input & ")"

block dateTableDrivenInvalid:
  ## Comprehensive table of invalid date formats — easy to extend.
  const invalidCases = [
    ("", "empty string"),
    ("2024-01-01", "date only, no time"),
    ("2024-01-01t12:00:00Z", "lowercase t separator"),
    ("2024-01-01T12:00:00z", "lowercase z timezone"),
    ("2024-01-01T12:00:00", "missing timezone"),
    ("2024-01-01T12:00:00.000Z", "all-zero 3-digit fractional"),
    ("2024-01-01T12:00:00.0Z", "all-zero 1-digit fractional"),
    ("2024-01-01T12:00:00.Z", "dot with no fractional digits"),
    ("2024/01/01T12:00:00Z", "slash separators in date"),
    ("2024-01-01T12-00:00Z", "dash separator in time"),
    ("2024-01-01T12:00:00+0500", "offset missing colon"),
    ("2024-01-01T12:00:00+05:00X", "trailing chars after offset"),
    ("2024-01-01T12:00:00Zextra", "trailing chars after Z"),
    ("short", "too short for RFC 3339"),
  ]
  for (input, reason) in invalidCases:
    doAssert parseDate(input).isErr, "expected Err for: " & reason & " (" & input & ")"
