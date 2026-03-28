# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based testing infrastructure with fixed-seed reproducibility,
## edge-biased generation, and tiered trial counts.

import std/json
import std/random
import std/strutils

import pkg/results

import jmap_client/capabilities
import jmap_client/envelope
import jmap_client/framework
import jmap_client/identifiers
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

# ---------------------------------------------------------------------------
# Property check templates
# ---------------------------------------------------------------------------

template checkProperty*(name: string, body: untyped) =
  ## Runs body DefaultTrials times with an injected `rng` and `trial` variable.
  ## Fixed seed (42) ensures deterministic reproduction.
  block:
    var rng {.inject.} = initRand(42)
    for trial {.inject.} in 0 ..< DefaultTrials:
      body

template checkPropertyN*(name: string, trials: int, body: untyped) =
  ## Runs body `trials` times. Use QuickTrials or ThoroughTrials for non-default
  ## counts.
  block:
    var rng {.inject.} = initRand(42)
    for trial {.inject.} in 0 ..< trials:
      body

# ---------------------------------------------------------------------------
# Composition helpers
# ---------------------------------------------------------------------------

proc oneOf*[T](rng: var Rand, options: openArray[T]): T =
  ## Picks uniformly from a fixed set of values.
  options[rng.rand(0 .. options.high)]

proc genStringFrom*(rng: var Rand, chars: set[char], minLen = 1, maxLen = 20): string =
  ## Builds a string of random length from the given character set.
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
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  chars[rng.rand(chars.high)]

proc genAsciiPrintable*(rng: var Rand): char =
  ## Characters 0x20-0x7E (space through tilde, excluding DEL).
  char(rng.rand(0x20 .. 0x7E))

proc genControlChar*(rng: var Rand): char =
  ## Characters 0x00-0x1F plus DEL (0x7F).
  let i = rng.rand(0 .. 32) # 33 control chars total
  if i == 32:
    return '\x7F'
  char(i)

proc genArbitraryByte*(rng: var Rand): char =
  char(rng.rand(0 .. 255))

# ---------------------------------------------------------------------------
# String generators (edge-biased)
# ---------------------------------------------------------------------------

proc genValidIdStrict*(
    rng: var Rand, trial: int = -1, minLen = 1, maxLen = 255
): string =
  ## Base64url string of 1-255 octets. When trial >= 0, the first few trials
  ## use boundary lengths (1, 2, 254, 255).
  let length =
    if trial >= 0 and trial < 4:
      [1, 2, 254, 255][trial]
    else:
      rng.rand(minLen .. maxLen)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genBase64UrlChar()

proc genArbitraryString*(rng: var Rand, trial: int = -1, maxLen = 512): string =
  ## Arbitrary bytes, 0-512 length. Edge-biased: first trials use "", "\x00",
  ## "\x7F", " ", 255*"A", 256*"A".
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
  ## 0..2^53-1, edge-biased at boundaries.
  if trial >= 0 and trial < 4:
    return [0'i64, 1'i64, MaxUnsignedIntVal - 1, MaxUnsignedIntVal][trial]
  rng.rand(0'i64 .. MaxUnsignedIntVal)

proc genValidJmapInt*(rng: var Rand, trial: int = -1): int64 =
  ## -(2^53-1)..2^53-1, edge-biased at boundaries.
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

proc genValidLenientString*(rng: var Rand, minLen = 1, maxLen = 255): string =
  ## Printable bytes (0x20-0x7E), no control chars. For lenient types like
  ## AccountId, JmapState, and parseIdFromServer.
  let length = rng.rand(minLen .. maxLen)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genAsciiPrintable()

proc genValidAccountId*(rng: var Rand): string =
  ## 1-255 printable ASCII octets (lenient charset).
  rng.genValidLenientString(1, 255)

proc genValidJmapState*(rng: var Rand): string =
  ## Non-empty, no control chars, variable length.
  rng.genValidLenientString(1, 100)

proc genValidMethodCallId*(rng: var Rand): string =
  ## Non-empty. MethodCallId has no control-char restriction, so include
  ## arbitrary bytes.
  let length = rng.rand(1 .. 50)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genArbitraryByte()

proc genValidCreationId*(rng: var Rand): string =
  ## Non-empty, must NOT start with '#'. Rest can be arbitrary.
  let length = rng.rand(1 .. 50)
  result = newString(length)
  # First char: any byte except '#'
  result[0] = block:
    var c = rng.genArbitraryByte()
    while c == '#':
      c = rng.genArbitraryByte()
    c
  for i in 1 ..< length:
    result[i] = rng.genArbitraryByte()

proc genValidPropertyName*(rng: var Rand): string =
  ## Non-empty string, typically short identifier-like.
  rng.genValidLenientString(1, 30)

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
  ## Structurally valid RFC 3339 date-time. Uses safe calendar values (day 1-28)
  ## to avoid calendar validation edge cases.
  let
    year = rng.rand(0 .. 9999)
    month = rng.rand(1 .. 12)
    day = rng.rand(1 .. 28)
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
  let tzChoice = rng.rand(0 .. 2)
  case tzChoice
  of 0:
    result.add 'Z'
  of 1:
    result.add '+'
    result.add zeroPad(rng.rand(0 .. 23), 2)
    result.add ':'
    result.add zeroPad(rng.rand(0 .. 59), 2)
  else:
    result.add '-'
    result.add zeroPad(rng.rand(0 .. 23), 2)
    result.add ':'
    result.add zeroPad(rng.rand(0 .. 59), 2)

proc genValidUtcDate*(rng: var Rand): string =
  ## Structurally valid RFC 3339 date-time ending with 'Z'.
  let
    year = rng.rand(0 .. 9999)
    month = rng.rand(1 .. 12)
    day = rng.rand(1 .. 28)
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
# URI template generators
# ---------------------------------------------------------------------------

proc genValidUriTemplate*(rng: var Rand): string =
  ## Non-empty string resembling a URI template. Includes {variable} patterns.
  const bases = [
    "https://example.com/{accountId}",
    "https://jmap.example.com/api/{accountId}/{blobId}/{name}?type={type}",
    "https://example.com/upload/{accountId}/",
    "https://example.com/events?types={types}&closeafter={closeafter}&ping={ping}",
    "https://example.com/resource",
  ]
  rng.oneOf(bases)

# ---------------------------------------------------------------------------
# Adversarial string generators
# ---------------------------------------------------------------------------

proc genMaliciousString*(rng: var Rand, trial: int): string =
  ## Curated attack payloads for first N trials; random bytes thereafter.
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
  ## Like genArbitraryString but with higher maxLen, same edge-biased first trials.
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
  ## Recursive generator for Filter[int] trees.
  if maxDepth <= 0 or rng.rand(0 .. 2) == 0:
    return filterCondition(rng.rand(int.low .. int.high))
  let op = rng.oneOf([foAnd, foOr, foNot])
  let childCount = rng.rand(0 .. 4)
  var children: seq[Filter[int]] = @[]
  for _ in 0 ..< childCount:
    children.add rng.genFilter(maxDepth - 1)
  filterOperator(op, children)

proc genPatchPath*(rng: var Rand): string =
  ## Random non-empty path strings resembling JSON Pointer segments.
  const paths = [
    "subject", "keywords/$seen", "mailboxIds/mb1", "body/content", "from/0/name",
    "to/0/email", "header:X-Custom", "attachments/0/blobId", "textBody/0/partId",
    "htmlBody/0/partId",
  ]
  rng.oneOf(paths)

proc genInvocation*(rng: var Rand): Invocation =
  ## Random Invocation with a realistic method name and random MethodCallId.
  const methods = ["Mailbox/get", "Email/get", "Email/query", "Email/set", "Thread/get"]
  let name = rng.oneOf(methods)
  let mcidStr = "c" & $rng.rand(0 .. 99)
  let mcid = parseMethodCallId(mcidStr).get()
  Invocation(name: name, arguments: newJObject(), methodCallId: mcid)

proc genValidAccount*(rng: var Rand): Account =
  ## Random Account with realistic structure.
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

{.pop.} # params
{.pop.} # hasDoc
