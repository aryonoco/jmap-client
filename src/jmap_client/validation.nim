# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared validation infrastructure — error type, borrow templates, charset
## constants, and Result helpers used by all smart constructors.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/sequtils
import std/sets

import results
export results

template ruleOff*(name: string) {.pragma.}
  ## Suppresses a nimalyzer rule for subsequent declarations until ruleOn.

template ruleOn*(name: string) {.pragma.}
  ## Re-enables a nimalyzer rule previously suppressed by ruleOff.

type ValidationError* = object
  ## Structured error carrying the type name, failure reason, and raw input.
  ## Returned on the error rail by all smart constructors on invalid input.
  typeName*: string ## Which type failed ("Id", "UnsignedInt", etc.)
  message*: string ## The failure reason
  value*: string ## The raw input that failed validation

func validationError*(typeName, message, value: string): ValidationError =
  ## Constructs a ValidationError value for use on the error rail.
  return ValidationError(typeName: typeName, message: message, value: value)

template defineStringDistinctOps*(T: typedesc) =
  ## Borrows standard operations for a ``distinct string`` type: equality,
  ## stringification, hashing, and length.
  func `==`*(a, b: T): bool {.borrow.}
    ## Equality comparison delegated to the underlying string.
  func `$`*(a: T): string {.borrow.}
    ## String representation delegated to the underlying string.
  func hash*(a: T): Hash {.borrow.} ## Hash delegated to the underlying string.
  func len*(a: T): int {.borrow.} ## Length delegated to the underlying string.

template defineIntDistinctOps*(T: typedesc) =
  ## Borrows standard operations for a ``distinct int`` type: equality,
  ## ordering, stringification, and hashing.
  func `==`*(a, b: T): bool {.borrow.}
    ## Equality comparison delegated to the underlying integer.
  func `<`*(a, b: T): bool {.borrow.}
    ## Less-than comparison delegated to the underlying integer.
  func `<=`*(a, b: T): bool {.borrow.}
    ## Less-or-equal comparison delegated to the underlying integer.
  func `$`*(a: T): string {.borrow.}
    ## String representation delegated to the underlying integer.
  func hash*(a: T): Hash {.borrow.} ## Hash delegated to the underlying integer.

template defineHashSetDistinctOps*(T: typedesc, E: typedesc) =
  ## Borrows standard read-only operations for a ``distinct HashSet``
  ## type. ``T`` is the distinct type, ``E`` is the element type.
  ## No mutation operations — these are immutable read models (Decision B3).
  ## No ``==`` or ``hash`` — set equality is not a domain operation for
  ## these types; they are constructed once and queried, never compared
  ## as whole sets or used as table keys.
  func len*(s: T): int {.borrow.}
    ## Number of elements delegated to the underlying HashSet.
  func contains*(s: T, e: E): bool =
    ## Membership test delegated to the underlying HashSet.
    ## Cannot use ``{.borrow.}`` — Nim unwraps both distinct types, causing
    ## a type mismatch when ``E`` is itself distinct (e.g. Keyword = distinct string).
    sets.contains(HashSet[E](s), e)
  func card*(s: T): int {.borrow.} ## Cardinality delegated to the underlying HashSet.

template defineNonEmptyHashSetDistinctOps*(T, E: typedesc) =
  ## Creation-context hashset ops. Composes the read-model base template
  ## and adds the operations legitimate when the set is client-constructed
  ## and carries a non-empty invariant. Kept distinct from
  ## defineHashSetDistinctOps so Decision B3 (no ``==`` on read-model
  ## sets) is preserved for the base case; creation-context types opt in
  ## to the richer op set explicitly. ``hash`` is deliberately absent —
  ## stdlib ``HashSet.hash`` reads ``result`` before initialising it,
  ## which fails ``strictDefs`` + ``Uninit``-as-error under ``{.borrow.}``.
  ## The domain has no use for a non-empty mailbox-id set as a Table key.
  defineHashSetDistinctOps(T, E) # inherits: len, contains, card
  func `==`*(a, b: T): bool {.borrow.} ## Equality delegated to the underlying HashSet.
  func `$`*(a: T): string {.borrow.}
    ## String representation delegated to the underlying HashSet.
  iterator items*(s: T): E =
    ## Yields each element. Unwraps the distinct type to iterate the
    ## underlying HashSet.
    for e in HashSet[E](s):
      yield e

  iterator pairs*(s: T): (int, E) =
    ## Yields (index, element) tuples. HashSet ordering is not defined;
    ## the index is a monotonic enumeration counter, not a stable position.
    var i = 0
    for e in HashSet[E](s):
      yield (i, e)
      inc i

template duplicatesByIt(s: untyped, keyExpr: untyped): untyped =
  ## Unexported helper. Returns ``seq[K]`` containing every key
  ## ``keyExpr`` that appears more than once in ``s``, each key at most
  ## once, in order of first repeat (when the key first becomes a
  ## known duplicate).
  ##
  ## Template (not ``func``) so ``keyExpr`` expands inline and inherits
  ## the caller's ``{.push raises: [], noSideEffect.}`` — mirrors the
  ## ``std/sequtils.mapIt`` / ``filterIt`` / ``anyIt`` idiom. Uses two
  ## local ``HashSet``s (functional-core Pattern 7: imperative kernel,
  ## local mutation only); each element dispatches through
  ## ``containsOrIncl`` (Pattern 3 equivalent for ``HashSet``), which
  ## never raises.
  block:
    type K = typeof(
      block:
        var it {.inject.}: typeof(items(s), typeOfIter)
        keyExpr
    )

    var seen = initHashSet[K]()
    var reported = initHashSet[K]()
    var dups: seq[K] = @[]
    for it {.inject.} in s:
      let k = keyExpr
      if seen.containsOrIncl(k):
        if not reported.containsOrIncl(k):
          dups.add k
    dups

template validateUniqueByIt*(
    s: untyped, keyExpr: untyped, typeName, emptyMsg, dupMsg: string
): seq[ValidationError] =
  ## Accumulating uniqueness validator for smart constructors. Returns
  ## a ``seq[ValidationError]`` that is empty iff ``s`` is non-empty
  ## and all keys (as produced by ``keyExpr`` over the injected ``it``)
  ## are distinct. Otherwise:
  ##   * one ``emptyMsg`` error when ``s.len == 0``;
  ##   * one ``dupMsg`` error per distinct repeated key — three
  ##     occurrences of the same key yield exactly one error, naming
  ##     the key once.
  ## Sole translation boundary from the internal uniqueness
  ## classification to the wire ``ValidationError`` shape — callers
  ## supply the three wire strings at the call site rather than
  ## hand-building ``ValidationError`` inline.
  block:
    var errs: seq[ValidationError] = @[]
    if s.len == 0:
      errs.add validationError(typeName, emptyMsg, "")
    for k in duplicatesByIt(s, keyExpr):
      errs.add validationError(typeName, dupMsg, $k)
    errs

const Base64UrlChars* = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '-', '_'}
  ## Characters permitted in RFC 8620 §1.2 entity identifiers.

type TokenViolation* = enum
  ## Shared structural-failure vocabulary for every token-shaped identifier
  ## parser in this library (``Id``, ``AccountId``, ``JmapState``,
  ## ``MethodCallId``, ``CreationId``, ``Keyword``, ``MailboxRole``). Each
  ## variant maps to exactly one wire message at ``toValidationError``; the
  ## message lives in one place. Adding a variant forces a compile error at
  ## the translator, not at every detector.
  tvEmpty
  tvLengthOutOfRange
  tvControlChars
  tvNonPrintableAscii
  tvForbiddenChar
  tvNotBase64Url
  tvCreationIdPrefix

func toValidationError*(v: TokenViolation, typeName, raw: string): ValidationError =
  ## Sole domain-to-wire translator for ``TokenViolation``. ``typeName`` is
  ## caller-supplied so every parser across every module shares this one site
  ## while branding its own outer type name. Adding a ``TokenViolation``
  ## variant forces a compile error here.
  case v
  of tvEmpty:
    validationError(typeName, "must not be empty", raw)
  of tvLengthOutOfRange:
    validationError(typeName, "length must be 1-255 octets", raw)
  of tvControlChars:
    validationError(typeName, "contains control characters", raw)
  of tvNonPrintableAscii:
    validationError(typeName, "contains non-printable character", raw)
  of tvForbiddenChar:
    validationError(typeName, "contains forbidden character", raw)
  of tvNotBase64Url:
    validationError(typeName, "contains characters outside base64url alphabet", raw)
  of tvCreationIdPrefix:
    validationError(typeName, "must not include '#' prefix", raw)

# --- Atomic detectors -------------------------------------------------------

func detectNonEmpty*(raw: string): Result[void, TokenViolation] =
  ## Non-empty precondition. Exported because ``parseMethodCallId`` uses it
  ## directly — the sole single-atomic parser.
  if raw.len == 0:
    return err(tvEmpty)
  return ok()

func detectLengthInRange(
    raw: string, minLen, maxLen: int
): Result[void, TokenViolation] =
  ## Fires ``tvLengthOutOfRange`` when ``raw.len`` falls outside
  ## ``[minLen, maxLen]``. At the canonical (1, 255) bounds this covers BOTH
  ## empty input and overlong input with the single
  ## "length must be 1-255 octets" wire message — matching the existing
  ## ``parseId`` / ``parseAccountId`` / ``parseKeyword`` contract.
  if raw.len < minLen or raw.len > maxLen:
    return err(tvLengthOutOfRange)
  return ok()

func detectNoControlChars(raw: string): Result[void, TokenViolation] =
  ## Rejects bytes below SP (0x20) and DEL (0x7F).
  if raw.anyIt(it < ' ' or it == '\x7F'):
    return err(tvControlChars)
  return ok()

func detectPrintableAscii(raw: string): Result[void, TokenViolation] =
  ## Restricts to printable ASCII (0x21..0x7E).
  if not raw.allIt(it >= '!' and it <= '~'):
    return err(tvNonPrintableAscii)
  return ok()

func detectNoForbiddenChar(
    raw: string, forbidden: set[char]
): Result[void, TokenViolation] =
  ## Rejects any byte in ``forbidden``. Caller supplies the per-type set
  ## (e.g., ``KeywordForbiddenChars`` for ``parseKeyword``).
  if raw.anyIt(it in forbidden):
    return err(tvForbiddenChar)
  return ok()

func detectBase64UrlAlphabet(raw: string): Result[void, TokenViolation] =
  ## Restricts to RFC 8620 §1.2 base64url characters.
  if not raw.allIt(it in Base64UrlChars):
    return err(tvNotBase64Url)
  return ok()

func detectNoCreationIdPrefix(raw: string): Result[void, TokenViolation] =
  ## Rejects leading '#' — the wire-format prefix is applied at serialisation,
  ## so interior ``CreationId`` values must not carry it.
  if raw.len > 0 and raw[0] == '#':
    return err(tvCreationIdPrefix)
  return ok()

# --- Composite detectors (name the per-parser policies) --------------------

func detectLenientToken*(raw: string): Result[void, TokenViolation] =
  ## 1..255 octets, no control characters. For server-assigned tokens that
  ## may deviate from strict charset rules (Postel's law). Consumed by
  ## ``parseAccountId``, ``parseIdFromServer``, ``parseKeywordFromServer``.
  ?detectLengthInRange(raw, 1, 255)
  ?detectNoControlChars(raw)
  return ok()

func detectNonControlString*(raw: string): Result[void, TokenViolation] =
  ## Non-empty, no control characters, no upper length bound. Consumed by
  ## ``parseJmapState`` and ``parseMailboxRole`` pre-classification.
  ?detectNonEmpty(raw)
  ?detectNoControlChars(raw)
  return ok()

func detectStrictBase64UrlToken*(raw: string): Result[void, TokenViolation] =
  ## 1..255 octets, RFC 8620 §1.2 base64url alphabet. Consumed by ``parseId``.
  ?detectLengthInRange(raw, 1, 255)
  ?detectBase64UrlAlphabet(raw)
  return ok()

func detectStrictPrintableToken*(
    raw: string, forbidden: set[char]
): Result[void, TokenViolation] =
  ## 1..255 octets, printable ASCII (0x21..0x7E), no ``forbidden`` bytes.
  ## Consumed by ``parseKeyword`` with ``KeywordForbiddenChars``.
  ?detectLengthInRange(raw, 1, 255)
  ?detectPrintableAscii(raw)
  ?detectNoForbiddenChar(raw, forbidden)
  return ok()

func detectNonEmptyNoPrefix*(raw: string): Result[void, TokenViolation] =
  ## Non-empty, no '#' prefix. Consumed by ``parseCreationId``.
  ?detectNonEmpty(raw)
  ?detectNoCreationIdPrefix(raw)
  return ok()
