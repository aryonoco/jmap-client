# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## RFC 8620 primitive types with smart constructors enforcing wire-format
## constraints. Bounded to JSON-safe integer ranges (2^53-1) per the JMAP
## specification.

{.push raises: [], noSideEffect.}

import std/hashes
import std/sequtils

import ./validation

type Id* = distinct string
  ## JMAP identifier: 1-255 octets, base64url charset (RFC 8620 §1.2).
  ## Requires explicit construction via parseId or parseIdFromServer.

defineStringDistinctOps(Id)

type UnsignedInt* = distinct int64
  ## Non-negative integer bounded to 0..2^53-1 for JSON interoperability
  ## (RFC 8620 §1.3).

defineIntDistinctOps(UnsignedInt)

type JmapInt* = distinct int64
  ## Signed integer bounded to -(2^53-1)..2^53-1 for JSON interoperability
  ## (RFC 8620 §1.3).

defineIntDistinctOps(JmapInt)
func `-`*(a: JmapInt): JmapInt {.borrow.} ## unary negation

type Date* = distinct string
  ## RFC 3339 date-time string with structural validation but no calendar
  ## semantics.

defineStringDistinctOps(Date)

type UTCDate* = distinct string
  ## RFC 3339 date-time that must use 'Z' (UTC) as its timezone offset.

defineStringDistinctOps(UTCDate)

type MaxChanges* = distinct UnsignedInt
  ## A positive count for maxChanges fields in Foo/changes and
  ## Foo/queryChanges requests. RFC 8620 §5.2 (lines 1694–1702)
  ## requires the value to be greater than 0.

defineIntDistinctOps(MaxChanges)

const MaxUnsignedInt*: int64 = 9_007_199_254_740_991'i64 ## 2^53 - 1

const
  MinJmapInt*: int64 = -9_007_199_254_740_991'i64 ## -(2^53 - 1)
  MaxJmapInt*: int64 = 9_007_199_254_740_991'i64 ## 2^53 - 1

const AsciiDigits = {'0' .. '9'}

func allDigits(raw: string, first, last: Natural): bool =
  ## Checks that raw[first..last] are all ASCII digits.
  if last >= raw.len:
    return false
  # min(last, raw.high) gives the prover a direct upper-bound proof
  for i in first .. min(last, raw.high):
    if raw[i] notin AsciiDigits:
      return false
  return true

func parseId*(raw: string): Result[Id, ValidationError] =
  ## Strict: 1-255 octets, base64url charset only.
  ## For client-constructed IDs (e.g., method call IDs used as creation IDs).
  if raw.len < 1 or raw.len > 255:
    return err(validationError("Id", "length must be 1-255 octets", raw))
  if not raw.allIt(it in Base64UrlChars):
    return
      err(validationError("Id", "contains characters outside base64url alphabet", raw))
  return ok(Id(raw))

func parseIdFromServer*(raw: string): Result[Id, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## For server-assigned IDs in responses. Tolerates servers that deviate
  ## from the strict base64url charset (e.g., Cyrus IMAP).
  ?validateServerAssignedToken("Id", raw)
  return ok(Id(raw))

func parseUnsignedInt*(value: int64): Result[UnsignedInt, ValidationError] =
  ## Must be 0..2^53-1. Prevents negative values and integers outside JSON's
  ## safe range.
  if value < 0:
    return err(validationError("UnsignedInt", "must be non-negative", $value))
  if value > MaxUnsignedInt:
    return err(validationError("UnsignedInt", "exceeds 2^53-1", $value))
  return ok(UnsignedInt(value))

func parseJmapInt*(value: int64): Result[JmapInt, ValidationError] =
  ## Must be -(2^53-1)..2^53-1. Rejects values outside JSON's safe integer
  ## range.
  if value < MinJmapInt or value > MaxJmapInt:
    return err(validationError("JmapInt", "outside JSON-safe integer range", $value))
  return ok(JmapInt(value))

func parseMaxChanges*(raw: UnsignedInt): Result[MaxChanges, ValidationError] =
  ## Smart constructor: rejects 0, which the RFC forbids.
  if int64(raw) == 0:
    return err(validationError("MaxChanges", "must be greater than 0", $int64(raw)))
  return ok(MaxChanges(raw))

func validateDatePortion(raw: string): Result[void, ValidationError] =
  ## YYYY-MM-DD at positions 0..9.
  if raw.len < 10:
    return err(validationError("Date", "invalid date portion", raw))
  elif not (
    allDigits(raw, 0, 3) and raw[4] == '-' and allDigits(raw, 5, 6) and raw[7] == '-' and
    allDigits(raw, 8, 9)
  ):
    return err(validationError("Date", "invalid date portion", raw))
  return ok()

func validateTimePortion(raw: string): Result[void, ValidationError] =
  ## HH:MM:SS at positions 11..18, with uppercase 'T' separator at 10.
  if raw.len < 19:
    return err(validationError("Date", "invalid time portion", raw))
  elif raw[10] != 'T':
    return err(validationError("Date", "'T' separator must be uppercase", raw))
  elif not (
    allDigits(raw, 11, 12) and raw[13] == ':' and allDigits(raw, 14, 15) and
    raw[16] == ':' and allDigits(raw, 17, 18)
  ):
    return err(validationError("Date", "invalid time portion", raw))
  elif raw.anyIt(it in {'t', 'z'}):
    return err(validationError("Date", "'T' and 'Z' must be uppercase (RFC 3339)", raw))
  return ok()

func validateFractionalSeconds(raw: string): Result[void, ValidationError] =
  ## If a '.' follows position 19, digits must follow and not all be zero.
  if raw.len > 19:
    if raw[19] == '.':
      var dotEnd = 20
      while dotEnd < raw.len:
        if raw[dotEnd] notin AsciiDigits:
          break
        inc dotEnd
      if dotEnd == 20:
        return err(
          validationError(
            "Date", "fractional seconds must contain at least one digit", raw
          )
        )
      var allZero = true
      for i in 20 ..< min(dotEnd, raw.len):
        if raw[i] != '0':
          allZero = false
          break
      if allZero:
        return
          err(validationError("Date", "zero fractional seconds must be omitted", raw))
  return ok()

func offsetStart(raw: string): Natural =
  ## Returns the position where the timezone offset begins (after fractional
  ## seconds, if any).
  if raw.len <= 19:
    return 19
  elif raw[19] != '.':
    return 19
  var pos: Natural = 20
  while pos < raw.len:
    if raw[pos] notin AsciiDigits:
      break
    inc pos
  return pos

func isValidNumericOffset(raw: string, pos: Natural): bool =
  ## Checks that raw[pos..pos+5] matches +HH:MM or -HH:MM structurally.
  if pos + 6 != raw.len:
    return false
  # min(pos + 5, raw.high) gives the prover a direct upper-bound proof;
  # Natural pos gives the lower-bound proof (pos + 1 >= 1 >= 0).
  for i in (pos + 1) .. min(pos + 5, raw.high):
    let ch = raw[i]
    if i == pos + 3:
      if ch != ':':
        return false
    else:
      if ch notin AsciiDigits:
        return false
  return true

func validateTimezoneOffset(raw: string): Result[void, ValidationError] =
  ## Validates timezone offset after seconds and optional fractional seconds.
  ## Must be 'Z' or '+HH:MM' or '-HH:MM'.
  let pos = offsetStart(raw)
  if pos >= raw.len:
    return err(validationError("Date", "missing timezone offset", raw))
  elif raw[pos] == 'Z':
    if pos + 1 != raw.len:
      return err(validationError("Date", "trailing characters after 'Z'", raw))
    return ok()
  elif raw[pos] notin {'+', '-'} or not isValidNumericOffset(raw, pos):
    return
      err(validationError("Date", "timezone offset must be 'Z' or '+/-HH:MM'", raw))
  return ok()

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
  return ok(Date(raw))

func parseUtcDate*(raw: string): Result[UTCDate, ValidationError] =
  ## All Date validation rules, plus: must end with 'Z'.
  discard ?parseDate(raw)
  if raw.len < 20:
    return err(validationError("UTCDate", "too short for RFC 3339 date-time", raw))
  elif raw[^1] != 'Z':
    return err(validationError("UTCDate", "time-offset must be 'Z'", raw))
  return ok(UTCDate(raw))

# =============================================================================
# NonEmptySeq[T]
# =============================================================================

type NonEmptySeq*[T] = distinct seq[T]
  ## A sequence guaranteed to contain at least one element. Construction is
  ## gated by parseNonEmptySeq; mutating operations (add, setLen, del) are
  ## deliberately not borrowed to preserve the non-empty invariant at the
  ## type level (Part E §4.6).

template defineNonEmptySeqOps*(T: typedesc) =
  ## Borrows the read-only operations legitimate for NonEmptySeq[T].
  ## Mirrors defineStringDistinctOps / defineHashSetDistinctOps: each
  ## element type T invokes this template once. Mutating ops intentionally
  ## absent — they would violate the non-empty invariant.
  func `==`*(a, b: NonEmptySeq[T]): bool {.borrow.}
    ## Equality delegated to the underlying seq.
  func `$`*(a: NonEmptySeq[T]): string {.borrow.}
    ## String representation delegated to the underlying seq.
  func hash*(a: NonEmptySeq[T]): Hash {.borrow.} ## Hash delegated to the underlying seq.
  func len*(a: NonEmptySeq[T]): int {.borrow.}
    ## Length delegated to the underlying seq (always at least 1).
  func `[]`*(a: NonEmptySeq[T], i: Natural): lent T =
    ## Indexed access; explicit unwrap because ``seq[T].[]`` is the compiler
    ## magic ``ArrGet`` (system.nim) whose declared signature uses ``T`` for
    ## the container, which ``{.borrow.}`` cannot reconcile with the
    ## element-``T`` here. Same workaround as ``defineHashSetDistinctOps``'s
    ## explicit-body ``contains`` (validation.nim).
    seq[T](a)[i]
  func contains*(a: NonEmptySeq[T], x: T): bool =
    ## Membership test; explicit body because ``{.borrow.}`` unwraps both
    ## distinct types — when ``T`` is itself distinct (e.g. ``Date``), the
    ## borrow's ``x`` collapses to the underlying type and the call no
    ## longer matches ``seq[T].contains``. Same workaround as
    ## ``defineHashSetDistinctOps``'s ``contains`` (validation.nim).
    system.contains(seq[T](a), x)
  iterator items*(a: NonEmptySeq[T]): T =
    ## Yields each element. Unwraps the distinct type to iterate the
    ## underlying seq.
    for x in seq[T](a):
      yield x

  iterator pairs*(a: NonEmptySeq[T]): (int, T) =
    ## Yields (index, element) tuples. Order matches the underlying seq.
    for p in pairs(seq[T](a)):
      yield p

func parseNonEmptySeq*[T](s: seq[T]): Result[NonEmptySeq[T], ValidationError] =
  ## Strict: rejects empty input on the error rail. The typeName field on
  ## the returned ValidationError is "NonEmptySeq" (not parametrised on T,
  ## matching the codebase convention for identifying the failing distinct
  ## type family).
  if s.len == 0:
    return err(validationError("NonEmptySeq", "must not be empty", ""))
  return ok(NonEmptySeq[T](s))
