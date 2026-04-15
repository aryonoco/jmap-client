# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

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

import jmap_client/capabilities
import jmap_client/envelope
import jmap_client/errors
import jmap_client/framework {.all.}
import jmap_client/identifiers
import jmap_client/methods_enum
import jmap_client/primitives
import jmap_client/session
import jmap_client/validation
import jmap_client/mail/addresses
import jmap_client/mail/headers
import jmap_client/mail/body
import jmap_client/mail/email
import jmap_client/mail/email_blueprint
import jmap_client/mail/keyword
import jmap_client/mail/mailbox
import jmap_client/mail/mail_filters
import jmap_client/mail/snippet

{.push ruleOff: "hasDoc".}
{.push ruleOff: "params".}

# ---------------------------------------------------------------------------
# Trial count tiers
# ---------------------------------------------------------------------------

const QuickTrials* = 200
  ## For trivially cheap properties (totality checks, single-constructor).

const DefaultTrials* = 500 ## Standard property trial count.

const ThoroughTrials* = 2000 ## For properties with large input spaces (Date, Session).

const CrossProcessTrials* = 100
  ## For properties whose per-trial cost is dominated by spawning a child
  ## process (``startProcess`` + ``waitForExit``). Nim-runtime init + exec
  ## runs ~100 ms/trial on Linux — five times the pure-Nim trial budget
  ## the other tiers assume. Tuned so cross-process tiers add ~10 s to CI
  ## rather than the ~200 s that ``ThoroughTrials`` would impose.

# ---------------------------------------------------------------------------
# Property check templates
# ---------------------------------------------------------------------------

template checkProperty*(name: string, body: untyped) =
  ## Runs body DefaultTrials times with an injected `rng` and `trial` variable.
  ## Fixed seed (42) ensures deterministic reproduction. With --panics:on,
  ## assertion failures abort immediately with a full stack trace.
  block:
    var rng {.inject.} = initRand(42)
    var lastInput {.inject.}: string = ""
    for trial {.inject.} in 0 ..< DefaultTrials:
      body

template checkPropertyN*(name: string, trials: int, body: untyped) =
  ## Runs body `trials` times. Use QuickTrials or ThoroughTrials for non-default
  ## counts. With --panics:on, assertion failures abort immediately.
  block:
    var rng {.inject.} = initRand(42)
    var lastInput {.inject.}: string = ""
    for trial {.inject.} in 0 ..< trials:
      body

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
  const methods = [mnMailboxGet, mnEmailGet, mnEmailQuery, mnEmailSet, mnThreadGet]
  let name = rng.oneOf(methods)
  let mcidStr = "c" & $rng.rand(0 .. 99)
  let mcid = parseMethodCallId(mcidStr).get()
  initInvocation(name, newJObject(), mcid)

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
  parseComparator(prop, asc, coll)

proc genAddedItem*(rng: var Rand): AddedItem =
  ## Generates a random AddedItem with a valid strict Id (1-20 chars base64url)
  ## and a random UnsignedInt index (0-10000).
  ## Does NOT generate: very long Ids, very large indices.
  let id = parseId(rng.genValidIdStrict(minLen = 1, maxLen = 20)).get()
  let idx = parseUnsignedInt(rng.rand(0'i64 .. 10000'i64)).get()
  initAddedItem(id, idx)

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
    mnMailboxGet, mnEmailGet, mnEmailQuery, mnEmailSet, mnThreadGet, mnIdentityGet,
    mnSearchSnippetGet,
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
  initInvocation(name, args, mcid)

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
  parseResultReference(
    resultOf = mcid,
    name = names[rng.rand(0 .. int(names.high))],
    path = paths[rng.rand(0 .. int(paths.high))],
  )
    .get()

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

# ---------------------------------------------------------------------------
# Mail Part A prereq generators (EmailAddress, EmailAddressGroup)
# ---------------------------------------------------------------------------

proc genEmailAddress*(rng: var Rand): EmailAddress =
  ## Generates a valid EmailAddress with random email and optional name.
  ## Email: picked from a pool of realistic addr-specs.
  ## Name: 50% Opt.some (random display name), 50% Opt.none.
  ## Does NOT generate: empty emails, format-invalid addr-specs.
  const emails = [
    "alice@example.com", "bob@corp.org", "charlie@test.io", "user+tag@domain.example",
    "a@b.c",
  ]
  const names = ["Alice Smith", "Bob Jones", "Charlie", "Dr. Example"]
  let email = rng.oneOf(emails)
  let name =
    if rng.rand(0 .. 1) == 0:
      Opt.some(rng.oneOf(names))
    else:
      Opt.none(string)
  parseEmailAddress(email, name).get()

proc genEmailAddressGroup*(rng: var Rand): EmailAddressGroup =
  ## Generates an EmailAddressGroup with optional name and 0–3 addresses.
  ## Name: 50% Opt.some, 50% Opt.none. Addresses may be empty.
  ## Does NOT generate: deeply nested structures (EmailAddressGroup is flat).
  const groupNames = ["Work", "Family", "Team", "undisclosed-recipients"]
  let name =
    if rng.rand(0 .. 1) == 0:
      Opt.some(rng.oneOf(groupNames))
    else:
      Opt.none(string)
  let count = rng.rand(0 .. 3)
  var addrs: seq[EmailAddress] = @[]
  for _ in 0 ..< count:
    addrs.add(rng.genEmailAddress())
  EmailAddressGroup(name: name, addresses: addrs)

# ---------------------------------------------------------------------------
# Mail Part C generators
# ---------------------------------------------------------------------------

proc genHeaderForm*(rng: var Rand): HeaderForm =
  ## Picks uniformly from all 7 HeaderForm variants.
  ## Does NOT bias toward any particular form.
  rng.oneOf(
    [hfRaw, hfText, hfAddresses, hfGroupedAddresses, hfMessageIds, hfDate, hfUrls]
  )

proc genEmailHeader*(rng: var Rand, trial: int = -1): EmailHeader =
  ## Generates a valid EmailHeader with a realistic header name and random value.
  ## Early trials (< 2): minimal name ("X"), empty value.
  ## Remaining: name from RFC 5322 pool, value 0–80 printable ASCII chars.
  ## Does NOT generate: empty names, control characters in values.
  const headerNames = [
    "From", "To", "Subject", "Date", "Message-Id", "Content-Type", "X-Mailer",
    "X-Custom", "Reply-To", "Cc", "Bcc", "In-Reply-To", "References",
    "List-Unsubscribe", "MIME-Version",
  ]
  if trial >= 0 and trial == 0:
    return parseEmailHeader("X", "").get()
  if trial >= 0 and trial == 1:
    return parseEmailHeader("From", "").get()
  let name = rng.oneOf(headerNames)
  let valueLen = rng.rand(0 .. 80)
  var value = newString(valueLen)
  for i in 0 ..< valueLen:
    value[i] = rng.genAsciiPrintable()
  parseEmailHeader(name, value).get()

proc buildHeaderPropertyWire(rng: var Rand, name: string, form: HeaderForm): string =
  ## Builds a wire-format header property string from name and form.
  result = "header:" & name
  if form != hfRaw or rng.rand(0 .. 1) == 0:
    result &= ":" & $form
  if rng.rand(0 .. 3) == 0:
    result &= ":all"

proc genHeaderPropertyKey*(rng: var Rand, trial: int = -1): HeaderPropertyKey =
  ## Generates a valid HeaderPropertyKey by constructing a wire-format string
  ## and parsing it. Mixes known RFC headers with unknown custom headers.
  ## Early trials (< 4): specific boundary cases (no form, with :all, etc.).
  ## Remaining: random header name + valid form + optional :all.
  ## Does NOT generate: invalid keys, empty names, unknown form suffixes.
  const knownHeaders = [
    "from", "to", "subject", "date", "message-id", "list-unsubscribe", "reply-to", "cc",
    "bcc", "in-reply-to", "references", "list-archive",
  ]
  const unknownHeaders = ["x-custom", "x-mailer", "x-priority", "x-vendor-ext"]
  if trial >= 0 and trial < 4:
    const earlyStrings = [
      "header:from:asAddresses", "header:subject:asText", "header:from",
      "header:from:asAddresses:all",
    ]
    return parseHeaderPropertyName(earlyStrings[trial]).get()
  # Pick a header name — 75% known, 25% unknown
  let name =
    if rng.rand(0 .. 3) < 3:
      rng.oneOf(knownHeaders)
    else:
      rng.oneOf(unknownHeaders)
  # Pick a valid form for this header
  let allowed = allowedForms(name)
  var formChoices: seq[HeaderForm] = @[]
  for f in HeaderForm:
    if f in allowed:
      formChoices.add(f)
  let form = rng.oneOf(formChoices)
  parseHeaderPropertyName(rng.buildHeaderPropertyWire(name, form)).get()

proc genPrintableString(rng: var Rand, maxLen: int = 60): string =
  ## Generates a random printable ASCII string of 0..maxLen characters.
  let valueLen = rng.rand(0 .. maxLen)
  result = newString(valueLen)
  for i in 0 ..< valueLen:
    result[i] = rng.genAsciiPrintable()

proc genHeaderValueString(rng: var Rand, form: HeaderForm): HeaderValue =
  ## Generates hfRaw or hfText HeaderValue variants with random content.
  let val = rng.genPrintableString(60)
  case form
  of hfRaw:
    HeaderValue(form: hfRaw, rawValue: val)
  of hfText:
    HeaderValue(form: hfText, textValue: val)
  else:
    HeaderValue(form: hfRaw, rawValue: val)

proc genHeaderValueNullable(rng: var Rand, form: HeaderForm): HeaderValue =
  ## Generates nullable HeaderValue variants (hfMessageIds, hfDate, hfUrls).
  ## 30% Opt.none, 70% Opt.some.
  case form
  of hfMessageIds:
    if rng.rand(0 .. 9) < 3:
      return HeaderValue(form: hfMessageIds, messageIds: Opt.none(seq[string]))
    let count = rng.rand(0 .. 3)
    var ids: seq[string] = @[]
    for i in 0 ..< count:
      ids.add("<msg" & $i & "@example.com>")
    HeaderValue(form: hfMessageIds, messageIds: Opt.some(ids))
  of hfDate:
    if rng.rand(0 .. 9) < 3:
      return HeaderValue(form: hfDate, date: Opt.none(Date))
    let d = parseDate(rng.genValidDate()).get()
    HeaderValue(form: hfDate, date: Opt.some(d))
  of hfUrls:
    if rng.rand(0 .. 9) < 3:
      return HeaderValue(form: hfUrls, urls: Opt.none(seq[string]))
    let count = rng.rand(0 .. 3)
    var urlList: seq[string] = @[]
    for i in 0 ..< count:
      urlList.add("https://example.com/path" & $i)
    HeaderValue(form: hfUrls, urls: Opt.some(urlList))
  else:
    HeaderValue(form: hfRaw, rawValue: "")

proc genHeaderValue*(rng: var Rand, form: HeaderForm): HeaderValue =
  ## Generates a HeaderValue for the given form variant.
  ## Nullable forms (hfMessageIds, hfDate, hfUrls): 30% Opt.none, 70% Opt.some.
  ## Does NOT generate: malformed addresses or dates.
  case form
  of hfRaw, hfText:
    rng.genHeaderValueString(form)
  of hfAddresses:
    let count = rng.rand(0 .. 3)
    var addrs: seq[EmailAddress] = @[]
    for _ in 0 ..< count:
      addrs.add(rng.genEmailAddress())
    HeaderValue(form: hfAddresses, addresses: addrs)
  of hfGroupedAddresses:
    let count = rng.rand(0 .. 2)
    var groups: seq[EmailAddressGroup] = @[]
    for _ in 0 ..< count:
      groups.add(rng.genEmailAddressGroup())
    HeaderValue(form: hfGroupedAddresses, groups: groups)
  of hfMessageIds, hfDate, hfUrls:
    rng.genHeaderValueNullable(form)

proc genHeaderValue*(rng: var Rand): HeaderValue =
  ## Generates a HeaderValue with a randomly chosen form variant.
  let form = rng.genHeaderForm()
  rng.genHeaderValue(form)

proc genPartId*(rng: var Rand, trial: int = -1): PartId =
  ## Generates a valid PartId (non-empty, no control characters).
  ## Early trials (< 4): typical MIME part numbers ("1", "1.2", "1.2.3", "2").
  ## Remaining: random printable ASCII strings (1–20 chars).
  ## Does NOT generate: empty strings, control characters.
  if trial >= 0 and trial < 4:
    const earlyIds = ["1", "1.2", "1.2.3", "2"]
    return parsePartIdFromServer(earlyIds[trial]).get()
  let length = rng.rand(1 .. 20)
  var s = newString(length)
  for i in 0 ..< length:
    s[i] = rng.genAsciiPrintable()
  parsePartIdFromServer(s).get()

proc genEmailBodyValue*(rng: var Rand): EmailBodyValue =
  ## Generates an EmailBodyValue with random content and flag combinations.
  ## Value: 0–100 printable ASCII chars. Flags: random booleans.
  ## Does NOT generate: values with control characters.
  let valueLen = rng.rand(0 .. 100)
  var val = newString(valueLen)
  for i in 0 ..< valueLen:
    val[i] = rng.genAsciiPrintable()
  EmailBodyValue(
    value: val,
    isEncodingProblem: rng.rand(0 .. 1) == 0,
    isTruncated: rng.rand(0 .. 1) == 0,
  )

type BodyPartSharedFields {.ruleOff: "objects".} = object
  ## Shared optional fields for genEmailBodyPart leaf/multipart generation.
  hdrs: seq[EmailHeader]
  name: Opt[string]
  disposition: Opt[string]
  cid: Opt[string]
  language: Opt[seq[string]]
  location: Opt[string]

proc genBodyPartSharedFields(rng: var Rand): BodyPartSharedFields =
  ## Generates shared optional fields for EmailBodyPart.
  var hdrs: seq[EmailHeader] = @[]
  for _ in 0 ..< rng.rand(0 .. 2):
    hdrs.add(rng.genEmailHeader())
  BodyPartSharedFields(
    hdrs: hdrs,
    name:
      if rng.rand(0 .. 2) == 0:
        Opt.some("file" & $rng.rand(1 .. 99) & ".dat")
      else:
        Opt.none(string),
    disposition:
      if rng.rand(0 .. 2) == 0:
        Opt.some(rng.oneOf(["inline", "attachment"]))
      else:
        Opt.none(string),
    cid:
      if rng.rand(0 .. 4) == 0:
        Opt.some("cid" & $rng.rand(1 .. 999) & "@example.com")
      else:
        Opt.none(string),
    language:
      if rng.rand(0 .. 3) == 0:
        Opt.some(@["en"])
      else:
        Opt.none(seq[string]),
    location:
      if rng.rand(0 .. 4) == 0:
        Opt.some("https://example.com/part/" & $rng.rand(1 .. 999))
      else:
        Opt.none(string),
  )

proc genEmailBodyPart*(rng: var Rand, maxDepth: int = 3): EmailBodyPart =
  ## Generates a random EmailBodyPart tree with controlled depth.
  ## At maxDepth <= 0 or 50% chance: leaf part with text/* or binary content
  ## type. Otherwise: multipart with 0–3 recursive children.
  ## Leaf charset follows the RFC rule: Opt.some for text/*, Opt.none otherwise.
  ## Does NOT generate: trees deeper than maxDepth, invalid partId or blobId.
  const leafTypes = ["text/plain", "text/html", "image/png", "application/pdf"]
  const multipartTypes =
    ["multipart/mixed", "multipart/alternative", "multipart/related"]
  let sf = rng.genBodyPartSharedFields()

  if maxDepth <= 0 or rng.rand(0 .. 1) == 0:
    let ct = rng.oneOf(leafTypes)
    let charset =
      if ct.startsWith("text/"):
        Opt.some("utf-8")
      else:
        Opt.none(string)
    return EmailBodyPart(
      headers: sf.hdrs,
      name: sf.name,
      contentType: ct,
      charset: charset,
      disposition: sf.disposition,
      cid: sf.cid,
      language: sf.language,
      location: sf.location,
      size: UnsignedInt(rng.rand(1'i64 .. 50000'i64)),
      isMultipart: false,
      partId: rng.genPartId(),
      blobId: Id(rng.genValidIdStrict(minLen = 3, maxLen = 20)),
    )
  let ct = rng.oneOf(multipartTypes)
  var children: seq[EmailBodyPart] = @[]
  for _ in 0 ..< rng.rand(0 .. 3):
    children.add(rng.genEmailBodyPart(maxDepth - 1))
  EmailBodyPart(
    headers: sf.hdrs,
    name: sf.name,
    contentType: ct,
    charset: Opt.none(string),
    disposition: sf.disposition,
    cid: sf.cid,
    language: sf.language,
    location: sf.location,
    size: UnsignedInt(0),
    isMultipart: true,
    subParts: children,
  )

proc genArbitraryHeaderPropertyString*(rng: var Rand, trial: int = -1): string =
  ## Generates strings for totality testing of parseHeaderPropertyName.
  ## Early trials (< 6): curated boundary cases (empty, missing prefix,
  ## empty name, unknown form, trailing colon, too many segments).
  ## Remaining: mix of valid-looking and garbage strings.
  ## Does NOT guarantee: valid or invalid — the full input space is covered.
  if trial >= 0 and trial < 6:
    const earlyStrings = [
      "", "header:", "header::", "From:asText", "header:From:asUnknown",
      "header:From:asAddresses:all:extra",
    ]
    return earlyStrings[trial]
  # Mix: 50% header:-prefixed with random content, 50% arbitrary
  if rng.rand(0 .. 1) == 0:
    let restLen = rng.rand(0 .. 40)
    var rest = newString(restLen)
    for i in 0 ..< restLen:
      rest[i] = rng.genArbitraryByte()
    return "header:" & rest
  let length = rng.rand(0 .. 50)
  var s = newString(length)
  for i in 0 ..< length:
    s[i] = rng.genArbitraryByte()
  return s

# ---------------------------------------------------------------------------
# Mail Part D generators
# ---------------------------------------------------------------------------

# -- Helper types (D7 shared parity) --

type ConvenienceHeadersGen {.ruleOff: "objects".} = object
  messageId: Opt[seq[string]]
  inReplyTo: Opt[seq[string]]
  references: Opt[seq[string]]
  sender: Opt[seq[EmailAddress]]
  fromAddr: Opt[seq[EmailAddress]]
  to: Opt[seq[EmailAddress]]
  cc: Opt[seq[EmailAddress]]
  bcc: Opt[seq[EmailAddress]]
  replyTo: Opt[seq[EmailAddress]]
  subject: Opt[string]
  sentAt: Opt[Date]

type BodyFieldsGen {.ruleOff: "objects".} = object
  bodyStructure: EmailBodyPart
  bodyValues: Table[PartId, EmailBodyValue]
  textBody: seq[EmailBodyPart]
  htmlBody: seq[EmailBodyPart]
  attachments: seq[EmailBodyPart]
  hasAttachment: bool
  preview: string

type DynamicHeadersGen {.ruleOff: "objects".} = object
  requestedHeaders: Table[HeaderPropertyKey, HeaderValue]
  requestedHeadersAll: Table[HeaderPropertyKey, seq[HeaderValue]]

# -- Internal helpers --

proc genOptStringSeq(rng: var Rand): Opt[seq[string]] =
  if rng.rand(0 .. 9) < 4:
    var ids: seq[string] = @[]
    for _ in 0 ..< rng.rand(0 .. 3):
      ids.add("<msg" & $rng.rand(1 .. 999) & "@example.com>")
    Opt.some(ids)
  else:
    Opt.none(seq[string])

proc genOptAddresses(rng: var Rand): Opt[seq[EmailAddress]] =
  if rng.rand(0 .. 9) < 4:
    var addrs: seq[EmailAddress] = @[]
    for _ in 0 ..< rng.rand(0 .. 3):
      addrs.add(rng.genEmailAddress())
    Opt.some(addrs)
  else:
    Opt.none(seq[EmailAddress])

# -- Leaf generators --

proc genKeyword*(rng: var Rand): Keyword =
  const kwConstants =
    [kwDraft, kwSeen, kwFlagged, kwAnswered, kwForwarded, kwPhishing, kwJunk, kwNotJunk]
  if rng.rand(0 .. 9) < 7:
    return rng.oneOf(kwConstants)
  let s = rng.genStringFrom({'a' .. 'z', '0' .. '9', '$', '-', '_', '.'}, 1, 20)
  parseKeyword(s).get()

proc genKeywordSet*(rng: var Rand): KeywordSet =
  var kws: seq[Keyword] = @[]
  for _ in 0 ..< rng.rand(0 .. 5):
    kws.add(rng.genKeyword())
  initKeywordSet(kws)

proc genMailboxIdSet*(rng: var Rand): MailboxIdSet =
  var ids: seq[Id] = @[]
  for _ in 0 ..< rng.rand(1 .. 5):
    ids.add(Id(rng.genValidIdStrict()))
  initMailboxIdSet(ids)

proc genSearchSnippet*(rng: var Rand): SearchSnippet =
  SearchSnippet(
    emailId: Id(rng.genValidIdStrict()),
    subject:
      if rng.rand(0 .. 1) == 0:
        Opt.some(rng.genPrintableString(80))
      else:
        Opt.none(string),
    preview:
      if rng.rand(0 .. 1) == 0:
        Opt.some(rng.genPrintableString(256))
      else:
        Opt.none(string),
  )

proc genEmailHeaderFilter*(rng: var Rand): EmailHeaderFilter =
  const namePool = ["Subject", "From", "To", "X-Custom", "Date"]
  let name = rng.oneOf(namePool)
  let value =
    if rng.rand(0 .. 1) == 0:
      Opt.some(rng.genPrintableString(30))
    else:
      Opt.none(string)
  parseEmailHeaderFilter(name, value).get()

# -- Shared helper generators (D7 parity) --

proc genHeaderPropertyKeyForDynamic(rng: var Rand, forAll: bool): HeaderPropertyKey =
  const knownHeaders = [
    "from", "to", "subject", "date", "message-id", "list-unsubscribe", "reply-to", "cc",
    "bcc", "in-reply-to", "references", "list-archive",
  ]
  const unknownHeaders = ["x-custom", "x-mailer", "x-priority", "x-vendor-ext"]
  let name =
    if rng.rand(0 .. 3) < 3:
      rng.oneOf(knownHeaders)
    else:
      rng.oneOf(unknownHeaders)
  let allowed = allowedForms(name)
  var formChoices: seq[HeaderForm] = @[]
  for f in HeaderForm:
    if f in allowed:
      formChoices.add(f)
  let form = rng.oneOf(formChoices)
  var wire = "header:" & name
  if form != hfRaw or rng.rand(0 .. 1) == 0:
    wire &= ":" & $form
  if forAll:
    wire &= ":all"
  parseHeaderPropertyName(wire).get()

proc genConvenienceHeaders(rng: var Rand): ConvenienceHeadersGen =
  ConvenienceHeadersGen(
    messageId: rng.genOptStringSeq(),
    inReplyTo: rng.genOptStringSeq(),
    references: rng.genOptStringSeq(),
    sender: rng.genOptAddresses(),
    fromAddr: rng.genOptAddresses(),
    to: rng.genOptAddresses(),
    cc: rng.genOptAddresses(),
    bcc: rng.genOptAddresses(),
    replyTo: rng.genOptAddresses(),
    subject:
      if rng.rand(0 .. 1) == 0:
        Opt.some(rng.genPrintableString(80))
      else:
        Opt.none(string),
    sentAt:
      if rng.rand(0 .. 1) == 0:
        Opt.some(parseDate(rng.genValidDate()).get())
      else:
        Opt.none(Date),
  )

proc genBodyFields(rng: var Rand): BodyFieldsGen =
  var bodyValues = initTable[PartId, EmailBodyValue]()
  for _ in 0 ..< rng.rand(0 .. 2):
    bodyValues[rng.genPartId()] = rng.genEmailBodyValue()
  var textBody: seq[EmailBodyPart] = @[]
  for _ in 0 ..< rng.rand(0 .. 1):
    textBody.add(rng.genEmailBodyPart(0))
  var htmlBody: seq[EmailBodyPart] = @[]
  for _ in 0 ..< rng.rand(0 .. 1):
    htmlBody.add(rng.genEmailBodyPart(0))
  var attachments: seq[EmailBodyPart] = @[]
  for _ in 0 ..< rng.rand(0 .. 2):
    attachments.add(rng.genEmailBodyPart(0))
  BodyFieldsGen(
    bodyStructure: rng.genEmailBodyPart(2),
    bodyValues: bodyValues,
    textBody: textBody,
    htmlBody: htmlBody,
    attachments: attachments,
    hasAttachment: rng.rand(0 .. 1) == 0,
    preview: rng.genPrintableString(256),
  )

proc genDynamicHeaders(rng: var Rand): DynamicHeadersGen =
  var reqHeaders = initTable[HeaderPropertyKey, HeaderValue]()
  for _ in 0 ..< rng.rand(0 .. 2):
    let key = rng.genHeaderPropertyKeyForDynamic(forAll = false)
    reqHeaders[key] = rng.genHeaderValue(key.form)
  var reqHeadersAll = initTable[HeaderPropertyKey, seq[HeaderValue]]()
  for _ in 0 ..< rng.rand(0 .. 1):
    let key = rng.genHeaderPropertyKeyForDynamic(forAll = true)
    var vals: seq[HeaderValue] = @[]
    for _ in 0 ..< rng.rand(1 .. 3):
      vals.add(rng.genHeaderValue(key.form))
    reqHeadersAll[key] = vals
  DynamicHeadersGen(requestedHeaders: reqHeaders, requestedHeadersAll: reqHeadersAll)

# -- Domain type generators --

proc genEmailComparator*(rng: var Rand): EmailComparator =
  const collationPool = ["i;ascii-casemap", "i;ascii-numeric", "i;unicode-casemap"]
  let isAscending =
    case rng.rand(0 .. 2)
    of 0:
      Opt.none(bool)
    of 1:
      Opt.some(true)
    else:
      Opt.some(false)
  let collation =
    if rng.rand(0 .. 9) < 3:
      Opt.some(rng.oneOf(collationPool))
    else:
      Opt.none(string)
  if rng.rand(0 .. 1) == 0:
    let prop =
      rng.oneOf([pspReceivedAt, pspSize, pspFrom, pspTo, pspSubject, pspSentAt])
    plainComparator(prop, isAscending, collation)
  else:
    let ksp =
      rng.oneOf([kspHasKeyword, kspAllInThreadHaveKeyword, kspSomeInThreadHaveKeyword])
    keywordComparator(ksp, rng.genKeyword(), isAscending, collation)

proc genEmailBodyFetchOptions*(rng: var Rand): EmailBodyFetchOptions =
  const bodyPropertyPool = [
    "partId", "blobId", "size", "name", "type", "charset", "disposition", "cid",
    "language", "location", "headers",
  ]
  let scope = rng.oneOf([bvsNone, bvsText, bvsHtml, bvsTextAndHtml, bvsAll])
  let bodyProperties =
    if rng.rand(0 .. 9) < 4:
      var props: seq[PropertyName] = @[]
      for _ in 0 ..< rng.rand(1 .. 5):
        props.add(parsePropertyName(rng.oneOf(bodyPropertyPool)).get())
      Opt.some(props)
    else:
      Opt.none(seq[PropertyName])
  let maxBytes =
    if rng.rand(0 .. 9) < 4:
      Opt.some(parseUnsignedInt(rng.genValidUnsignedInt()).get())
    else:
      Opt.none(UnsignedInt)
  EmailBodyFetchOptions(
    bodyProperties: bodyProperties, fetchBodyValues: scope, maxBodyValueBytes: maxBytes
  )

# -- EmailFilterCondition sub-helpers --

proc fillMailboxFilterFields(
    rng: var Rand, fc: var EmailFilterCondition, allSome: bool
) =
  if allSome or rng.rand(0 .. 9) < 3:
    fc.inMailbox = Opt.some(Id(rng.genValidIdStrict()))
  if allSome or rng.rand(0 .. 9) < 3:
    var ids: seq[Id] = @[]
    for _ in 0 ..< rng.rand(1 .. 3):
      ids.add(Id(rng.genValidIdStrict()))
    fc.inMailboxOtherThan = Opt.some(ids)

proc fillDateSizeFilterFields(
    rng: var Rand, fc: var EmailFilterCondition, allSome: bool
) =
  if allSome or rng.rand(0 .. 9) < 3:
    fc.before = Opt.some(parseUtcDate(rng.genValidUtcDate()).get())
  if allSome or rng.rand(0 .. 9) < 3:
    fc.after = Opt.some(parseUtcDate(rng.genValidUtcDate()).get())
  if allSome or rng.rand(0 .. 9) < 3:
    fc.minSize = Opt.some(parseUnsignedInt(rng.genValidUnsignedInt()).get())
  if allSome or rng.rand(0 .. 9) < 3:
    fc.maxSize = Opt.some(parseUnsignedInt(rng.genValidUnsignedInt()).get())

proc fillThreadKeywordFilterFields(
    rng: var Rand, fc: var EmailFilterCondition, allSome: bool
) =
  if allSome or rng.rand(0 .. 9) < 3:
    fc.allInThreadHaveKeyword = Opt.some(rng.genKeyword())
  if allSome or rng.rand(0 .. 9) < 3:
    fc.someInThreadHaveKeyword = Opt.some(rng.genKeyword())
  if allSome or rng.rand(0 .. 9) < 3:
    fc.noneInThreadHaveKeyword = Opt.some(rng.genKeyword())

proc fillPerEmailKeywordFilterFields(
    rng: var Rand, fc: var EmailFilterCondition, allSome: bool
) =
  if allSome or rng.rand(0 .. 9) < 3:
    fc.hasKeyword = Opt.some(rng.genKeyword())
  if allSome or rng.rand(0 .. 9) < 3:
    fc.notKeyword = Opt.some(rng.genKeyword())

proc fillTextSearchFilterFields(
    rng: var Rand, fc: var EmailFilterCondition, allSome: bool
) =
  if allSome or rng.rand(0 .. 9) < 3:
    fc.text = Opt.some(rng.genPrintableString(30))
  if allSome or rng.rand(0 .. 9) < 3:
    fc.fromAddr = Opt.some(rng.genPrintableString(30))
  if allSome or rng.rand(0 .. 9) < 3:
    fc.to = Opt.some(rng.genPrintableString(30))
  if allSome or rng.rand(0 .. 9) < 3:
    fc.cc = Opt.some(rng.genPrintableString(30))

proc fillTextSearchFilterFields2(
    rng: var Rand, fc: var EmailFilterCondition, allSome: bool
) =
  if allSome or rng.rand(0 .. 9) < 3:
    fc.bcc = Opt.some(rng.genPrintableString(30))
  if allSome or rng.rand(0 .. 9) < 3:
    fc.subject = Opt.some(rng.genPrintableString(30))
  if allSome or rng.rand(0 .. 9) < 3:
    fc.body = Opt.some(rng.genPrintableString(30))

proc genEmailFilterCondition*(rng: var Rand, trial: int = -1): EmailFilterCondition =
  if trial == 0:
    return EmailFilterCondition()
  let allSome = trial == 1
  var fc = EmailFilterCondition()
  rng.fillMailboxFilterFields(fc, allSome)
  rng.fillDateSizeFilterFields(fc, allSome)
  rng.fillThreadKeywordFilterFields(fc, allSome)
  rng.fillPerEmailKeywordFilterFields(fc, allSome)
  if allSome or rng.rand(0 .. 9) < 3:
    fc.hasAttachment = Opt.some(rng.rand(0 .. 1) == 0)
  rng.fillTextSearchFilterFields(fc, allSome)
  rng.fillTextSearchFilterFields2(fc, allSome)
  if allSome or rng.rand(0 .. 9) < 3:
    fc.header = Opt.some(rng.genEmailHeaderFilter())
  fc

# -- Stress generator --

proc genDeepBodyStructure*(rng: var Rand, depth: int): EmailBodyPart =
  let sf = rng.genBodyPartSharedFields()
  if depth <= 0:
    return EmailBodyPart(
      headers: sf.hdrs,
      name: sf.name,
      contentType: "text/plain",
      charset: Opt.some("utf-8"),
      disposition: sf.disposition,
      cid: sf.cid,
      language: sf.language,
      location: sf.location,
      size: UnsignedInt(rng.rand(1'i64 .. 50000'i64)),
      isMultipart: false,
      partId: rng.genPartId(),
      blobId: Id(rng.genValidIdStrict(minLen = 3, maxLen = 20)),
    )
  var children: seq[EmailBodyPart] = @[]
  children.add(rng.genDeepBodyStructure(depth - 1))
  if rng.rand(0 .. 1) == 0:
    children.add(rng.genEmailBodyPart(0))
  EmailBodyPart(
    headers: sf.hdrs,
    name: sf.name,
    contentType: "multipart/mixed",
    charset: Opt.none(string),
    disposition: sf.disposition,
    cid: sf.cid,
    language: sf.language,
    location: sf.location,
    size: UnsignedInt(0),
    isMultipart: true,
    subParts: children,
  )

# -- Composite generators --

proc genEmail*(rng: var Rand): Email =
  let ch = rng.genConvenienceHeaders()
  let bf = rng.genBodyFields()
  let dh = rng.genDynamicHeaders()
  var rawHeaders: seq[EmailHeader] = @[]
  for _ in 0 ..< rng.rand(0 .. 3):
    rawHeaders.add(rng.genEmailHeader())
  Email(
    id: Id(rng.genValidIdStrict()),
    blobId: Id(rng.genValidIdStrict()),
    threadId: Id(rng.genValidIdStrict()),
    mailboxIds: rng.genMailboxIdSet(),
    keywords: rng.genKeywordSet(),
    size: parseUnsignedInt(rng.genValidUnsignedInt()).get(),
    receivedAt: parseUtcDate(rng.genValidUtcDate()).get(),
    messageId: ch.messageId,
    inReplyTo: ch.inReplyTo,
    references: ch.references,
    sender: ch.sender,
    fromAddr: ch.fromAddr,
    to: ch.to,
    cc: ch.cc,
    bcc: ch.bcc,
    replyTo: ch.replyTo,
    subject: ch.subject,
    sentAt: ch.sentAt,
    headers: rawHeaders,
    requestedHeaders: dh.requestedHeaders,
    requestedHeadersAll: dh.requestedHeadersAll,
    bodyStructure: bf.bodyStructure,
    bodyValues: bf.bodyValues,
    textBody: bf.textBody,
    htmlBody: bf.htmlBody,
    attachments: bf.attachments,
    hasAttachment: bf.hasAttachment,
    preview: bf.preview,
  )

proc genParsedEmail*(rng: var Rand): ParsedEmail =
  let ch = rng.genConvenienceHeaders()
  let bf = rng.genBodyFields()
  let dh = rng.genDynamicHeaders()
  var rawHeaders: seq[EmailHeader] = @[]
  for _ in 0 ..< rng.rand(0 .. 3):
    rawHeaders.add(rng.genEmailHeader())
  let threadId =
    if rng.rand(0 .. 1) == 0:
      Opt.some(Id(rng.genValidIdStrict()))
    else:
      Opt.none(Id)
  ParsedEmail(
    threadId: threadId,
    messageId: ch.messageId,
    inReplyTo: ch.inReplyTo,
    references: ch.references,
    sender: ch.sender,
    fromAddr: ch.fromAddr,
    to: ch.to,
    cc: ch.cc,
    bcc: ch.bcc,
    replyTo: ch.replyTo,
    subject: ch.subject,
    sentAt: ch.sentAt,
    headers: rawHeaders,
    requestedHeaders: dh.requestedHeaders,
    requestedHeadersAll: dh.requestedHeadersAll,
    bodyStructure: bf.bodyStructure,
    bodyValues: bf.bodyValues,
    textBody: bf.textBody,
    htmlBody: bf.htmlBody,
    attachments: bf.attachments,
    hasAttachment: bf.hasAttachment,
    preview: bf.preview,
  )

# ---------------------------------------------------------------------------
# Mail Part E generators (J-1..J-16) — design §6.3, §6.5.3
# ---------------------------------------------------------------------------

# J-1 ------------------------------------------------------------------------
proc genBlueprintEmailHeaderName*(
    rng: var Rand, trial: int = -1
): BlueprintEmailHeaderName =
  ## Generates valid ``BlueprintEmailHeaderName`` values (construction gated
  ## by ``parseBlueprintEmailHeaderName``: non-empty, printable 0x21..0x7E,
  ## no colon, not ``content-``-prefixed). Names are normalised to lowercase.
  ## Covers: minimal length (``"a"``), max-length printable-no-colon,
  ## mixed-case round-trip, a ``"content"`` bare name (allowed — only the
  ## ``content-`` prefix is rejected).
  ## Does NOT generate: invalid names (use ``genInvalidBlueprintEmailHeaderName``
  ## for those), names with colon, names with non-printable bytes.
  if trial >= 0 and trial < 6:
    const earlyNames = [
      "a", "X-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij", "X-Foo", "X-BAR", "X-baZ",
      "content",
    ]
    return parseBlueprintEmailHeaderName(earlyNames[trial]).get()
  let length = rng.rand(1 .. 40)
  var s = newString(length)
  for i in 0 ..< length:
    # 0x21..0x7E minus ':' (0x3A)
    var c = char(rng.rand(0x21 .. 0x7E))
    while c == ':':
      c = char(rng.rand(0x21 .. 0x7E))
    s[i] = c
  # Avoid content- prefix — prepend 'x-' if the random body would start that way.
  if s.toLowerAscii().startsWith("content-"):
    s = "x-" & s
  parseBlueprintEmailHeaderName(s).get()

# J-2 ------------------------------------------------------------------------
proc genInvalidBlueprintEmailHeaderName*(rng: var Rand, trial: int = -1): string =
  ## Generates strings that ``parseBlueprintEmailHeaderName`` rejects.
  ## Covers: empty string, ``content-`` family, wire-form literals (colon),
  ## whitespace-containing, NUL-containing, and the shortest ``content-``
  ## prefix (``"content-"`` with no body).
  ## Does NOT generate: strings that happen to pass validation (those would
  ## belong in J-1); exhaustive adversarial bytes (``genMaliciousString`` is
  ## the dedicated source for those).
  if trial >= 0 and trial < 6:
    const earlyStrings = [
      "", "Content-Type", "header:From:asText", "X-Has Space", "X-Has\x00NUL",
      "content-",
    ]
    return earlyStrings[trial]
  rng.genMaliciousString(trial)

# J-3 ------------------------------------------------------------------------
proc genBlueprintBodyHeaderName*(
    rng: var Rand, trial: int = -1
): BlueprintBodyHeaderName =
  ## Generates valid ``BlueprintBodyHeaderName`` values (construction gated
  ## by ``parseBlueprintBodyHeaderName``: non-empty, printable 0x21..0x7E,
  ## no colon, not exactly ``content-transfer-encoding``). The ``Content-*``
  ## family IS permitted on body parts — only CTE is blocked.
  ## Covers: ``content-type`` (allowed on body parts), ``content-disposition``
  ## (allowed), ``X-Custom`` (user-defined), ``content-transfer-encoding-x``
  ## (near-miss: not the exact rejected name, so passes).
  ## Does NOT generate: ``content-transfer-encoding`` exactly, empty,
  ## colon-bearing, non-printable.
  if trial >= 0 and trial < 4:
    const earlyNames =
      ["Content-Type", "Content-Disposition", "X-Custom", "Content-Transfer-Encoding-X"]
    return parseBlueprintBodyHeaderName(earlyNames[trial]).get()
  let length = rng.rand(1 .. 40)
  var s = newString(length)
  for i in 0 ..< length:
    var c = char(rng.rand(0x21 .. 0x7E))
    while c == ':':
      c = char(rng.rand(0x21 .. 0x7E))
    s[i] = c
  if s.toLowerAscii() == "content-transfer-encoding":
    s = "x-" & s
  parseBlueprintBodyHeaderName(s).get()

proc genInvalidBlueprintBodyHeaderName*(rng: var Rand, trial: int = -1): string =
  ## Generates strings that ``parseBlueprintBodyHeaderName`` rejects.
  ## Covers: empty, exact ``content-transfer-encoding`` (+ case variants),
  ## colon-bearing, whitespace, NUL-bearing.
  ## Does NOT generate: valid body-header names (those belong in J-3's
  ## positive branch).
  if trial >= 0 and trial < 5:
    const earlyStrings = [
      "", "Content-Transfer-Encoding", "content-transfer-encoding", "X-Has Space",
      "X-Has\x00NUL",
    ]
    return earlyStrings[trial]
  rng.genMaliciousString(trial)

# J-6 ------------------------------------------------------------------------
proc genNonEmptySeq*[T](
    rng: var Rand,
    genElem: proc(rng: var Rand): T {.noSideEffect, raises: [].},
    trial: int = -1,
): NonEmptySeq[T] =
  ## Generic non-empty-seq generator. Composes an element generator up to
  ## 10 times; early trials hit the boundaries (len 1, len 2).
  ## Covers: minimum length (1), len 2, random length up to 10.
  ## Does NOT generate: empty seqs (rejected by ``parseNonEmptySeq``), or
  ## lengths beyond 10 (extraHeaders-form cardinality rarely exceeds a
  ## handful in practice; larger fan-outs are covered by adversarial
  ## generators J-15).
  let length =
    if trial >= 0 and trial < 2:
      [1, 2][trial]
    else:
      rng.rand(1 .. 10)
  var s: seq[T] = @[]
  for _ in 0 ..< length:
    s.add(genElem(rng))
  parseNonEmptySeq(s).get()

# J-4 ------------------------------------------------------------------------
proc genRawValue(rng: var Rand): string =
  ## One raw header value. Printable ASCII, 1..40 chars.
  let length = rng.rand(1 .. 40)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genAsciiPrintable()

proc genTextValue(rng: var Rand): string =
  ## One structured-text header value. Printable ASCII, 1..40 chars.
  let length = rng.rand(1 .. 40)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genAsciiPrintable()

proc genAddressListValue(rng: var Rand): seq[EmailAddress] =
  ## One address-list element (for ``hfAddresses``).
  let count = rng.rand(1 .. 3)
  result = @[]
  for _ in 0 ..< count:
    result.add(rng.genEmailAddress())

proc genGroupedAddressListValue(rng: var Rand): seq[EmailAddressGroup] =
  ## One grouped-address-list element (for ``hfGroupedAddresses``).
  let count = rng.rand(1 .. 2)
  result = @[]
  for _ in 0 ..< count:
    result.add(rng.genEmailAddressGroup())

proc genMessageIdListValue(rng: var Rand): seq[string] =
  ## One Message-Id list element (for ``hfMessageIds``).
  let count = rng.rand(1 .. 3)
  result = @[]
  for i in 0 ..< count:
    result.add("<mid" & $i & "@example.com>")

proc genUrlListValue(rng: var Rand): seq[string] =
  ## One URL list element (for ``hfUrls``).
  let count = rng.rand(1 .. 2)
  result = @[]
  for i in 0 ..< count:
    result.add("https://example.com/" & $i)

proc genDateValue(rng: var Rand): Date =
  ## One Date element (for ``hfDate``).
  parseDate(rng.genValidDate()).get()

proc genBlueprintHeaderMultiValue*(
    rng: var Rand, form: HeaderForm, trial: int = -1
): BlueprintHeaderMultiValue =
  ## Generates a ``BlueprintHeaderMultiValue`` for the given ``form``.
  ## Covers: single-value case (len 1, triggers no ``:all`` suffix) and
  ## multi-value case (len 2, triggers the ``:all`` suffix). Delegates
  ## per-form element construction to private helpers above.
  ## Does NOT generate: cross-form mismatches (each invocation fixes one
  ## ``HeaderForm``), or lengths beyond 10.
  case form
  of hfRaw:
    BlueprintHeaderMultiValue(
      form: hfRaw, rawValues: rng.genNonEmptySeq(genRawValue, trial)
    )
  of hfText:
    BlueprintHeaderMultiValue(
      form: hfText, textValues: rng.genNonEmptySeq(genTextValue, trial)
    )
  of hfAddresses:
    BlueprintHeaderMultiValue(
      form: hfAddresses, addressLists: rng.genNonEmptySeq(genAddressListValue, trial)
    )
  of hfGroupedAddresses:
    BlueprintHeaderMultiValue(
      form: hfGroupedAddresses,
      groupLists: rng.genNonEmptySeq(genGroupedAddressListValue, trial),
    )
  of hfMessageIds:
    BlueprintHeaderMultiValue(
      form: hfMessageIds,
      messageIdLists: rng.genNonEmptySeq(genMessageIdListValue, trial),
    )
  of hfDate:
    BlueprintHeaderMultiValue(
      form: hfDate, dateValues: rng.genNonEmptySeq(genDateValue, trial)
    )
  of hfUrls:
    BlueprintHeaderMultiValue(
      form: hfUrls, urlLists: rng.genNonEmptySeq(genUrlListValue, trial)
    )

# J-5 ------------------------------------------------------------------------
proc genNonEmptyMailboxIdSet*(rng: var Rand, trial: int = -1): NonEmptyMailboxIdSet =
  ## Generates valid ``NonEmptyMailboxIdSet`` values with varying cardinality.
  ## Covers: len 1 (boundary), len 2 with a duplicate that collapses to 1,
  ## 2..20 distinct Ids.
  ## Does NOT generate: empty seqs (rejected by
  ## ``parseNonEmptyMailboxIdSet``), invalid ID payloads, sets >20 elements.
  if trial >= 0 and trial < 3:
    case trial
    of 0:
      return parseNonEmptyMailboxIdSet(@[parseId("mbx-0").get()]).get()
    of 1:
      let id = parseId("mbx-dup").get()
      return parseNonEmptyMailboxIdSet(@[id, id, id]).get()
    else:
      return parseNonEmptyMailboxIdSet(
          @[parseId("mbx-a").get(), parseId("mbx-b").get()]
        )
        .get()
  let count = rng.rand(1 .. 20)
  var ids: seq[Id] = @[]
  for i in 0 ..< count:
    ids.add(parseId("mbx-" & $i).get())
  parseNonEmptyMailboxIdSet(ids).get()

# J-7 ------------------------------------------------------------------------
proc genBlueprintBodyValue*(rng: var Rand, trial: int = -1): BlueprintBodyValue =
  ## Generates a ``BlueprintBodyValue`` with varying content shape.
  ## Covers: empty string, control bytes, 64 KiB payload, short printable.
  ## Does NOT generate: invalid-encoding or truncated states — those are
  ## fields on ``EmailBodyValue`` (the read model), not ``BlueprintBodyValue``,
  ## which intentionally strips them (illegal on creation, §4.6 constraint 6).
  if trial >= 0 and trial < 4:
    const earlyValues = ["", "\x00\x01", "", "Hello"]
    if trial == 2:
      return BlueprintBodyValue(value: 'a'.repeat(65536))
    return BlueprintBodyValue(value: earlyValues[trial])
  let length = rng.rand(0 .. 1000)
  var s = newString(length)
  for i in 0 ..< length:
    s[i] = rng.genAsciiPrintable()
  BlueprintBodyValue(value: s)

# J-8 helpers ---------------------------------------------------------------
proc genBlueprintPartCid(rng: var Rand): Opt[string] =
  if rng.rand(0 .. 4) == 0:
    Opt.some("cid" & $rng.rand(1 .. 999) & "@example.com")
  else:
    Opt.none(string)

proc genBlueprintPartLocation(rng: var Rand): Opt[string] =
  if rng.rand(0 .. 4) == 0:
    Opt.some("https://example.com/part/" & $rng.rand(1 .. 999))
  else:
    Opt.none(string)

proc genBlueprintPartLanguage(rng: var Rand): Opt[seq[string]] =
  if rng.rand(0 .. 3) == 0:
    Opt.some(@["en"])
  else:
    Opt.none(seq[string])

proc genBlueprintPartName(rng: var Rand): Opt[string] =
  if rng.rand(0 .. 2) == 0:
    Opt.some("file" & $rng.rand(1 .. 99) & ".dat")
  else:
    Opt.none(string)

proc genBlueprintPartDisposition(rng: var Rand): Opt[string] =
  if rng.rand(0 .. 2) == 0:
    Opt.some(rng.oneOf(["inline", "attachment"]))
  else:
    Opt.none(string)

proc genBodyPartExtraHeaders(
    rng: var Rand
): Table[BlueprintBodyHeaderName, BlueprintHeaderMultiValue] =
  result = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  let count = rng.rand(0 .. 2)
  for i in 0 ..< count:
    let name = parseBlueprintBodyHeaderName("x-body-" & $rng.rand(0 .. 999)).get()
    if name notin result:
      result[name] = rng.genBlueprintHeaderMultiValue(hfText)

# J-8 ------------------------------------------------------------------------
proc genBlueprintBodyPart*(rng: var Rand, maxDepth: int = 4): BlueprintBodyPart =
  ## Generates a ``BlueprintBodyPart`` tree with depth <= ``maxDepth``.
  ## Leaves alternate between ``bpsInline`` (co-located partId+value) and
  ## ``bpsBlobRef`` (uploaded-blob reference). Multipart containers carry
  ## 0..3 recursive children. ``MaxBodyPartDepth`` is the hard cap —
  ## callers that want pathological depths construct them directly.
  ## Covers: inline leaves, blob-ref leaves, multipart containers,
  ## optional fields (``name`` / ``disposition`` / ``cid`` / ``language``
  ## / ``location``).
  ## Does NOT generate: trees of depth > ``MaxBodyPartDepth`` (would be
  ## rejected by ``parseEmailBlueprint``), colliding ``partId`` across
  ## sibling leaves (documented gap §7 E30 — last-wins applies).
  const leafTypes = ["text/plain", "text/html", "image/png", "application/pdf"]
  const multipartTypes =
    ["multipart/mixed", "multipart/alternative", "multipart/related"]

  if maxDepth <= 0 or rng.rand(0 .. 1) == 0:
    let ct = rng.oneOf(leafTypes)
    let name = rng.genBlueprintPartName()
    let disposition = rng.genBlueprintPartDisposition()
    let cid = rng.genBlueprintPartCid()
    let language = rng.genBlueprintPartLanguage()
    let location = rng.genBlueprintPartLocation()
    let extraHeaders = rng.genBodyPartExtraHeaders()
    if rng.rand(0 .. 1) == 0:
      return BlueprintBodyPart(
        contentType: ct,
        name: name,
        disposition: disposition,
        cid: cid,
        language: language,
        location: location,
        extraHeaders: extraHeaders,
        isMultipart: false,
        source: bpsInline,
        partId: rng.genPartId(),
        value: rng.genBlueprintBodyValue(),
      )
    return BlueprintBodyPart(
      contentType: ct,
      name: name,
      disposition: disposition,
      cid: cid,
      language: language,
      location: location,
      extraHeaders: extraHeaders,
      isMultipart: false,
      source: bpsBlobRef,
      blobId: Id(rng.genValidIdStrict(minLen = 3, maxLen = 20)),
      size: Opt.none(UnsignedInt),
      charset: Opt.none(string),
    )
  let ct = rng.oneOf(multipartTypes)
  var children: seq[BlueprintBodyPart] = @[]
  for _ in 0 ..< rng.rand(0 .. 3):
    children.add(rng.genBlueprintBodyPart(maxDepth - 1))
  BlueprintBodyPart(
    contentType: ct,
    name: rng.genBlueprintPartName(),
    disposition: rng.genBlueprintPartDisposition(),
    cid: rng.genBlueprintPartCid(),
    language: rng.genBlueprintPartLanguage(),
    location: rng.genBlueprintPartLocation(),
    extraHeaders: rng.genBodyPartExtraHeaders(),
    isMultipart: true,
    subParts: children,
  )

# J-9 ------------------------------------------------------------------------
proc genEmailBlueprintBody*(rng: var Rand, trial: int = -1): EmailBlueprintBody =
  ## Generates an ``EmailBlueprintBody`` (case object discriminated on
  ## ``EmailBodyKind``).
  ## Covers: empty ``flatBody()``; ``structuredBody`` with a multipart
  ## root; ``flatBody`` with textBody + htmlBody + 2 attachments.
  ## Does NOT generate: flat bodies whose textBody isn't text/plain (would
  ## fail ``parseEmailBlueprint`` constraint 5a) or htmlBody isn't text/html
  ## (5b) — use the adversarial generator J-15 for those.
  if trial >= 0 and trial < 3:
    case trial
    of 0:
      return flatBody()
    of 1:
      return structuredBody(
        BlueprintBodyPart(
          contentType: "multipart/mixed",
          name: Opt.none(string),
          disposition: Opt.none(string),
          cid: Opt.none(string),
          language: Opt.none(seq[string]),
          location: Opt.none(string),
          extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
          isMultipart: true,
          subParts: @[rng.genBlueprintBodyPart(maxDepth = 1)],
        )
      )
    else:
      let textLeaf = BlueprintBodyPart(
        contentType: "text/plain",
        name: Opt.none(string),
        disposition: Opt.none(string),
        cid: Opt.none(string),
        language: Opt.none(seq[string]),
        location: Opt.none(string),
        extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
        isMultipart: false,
        source: bpsInline,
        partId: rng.genPartId(),
        value: rng.genBlueprintBodyValue(),
      )
      let htmlLeaf = BlueprintBodyPart(
        contentType: "text/html",
        name: Opt.none(string),
        disposition: Opt.none(string),
        cid: Opt.none(string),
        language: Opt.none(seq[string]),
        location: Opt.none(string),
        extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
        isMultipart: false,
        source: bpsInline,
        partId: rng.genPartId(),
        value: rng.genBlueprintBodyValue(),
      )
      return flatBody(
        textBody = Opt.some(textLeaf),
        htmlBody = Opt.some(htmlLeaf),
        attachments = @[
          rng.genBlueprintBodyPart(maxDepth = 1), rng.genBlueprintBodyPart(maxDepth = 1)
        ],
      )
  # Random: 50/50 structured vs flat.
  if rng.rand(0 .. 1) == 0:
    structuredBody(rng.genBlueprintBodyPart(maxDepth = 3))
  else:
    let textLeaf =
      if rng.rand(0 .. 1) == 0:
        Opt.some(
          BlueprintBodyPart(
            contentType: "text/plain",
            name: Opt.none(string),
            disposition: Opt.none(string),
            cid: Opt.none(string),
            language: Opt.none(seq[string]),
            location: Opt.none(string),
            extraHeaders:
              initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
            isMultipart: false,
            source: bpsInline,
            partId: rng.genPartId(),
            value: rng.genBlueprintBodyValue(),
          )
        )
      else:
        Opt.none(BlueprintBodyPart)
    let htmlLeaf =
      if rng.rand(0 .. 1) == 0:
        Opt.some(
          BlueprintBodyPart(
            contentType: "text/html",
            name: Opt.none(string),
            disposition: Opt.none(string),
            cid: Opt.none(string),
            language: Opt.none(seq[string]),
            location: Opt.none(string),
            extraHeaders:
              initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
            isMultipart: false,
            source: bpsInline,
            partId: rng.genPartId(),
            value: rng.genBlueprintBodyValue(),
          )
        )
      else:
        Opt.none(BlueprintBodyPart)
    var attachments: seq[BlueprintBodyPart] = @[]
    let attCount = rng.rand(0 .. 2)
    for _ in 0 ..< attCount:
      attachments.add(rng.genBlueprintBodyPart(maxDepth = 1))
    flatBody(textBody = textLeaf, htmlBody = htmlLeaf, attachments = attachments)

# J-10 -----------------------------------------------------------------------
proc genEmailBlueprint*(rng: var Rand, trial: int = -1): EmailBlueprint =
  ## Generates a valid ``EmailBlueprint``. Trial biasing picks minimal and
  ## maximal fixtures early, then composes random content for the rest.
  ## Composes J-5 (mailboxIds), J-9 (body), J-4 (header values).
  ## Covers: minimal blueprint (single mailbox, empty body), fully-populated
  ## blueprint (every convenience field set, one extraHeaders entry), random
  ## compositions.
  ## Does NOT generate: blueprints that would fail ``parseEmailBlueprint``
  ## (use J-15 for adversarial composition). Table insertion order matters
  ## for the wire output — J-16 handles permutation testing.
  if trial >= 0 and trial < 2:
    case trial
    of 0:
      return
        parseEmailBlueprint(mailboxIds = rng.genNonEmptyMailboxIdSet(trial = 0)).get()
    else:
      # Fully populated fixture mirroring makeFullEmailBlueprint.
      let alice = parseEmailAddress("alice@example.com", Opt.some("Alice")).get()
      let bob = parseEmailAddress("bob@example.com", Opt.some("Bob")).get()
      var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
      extra[parseBlueprintEmailHeaderName("x-marker").get()] = textSingle("full")
      let textInline = BlueprintBodyPart(
        contentType: "text/plain",
        name: Opt.none(string),
        disposition: Opt.none(string),
        cid: Opt.none(string),
        language: Opt.none(seq[string]),
        location: Opt.none(string),
        extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
        isMultipart: false,
        source: bpsInline,
        partId: parsePartIdFromServer("1").get(),
        value: BlueprintBodyValue(value: "text leaf"),
      )
      let body = flatBody(textBody = Opt.some(textInline))
      return parseEmailBlueprint(
          mailboxIds = rng.genNonEmptyMailboxIdSet(trial = 2),
          body = body,
          keywords = initKeywordSet(@[parseKeyword("$seen").get()]),
          receivedAt = Opt.some(parseUtcDate("2025-01-15T09:00:00Z").get()),
          fromAddr = Opt.some(@[alice]),
          to = Opt.some(@[bob]),
          cc = Opt.some(@[alice]),
          bcc = Opt.some(@[bob]),
          replyTo = Opt.some(@[alice]),
          sender = Opt.some(alice),
          subject = Opt.some("hello"),
          sentAt = Opt.some(parseDate("2025-01-15T08:00:00Z").get()),
          messageId = Opt.some(@["<id1@host>"]),
          inReplyTo = Opt.some(@["<id0@host>"]),
          references = Opt.some(@["<id0@host>"]),
          extraHeaders = extra,
        )
        .get()
  # Random composition — avoid constraint violations by keeping convenience
  # fields and body-part extraHeaders drawn from non-colliding namespaces.
  let ids = rng.genNonEmptyMailboxIdSet()
  let body = rng.genEmailBlueprintBody()
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  let extraCount = rng.rand(0 .. 3)
  for i in 0 ..< extraCount:
    let nameStr = "x-r" & $i & "-" & $rng.rand(0 .. 999)
    let nameRes = parseBlueprintEmailHeaderName(nameStr)
    if nameRes.isOk:
      let name = nameRes.get()
      if name notin extra:
        extra[name] = rng.genBlueprintHeaderMultiValue(hfText)
  let res = parseEmailBlueprint(mailboxIds = ids, body = body, extraHeaders = extra)
  if res.isOk:
    return res.get()
  # Fall back to minimal on unexpected rejection (e.g., depth bias hit).
  parseEmailBlueprint(mailboxIds = ids).get()

# J-11 -----------------------------------------------------------------------
type BlueprintTriggerArgs* {.ruleOff: "objects".} = object
  ## Captured arguments + expected constraint-set for J-11. Property 88
  ## and 94 surface ``$args`` on failure via ``lastInput``.
  mailboxIds*: NonEmptyMailboxIdSet
  body*: EmailBlueprintBody
  fromAddr*: Opt[seq[EmailAddress]]
  subject*: Opt[string]
  extraHeaders*: Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]
  expected*: set[EmailBlueprintConstraint]

proc buildTrigger(
    rng: var Rand, variant: EmailBlueprintConstraint
): BlueprintTriggerArgs =
  ## Per-variant trigger builder. Each branch returns args that fire the
  ## single named constraint. ``ebcBodyPartDepthExceeded`` uses a depth-129
  ## spine; the mutually-exclusive-body variants take the appropriate body
  ## shape.
  case variant
  of ebcEmailTopLevelHeaderDuplicate:
    var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
    extra[parseBlueprintEmailHeaderName("from").get()] = textSingle("v")
    let addr0 = parseEmailAddress("a@b.c", Opt.none(string)).get()
    BlueprintTriggerArgs(
      mailboxIds: rng.genNonEmptyMailboxIdSet(trial = 0),
      body: flatBody(),
      fromAddr: Opt.some(@[addr0]),
      subject: Opt.none(string),
      extraHeaders: extra,
      expected: {ebcEmailTopLevelHeaderDuplicate},
    )
  of ebcBodyStructureHeaderDuplicate:
    var rootExtra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
    rootExtra[parseBlueprintBodyHeaderName("from").get()] = textSingle("v")
    let root = BlueprintBodyPart(
      contentType: "multipart/mixed",
      name: Opt.none(string),
      disposition: Opt.none(string),
      cid: Opt.none(string),
      language: Opt.none(seq[string]),
      location: Opt.none(string),
      extraHeaders: rootExtra,
      isMultipart: true,
      subParts: @[],
    )
    var topExtra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
    topExtra[parseBlueprintEmailHeaderName("from").get()] = textSingle("v")
    BlueprintTriggerArgs(
      mailboxIds: rng.genNonEmptyMailboxIdSet(trial = 0),
      body: structuredBody(root),
      fromAddr: Opt.none(seq[EmailAddress]),
      subject: Opt.none(string),
      extraHeaders: topExtra,
      expected: {ebcBodyStructureHeaderDuplicate},
    )
  of ebcBodyPartHeaderDuplicate:
    var partExtra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
    partExtra[parseBlueprintBodyHeaderName("content-type").get()] = textSingle("v")
    let leaf = BlueprintBodyPart(
      contentType: "text/plain",
      name: Opt.none(string),
      disposition: Opt.none(string),
      cid: Opt.none(string),
      language: Opt.none(seq[string]),
      location: Opt.none(string),
      extraHeaders: partExtra,
      isMultipart: false,
      source: bpsInline,
      partId: parsePartIdFromServer("1").get(),
      value: BlueprintBodyValue(value: "v"),
    )
    BlueprintTriggerArgs(
      mailboxIds: rng.genNonEmptyMailboxIdSet(trial = 0),
      body: flatBody(textBody = Opt.some(leaf)),
      fromAddr: Opt.none(seq[EmailAddress]),
      subject: Opt.none(string),
      extraHeaders: initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue](),
      expected: {ebcBodyPartHeaderDuplicate},
    )
  of ebcTextBodyNotTextPlain:
    let leaf = BlueprintBodyPart(
      contentType: "application/pdf",
      name: Opt.none(string),
      disposition: Opt.none(string),
      cid: Opt.none(string),
      language: Opt.none(seq[string]),
      location: Opt.none(string),
      extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
      isMultipart: false,
      source: bpsInline,
      partId: parsePartIdFromServer("1").get(),
      value: BlueprintBodyValue(value: "v"),
    )
    BlueprintTriggerArgs(
      mailboxIds: rng.genNonEmptyMailboxIdSet(trial = 0),
      body: flatBody(textBody = Opt.some(leaf)),
      fromAddr: Opt.none(seq[EmailAddress]),
      subject: Opt.none(string),
      extraHeaders: initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue](),
      expected: {ebcTextBodyNotTextPlain},
    )
  of ebcHtmlBodyNotTextHtml:
    let leaf = BlueprintBodyPart(
      contentType: "text/plain",
      name: Opt.none(string),
      disposition: Opt.none(string),
      cid: Opt.none(string),
      language: Opt.none(seq[string]),
      location: Opt.none(string),
      extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
      isMultipart: false,
      source: bpsInline,
      partId: parsePartIdFromServer("1").get(),
      value: BlueprintBodyValue(value: "v"),
    )
    BlueprintTriggerArgs(
      mailboxIds: rng.genNonEmptyMailboxIdSet(trial = 0),
      body: flatBody(htmlBody = Opt.some(leaf)),
      fromAddr: Opt.none(seq[EmailAddress]),
      subject: Opt.none(string),
      extraHeaders: initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue](),
      expected: {ebcHtmlBodyNotTextHtml},
    )
  of ebcAllowedFormRejected:
    var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
    extra[parseBlueprintEmailHeaderName("subject").get()] =
      dateSingle(parseDate("2025-01-15T09:00:00Z").get())
    BlueprintTriggerArgs(
      mailboxIds: rng.genNonEmptyMailboxIdSet(trial = 0),
      body: flatBody(),
      fromAddr: Opt.none(seq[EmailAddress]),
      subject: Opt.none(string),
      extraHeaders: extra,
      expected: {ebcAllowedFormRejected},
    )
  of ebcBodyPartDepthExceeded:
    # Build a depth-129 spine of multipart containers around one leaf.
    var leaf: BlueprintBodyPart = BlueprintBodyPart(
      contentType: "text/plain",
      name: Opt.none(string),
      disposition: Opt.none(string),
      cid: Opt.none(string),
      language: Opt.none(seq[string]),
      location: Opt.none(string),
      extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
      isMultipart: false,
      source: bpsInline,
      partId: parsePartIdFromServer("1").get(),
      value: BlueprintBodyValue(value: "v"),
    )
    for _ in 0 .. 128:
      leaf = BlueprintBodyPart(
        contentType: "multipart/mixed",
        name: Opt.none(string),
        disposition: Opt.none(string),
        cid: Opt.none(string),
        language: Opt.none(seq[string]),
        location: Opt.none(string),
        extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
        isMultipart: true,
        subParts: @[leaf],
      )
    BlueprintTriggerArgs(
      mailboxIds: rng.genNonEmptyMailboxIdSet(trial = 0),
      body: structuredBody(leaf),
      fromAddr: Opt.none(seq[EmailAddress]),
      subject: Opt.none(string),
      extraHeaders: initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue](),
      expected: {ebcBodyPartDepthExceeded},
    )

proc genBlueprintErrorTrigger*(rng: var Rand, trial: int = -1): BlueprintTriggerArgs =
  ## Generates ``parseEmailBlueprint`` args that fire at least one named
  ## constraint variant on the error rail. Early trials 0..6 bijection one
  ## variant each (bijection over the 7-variant ``EmailBlueprintConstraint``
  ## enum); later trials pick one at random.
  ## Covers: every ``EmailBlueprintConstraint`` variant at least once via
  ## the first seven trials.
  ## Does NOT generate: multi-variant composite triggers (scenario 101's
  ## job — lives in the stress suite).
  const variants = [
    ebcEmailTopLevelHeaderDuplicate, ebcBodyStructureHeaderDuplicate,
    ebcBodyPartHeaderDuplicate, ebcTextBodyNotTextPlain, ebcHtmlBodyNotTextHtml,
    ebcAllowedFormRejected, ebcBodyPartDepthExceeded,
  ]
  let idx =
    if trial >= 0 and trial < variants.len:
      trial
    else:
      rng.rand(0 .. variants.len - 1)
  buildTrigger(rng, variants[idx])

# J-12 -----------------------------------------------------------------------
proc genBodyPartPath*(rng: var Rand, trial: int = -1): BodyPartPath =
  ## Generates ``BodyPartPath`` values for locator tests.
  ## Covers: root (``@[]``), depth-1 (``@[0]``), depth-3 (``@[0,1,2]``),
  ## random short paths.
  ## Does NOT generate: paths longer than ``MaxBodyPartDepth``, negative or
  ## ``int.low``/``int.high`` entries (scenario 99f owns that axis).
  if trial >= 0 and trial < 3:
    case trial
    of 0:
      return BodyPartPath(@[])
    of 1:
      return BodyPartPath(@[0])
    else:
      return BodyPartPath(@[0, 1, 2])
  let length = rng.rand(0 .. 8)
  var s: seq[int] = @[]
  for _ in 0 ..< length:
    s.add(rng.rand(0 .. 16))
  BodyPartPath(s)

proc genBodyPartLocation*(rng: var Rand, trial: int = -1): BodyPartLocation =
  ## Generates ``BodyPartLocation`` values across all three kinds.
  ## Covers: inline/blob-ref/multipart — one per early trial.
  ## Does NOT generate: locations with adversarial int payloads (scenario
  ## 99f).
  if trial >= 0 and trial < 3:
    case trial
    of 0:
      return BodyPartLocation(kind: bplInline, partId: rng.genPartId(trial = 0))
    of 1:
      return
        BodyPartLocation(kind: bplBlobRef, blobId: Id(rng.genValidIdStrict(minLen = 3)))
    else:
      return BodyPartLocation(kind: bplMultipart, path: rng.genBodyPartPath(trial = 1))
  case rng.rand(0 .. 2)
  of 0:
    BodyPartLocation(kind: bplInline, partId: rng.genPartId())
  of 1:
    BodyPartLocation(kind: bplBlobRef, blobId: Id(rng.genValidIdStrict(minLen = 3)))
  else:
    BodyPartLocation(kind: bplMultipart, path: rng.genBodyPartPath())

# J-13 -----------------------------------------------------------------------
proc genEmailBlueprintError*(rng: var Rand, trial: int = -1): EmailBlueprintError =
  ## Generates a single ``EmailBlueprintError`` uniformly over the seven
  ## ``EmailBlueprintConstraint`` variants. Payload strings are drawn from
  ## ``genMaliciousString`` / ``genLongArbitraryString`` — the same
  ## adversarial sources the suite already uses, so payload coverage is
  ## centralised. DO NOT reimplement a local NUL/CRLF helper here.
  ## Covers: every variant at least once via the first seven trials; every
  ## payload slot eventually sees adversarial bytes.
  ## Does NOT generate: sealed ``EmailBlueprintErrors`` directly (use
  ## ``genEmailBlueprintErrors`` which constructs via ``parseEmailBlueprint``
  ## triggers).
  const variants = [
    ebcEmailTopLevelHeaderDuplicate, ebcBodyStructureHeaderDuplicate,
    ebcBodyPartHeaderDuplicate, ebcTextBodyNotTextPlain, ebcHtmlBodyNotTextHtml,
    ebcAllowedFormRejected, ebcBodyPartDepthExceeded,
  ]
  let idx =
    if trial >= 0 and trial < variants.len:
      trial
    else:
      rng.rand(0 .. variants.len - 1)
  case variants[idx]
  of ebcEmailTopLevelHeaderDuplicate:
    EmailBlueprintError(
      constraint: ebcEmailTopLevelHeaderDuplicate,
      dupName: rng.genMaliciousString(trial),
    )
  of ebcBodyStructureHeaderDuplicate:
    EmailBlueprintError(
      constraint: ebcBodyStructureHeaderDuplicate,
      bodyStructureDupName: rng.genMaliciousString(trial),
    )
  of ebcBodyPartHeaderDuplicate:
    EmailBlueprintError(
      constraint: ebcBodyPartHeaderDuplicate,
      where: rng.genBodyPartLocation(),
      bodyPartDupName: rng.genMaliciousString(trial),
    )
  of ebcTextBodyNotTextPlain:
    EmailBlueprintError(
      constraint: ebcTextBodyNotTextPlain,
      actualTextType: rng.genLongArbitraryString(trial, maxLen = 1024),
    )
  of ebcHtmlBodyNotTextHtml:
    EmailBlueprintError(
      constraint: ebcHtmlBodyNotTextHtml,
      actualHtmlType: rng.genLongArbitraryString(trial, maxLen = 1024),
    )
  of ebcAllowedFormRejected:
    EmailBlueprintError(
      constraint: ebcAllowedFormRejected,
      rejectedName: rng.genMaliciousString(trial),
      rejectedForm: rng.oneOf(
        [hfRaw, hfText, hfAddresses, hfGroupedAddresses, hfMessageIds, hfDate, hfUrls]
      ),
    )
  of ebcBodyPartDepthExceeded:
    EmailBlueprintError(
      constraint: ebcBodyPartDepthExceeded,
      observedDepth: rng.rand(129 .. 10_000),
      depthLocation: rng.genBodyPartLocation(),
    )

proc genEmailBlueprintErrors*(rng: var Rand, trial: int = -1): EmailBlueprintErrors =
  ## Generates a non-empty ``EmailBlueprintErrors`` aggregate by composing
  ## triggers and running them through the public smart constructor
  ## ``parseEmailBlueprint``. Pattern A seal means that IS the only
  ## construction path — no internal short-cut exists.
  ## Covers: 1..3 simultaneous triggers (composed over the same args).
  ## Does NOT generate: empty aggregates (sealed type forbids that state).
  let args = rng.genBlueprintErrorTrigger(trial)
  let res = parseEmailBlueprint(
    mailboxIds = args.mailboxIds,
    body = args.body,
    fromAddr = args.fromAddr,
    subject = args.subject,
    extraHeaders = args.extraHeaders,
  )
  doAssert res.isErr
  res.unsafeError

# J-14 -----------------------------------------------------------------------
proc genEmailBlueprintDelta*(
    rng: var Rand, trial: int = -1
): tuple[a, b: EmailBlueprint] =
  ## Generates a pair of blueprints differing in exactly one observable
  ## field — subject, one extraHeaders entry, or one Opt flip. Property 91
  ## (injectivity) relies on the inequality precondition.
  ## Covers: subject difference, extraHeaders cardinality difference,
  ## Opt flip on messageId.
  ## Does NOT generate: equal blueprints, blueprints differing in
  ## multiple fields simultaneously.
  let ids = rng.genNonEmptyMailboxIdSet()
  let k = rng.rand(0 .. 2)
  case k
  of 0:
    # Subject difference: a has subject, b is otherwise identical but lacks it.
    let a = parseEmailBlueprint(
        mailboxIds = ids, subject = Opt.some("alpha-" & $rng.rand(0 .. 9_999))
      )
      .get()
    let b = parseEmailBlueprint(mailboxIds = ids, subject = Opt.none(string)).get()
    (a: a, b: b)
  of 1:
    # extraHeaders cardinality: a has one entry, b has none.
    var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
    extra[parseBlueprintEmailHeaderName("x-delta").get()] =
      textSingle("v-" & $rng.rand(0 .. 9_999))
    let a = parseEmailBlueprint(mailboxIds = ids, extraHeaders = extra).get()
    let b = parseEmailBlueprint(mailboxIds = ids).get()
    (a: a, b: b)
  else:
    # messageId Opt flip.
    let a = parseEmailBlueprint(
        mailboxIds = ids, messageId = Opt.some(@["<m-" & $rng.rand(0 .. 9_999) & "@h>"])
      )
      .get()
    let b =
      parseEmailBlueprint(mailboxIds = ids, messageId = Opt.none(seq[string])).get()
    (a: a, b: b)

# J-15 -----------------------------------------------------------------------
type BlueprintCtorArgs* {.ruleOff: "objects".} = object
  ## Argument packet for property 95's adversarial totality trial.
  ## ``lastInput`` is set from a stringified digest so failures report
  ## which adversarial shape tripped the assertion.
  mailboxIds*: NonEmptyMailboxIdSet
  body*: EmailBlueprintBody
  keywords*: KeywordSet
  receivedAt*: Opt[UTCDate]
  fromAddr*: Opt[seq[EmailAddress]]
  to*: Opt[seq[EmailAddress]]
  cc*: Opt[seq[EmailAddress]]
  bcc*: Opt[seq[EmailAddress]]
  replyTo*: Opt[seq[EmailAddress]]
  sender*: Opt[EmailAddress]
  subject*: Opt[string]
  sentAt*: Opt[Date]
  messageId*: Opt[seq[string]]
  inReplyTo*: Opt[seq[string]]
  references*: Opt[seq[string]]
  extraHeaders*: Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]
  digest*: string

proc genAdversarialSubject(rng: var Rand, trial: int): string =
  rng.genMaliciousString(trial)

proc genAdversarialExtraHeaders(
    rng: var Rand
): Table[BlueprintEmailHeaderName, BlueprintHeaderMultiValue] =
  ## Adversarial header fan-out. Cardinality drawn from {0, 1, 1000}. The
  ## design note called for 10_000 but I-19 caps realistic fan-out at ~1000
  ## before the brute-force collision scan runs out of candidates — adopted
  ## the same ceiling here.
  result = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  const cardOptions = [0, 1, 1000]
  let card = rng.oneOf(cardOptions)
  for i in 0 ..< card:
    let nameStr = "x-adv-" & $i
    let nameRes = parseBlueprintEmailHeaderName(nameStr)
    if nameRes.isOk:
      result[nameRes.get()] = textSingle("v")

proc adversarialDepthBody(rng: var Rand): EmailBlueprintBody =
  ## Body shape with depth drawn from {0, 128, 129, 256} — boundary values
  ## that exercise ``parseEmailBlueprint``'s depth check on both sides of
  ## ``MaxBodyPartDepth``.
  const depths = [0, 128, 129, 256]
  let depth = rng.oneOf(depths)
  var leaf: BlueprintBodyPart = BlueprintBodyPart(
    contentType: "text/plain",
    name: Opt.none(string),
    disposition: Opt.none(string),
    cid: Opt.none(string),
    language: Opt.none(seq[string]),
    location: Opt.none(string),
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    isMultipart: false,
    source: bpsInline,
    partId: parsePartIdFromServer("1").get(),
    value: BlueprintBodyValue(value: "v"),
  )
  for _ in 0 ..< depth:
    leaf = BlueprintBodyPart(
      contentType: "multipart/mixed",
      name: Opt.none(string),
      disposition: Opt.none(string),
      cid: Opt.none(string),
      language: Opt.none(seq[string]),
      location: Opt.none(string),
      extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
      isMultipart: true,
      subParts: @[leaf],
    )
  structuredBody(leaf)

proc genAdversarialBlueprintArgs*(rng: var Rand, trial: int = -1): BlueprintCtorArgs =
  ## Adversarial ctor argument pack — composes malicious subject / body
  ## depth boundaries {0, 128, 129, 256} / header cardinalities {0, 1, 1000}.
  ## Consumers MUST use ``ThoroughTrials`` (property 95's budget of 2000
  ## trials), NOT the default 500 — the input space is large and the
  ## property (no raise) is cheap enough to warrant saturation.
  ## Covers: all four depth boundaries, three cardinalities, ten
  ## ``genMaliciousString`` payloads.
  ## Does NOT generate: adversarial invalid inputs to parsers themselves
  ## (e.g. malformed mailbox Ids — those are J-2/J-3's axis).
  let ids = rng.genNonEmptyMailboxIdSet()
  let body = rng.adversarialDepthBody()
  let extra = rng.genAdversarialExtraHeaders()
  let subject = rng.genAdversarialSubject(trial)
  BlueprintCtorArgs(
    mailboxIds: ids,
    body: body,
    keywords: initKeywordSet(@[]),
    receivedAt: Opt.none(UTCDate),
    fromAddr: Opt.none(seq[EmailAddress]),
    to: Opt.none(seq[EmailAddress]),
    cc: Opt.none(seq[EmailAddress]),
    bcc: Opt.none(seq[EmailAddress]),
    replyTo: Opt.none(seq[EmailAddress]),
    sender: Opt.none(EmailAddress),
    subject: Opt.some(subject),
    sentAt: Opt.none(Date),
    messageId: Opt.none(seq[string]),
    inReplyTo: Opt.none(seq[string]),
    references: Opt.none(seq[string]),
    extraHeaders: extra,
    digest: "trial=" & $trial & " subjectLen=" & $subject.len & " extras=" & $extra.len,
  )

# J-16 -----------------------------------------------------------------------
proc genBlueprintInsertionPermutation*(
    rng: var Rand, trial: int = -1
): tuple[a, permuted: EmailBlueprint] =
  ## Generates a blueprint pair ``(a, permuted)`` whose ``extraHeaders``
  ## Tables were populated in different insertion orders but carry
  ## identical ``(name, value)`` pairs. Property 97e asserts
  ## ``emailBlueprintEq`` ignores insertion order.
  ## Covers: reverse-order (trial 0), random permutations (trials 1..).
  ## Does NOT generate: structurally different Tables (same key-set by
  ## construction).
  let ids = rng.genNonEmptyMailboxIdSet()
  var entries: seq[(BlueprintEmailHeaderName, BlueprintHeaderMultiValue)] = @[]
  let count = rng.rand(2 .. 6)
  var seenNames = initHashSet[string]()
  while entries.len < count:
    let i = entries.len
    let nameStr = "x-perm-" & $i & "-" & $rng.rand(0 .. 999)
    if nameStr in seenNames:
      continue
    seenNames.incl(nameStr)
    let nameRes = parseBlueprintEmailHeaderName(nameStr)
    if nameRes.isOk:
      entries.add((nameRes.get(), textSingle("v" & $i)))

  var tableA = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  for (k, v) in entries:
    tableA[k] = v

  var entriesB: seq[(BlueprintEmailHeaderName, BlueprintHeaderMultiValue)] =
    if trial == 0:
      var reversed = entries
      for i in 0 ..< reversed.len div 2:
        let j = reversed.len - 1 - i
        let tmp = reversed[i]
        reversed[i] = reversed[j]
        reversed[j] = tmp
      reversed
    else:
      var shuffled = entries
      rng.shuffle(shuffled)
      shuffled

  var tableB = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  for (k, v) in entriesB:
    tableB[k] = v

  (
    a: parseEmailBlueprint(mailboxIds = ids, extraHeaders = tableA).get(),
    permuted: parseEmailBlueprint(mailboxIds = ids, extraHeaders = tableB).get(),
  )

{.pop.} # params
{.pop.} # hasDoc
