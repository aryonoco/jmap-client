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

template defineSealedStringOps*(T: typedesc) =
  ## Sealed-object string ops: equality, stringification, hashing, length.
  ## Companion to ``defineSealedOpaqueStringOps`` (no ``len``) — choose
  ## based on whether the underlying length is a meaningful domain quantity.
  func `==`*(a, b: T): bool =
    ## Equality delegated to the underlying string.
    a.rawValue == b.rawValue
  func `$`*(a: T): string =
    ## String representation — the underlying string verbatim.
    a.rawValue
  func hash*(a: T): Hash =
    ## Hash delegated to the underlying string.
    hash(a.rawValue)
  func len*(a: T): int =
    ## Length of the underlying string.
    a.rawValue.len

template defineSealedOpaqueStringOps*(T: typedesc) =
  ## Opaque-token string ops — equality, stringification, hashing. No
  ## ``len`` because the underlying string is a server-assigned token
  ## whose byte length carries no domain meaning. Used by ``JmapState``,
  ## ``MethodCallId``, ``CreationId``, ``BlobId``.
  func `==`*(a, b: T): bool =
    ## Equality delegated to the underlying string.
    a.rawValue == b.rawValue
  func `$`*(a: T): string =
    ## String representation — the underlying token verbatim.
    a.rawValue
  func hash*(a: T): Hash =
    ## Hash delegated to the underlying string.
    hash(a.rawValue)

template defineSealedIntOps*(T: typedesc) =
  ## Orderable integer-backed ops: equality, ``<``, ``<=``,
  ## stringification, hashing. Companion to ``defineSealedTagIntOps``
  ## (no ordering).
  func `==`*(a, b: T): bool =
    ## Equality delegated to the underlying integer.
    a.rawValue == b.rawValue
  func `<`*(a, b: T): bool =
    ## Less-than delegated to the underlying integer.
    a.rawValue < b.rawValue
  func `<=`*(a, b: T): bool =
    ## Less-or-equal delegated to the underlying integer.
    a.rawValue <= b.rawValue
  func `$`*(a: T): string =
    ## Decimal representation of the underlying integer.
    $a.rawValue
  func hash*(a: T): Hash =
    ## Hash delegated to the underlying integer.
    hash(a.rawValue)

template defineSealedTagIntOps*(T: typedesc) =
  ## Tag integer ops — equality, stringification, hashing. No ``<`` /
  ## ``<=`` because these values are categorical (e.g. RFC 3463 status
  ## code triples), not orderable. Used by ``ReplyCode``, ``SubjectCode``,
  ## ``DetailCode``.
  func `==`*(a, b: T): bool =
    ## Equality delegated to the underlying integer.
    a.rawValue == b.rawValue
  func `$`*(a: T): string =
    ## Decimal representation of the underlying integer.
    $a.rawValue
  func hash*(a: T): Hash =
    ## Hash delegated to the underlying integer.
    hash(a.rawValue)

template defineSealedHashSetOps*(T: typedesc, E: typedesc) =
  ## Read-only HashSet ops: ``len``, ``contains``, ``card``. ``T`` is the
  ## sealed object wrapping ``HashSet[E]``; the field is ``rawValue``. No
  ## ``==`` / ``hash`` — set equality is not a domain operation here;
  ## these sets are constructed once, queried, never compared as wholes.
  func len*(s: T): int =
    ## Number of elements in the underlying set.
    s.rawValue.len
  func contains*(s: T, e: E): bool =
    ## Membership test. ``sets.contains`` is named explicitly so the
    ## resolver picks the ``HashSet`` overload when ``E`` is itself a
    ## sealed object whose ``contains`` would otherwise win by overload
    ## proximity.
    sets.contains(s.rawValue, e)
  func card*(s: T): int =
    ## Cardinality of the underlying set.
    s.rawValue.card

template defineSealedNonEmptyHashSetOps*(T: typedesc, E: typedesc) =
  ## Creation-context HashSet ops: composes ``defineSealedHashSetOps``
  ## and adds ``==``, ``$``, ``items``, ``pairs`` for client-constructed
  ## sets carrying a non-empty invariant. ``hash`` is deliberately
  ## absent — stdlib ``HashSet.hash`` reads ``result`` before
  ## initialising it, which fails ``strictDefs`` + ``Uninit``-as-error.
  defineSealedHashSetOps(T, E)
  func `==`*(a, b: T): bool =
    ## Equality delegated to the underlying set.
    a.rawValue == b.rawValue
  func `$`*(a: T): string =
    ## String representation delegated to the underlying set.
    $a.rawValue
  iterator items*(s: T): E =
    ## Yields each element. Iteration order matches the underlying
    ## ``HashSet`` order (which is undefined).
    for e in s.rawValue:
      yield e

  iterator pairs*(s: T): (int, E) =
    ## Yields ``(index, element)`` tuples. The index is a monotonic
    ## enumeration counter, not a stable position — ``HashSet`` has no
    ## defined order.
    var i = 0
    for e in s.rawValue:
      yield (i, e)
      inc i

template defineSealedNonEmptySeqOps*(T: typedesc) =
  ## Sealed-object ops for ``NonEmptySeq[T]``: equality, stringification,
  ## hashing, length, indexed access, membership, iteration.
  ## Per-element-type instantiation, mirroring the old
  ## ``defineNonEmptySeqOps``. Mutating ops are deliberately absent —
  ## they would violate the non-empty invariant. The underlying seq is
  ## reached via ``toSeq`` (defined in ``primitives.nim``) so the
  ## template can expand outside the defining module of ``NonEmptySeq``.
  func `==`*(a, b: NonEmptySeq[T]): bool =
    ## Equality delegated to the underlying seq.
    asSeq(a) == asSeq(b)
  func `$`*(a: NonEmptySeq[T]): string =
    ## String representation delegated to the underlying seq.
    $asSeq(a)
  func hash*(a: NonEmptySeq[T]): Hash =
    ## Hash delegated to the underlying seq.
    hash(asSeq(a))
  func len*(a: NonEmptySeq[T]): int =
    ## Length of the underlying seq (always at least 1).
    asSeq(a).len
  func `[]`*(a: NonEmptySeq[T], i: Idx): lent T =
    ## Indexed access via sealed non-negative ``Idx``. Upper-bound
    ## violations panic via the underlying seq's ``IndexDefect``; the
    ## ``Idx`` invariant statically rules out the negative-``i`` case.
    asSeq(a)[i.toInt]
  func contains*(a: NonEmptySeq[T], x: T): bool =
    ## Membership test. ``system.contains`` is named explicitly to
    ## bypass distinct-type unwrapping when ``T`` is itself sealed.
    system.contains(asSeq(a), x)
  iterator items*(a: NonEmptySeq[T]): T =
    ## Yields each element in declaration order.
    for x in asSeq(a):
      yield x

  iterator pairs*(a: NonEmptySeq[T]): (int, T) =
    ## Yields ``(index, element)`` tuples in declaration order.
    for p in pairs(asSeq(a)):
      yield p

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

# =============================================================================
# Idx — sealed non-negative index type
# =============================================================================

type Idx* {.ruleOff: "objects".} = object
  ## Validated non-negative integer, used as an index into strings, seqs,
  ## and other ordered containers. Sealed Pattern-A object: the raw
  ## integer is module-private (``rawValue``); external code cannot
  ## bypass validation. Construction is sealed:
  ##   * ``idx(i: static[int])`` — compile-time, negative literals rejected
  ##     via the ``{.error.}`` pragma (a pragma, not ``doAssert`` — no
  ##     runtime code emitted, no panic path).
  ##   * ``parseIdx(raw: int)`` — runtime, negativity flows through the
  ##     Result error rail (not ``RangeDefect``).
  ## Replaces ``Natural`` at the domain layer per the project rule against
  ## ``range[T]`` for domain constraints (``nim-type-safety.md``).
  rawValue: int

defineSealedIntOps(Idx)

func unsafeMakeIdx(raw: int): Idx {.inline.} =
  ## Module-private wrap that bypasses validation. Sole producer used by
  ## ``idx`` (compile-time literals) and ``parseIdx`` (runtime checked).
  ## Hygienic templates carry symbols bound at definition site, so
  ## ``idx(static[int])`` can call this from any module without exposing
  ## the unchecked path.
  Idx(rawValue: raw)

func toInt*(i: Idx): int {.inline.} =
  ## Projection to raw ``int``. Total, zero-cost.
  i.rawValue

func toNatural*(i: Idx): Natural {.inline.} =
  ## Projection to ``Natural`` at stdlib API boundaries that still declare
  ## ``Natural`` (``newStringOfCap``, ``strutils.find(start=...)``). The
  ## ``Idx`` invariant guarantees ``i.rawValue >= 0``; the compiler-inserted
  ## range check at the conversion is therefore a statically unreachable
  ## backstop, not a correctness-load-bearing check.
  Natural(i.rawValue)

func `+`*(a, b: Idx): Idx {.inline.} =
  ## Invariant-preserving sum. Two non-negative operands ⇒ non-negative
  ## result. Deliberately no ``Idx - Idx`` (could underflow) and no
  ## ``Idx + int`` (right operand unsafe); callers needing those route
  ## through ``parseIdx`` and take the error-rail hit.
  unsafeMakeIdx(a.rawValue + b.rawValue)

func succ*(i: Idx): Idx {.inline.} =
  ## Successor — equivalent to ``i + idx(1)``.
  unsafeMakeIdx(i.rawValue + 1)

func `<`*(a: Idx, b: int): bool {.inline.} =
  ## Read-only mixed comparison. No path smuggles a negative ``int``
  ## into ``Idx``; comparison against a raw ``int`` is one-way.
  a.rawValue < b

func `<=`*(a: Idx, b: int): bool {.inline.} =
  ## Read-only mixed less-or-equal; see ``<(Idx, int)`` for rationale.
  a.rawValue <= b

func `>=`*(a: Idx, b: int): bool {.inline.} =
  ## Read-only mixed greater-or-equal; see ``<(Idx, int)`` for rationale.
  a.rawValue >= b

func `>`*(a: Idx, b: int): bool {.inline.} =
  ## Read-only mixed greater-than; see ``<(Idx, int)`` for rationale.
  a.rawValue > b

func `==`*(a: Idx, b: int): bool {.inline.} =
  ## Read-only mixed equality; see ``<(Idx, int)`` for rationale.
  a.rawValue == b

func `+=`*(a: var Idx, b: Idx) {.inline.} =
  ## Compound addition. Both operands non-negative ⇒ result
  ## non-negative — invariant preserved by construction.
  a = unsafeMakeIdx(a.rawValue + b.rawValue)

template idx*(i: static[int]): Idx =
  ## Compile-time smart constructor. Negative literals are rejected at
  ## compilation via ``{.error.}`` — a pragma, not ``doAssert``. No
  ## runtime code is emitted and no panic path exists.
  when i < 0:
    {.error: "idx requires a non-negative literal; refactor or use parseIdx".}
  else:
    unsafeMakeIdx(i)

func parseIdx*(raw: int): Result[Idx, ValidationError] =
  ## Runtime smart constructor. Negativity surfaces on the Result error
  ## rail, consistent with ``parseUnsignedInt`` / ``parseJmapInt``.
  if raw < 0:
    return err(validationError("Idx", "must be non-negative", $raw))
  return ok(unsafeMakeIdx(raw))

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
