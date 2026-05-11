# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## RFC 8620 primitive types with smart constructors enforcing wire-format
## constraints. Bounded to JSON-safe integer ranges (2^53-1) per the JMAP
## specification.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

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

func allDigits(raw: string, first, last: Idx): bool =
  ## Checks that raw[first..last] are all ASCII digits. ``Idx`` operands
  ## make non-negativity a type-level invariant — callers prove
  ## ``0 <= first <= last`` at construction (compile-time via ``idx(...)``
  ## or runtime via ``parseIdx``).
  if last >= raw.len:
    return false
  for i in first.toInt .. min(last.toInt, raw.high):
    if raw[i] notin AsciiDigits:
      return false
  return true

func parseId*(raw: string): Result[Id, ValidationError] =
  ## Strict: 1-255 octets, base64url charset only.
  ## For client-constructed IDs (e.g., method call IDs used as creation IDs).
  detectStrictBase64UrlToken(raw).isOkOr:
    return err(toValidationError(error, "Id", raw))
  return ok(Id(raw))

func parseIdFromServer*(raw: string): Result[Id, ValidationError] =
  ## Lenient: 1-255 octets, no control characters.
  ## For server-assigned IDs in responses. Tolerates servers that deviate
  ## from the strict base64url charset (e.g., Cyrus IMAP).
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "Id", raw))
  return ok(Id(raw))

func parseFromString*(T: typedesc[Id], raw: string): Result[Id, ValidationError] =
  ## ``parseFromString`` typedesc-overload adapter consumed by the generic
  ## ``Table[K, V].fromJson`` in ``serialisation/serde.nim``. Delegates to
  ## ``parseIdFromServer`` — server-assigned ``Id`` keys take the lenient
  ## path on the receive side (Postel's law).
  discard $T
  return parseIdFromServer(raw)

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

type DateViolation = enum
  ## Structural failures of an RFC 3339 date-time string. Module-private;
  ## the public parsers translate these to ``ValidationError`` at the
  ## wire boundary (``toValidationError``) so every failure message
  ## lives in exactly one place and adding a variant forces a compile
  ## error at the translator, not at every detector.
  dvTooShort
  dvBadDatePortion
  dvLowercaseT
  dvBadTimePortion
  dvLowercaseTOrZ
  dvEmptyFraction
  dvZeroFraction
  dvMissingOffset
  dvTrailingAfterZ
  dvBadNumericOffset
  dvRequiresZ

func detectDatePortion(raw: string): Result[void, DateViolation] =
  ## YYYY-MM-DD at positions 0..9. Precondition: raw.len >= 20
  ## (enforced by detectDate before this detector is reached).
  if not (
    allDigits(raw, idx(0), idx(3)) and raw[4] == '-' and allDigits(raw, idx(5), idx(6)) and
    raw[7] == '-' and allDigits(raw, idx(8), idx(9))
  ):
    return err(dvBadDatePortion)
  return ok()

func detectTimePortion(raw: string): Result[void, DateViolation] =
  ## HH:MM:SS at positions 11..18, with uppercase 'T' separator at 10.
  ## Precondition: raw.len >= 20 (enforced by detectDate).
  if raw[10] != 'T':
    return err(dvLowercaseT)
  elif not (
    allDigits(raw, idx(11), idx(12)) and raw[13] == ':' and
    allDigits(raw, idx(14), idx(15)) and raw[16] == ':' and
    allDigits(raw, idx(17), idx(18))
  ):
    return err(dvBadTimePortion)
  elif raw.anyIt(it in {'t', 'z'}):
    return err(dvLowercaseTOrZ)
  return ok()

func detectFractionalSeconds(raw: string): Result[void, DateViolation] =
  ## If a '.' follows position 19, digits must follow and not all be zero.
  if raw.len > 19:
    if raw[19] == '.':
      var dotEnd = 20
      while dotEnd < raw.len:
        if raw[dotEnd] notin AsciiDigits:
          break
        inc dotEnd
      if dotEnd == 20:
        return err(dvEmptyFraction)
      var allZero = true
      for i in 20 ..< min(dotEnd, raw.len):
        if raw[i] != '0':
          allZero = false
          break
      if allZero:
        return err(dvZeroFraction)
  return ok()

func offsetStart(raw: string): Idx =
  ## Returns the position where the timezone offset begins (after fractional
  ## seconds, if any). ``Idx`` return type makes non-negativity a type-level
  ## invariant for every caller.
  if raw.len <= 19:
    return idx(19)
  elif raw[19] != '.':
    return idx(19)
  var pos: Idx = idx(20)
  while pos < raw.len:
    if raw[pos.toInt] notin AsciiDigits:
      break
    pos = pos.succ
  return pos

func isValidNumericOffset(raw: string, pos: Idx): bool =
  ## Checks that raw[pos..pos+5] matches +HH:MM or -HH:MM structurally.
  ## ``Idx`` signature makes non-negativity a type-level invariant; the
  ## ``let p = pos.toInt`` projection is zero-cost and the subsequent
  ## arithmetic stays in ``int`` for idiomatic stdlib interop.
  let p = pos.toInt
  if p + 6 != raw.len:
    return false
  for i in (p + 1) .. min(p + 5, raw.high):
    let ch = raw[i]
    if i == p + 3:
      if ch != ':':
        return false
    else:
      if ch notin AsciiDigits:
        return false
  return true

func detectTimezoneOffset(raw: string): Result[void, DateViolation] =
  ## Validates timezone offset after seconds and optional fractional seconds.
  ## Must be 'Z' or '+HH:MM' or '-HH:MM'.
  let pos = offsetStart(raw)
  if pos >= raw.len:
    return err(dvMissingOffset)
  elif raw[pos.toInt] == 'Z':
    if pos + idx(1) != raw.len:
      return err(dvTrailingAfterZ)
    return ok()
  elif raw[pos.toInt] notin {'+', '-'} or not isValidNumericOffset(raw, pos):
    return err(dvBadNumericOffset)
  return ok()

func detectDate(raw: string): Result[void, DateViolation] =
  ## Composes the four structural sub-detectors. ``?`` short-circuits
  ## on the first violation, mirroring the existing contract.
  if raw.len < 20:
    return err(dvTooShort)
  ?detectDatePortion(raw)
  ?detectTimePortion(raw)
  ?detectFractionalSeconds(raw)
  ?detectTimezoneOffset(raw)
  return ok()

func detectUtcDate(raw: string): Result[void, DateViolation] =
  ## Composes ``detectDate`` with the UTCDate-specific Z narrowing.
  ## Precondition after ``?detectDate``: raw.len >= 20 and the offset
  ## parses; RFC 8620 §1.4 narrows that offset to the literal 'Z'.
  ?detectDate(raw)
  if raw[^1] != 'Z':
    return err(dvRequiresZ)
  return ok()

func toValidationError(v: DateViolation, typeName, raw: string): ValidationError =
  ## Sole domain-to-wire translator. ``typeName`` is caller-supplied so
  ## ``parseDate`` and ``parseUtcDate`` share the translator while each
  ## reports its own outer type name — closing the pre-existing leak
  ## where UTCDate failures in the shared path surfaced as
  ## ``typeName="Date"``.
  case v
  of dvTooShort:
    validationError(typeName, "too short for RFC 3339 date-time", raw)
  of dvBadDatePortion:
    validationError(typeName, "invalid date portion", raw)
  of dvLowercaseT:
    validationError(typeName, "'T' separator must be uppercase", raw)
  of dvBadTimePortion:
    validationError(typeName, "invalid time portion", raw)
  of dvLowercaseTOrZ:
    validationError(typeName, "'T' and 'Z' must be uppercase (RFC 3339)", raw)
  of dvEmptyFraction:
    validationError(typeName, "fractional seconds must contain at least one digit", raw)
  of dvZeroFraction:
    validationError(typeName, "zero fractional seconds must be omitted", raw)
  of dvMissingOffset:
    validationError(typeName, "missing timezone offset", raw)
  of dvTrailingAfterZ:
    validationError(typeName, "trailing characters after 'Z'", raw)
  of dvBadNumericOffset:
    validationError(typeName, "timezone offset must be 'Z' or '+/-HH:MM'", raw)
  of dvRequiresZ:
    validationError(typeName, "time-offset must be 'Z'", raw)

func parseDate*(raw: string): Result[Date, ValidationError] =
  ## Structural validation of an RFC 3339 date-time string.
  ## Does NOT perform calendar validation (e.g., February 30) or
  ## validate timezone offset format beyond uppercase checks.
  detectDate(raw).isOkOr:
    return err(toValidationError(error, "Date", raw))
  return ok(Date(raw))

func parseUtcDate*(raw: string): Result[UTCDate, ValidationError] =
  ## All Date validation rules, plus: must end with 'Z'. Shares
  ## ``detectDate`` with ``parseDate`` via the translator's
  ## caller-supplied ``typeName``, so UTCDate failures never leak the
  ## ``Date`` typeName as they did before the ADT refactor.
  detectUtcDate(raw).isOkOr:
    return err(toValidationError(error, "UTCDate", raw))
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
  func `[]`*(a: NonEmptySeq[T], i: Idx): lent T =
    ## Indexed access via sealed non-negative ``Idx``. Explicit unwrap
    ## because ``seq[T].[]`` is the compiler magic ``ArrGet`` (system.nim)
    ## whose declared signature uses ``T`` for the container, which
    ## ``{.borrow.}`` cannot reconcile with the element-``T`` here.
    ## Upper-bound violations still panic via the underlying seq's
    ## ``IndexDefect``; the ``Idx`` invariant statically rules out the
    ## negative-``i`` case.
    seq[T](a)[i.toInt]
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

func head*[T](a: NonEmptySeq[T]): lent T =
  ## First element — guaranteed present by the non-empty invariant.
  ## Semantic accessor that reads cleaner than ``a[idx(0)]``; no
  ## per-``T`` template instantiation required because ``T`` is
  ## inferrable from the argument.
  seq[T](a)[0]
