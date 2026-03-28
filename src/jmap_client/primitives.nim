# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## RFC 8620 primitive types with smart constructors enforcing wire-format
## constraints. Bounded to JSON-safe integer ranges (2^53-1) per the JMAP
## specification.

import std/hashes
import std/sequtils

import pkg/results

import ./validation

type Id* {.requiresInit.} = distinct string
  ## JMAP identifier: 1-255 octets, base64url charset (RFC 8620 §1.2).
  ## Requires explicit construction via parseId or parseIdFromServer.

defineStringDistinctOps(Id)

type UnsignedInt* {.requiresInit.} = distinct int64
  ## Non-negative integer bounded to 0..2^53-1 for JSON interoperability
  ## (RFC 8620 §1.3).

defineIntDistinctOps(UnsignedInt)

type JmapInt* {.requiresInit.} = distinct int64
  ## Signed integer bounded to -(2^53-1)..2^53-1 for JSON interoperability
  ## (RFC 8620 §1.3).

defineIntDistinctOps(JmapInt)
func `-`*(a: JmapInt): JmapInt {.borrow.} ## unary negation

type Date* {.requiresInit.} = distinct string
  ## RFC 3339 date-time string with structural validation but no calendar
  ## semantics.

defineStringDistinctOps(Date)

type UTCDate* {.requiresInit.} = distinct string
  ## RFC 3339 date-time that must use 'Z' (UTC) as its timezone offset.

defineStringDistinctOps(UTCDate)

const MaxUnsignedInt*: int64 = 9_007_199_254_740_991'i64 ## 2^53 - 1

const
  MinJmapInt*: int64 = -9_007_199_254_740_991'i64 ## -(2^53 - 1)
  MaxJmapInt*: int64 = 9_007_199_254_740_991'i64 ## 2^53 - 1

const AsciiDigits = {'0' .. '9'}

func parseId*(raw: string): Result[Id, ValidationError] =
  ## Strict: 1-255 octets, base64url charset only.
  ## For client-constructed IDs (e.g., method call IDs used as creation IDs).
  if raw.len < 1 or raw.len > 255:
    return err(validationError("Id", "length must be 1-255 octets", raw))
  if not raw.allIt(it in Base64UrlChars):
    return
      err(validationError("Id", "contains characters outside base64url alphabet", raw))
  ok(Id(raw))

func parseIdFromServer*(raw: string): Result[Id, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## For server-assigned IDs in responses. Tolerates servers that deviate
  ## from the strict base64url charset (e.g., Cyrus IMAP).
  if raw.len < 1 or raw.len > 255:
    return err(validationError("Id", "length must be 1-255 octets", raw))
  if raw.anyIt(it < ' ' or it == '\x7F'):
    return err(validationError("Id", "contains control characters", raw))
  ok(Id(raw))

func parseUnsignedInt*(value: int64): Result[UnsignedInt, ValidationError] =
  ## Must be 0..2^53-1. Prevents negative values and integers outside JSON's
  ## safe range.
  if value < 0:
    return err(validationError("UnsignedInt", "must be non-negative", $value))
  if value > MaxUnsignedInt:
    return err(validationError("UnsignedInt", "exceeds 2^53-1", $value))
  ok(UnsignedInt(value))

func parseJmapInt*(value: int64): Result[JmapInt, ValidationError] =
  ## Must be -(2^53-1)..2^53-1. Rejects values outside JSON's safe integer
  ## range.
  if value < MinJmapInt or value > MaxJmapInt:
    return err(validationError("JmapInt", "outside JSON-safe integer range", $value))
  ok(JmapInt(value))

func validateDatePortion(raw: string): Result[void, ValidationError] =
  ## YYYY-MM-DD at positions 0..9.
  if not (
    raw[0 .. 3].allIt(it in AsciiDigits) and raw[4] == '-' and
    raw[5 .. 6].allIt(it in AsciiDigits) and raw[7] == '-' and
    raw[8 .. 9].allIt(it in AsciiDigits)
  ):
    return err(validationError("Date", "invalid date portion", raw))
  ok()

func validateTimePortion(raw: string): Result[void, ValidationError] =
  ## HH:MM:SS at positions 11..18, with uppercase 'T' separator at 10.
  if raw[10] != 'T':
    return err(validationError("Date", "'T' separator must be uppercase", raw))
  if not (
    raw[11 .. 12].allIt(it in AsciiDigits) and raw[13] == ':' and
    raw[14 .. 15].allIt(it in AsciiDigits) and raw[16] == ':' and
    raw[17 .. 18].allIt(it in AsciiDigits)
  ):
    return err(validationError("Date", "invalid time portion", raw))
  if raw.anyIt(it in {'t', 'z'}):
    return err(validationError("Date", "'T' and 'Z' must be uppercase (RFC 3339)", raw))
  ok()

func validateFractionalSeconds(raw: string): Result[void, ValidationError] =
  ## If a '.' follows position 19, digits must follow and not all be zero.
  if raw.len > 19 and raw[19] == '.':
    let dotEnd = block:
      var i = 20
      while i < raw.len and raw[i] in AsciiDigits:
        inc i
      i
    if dotEnd == 20:
      return err(
        validationError(
          "Date", "fractional seconds must contain at least one digit", raw
        )
      )
    if raw[20 ..< dotEnd].allIt(it == '0'):
      return
        err(validationError("Date", "zero fractional seconds must be omitted", raw))
  ok()

func offsetStart(raw: string): int =
  ## Returns the position where the timezone offset begins (after fractional
  ## seconds, if any).
  result = 19
  if result < raw.len and raw[result] == '.':
    inc result
    while result < raw.len and raw[result] in AsciiDigits:
      inc result

func isValidNumericOffset(raw: string, pos: int): bool =
  ## Checks that raw[pos..pos+5] matches +HH:MM or -HH:MM structurally.
  pos + 6 == raw.len and raw[pos + 1] in AsciiDigits and raw[pos + 2] in AsciiDigits and
    raw[pos + 3] == ':' and raw[pos + 4] in AsciiDigits and raw[pos + 5] in AsciiDigits

func validateTimezoneOffset(raw: string): Result[void, ValidationError] =
  ## Validates timezone offset after seconds and optional fractional seconds.
  ## Must be 'Z' or '+HH:MM' or '-HH:MM'.
  let pos = offsetStart(raw)
  if pos >= raw.len:
    return err(validationError("Date", "missing timezone offset", raw))
  if raw[pos] == 'Z':
    if pos + 1 != raw.len:
      return err(validationError("Date", "trailing characters after 'Z'", raw))
    return ok()
  if raw[pos] notin {'+', '-'} or not isValidNumericOffset(raw, pos):
    return
      err(validationError("Date", "timezone offset must be 'Z' or '+/-HH:MM'", raw))
  ok()

func parseDate*(raw: string): Result[Date, ValidationError] =
  ## Structural validation of an RFC 3339 date-time string.
  ## Does NOT perform calendar validation (e.g., February 30) or
  ## validate timezone offset format beyond uppercase checks.
  if raw.len < 20:
    return err(validationError("Date", "too short for RFC 3339 date-time", raw))
  ?validateDatePortion(raw)
  ?validateTimePortion(raw)
  ?validateFractionalSeconds(raw)
  ?validateTimezoneOffset(raw)
  ok(Date(raw))

func parseUtcDate*(raw: string): Result[UTCDate, ValidationError] =
  ## All Date validation rules, plus: must end with 'Z'.
  let dateResult = parseDate(raw)
  if dateResult.isErr:
    return err(dateResult.error)
  if raw[^1] != 'Z':
    return err(validationError("UTCDate", "time-offset must be 'Z'", raw))
  ok(UTCDate(raw))
