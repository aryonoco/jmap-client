# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

import std/hashes
import std/sequtils

import pkg/results

import ./validation

type Id* {.requiresInit.} = distinct string

defineStringDistinctOps(Id)

type UnsignedInt* {.requiresInit.} = distinct int64

defineIntDistinctOps(UnsignedInt)

type JmapInt* {.requiresInit.} = distinct int64

defineIntDistinctOps(JmapInt)
func `-`*(a: JmapInt): JmapInt {.borrow.} ## unary negation

type Date* {.requiresInit.} = distinct string

defineStringDistinctOps(Date)

type UTCDate* {.requiresInit.} = distinct string

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
  if raw.anyIt(it < ' '):
    return err(validationError("Id", "contains control characters", raw))
  ok(Id(raw))

func parseUnsignedInt*(value: int64): Result[UnsignedInt, ValidationError] =
  if value < 0:
    return err(validationError("UnsignedInt", "must be non-negative", $value))
  if value > MaxUnsignedInt:
    return err(validationError("UnsignedInt", "exceeds 2^53-1", $value))
  ok(UnsignedInt(value))

func parseJmapInt*(value: int64): Result[JmapInt, ValidationError] =
  if value < MinJmapInt or value > MaxJmapInt:
    return err(validationError("JmapInt", "outside JSON-safe integer range", $value))
  ok(JmapInt(value))

func parseDate*(raw: string): Result[Date, ValidationError] =
  ## Pattern validates RFC 3339 date-time structural constraints:
  ## - Minimum length (YYYY-MM-DDTHH:MM:SSZ = 20 chars)
  ## - 'T' separator present and uppercase
  ## - No lowercase 't' or 'z'
  ## - If fractional seconds present, must not be all zeroes
  ## Does NOT perform full calendar validation (e.g., February 30).
  ## Does NOT validate the timezone offset format beyond uppercase checks.
  if raw.len < 20:
    return err(validationError("Date", "too short for RFC 3339 date-time", raw))
  # Check date part: YYYY-MM-DD
  if not (
    raw[0 .. 3].allIt(it in AsciiDigits) and raw[4] == '-' and
    raw[5 .. 6].allIt(it in AsciiDigits) and raw[7] == '-' and
    raw[8 .. 9].allIt(it in AsciiDigits)
  ):
    return err(validationError("Date", "invalid date portion", raw))
  # Check 'T' separator
  if raw[10] != 'T':
    return err(validationError("Date", "'T' separator must be uppercase", raw))
  # Check time part: HH:MM:SS
  if not (
    raw[11 .. 12].allIt(it in AsciiDigits) and raw[13] == ':' and
    raw[14 .. 15].allIt(it in AsciiDigits) and raw[16] == ':' and
    raw[17 .. 18].allIt(it in AsciiDigits)
  ):
    return err(validationError("Date", "invalid time portion", raw))
  # Check no lowercase 't' or 'z' (the only letters in RFC 3339 date-time are T and Z)
  if raw.anyIt(it in {'t', 'z'}):
    return err(validationError("Date", "'T' and 'Z' must be uppercase (RFC 3339)", raw))
  # Check fractional seconds: if present, must have at least one digit
  # and must not be all zeroes.
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
  ok(Date(raw))

func parseUtcDate*(raw: string): Result[UTCDate, ValidationError] =
  ## All Date validation rules, plus: must end with 'Z'.
  let dateResult = parseDate(raw)
  if dateResult.isErr:
    return err(dateResult.error)
  if raw[^1] != 'Z':
    return err(validationError("UTCDate", "time-offset must be 'Z'", raw))
  ok(UTCDate(raw))
