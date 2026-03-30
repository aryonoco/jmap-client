# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based testing infrastructure with fixed-seed reproducibility,
## edge-biased generation, and tiered trial counts.
##
## When adding a new generator gen<T>():
## 1. Cover valid edge cases in early trials (trial < N bias)
## 2. Cover the full valid input space for remaining trials
## 3. Add a docstring listing covered and NOT-covered cases
## 4. Add matching gen<Invalid><T>() if the type has validation
## 5. Register property tests in tests/property/tprop_<module>.nim

import std/json
import std/random
import std/sets
import std/strutils

import results

import jmap_client/capabilities
import jmap_client/envelope
import jmap_client/errors
import jmap_client/framework
import jmap_client/identifiers
import jmap_client/primitives
import jmap_client/session
import jmap_client/validation

{.push ruleOff: "hasDoc".}
{.push ruleOff: "params".}

# ---------------------------------------------------------------------------
# Trial count tiers
# ---------------------------------------------------------------------------

const QuickTrials* = 200
  ## For trivially cheap properties (totality checks, single-constructor).

const DefaultTrials* = 500 ## Standard property trial count.

const ThoroughTrials* = 2000 ## For properties with large input spaces (Date, Session).

const CriticalTrials* = 5000
  ## For high-assurance properties requiring extensive coverage.

# ---------------------------------------------------------------------------
# Property check templates
# ---------------------------------------------------------------------------

{.push ruleOff: "trystatements".}

template checkProperty*(name: string, body: untyped) =
  ## Runs body DefaultTrials times with an injected `rng` and `trial` variable.
  ## Fixed seed (42) ensures deterministic reproduction. On failure, re-raises
  ## with trial number for diagnostics.
  block:
    var rng {.inject.} = initRand(42)
    var lastInput {.inject.}: string = ""
    for trial {.inject.} in 0 ..< DefaultTrials:
      try:
        body
      except AssertionDefect as e:
        let ctx =
          name & " failed at trial " & $trial &
          (if lastInput.len > 0: " (input: " & lastInput & ")" else: "") & ": " & e.msg
        raiseAssert ctx

template checkPropertyN*(name: string, trials: int, body: untyped) =
  ## Runs body `trials` times. Use QuickTrials or ThoroughTrials for non-default
  ## counts. On failure, re-raises with trial number for diagnostics.
  block:
    var rng {.inject.} = initRand(42)
    var lastInput {.inject.}: string = ""
    for trial {.inject.} in 0 ..< trials:
      try:
        body
      except AssertionDefect as e:
        let ctx =
          name & " failed at trial " & $trial &
          (if lastInput.len > 0: " (input: " & lastInput & ")" else: "") & ": " & e.msg
        raiseAssert ctx

{.pop.} # trystatements

# ---------------------------------------------------------------------------
# Parameterised property templates (Phase 4E)
# ---------------------------------------------------------------------------

{.push ruleOff: "trystatements".}

template checkJsonRoundTrip*(
    name: string, trials: int, gen: untyped, eq: untyped, toJ: untyped, fromJ: untyped
) =
  ## Generic JSON round-trip property: fromJson(toJson(x)) == x.
  ## `gen` generates a value, `eq` compares two values, `toJ` serialises,
  ## `fromJ` deserialises. All four are called with the generated value or
  ## its serialised form.
  block:
    var rng {.inject.} = initRand(42)
    var lastInput {.inject.}: string = ""
    for trial {.inject.} in 0 ..< trials:
      try:
        let x = gen
        let j = toJ(x)
        let rt = fromJ(j)
        doAssert rt.isOk, name & ": round-trip parse failed"
        doAssert eq(rt.get(), x), name & ": round-trip identity violated"
      except AssertionDefect as e:
        let ctx =
          name & " failed at trial " & $trial &
          (if lastInput.len > 0: " (input: " & lastInput & ")" else: "") & ": " & e.msg
        raiseAssert ctx

template checkStability*(name: string, trials: int, gen: untyped, toJ: untyped) =
  ## Generic stability property: toJson(x) == toJson(x).
  ## Verifies that serialisation is deterministic (no hash-order jitter).
  block:
    var rng {.inject.} = initRand(42)
    var lastInput {.inject.}: string = ""
    for trial {.inject.} in 0 ..< trials:
      try:
        let x = gen
        let j1 = toJ(x)
        let j2 = toJ(x)
        doAssert j1 == j2, name & ": toJson is not stable"
      except AssertionDefect as e:
        let ctx =
          name & " failed at trial " & $trial &
          (if lastInput.len > 0: " (input: " & lastInput & ")" else: "") & ": " & e.msg
        raiseAssert ctx

{.pop.} # trystatements

# ---------------------------------------------------------------------------
# Composition helpers
# ---------------------------------------------------------------------------

proc oneOf*[T](rng: var Rand, options: openArray[T]): T =
  ## Picks a single element uniformly at random from a fixed set of values.
  options[rng.rand(0 .. options.high)]

proc genStringFrom*(rng: var Rand, chars: set[char], minLen = 1, maxLen = 20): string =
  ## Generates a string of random length (minLen..maxLen) where each character
  ## is drawn uniformly from the given character set.
  ## Does NOT bias toward: boundary lengths, specific characters within the set.
  let length = rng.rand(minLen .. maxLen)
  result = newString(length)
  # Convert set to seq for indexed access
  var charSeq: seq[char] = @[]
  for c in chars:
    charSeq.add c
  for i in 0 ..< length:
    result[i] = charSeq[rng.rand(0 .. charSeq.high)]

# ---------------------------------------------------------------------------
# Basic character generators
# ---------------------------------------------------------------------------

proc genBase64UrlChar*(rng: var Rand): char =
  ## Generates a single base64url character (A-Z, a-z, 0-9, '-', '_').
  ## Does NOT generate: padding '=', standard base64 '+' or '/', control chars.
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  chars[rng.rand(chars.high)]

proc genAsciiPrintable*(rng: var Rand): char =
  ## Generates a single ASCII printable character (0x20-0x7E, space through tilde).
  ## Does NOT generate: control characters (0x00-0x1F), DEL (0x7F), high bytes (0x80-0xFF).
  char(rng.rand(0x20 .. 0x7E))

proc genControlChar*(rng: var Rand): char =
  ## Generates a single control character from 0x00-0x1F or DEL (0x7F).
  ## Covers all 33 ASCII control characters uniformly.
  ## Does NOT generate: printable characters, high bytes.
  let i = rng.rand(0 .. 32) # 33 control chars total
  if i == 32:
    return '\x7F'
  char(i)

proc genArbitraryByte*(rng: var Rand): char =
  ## Generates a single arbitrary byte (0x00-0xFF) uniformly.
  ## Covers the full byte range including control chars, printable, and high bytes.
  char(rng.rand(0 .. 255))

# ---------------------------------------------------------------------------
# String generators (edge-biased)
# ---------------------------------------------------------------------------

proc genValidIdStrict*(
    rng: var Rand, trial: int = -1, minLen = 1, maxLen = 255
): string =
  ## Generates strings that pass strict Id validation (base64url, 1-255 octets).
  ## Early trials (< 4) cover boundary lengths (minLen, minLen+1, maxLen-1, maxLen).
  ## Remaining trials generate random lengths with random base64url characters.
  ## Does NOT generate: control characters, non-base64url characters, empty strings.
  let length =
    if trial >= 0 and trial < 4:
      let raw = [minLen, min(minLen + 1, maxLen), max(maxLen - 1, minLen), maxLen]
      raw[trial]
    else:
      rng.rand(minLen .. maxLen)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genBase64UrlChar()

proc genArbitraryString*(rng: var Rand, trial: int = -1, maxLen = 512): string =
  ## Generates arbitrary byte strings of 0-512 length for fuzz testing.
  ## Early trials (< 6) cover edge cases: empty, null byte, DEL, space,
  ## max-length (255), and over-length (256) strings.
  ## Remaining trials generate random-length strings with random bytes.
  ## Does NOT bias toward: specific character sets, valid identifiers.
  if trial >= 0 and trial < 6:
    let edges = ["", "\x00", "\x7F", " ", 'A'.repeat(255), 'A'.repeat(256)]
    return edges[trial]
  let length = rng.rand(0 .. maxLen)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genArbitraryByte()

# ---------------------------------------------------------------------------
# Integer generators (edge-biased)
# ---------------------------------------------------------------------------

const MaxUnsignedIntVal = 9_007_199_254_740_991'i64

proc genValidUnsignedInt*(rng: var Rand, trial: int = -1): int64 =
  ## Generates valid UnsignedInt values in 0..2^53-1 range.
  ## Early trials (< 4) cover boundaries: 0, 1, max-1, max.
  ## Remaining trials generate uniform random values across the full range.
  ## Does NOT generate: negative values, values exceeding 2^53-1.
  if trial >= 0 and trial < 4:
    return [0'i64, 1'i64, MaxUnsignedIntVal - 1, MaxUnsignedIntVal][trial]
  rng.rand(0'i64 .. MaxUnsignedIntVal)

proc genValidJmapInt*(rng: var Rand, trial: int = -1): int64 =
  ## Generates valid JmapInt values in -(2^53-1)..2^53-1 range.
  ## Early trials (< 7) cover boundaries: min, min+1, -1, 0, 1, max-1, max.
  ## Remaining trials generate uniform random values across the full range.
  ## Does NOT generate: values outside the safe integer range.
  if trial >= 0 and trial < 7:
    return [
      -MaxUnsignedIntVal,
      -MaxUnsignedIntVal + 1,
      -1'i64,
      0'i64,
      1'i64,
      MaxUnsignedIntVal - 1,
      MaxUnsignedIntVal,
    ][trial]
  rng.rand(-MaxUnsignedIntVal .. MaxUnsignedIntVal)

# ---------------------------------------------------------------------------
# Identifier generators (lenient charset)
# ---------------------------------------------------------------------------

proc genValidLenientString*(
    rng: var Rand, trial: int = -1, minLen = 1, maxLen = 255
): string =
  ## Generates printable ASCII strings (0x20-0x7E) for lenient identifier types
  ## (AccountId, JmapState, parseIdFromServer). No control characters.
  ## Early trials (< 4) cover boundary lengths clamped to [minLen, maxLen].
  ## Remaining trials generate random lengths with random printable characters.
  ## Does NOT generate: control characters, high bytes (0x80+), empty strings.
  let length =
    if trial >= 0 and trial < 4:
      let raw = [minLen, min(minLen + 1, maxLen), max(maxLen - 1, minLen), maxLen]
      raw[trial]
    else:
      rng.rand(minLen .. maxLen)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genAsciiPrintable()

proc genValidAccountId*(rng: var Rand, trial: int = -1): string =
  ## Generates valid AccountId strings: 1-255 printable ASCII octets (lenient charset).
  ## Early trials cover boundary lengths (1, 2, 254, 255).
  ## Does NOT generate: empty strings, strings with control characters, strings > 255.
  rng.genValidLenientString(trial, 1, 255)

proc genValidJmapState*(rng: var Rand, trial: int = -1): string =
  ## Generates valid JmapState strings: non-empty, no control characters, 1-500 octets.
  ## Early trials cover boundary lengths. No upper bound in the spec — uses a generous
  ## max to exercise longer tokens.
  ## Does NOT generate: empty strings, strings with control characters.
  rng.genValidLenientString(trial, 1, 500)

proc genValidMethodCallId*(rng: var Rand, trial: int = -1): string =
  ## Generates valid MethodCallId strings: non-empty, arbitrary bytes including
  ## control characters. MethodCallId has no charset restriction.
  ## Early trials (< 4) cover boundary lengths: 1, 2, 249, 500.
  ## Remaining trials generate random lengths (1-500) with random bytes.
  ## Does NOT generate: empty strings.
  let length =
    if trial >= 0 and trial < 4:
      [1, 2, 249, 500][trial]
    else:
      rng.rand(1 .. 500)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genArbitraryByte()

proc genValidCreationId*(rng: var Rand, trial: int = -1): string =
  ## Generates valid CreationId strings: non-empty, first character is not '#'.
  ## Remaining characters can be arbitrary bytes.
  ## Early trials (< 4) cover boundary lengths: 1, 2, 49, 50.
  ## Does NOT generate: empty strings, strings starting with '#'.
  let length =
    if trial >= 0 and trial < 4:
      [1, 2, 49, 50][trial]
    else:
      rng.rand(1 .. 50)
  result = newString(length)
  # First char: any byte except '#'
  result[0] = block:
    var c = rng.genArbitraryByte()
    while c == '#':
      c = rng.genArbitraryByte()
    c
  for i in 1 ..< length:
    result[i] = rng.genArbitraryByte()

proc genValidPropertyName*(rng: var Rand, trial: int = -1): string =
  ## Generates valid PropertyName strings: non-empty, 1-30 printable ASCII octets.
  ## Early trials cover boundary lengths.
  ## Does NOT generate: empty strings, very long strings, strings with control characters.
  rng.genValidLenientString(trial, 1, 30)

# ---------------------------------------------------------------------------
# Date / UTCDate generators
# ---------------------------------------------------------------------------

proc zeroPad(n: int, width: int): string =
  result = $n
  while result.len < width:
    result = "0" & result

proc allZeros(s: string): bool =
  for c in s:
    if c != '0':
      return false
  true

proc genNonZeroFracDigits(rng: var Rand): string =
  ## 1-6 fractional-second digits, not all zeros.
  let fracLen = rng.rand(1 .. 6)
  result = newString(fracLen)
  for i in 0 ..< fracLen:
    result[i] = char(rng.rand(ord('0') .. ord('9')))
  if result.allZeros():
    result[result.high] = '1'

proc genValidDate*(rng: var Rand): string =
  ## Generates structurally valid RFC 3339 date-time strings with random components.
  ## Covers: all months (1-12), all days (1-31), optional fractional seconds,
  ## timezone variants (Z, +HH:MM, -HH:MM, +00:00, -00:00, +23:59).
  ## Does NOT generate: calendar-invalid dates (e.g. Feb 30), leap seconds,
  ## lowercase 't'/'z', all-zero fractional seconds.
  let
    year = rng.rand(0 .. 9999)
    month = rng.rand(1 .. 12)
    day = rng.rand(1 .. 31)
    hour = rng.rand(0 .. 23)
    minute = rng.rand(0 .. 59)
    second = rng.rand(0 .. 59)

  result =
    zeroPad(year, 4) & "-" & zeroPad(month, 2) & "-" & zeroPad(day, 2) & "T" &
    zeroPad(hour, 2) & ":" & zeroPad(minute, 2) & ":" & zeroPad(second, 2)

  # Optional fractional seconds (non-zero digits)
  let fracChoice = rng.rand(0 .. 2)
  if fracChoice == 1:
    result.add '.'
    result.add rng.genNonZeroFracDigits()

  # Timezone: Z or +HH:MM or -HH:MM
  let tzChoice = rng.rand(0 .. 5)
  case tzChoice
  of 0:
    result.add 'Z'
  of 1:
    result.add "+00:00"
  of 2:
    result.add "-00:00"
  of 3:
    result.add '+'
    result.add zeroPad(rng.rand(0 .. 23), 2)
    result.add ':'
    result.add zeroPad(rng.rand(0 .. 59), 2)
  of 4:
    result.add '-'
    result.add zeroPad(rng.rand(0 .. 23), 2)
    result.add ':'
    result.add zeroPad(rng.rand(0 .. 59), 2)
  else:
    result.add "+23:59"

proc genValidUtcDate*(rng: var Rand): string =
  ## Generates structurally valid RFC 3339 date-time strings ending with 'Z'.
  ## Same as genValidDate but always uses UTC timezone suffix.
  ## Does NOT generate: non-Z timezone offsets, calendar-invalid dates.
  let
    year = rng.rand(0 .. 9999)
    month = rng.rand(1 .. 12)
    day = rng.rand(1 .. 31)
    hour = rng.rand(0 .. 23)
    minute = rng.rand(0 .. 59)
    second = rng.rand(0 .. 59)

  result =
    zeroPad(year, 4) & "-" & zeroPad(month, 2) & "-" & zeroPad(day, 2) & "T" &
    zeroPad(hour, 2) & ":" & zeroPad(minute, 2) & ":" & zeroPad(second, 2)

  let fracChoice = rng.rand(0 .. 1)
  if fracChoice == 1:
    result.add '.'
    result.add rng.genNonZeroFracDigits()

  result.add 'Z'

# ---------------------------------------------------------------------------
# Invalid-input generators (for negative property tests)
# ---------------------------------------------------------------------------

proc genInvalidDate*(rng: var Rand, trial: int = -1): string =
  ## Generates structurally malformed date strings for rejection testing.
  ## Early trials (< 10) cover: empty, too short, lowercase t/z, all-zero
  ## fractional seconds, empty fractional, missing timezone, wrong separator,
  ## space instead of T, truncated offset.
  ## Remaining trials generate random garbage strings.
  ## Does NOT generate: calendar-invalid but structurally valid dates.
  const payloads = [
    "", # empty
    "2024", # too short
    "2024-01-01t12:00:00Z", # lowercase 't'
    "2024-01-01T12:00:00z", # lowercase 'z'
    "2024-01-01T12:00:00.000Z", # all-zero fractional seconds
    "2024-01-01T12:00:00.Z", # empty fractional seconds
    "2024-01-01T12:00:00", # missing timezone
    "2024/01/01T12:00:00Z", # wrong date separator
    "2024-01-01 12:00:00Z", # space instead of T
    "2024-01-01T12:00:00+", # truncated offset
  ]
  if trial >= 0 and trial < payloads.len:
    return payloads[trial]
  # Random garbage string
  let length = rng.rand(0 .. 40)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genArbitraryByte()

proc genInvalidUtcDate*(rng: var Rand, trial: int = -1): string =
  ## Generates dates that are valid RFC 3339 but have non-Z timezone offsets
  ## (rejected by parseUtcDate). Early trials (< 4) cover: positive offset,
  ## negative offset, +00:00 instead of Z, -00:00 instead of Z.
  ## Remaining trials delegate to genInvalidDate for structurally invalid dates.
  ## Does NOT generate: dates ending with 'Z'.
  const payloads = [
    "2024-01-01T12:00:00+05:30", # positive offset
    "2024-01-01T12:00:00-08:00", # negative offset
    "2024-01-01T12:00:00.123+00:00", # +00:00 instead of Z
    "2024-01-01T12:00:00-00:00", # -00:00 instead of Z
  ]
  if trial >= 0 and trial < payloads.len:
    return payloads[trial]
  rng.genInvalidDate(trial)

# ---------------------------------------------------------------------------
# Adversarial string generators
# ---------------------------------------------------------------------------

proc genMaliciousString*(rng: var Rand, trial: int): string =
  ## Generates adversarial string payloads for security testing.
  ## Early trials (< 10) cover curated attacks: null byte, embedded null,
  ## overlong UTF-8, lone surrogate half, RTL override, BOM, 255x control
  ## chars, 255x null bytes, 255x spaces, 64KB single character.
  ## Remaining trials generate random-length random-byte strings up to 64KB.
  ## Does NOT bias toward: valid identifiers, printable strings.
  const payloads = [
    "\x00",
    "abc\x00def",
    "\xC0\x80",
    "\xED\xA0\x80",
    "\xE2\x80\xAE",
    "\xEF\xBB\xBF",
    '\x01'.repeat(255),
    '\x00'.repeat(255),
    ' '.repeat(255),
    'a'.repeat(65536),
  ]
  if trial >= 0 and trial < payloads.len:
    return payloads[trial]
  let length = rng.rand(0 .. 65536)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genArbitraryByte()

proc genLongArbitraryString*(rng: var Rand, trial: int = -1, maxLen = 65536): string =
  ## Generates arbitrary byte strings with higher maxLen (default 64KB).
  ## Early trials (< 6) cover same edge cases as genArbitraryString.
  ## Remaining trials generate random-length strings with random bytes up to maxLen.
  ## Does NOT bias toward: valid identifiers, printable strings, short strings.
  if trial >= 0 and trial < 6:
    let edges = ["", "\x00", "\x7F", " ", 'A'.repeat(255), 'A'.repeat(256)]
    return edges[trial]
  let length = rng.rand(0 .. maxLen)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genArbitraryByte()

# ---------------------------------------------------------------------------
# Structured type generators
# ---------------------------------------------------------------------------

proc genFilter*(rng: var Rand, maxDepth: int): Filter[int] =
  ## Generates random Filter[int] trees with controlled depth.
  ## Leaf nodes are random int conditions. Operator nodes use AND/OR/NOT with
  ## 0-4 children. Base case: maxDepth <= 0 or 1/3 chance of leaf at any depth.
  ## Does NOT generate: deeply nested trees beyond maxDepth, non-int conditions.
  if maxDepth <= 0 or rng.rand(0 .. 2) == 0:
    return filterCondition(rng.rand(int.low .. int.high))
  let op = rng.oneOf([foAnd, foOr, foNot])
  let childCount = rng.rand(0 .. 4)
  var children: seq[Filter[int]] = @[]
  for _ in 0 ..< childCount:
    children.add rng.genFilter(maxDepth - 1)
  filterOperator(op, children)

proc genPatchPath*(rng: var Rand): string =
  ## Generates random PatchObject path strings from a fixed set of realistic
  ## JSON Pointer-like segments (subject, keywords/$seen, mailboxIds/mb1, etc.).
  ## Does NOT generate: empty paths, very long paths, paths with special characters.
  const paths = [
    "subject", "keywords/$seen", "mailboxIds/mb1", "body/content", "from/0/name",
    "to/0/email", "header:X-Custom", "attachments/0/blobId", "textBody/0/partId",
    "htmlBody/0/partId",
  ]
  rng.oneOf(paths)

proc genInvocation*(rng: var Rand): Invocation =
  ## Generates a random Invocation with a realistic method name (Mailbox/get,
  ## Email/get, etc.) and a random MethodCallId (c0-c99).
  ## Arguments are always an empty JObject.
  ## Does NOT generate: non-standard method names, complex arguments.
  const methods = ["Mailbox/get", "Email/get", "Email/query", "Email/set", "Thread/get"]
  let name = rng.oneOf(methods)
  let mcidStr = "c" & $rng.rand(0 .. 99)
  let mcid = parseMethodCallId(mcidStr).get()
  Invocation(name: name, arguments: newJObject(), methodCallId: mcid)

proc genValidAccount*(rng: var Rand): Account =
  ## Generates a random Account with realistic structure: random name from a
  ## fixed set, random isPersonal/isReadOnly flags, 0-3 capabilities from
  ## mail/submission/contacts/calendars.
  ## NOTE: may produce duplicate capability URIs (caller must handle).
  ## Does NOT generate: vendor extensions, custom capability data.
  const names = ["alice@example.com", "bob@corp.org", "shared-inbox", "admin"]
  let name = rng.oneOf(names)
  let isPersonal = rng.rand(0 .. 1) == 0
  let isReadOnly = rng.rand(0 .. 1) == 0
  let capCount = rng.rand(0 .. 3)
  var caps: seq[AccountCapabilityEntry] = @[]
  let allCaps = [
    AccountCapabilityEntry(
      kind: ckMail, rawUri: "urn:ietf:params:jmap:mail", data: newJObject()
    ),
    AccountCapabilityEntry(
      kind: ckSubmission, rawUri: "urn:ietf:params:jmap:submission", data: newJObject()
    ),
    AccountCapabilityEntry(
      kind: ckContacts, rawUri: "urn:ietf:params:jmap:contacts", data: newJObject()
    ),
    AccountCapabilityEntry(
      kind: ckCalendars, rawUri: "urn:ietf:params:jmap:calendars", data: newJObject()
    ),
  ]
  for i in 0 ..< capCount:
    let idx = rng.rand(0 .. int(allCaps.high))
    caps.add allCaps[idx]
  Account(
    name: name,
    isPersonal: isPersonal,
    isReadOnly: isReadOnly,
    accountCapabilities: caps,
  )

# ---------------------------------------------------------------------------
# Error type generators
# ---------------------------------------------------------------------------

proc genTransportError*(rng: var Rand): TransportError =
  ## Generates a random TransportError covering all 4 kind variants
  ## (tekNetwork, tekTls, tekTimeout, tekHttpStatus) with random messages.
  ## HTTP status codes drawn from common values (400, 401, 403, 404, 500, 502, 503).
  ## Does NOT generate: non-standard HTTP status codes, empty messages.
  let kinds = [tekNetwork, tekTls, tekTimeout, tekHttpStatus]
  let kind = rng.oneOf(kinds)
  let msg = "error-" & $rng.rand(0 .. 999)
  case kind
  of tekHttpStatus:
    httpStatusError(rng.oneOf([400, 401, 403, 404, 500, 502, 503]), msg)
  of tekNetwork, tekTls, tekTimeout:
    transportError(kind, msg)

proc genRequestError*(rng: var Rand): RequestError =
  ## Generates a random RequestError with randomised optional fields.
  ## rawType from RFC-standard URIs plus a custom vendor error. Optional status
  ## (400/403/500), title, detail, limit, and extras fields each have ~50%
  ## chance of being present. Title and detail strings are diversified.
  ## Does NOT generate: non-standard status codes, deeply nested extras.
  const rawTypes = [
    "urn:ietf:params:jmap:error:unknownCapability",
    "urn:ietf:params:jmap:error:notJSON", "urn:ietf:params:jmap:error:notRequest",
    "urn:ietf:params:jmap:error:limit", "urn:example:custom:error",
  ]
  let raw = rng.oneOf(rawTypes)
  let status =
    if rng.rand(0 .. 1) == 0:
      Opt.some(rng.oneOf([400, 403, 404, 500, 503]))
    else:
      Opt.none(int)
  const titles =
    ["Error Title", "Bad Request", "Forbidden", "Rate Limited", "Capability Missing"]
  let title =
    if rng.rand(0 .. 1) == 0:
      Opt.some(rng.oneOf(titles) & "-" & $rng.rand(0 .. 99))
    else:
      Opt.none(string)
  const details = [
    "Detailed description", "The request body is not valid JSON",
    "Unknown capability requested", "Too many concurrent requests",
    "Malformed method call arguments",
  ]
  let detail =
    if rng.rand(0 .. 1) == 0:
      Opt.some(rng.oneOf(details) & " #" & $rng.rand(0 .. 99))
    else:
      Opt.none(string)
  const limits = [
    "maxSizeUpload", "maxConcurrentUpload", "maxSizeRequest", "maxConcurrentRequests",
    "maxCallsInRequest",
  ]
  let limit =
    if rng.rand(0 .. 1) == 0:
      Opt.some(rng.oneOf(limits))
    else:
      Opt.none(string)
  let extras =
    if rng.rand(0 .. 2) == 0:
      let node = newJObject()
      node["vendor"] = newJString("ext-" & $rng.rand(0 .. 99))
      Opt.some(node)
    else:
      Opt.none(JsonNode)
  requestError(raw, status, title, detail, limit, extras)

proc genMethodError*(rng: var Rand): MethodError =
  ## Generates a random MethodError with randomised optional description and extras.
  ## rawType from RFC-standard types (serverFail, invalidArguments, etc.) plus
  ## a custom vendor error. Description and extras each have ~50% chance of being present.
  ## Does NOT generate: deeply nested extras, empty rawType.
  const rawTypes = [
    "serverFail", "invalidArguments", "unknownMethod", "forbidden", "accountNotFound",
    "customVendorError",
  ]
  let raw = rng.oneOf(rawTypes)
  let desc =
    if rng.rand(0 .. 1) == 0:
      Opt.some("description-" & $rng.rand(0 .. 99))
    else:
      Opt.none(string)
  let extras =
    if rng.rand(0 .. 2) == 0:
      let node = newJObject()
      node["extra"] = newJString("value-" & $rng.rand(0 .. 99))
      Opt.some(node)
    else:
      Opt.none(JsonNode)
  methodError(raw, desc, extras)

proc genSetError*(rng: var Rand): SetError =
  ## Generates a random SetError covering all 3 variant branches:
  ## invalidProperties (1-5 property names), alreadyExists (random valid Id),
  ## and generic (forbidden/overQuota/tooLarge/notFound/vendorError).
  ## Optional description and extras each have ~50% chance of being present.
  ## Does NOT generate: empty properties lists, invalid Ids in alreadyExists.
  let branch = rng.rand(0 .. 2)
  let desc =
    if rng.rand(0 .. 1) == 0:
      Opt.some("desc-" & $rng.rand(0 .. 99))
    else:
      Opt.none(string)
  let extras =
    if rng.rand(0 .. 2) == 0:
      let node = newJObject()
      node["vendorField"] = newJString("value-" & $rng.rand(0 .. 99))
      Opt.some(node)
    else:
      Opt.none(JsonNode)
  case branch
  of 0:
    # invalidProperties variant
    let propCount = rng.rand(1 .. 5)
    var props: seq[string] = @[]
    for i in 0 ..< propCount:
      props.add "prop" & $i
    setErrorInvalidProperties("invalidProperties", props, desc, extras)
  of 1:
    # alreadyExists variant
    let id = parseId(rng.genValidIdStrict(minLen = 1, maxLen = 20)).get()
    setErrorAlreadyExists("alreadyExists", id, desc, extras)
  else:
    # Generic variant
    const rawTypes = ["forbidden", "overQuota", "tooLarge", "notFound", "vendorError"]
    setError(rng.oneOf(rawTypes), desc, extras)

proc genClientError*(rng: var Rand): ClientError =
  ## Generates a random ClientError wrapping either a transport error or a
  ## request error (50/50 split). Delegates to genTransportError/genRequestError.
  ## Does NOT generate: one variant type preferentially over the other.
  if rng.rand(0 .. 1) == 0:
    clientError(rng.genTransportError())
  else:
    clientError(rng.genRequestError())

# ---------------------------------------------------------------------------
# Structured type generators (additional)
# ---------------------------------------------------------------------------

proc genUnsignedInt*(rng: var Rand, trial: int = -1): UnsignedInt =
  ## Generates a random UnsignedInt for capability fields.
  ## Early trials (< 4) cover boundaries: 0, 1, max-1, max (2^53-1).
  ## Remaining trials generate random values in 0..100,000,000.
  ## Does NOT generate: values exceeding 100M outside early trials.
  let val =
    if trial >= 0 and trial < 4:
      [0'i64, 1'i64, MaxUnsignedIntVal - 1, MaxUnsignedIntVal][trial]
    else:
      rng.rand(0'i64 .. 100_000_000'i64)
  parseUnsignedInt(val).get()

proc genCoreCapabilities*(rng: var Rand): CoreCapabilities =
  ## Generates a random CoreCapabilities with varied UnsignedInt values for each
  ## field and 0-3 collation algorithms from the RFC set.
  ## Does NOT generate: custom collation algorithms, extremely large field values.
  var collations = initHashSet[string]()
  let collCount = rng.rand(0 .. 3)
  const allColl = ["i;ascii-casemap", "i;ascii-numeric", "i;unicode-casemap", "i;octet"]
  for i in 0 ..< collCount:
    collations.incl rng.oneOf(allColl)
  CoreCapabilities(
    maxSizeUpload: rng.genUnsignedInt(),
    maxConcurrentUpload: rng.genUnsignedInt(),
    maxSizeRequest: rng.genUnsignedInt(),
    maxConcurrentRequests: rng.genUnsignedInt(),
    maxCallsInRequest: rng.genUnsignedInt(),
    maxObjectsInGet: rng.genUnsignedInt(),
    maxObjectsInSet: rng.genUnsignedInt(),
    collationAlgorithms: collations,
  )

proc genVendorCapabilityJson*(rng: var Rand): JsonNode =
  ## Generates a realistic vendor capability JSON object with 2-5 fields.
  ## Field types: integers, booleans, and strings drawn from plausible names.
  ## Does NOT generate: deeply nested objects, arrays.
  result = newJObject()
  let fieldCount = rng.rand(2 .. 5)
  const fieldNames = [
    "maxFoosFinangled", "enabled", "version", "supportedFeatures", "maxBatchSize",
    "defaultTimeout", "allowHtml", "debugMode",
  ]
  for i in 0 ..< fieldCount:
    let name = fieldNames[min(i, fieldNames.high)]
    let kind = rng.rand(0 .. 2)
    case kind
    of 0:
      result[name] = newJInt(rng.rand(1'i64 .. 10000'i64))
    of 1:
      result[name] = newJBool(rng.rand(0 .. 1) == 0)
    else:
      result[name] = newJString("val-" & $rng.rand(0 .. 99))

proc genServerCapability*(rng: var Rand): ServerCapability =
  ## Generates a random ServerCapability: 25% chance of ckCore (with random
  ## CoreCapabilities), 75% chance of a non-core variant from all 12
  ## IANA-registered capability kinds plus a vendor extension.
  ## Non-core variants get realistic vendor capability JSON (2-5 fields).
  ## Does NOT generate: nil rawData for non-core variants.
  if rng.rand(0 .. 3) == 0:
    ServerCapability(
      rawUri: "urn:ietf:params:jmap:core", kind: ckCore, core: rng.genCoreCapabilities()
    )
  else:
    const uris = [
      "urn:ietf:params:jmap:mail", "urn:ietf:params:jmap:submission",
      "urn:ietf:params:jmap:vacationresponse", "urn:ietf:params:jmap:websocket",
      "urn:ietf:params:jmap:mdn", "urn:ietf:params:jmap:smimeverify",
      "urn:ietf:params:jmap:blob", "urn:ietf:params:jmap:quota",
      "urn:ietf:params:jmap:contacts", "urn:ietf:params:jmap:calendars",
      "urn:ietf:params:jmap:sieve", "https://vendor.example.com/ext",
    ]
    let uri = rng.oneOf(uris)
    let data = rng.genVendorCapabilityJson()
    ServerCapability(rawUri: uri, kind: parseCapabilityKind(uri), rawData: data)

proc genComparator*(rng: var Rand): Comparator =
  ## Generates a random Comparator with a random printable PropertyName,
  ## random isAscending flag, and optional collation (33% chance of "i;ascii-casemap").
  ## Does NOT generate: empty collation strings, non-standard collation algorithms.
  let prop = parsePropertyName(rng.genValidPropertyName()).get()
  let asc = rng.rand(0 .. 1) == 0
  let coll =
    if rng.rand(0 .. 2) == 0:
      Opt.some("i;ascii-casemap")
    else:
      Opt.none(string)
  parseComparator(prop, asc, coll).get()

proc genAddedItem*(rng: var Rand): AddedItem =
  ## Generates a random AddedItem with a valid strict Id (1-20 chars base64url)
  ## and a random UnsignedInt index (0-10000).
  ## Does NOT generate: very long Ids, very large indices.
  let id = parseId(rng.genValidIdStrict(minLen = 1, maxLen = 20)).get()
  let idx = parseUnsignedInt(rng.rand(0'i64 .. 10000'i64)).get()
  AddedItem(id: id, index: idx)

proc genPatchObject*(rng: var Rand, maxKeys: int): PatchObject =
  ## Generates a random PatchObject with 0..maxKeys entries using realistic
  ## path strings. ~30% of entries are deleteProp (null values); the rest
  ## are setProp with empty JObject values.
  ## Does NOT generate: very long path strings, deeply nested JSON values.
  let count = rng.rand(0 .. maxKeys)
  var p = emptyPatch()
  for i in 0 ..< count:
    let path = rng.genPatchPath()
    if rng.rand(0 .. 9) < 3: # ~30% probability of delete
      p = p.deleteProp(path).get()
    else:
      let val = newJObject()
      p = p.setProp(path, val).get()
  p

proc genValidUriTemplateParametric*(rng: var Rand): string =
  ## Generates parametric URI template strings by assembling random path segments
  ## and {variable} placeholders from JMAP-standard variable names. Optional
  ## query string with 1-3 variable parameters.
  ## Does NOT generate: empty templates, templates without https:// scheme.
  const segments = ["api", "jmap", "download", "upload", "events", "resource"]
  const variables =
    ["accountId", "blobId", "name", "type", "types", "closeafter", "ping"]
  result = "https://example.com"
  let segCount = rng.rand(1 .. 3)
  for i in 0 ..< segCount:
    result.add "/"
    if rng.rand(0 .. 1) == 0:
      result.add rng.oneOf(segments)
    else:
      result.add "{"
      result.add rng.oneOf(variables)
      result.add "}"
  # Optionally add query string with variables
  if rng.rand(0 .. 1) == 0:
    result.add "?"
    let paramCount = rng.rand(1 .. 3)
    for i in 0 ..< paramCount:
      if i > 0:
        result.add "&"
      let v = rng.oneOf(variables)
      result.add v
      result.add "={"
      result.add v
      result.add "}"

proc genInvalidIdStrict*(rng: var Rand, trial: int = -1): string =
  ## Generates strings deliberately designed to be rejected by parseId (strict).
  ## Early trials (< 6) cover: empty, too long (256), standard base64 '+' and '/',
  ## padding '=', embedded null byte.
  ## Remaining trials inject one bad character (+, /, =, space, @, null, DEL, !)
  ## into an otherwise valid base64url string.
  ## Does NOT generate: valid base64url strings (by design).
  if trial >= 0 and trial < 6:
    let payloads = [
      "", # empty
      'A'.repeat(256), # too long
      "abc+def", # standard base64 (not url-safe)
      "abc/def", # standard base64 (not url-safe)
      "abc=def", # pad char
      "\x00abc", # control char
    ]
    return payloads[trial]
  # Random invalid: introduce at least one bad character
  let length = rng.rand(1 .. 255)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genBase64UrlChar()
  # Inject one bad character
  let badPos = rng.rand(0 .. result.high)
  const badChars = ['+', '/', '=', ' ', '@', '\x00', '\x7F', '!']
  result[badPos] = rng.oneOf(badChars)

# ---------------------------------------------------------------------------
# Boundary-length ID generators
# ---------------------------------------------------------------------------

proc genBoundaryIdStrict*(rng: var Rand, trial: int): string =
  ## Generates IDs at exact boundary lengths (250-255 octets) for boundary testing.
  ## Early trials (< 4): 254x 'A', 255x 'A', 254x '_', 255 random base64url.
  ## Remaining trials: random length 250-255 with random base64url characters.
  ## Does NOT generate: short IDs, IDs exceeding 255 octets.
  case trial
  of 0:
    result = 'A'.repeat(254)
  of 1:
    result = 'A'.repeat(255)
  of 2:
    result = '_'.repeat(254)
  of 3:
    result = newString(255)
    for i in 0 ..< 255:
      result[i] = rng.genBase64UrlChar()
  else:
    let length = rng.rand(250 .. 255)
    result = newString(length)
    for i in 0 ..< length:
      result[i] = rng.genBase64UrlChar()

# ---------------------------------------------------------------------------
# Calendar-invalid date generators
# ---------------------------------------------------------------------------

proc genCalendarInvalidDate*(rng: var Rand): string =
  ## Generates structurally valid RFC 3339 dates with calendar-invalid values.
  ## Covers 4 variants: month 13, day 32, February 30, month 0.
  ## All use UTC ('Z') timezone suffix. Hours, minutes, and seconds are valid.
  ## Does NOT generate: structurally invalid dates (those are in genInvalidDate).
  let
    hour = rng.rand(0 .. 23)
    minute = rng.rand(0 .. 59)
    second = rng.rand(0 .. 59)
  # Pick a random invalid combination
  let variant = rng.rand(0 .. 3)
  let (year, month, day) =
    case variant
    of 0:
      (rng.rand(0 .. 9999), 13, rng.rand(1 .. 28))
    of 1:
      (rng.rand(0 .. 9999), rng.rand(1 .. 12), 32)
    of 2:
      (rng.rand(0 .. 9999), 2, 30)
    else:
      (rng.rand(0 .. 9999), 0, rng.rand(1 .. 28))
  zeroPad(year, 4) & "-" & zeroPad(month, 2) & "-" & zeroPad(day, 2) & "T" &
    zeroPad(hour, 2) & ":" & zeroPad(minute, 2) & ":" & zeroPad(second, 2) & "Z"

# ---------------------------------------------------------------------------
# JSON node generators (for serde totality testing)
# ---------------------------------------------------------------------------

import std/tables

proc genArbitraryJsonNode*(rng: var Rand, maxDepth: int = 3): JsonNode =
  ## Generates a random JsonNode of any kind (null, bool, int, float, string,
  ## array, object) with controlled nesting depth. Arrays have 0-3 elements,
  ## objects have 0-4 fields with "k0"-style keys. Used for totality testing.
  ## Does NOT generate: deeply nested structures beyond maxDepth, large collections.
  let kind = rng.rand(0 .. 6)
  case kind
  of 0:
    newJNull()
  of 1:
    newJBool(rng.rand(0 .. 1) == 0)
  of 2:
    newJInt(rng.rand(-9_999_999'i64 .. 9_999_999'i64))
  of 3:
    newJFloat(rng.rand(-1000.0 .. 1000.0))
  of 4:
    let s = rng.genStringFrom({'a' .. 'z', '0' .. '9', '-', '_', ' '}, 0, 30)
    newJString(s)
  of 5:
    if maxDepth <= 0:
      return newJString("leaf")
    var arr = newJArray()
    let count = rng.rand(0 .. 3)
    for _ in 0 ..< count:
      arr.add(rng.genArbitraryJsonNode(maxDepth - 1))
    arr
  else:
    if maxDepth <= 0:
      return newJString("leaf")
    var obj = newJObject()
    let count = rng.rand(0 .. 4)
    for i in 0 ..< count:
      let key = "k" & $i
      obj[key] = rng.genArbitraryJsonNode(maxDepth - 1)
    obj

proc genArbitraryJsonObject*(rng: var Rand, maxDepth: int = 2): JsonNode =
  ## Generates a random JObject with 0-6 fields drawn from JMAP-standard field
  ## names (type, name, id, capabilities, etc.). Values are random JsonNodes.
  ## Used for totality testing of fromJson functions that expect JObject input.
  ## Does NOT generate: fields with non-standard keys, empty-key fields.
  var obj = newJObject()
  let count = rng.rand(0 .. 6)
  const keys = [
    "type", "name", "id", "status", "properties", "operator", "conditions", "property",
    "isAscending", "collation", "description", "resultOf", "path", "index", "value",
    "maxSizeUpload", "using", "methodCalls", "methodResponses", "sessionState",
    "capabilities", "accounts", "primaryAccounts", "username", "apiUrl", "state",
    "accountCapabilities", "isPersonal", "isReadOnly", "existingId", "vendorExtra",
  ]
  for i in 0 ..< count:
    let key = rng.oneOf(keys)
    obj[key] = rng.genArbitraryJsonNode(maxDepth)
  obj

# ---------------------------------------------------------------------------
# Composite serde generators (Request, Response, Session)
# ---------------------------------------------------------------------------

proc genInvocationWithArgs*(rng: var Rand): Invocation =
  ## Generates a random Invocation with non-trivial arguments including accountId,
  ## optional ids array (0-3 entries), and optional properties array.
  ## Method names from 7 standard JMAP methods. MethodCallId range: c0-c999.
  ## Does NOT generate: result references, vendor-specific method names.
  const methods = [
    "Mailbox/get", "Email/get", "Email/query", "Email/set", "Thread/get",
    "Identity/get", "SearchSnippet/get",
  ]
  let name = rng.oneOf(methods)
  let mcidStr = "c" & $rng.rand(0 .. 999)
  let mcid = parseMethodCallId(mcidStr).get()
  var args = newJObject()
  args["accountId"] = newJString("A" & $rng.rand(1 .. 99))
  if rng.rand(0 .. 1) == 0:
    var ids = newJArray()
    for j in 0 ..< rng.rand(0 .. 3):
      ids.add(newJString("id" & $j))
    args["ids"] = ids
  if rng.rand(0 .. 2) == 0:
    args["properties"] = block:
      var p = newJArray()
      for prop in ["subject", "from", "to", "receivedAt"]:
        if rng.rand(0 .. 1) == 0:
          p.add(newJString(prop))
      p
  Invocation(name: name, arguments: args, methodCallId: mcid)

proc genRequest*(rng: var Rand): Request =
  ## Generates a random Request with 1-5 invocations (with non-trivial arguments),
  ## 1-3 using URIs from core/mail/submission, and optional createdIds (33% chance,
  ## 1-3 entries). Does NOT generate: empty methodCalls, empty using, vendor URIs.
  let n = rng.rand(1 .. 5)
  var calls: seq[Invocation] = @[]
  for _ in 0 ..< n:
    calls.add rng.genInvocationWithArgs()
  let usingCount = rng.rand(1 .. 3)
  const uris = [
    "urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail",
    "urn:ietf:params:jmap:submission",
  ]
  var usingUris: seq[string] = @[]
  for i in 0 ..< usingCount:
    usingUris.add uris[min(i, uris.high)]
  let createdIds =
    if rng.rand(0 .. 2) == 0:
      var tbl = initTable[CreationId, Id]()
      for i in 0 ..< rng.rand(1 .. 3):
        let cid = parseCreationId("new" & $i).get()
        let id = parseIdFromServer("id" & $i).get()
        tbl[cid] = id
      Opt.some(tbl)
    else:
      Opt.none(Table[CreationId, Id])
  Request(`using`: usingUris, methodCalls: calls, createdIds: createdIds)

proc genResponse*(rng: var Rand): Response =
  ## Generates a random Response with 1-5 methodResponses (with non-trivial
  ## arguments), a random sessionState, and optional createdIds (33% chance, 1-3
  ## entries). Does NOT generate: empty methodResponses, error invocations.
  let n = rng.rand(1 .. 5)
  var resps: seq[Invocation] = @[]
  for _ in 0 ..< n:
    resps.add rng.genInvocationWithArgs()
  let stateStr = "state" & $rng.rand(0 .. 9999)
  let state = parseJmapState(stateStr).get()
  let createdIds =
    if rng.rand(0 .. 2) == 0:
      var tbl = initTable[CreationId, Id]()
      for i in 0 ..< rng.rand(1 .. 3):
        let cid = parseCreationId("new" & $i).get()
        let id = parseIdFromServer("id" & $i).get()
        tbl[cid] = id
      Opt.some(tbl)
    else:
      Opt.none(Table[CreationId, Id])
  Response(methodResponses: resps, createdIds: createdIds, sessionState: state)

proc genSession*(rng: var Rand): Session =
  ## Generates a random valid Session: always includes ckCore, plus 0-3 additional
  ## capabilities (mail/submission/contacts/calendars). 0-3 random accounts with
  ## the first account's primary designation. Uses golden URL templates.
  ## Does NOT generate: vendor extensions, non-standard URL templates, empty capabilities.
  let core = rng.genCoreCapabilities()
  var caps: seq[ServerCapability] =
    @[ServerCapability(rawUri: "urn:ietf:params:jmap:core", kind: ckCore, core: core)]
  let extraCaps = rng.rand(0 .. 3)
  const extraUris = [
    "urn:ietf:params:jmap:mail", "urn:ietf:params:jmap:submission",
    "urn:ietf:params:jmap:contacts", "urn:ietf:params:jmap:calendars",
  ]
  for i in 0 ..< extraCaps:
    let uri = extraUris[min(i, extraUris.high)]
    caps.add ServerCapability(
      rawUri: uri, kind: parseCapabilityKind(uri), rawData: newJObject()
    )
  let acctCount = rng.rand(0 .. 3)
  var accounts = initTable[AccountId, Account]()
  var primaryAccounts = initTable[string, AccountId]()
  for i in 0 ..< acctCount:
    let aid = parseAccountId("A" & $rng.rand(1000 .. 9999)).get()
    accounts[aid] = rng.genValidAccount()
    if i == 0 and caps.len > 1:
      primaryAccounts[caps[1].rawUri] = aid
  let state = parseJmapState("s" & $rng.rand(0 .. 9999)).get()
  let downloadUrl = parseUriTemplate(
      "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}"
    )
    .get()
  let uploadUrl = parseUriTemplate("https://jmap.example.com/upload/{accountId}/").get()
  let eventSourceUrl = parseUriTemplate(
      "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}"
    )
    .get()
  parseSession(
    caps, accounts, primaryAccounts, "user@example.com",
    "https://jmap.example.com/api/", downloadUrl, uploadUrl, eventSourceUrl, state,
  )
    .get()

proc genResultReference*(rng: var Rand): ResultReference =
  ## Generates a random valid ResultReference with MethodCallId (c0-c999),
  ## method name from 4 standard JMAP methods, and path from 4 common paths.
  ## Does NOT generate: vendor method names, deeply nested paths, invalid refs.
  let mcid = parseMethodCallId("c" & $rng.rand(0 .. 999)).get()
  const names = ["Mailbox/get", "Email/get", "Thread/get", "Identity/get"]
  const paths = ["/ids", "/list/*/id", "/notFound", "/state"]
  ResultReference(
    resultOf: mcid,
    name: names[rng.rand(0 .. int(names.high))],
    path: paths[rng.rand(0 .. int(paths.high))],
  )

proc genFilterWithJsonConditions*(rng: var Rand, maxDepth: int): Filter[JsonNode] =
  ## Generates random Filter[JsonNode] trees with arbitrary JSON object leaf
  ## conditions. Operators use AND/OR/NOT with 0-3 children. 33% chance of leaf
  ## at any depth. Used for testing serde round-trip on generic Filter type.
  ## Does NOT generate: deeply nested trees beyond maxDepth, non-object conditions.
  if maxDepth <= 0 or rng.rand(0 .. 2) == 0:
    let cond = rng.genArbitraryJsonObject(1)
    return filterCondition(cond)
  let op = [foAnd, foOr, foNot][rng.rand(0 .. 2)]
  let childCount = rng.rand(0 .. 3)
  var children: seq[Filter[JsonNode]] = @[]
  for _ in 0 ..< childCount:
    children.add rng.genFilterWithJsonConditions(maxDepth - 1)
  filterOperator(op, children)

proc genMalformedSessionJson*(rng: var Rand): JsonNode =
  ## Generates plausible but subtly broken Session JSON for totality testing.
  ## 10 variants with different structural defects: missing capabilities, array
  ## capabilities, missing core, negative UnsignedInt, wrong boolean type,
  ## missing apiUrl, empty state, null username, accounts as array, and missing
  ## all URL templates. Does NOT generate: valid Session JSON, deeply nested defects.
  let variant = rng.rand(0 .. 9)
  {.cast(noSideEffect).}:
    case variant
    of 0: # Missing capabilities entirely
      %*{
        "accounts": {},
        "primaryAccounts": {},
        "username": "test",
        "apiUrl": "https://example.com/api/",
        "downloadUrl": "https://example.com/d",
        "uploadUrl": "https://example.com/u",
        "eventSourceUrl": "https://example.com/e",
        "state": "s1",
      }
    of 1: # Capabilities is array, not object
      %*{
        "capabilities": [1, 2, 3],
        "accounts": {},
        "primaryAccounts": {},
        "username": "test",
        "apiUrl": "https://example.com/api/",
        "downloadUrl": "https://example.com/d",
        "uploadUrl": "https://example.com/u",
        "eventSourceUrl": "https://example.com/e",
        "state": "s1",
      }
    of 2: # Missing core capability
      %*{
        "capabilities": {"urn:ietf:params:jmap:mail": {}},
        "accounts": {},
        "primaryAccounts": {},
        "username": "test",
        "apiUrl": "https://example.com/api/",
        "downloadUrl": "https://example.com/d",
        "uploadUrl": "https://example.com/u",
        "eventSourceUrl": "https://example.com/e",
        "state": "s1",
      }
    of 3: # Core capability with negative UnsignedInt
      %*{
        "capabilities": {
          "urn:ietf:params:jmap:core": {
            "maxSizeUpload": -1,
            "maxConcurrentUpload": 1,
            "maxSizeRequest": 1,
            "maxConcurrentRequests": 1,
            "maxCallsInRequest": 1,
            "maxObjectsInGet": 1,
            "maxObjectsInSet": 1,
            "collationAlgorithms": [],
          }
        },
        "accounts": {},
        "primaryAccounts": {},
        "username": "test",
        "apiUrl": "https://example.com/api/",
        "downloadUrl": "https://example.com/d",
        "uploadUrl": "https://example.com/u",
        "eventSourceUrl": "https://example.com/e",
        "state": "s1",
      }
    of 4: # Empty apiUrl
      %*{
        "capabilities": {
          "urn:ietf:params:jmap:core": {
            "maxSizeUpload": 1,
            "maxConcurrentUpload": 1,
            "maxSizeRequest": 1,
            "maxConcurrentRequests": 1,
            "maxCallsInRequest": 1,
            "maxObjectsInGet": 1,
            "maxObjectsInSet": 1,
            "collationAlgorithms": [],
          }
        },
        "accounts": {},
        "primaryAccounts": {},
        "username": "test",
        "apiUrl": "",
        "downloadUrl": "https://example.com/d",
        "uploadUrl": "https://example.com/u",
        "eventSourceUrl": "https://example.com/e",
        "state": "s1",
      }
    of 5: # primaryAccounts value is int, not string
      %*{
        "capabilities": {
          "urn:ietf:params:jmap:core": {
            "maxSizeUpload": 1,
            "maxConcurrentUpload": 1,
            "maxSizeRequest": 1,
            "maxConcurrentRequests": 1,
            "maxCallsInRequest": 1,
            "maxObjectsInGet": 1,
            "maxObjectsInSet": 1,
            "collationAlgorithms": [],
          }
        },
        "accounts": {},
        "primaryAccounts": {"urn:ietf:params:jmap:mail": 42},
        "username": "test",
        "apiUrl": "https://example.com/api/",
        "downloadUrl": "https://example.com/d",
        "uploadUrl": "https://example.com/u",
        "eventSourceUrl": "https://example.com/e",
        "state": "s1",
      }
    of 6: # Account missing required field
      %*{
        "capabilities": {
          "urn:ietf:params:jmap:core": {
            "maxSizeUpload": 1,
            "maxConcurrentUpload": 1,
            "maxSizeRequest": 1,
            "maxConcurrentRequests": 1,
            "maxCallsInRequest": 1,
            "maxObjectsInGet": 1,
            "maxObjectsInSet": 1,
            "collationAlgorithms": [],
          }
        },
        "accounts": {"A1": {"name": "test"}},
        "primaryAccounts": {},
        "username": "test",
        "apiUrl": "https://example.com/api/",
        "downloadUrl": "https://example.com/d",
        "uploadUrl": "https://example.com/u",
        "eventSourceUrl": "https://example.com/e",
        "state": "s1",
      }
    of 7: # Completely empty object
      newJObject()
    of 8: # Not even an object
      %42
    else: # Null
      newJNull()

{.pop.} # params
{.pop.} # hasDoc
