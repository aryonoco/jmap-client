# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based testing infrastructure with fixed-seed reproducibility,
## edge-biased generation, and tiered trial counts.

import std/json
import std/random
import std/sets
import std/strutils

import pkg/results

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
  ## use boundary lengths clamped to [minLen, maxLen].
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

proc genValidLenientString*(
    rng: var Rand, trial: int = -1, minLen = 1, maxLen = 255
): string =
  ## Printable bytes (0x20-0x7E), no control chars. For lenient types like
  ## AccountId, JmapState, and parseIdFromServer. Edge-biased at boundary
  ## lengths when trial >= 0.
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
  ## 1-255 printable ASCII octets (lenient charset). Edge-biased.
  rng.genValidLenientString(trial, 1, 255)

proc genValidJmapState*(rng: var Rand, trial: int = -1): string =
  ## Non-empty, no control chars, variable length. Edge-biased.
  rng.genValidLenientString(trial, 1, 100)

proc genValidMethodCallId*(rng: var Rand, trial: int = -1): string =
  ## Non-empty. MethodCallId has no control-char restriction, so include
  ## arbitrary bytes. Edge-biased at boundary lengths.
  let length =
    if trial >= 0 and trial < 4:
      [1, 2, 49, 50][trial]
    else:
      rng.rand(1 .. 50)
  result = newString(length)
  for i in 0 ..< length:
    result[i] = rng.genArbitraryByte()

proc genValidCreationId*(rng: var Rand, trial: int = -1): string =
  ## Non-empty, must NOT start with '#'. Rest can be arbitrary. Edge-biased
  ## at boundary lengths.
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
  ## Non-empty string, typically short identifier-like. Edge-biased.
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
# Invalid-input generators (for negative property tests)
# ---------------------------------------------------------------------------

proc genInvalidDate*(rng: var Rand, trial: int = -1): string =
  ## Structurally malformed dates for rejection testing. Edge-biased payloads
  ## cover common failure modes; random trials append arbitrary garbage.
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
  ## Valid Date but non-Z offset (rejected by parseUtcDate).
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

# ---------------------------------------------------------------------------
# Error type generators
# ---------------------------------------------------------------------------

proc genTransportError*(rng: var Rand): TransportError =
  ## Random TransportError across all 4 kind variants.
  let kinds = [tekNetwork, tekTls, tekTimeout, tekHttpStatus]
  let kind = rng.oneOf(kinds)
  let msg = "error-" & $rng.rand(0 .. 999)
  case kind
  of tekHttpStatus:
    httpStatusError(rng.oneOf([400, 401, 403, 404, 500, 502, 503]), msg)
  of tekNetwork, tekTls, tekTimeout:
    transportError(kind, msg)

proc genRequestError*(rng: var Rand): RequestError =
  ## Random RequestError with randomised optional fields.
  const rawTypes = [
    "urn:ietf:params:jmap:error:unknownCapability",
    "urn:ietf:params:jmap:error:notJSON", "urn:ietf:params:jmap:error:notRequest",
    "urn:ietf:params:jmap:error:limit", "urn:example:custom:error",
  ]
  let raw = rng.oneOf(rawTypes)
  let status =
    if rng.rand(0 .. 1) == 0:
      Opt.some(rng.oneOf([400, 403, 500]))
    else:
      Opt.none(int)
  let title =
    if rng.rand(0 .. 1) == 0:
      Opt.some("Error Title")
    else:
      Opt.none(string)
  let detail =
    if rng.rand(0 .. 1) == 0:
      Opt.some("Detailed description")
    else:
      Opt.none(string)
  requestError(raw, status, title, detail)

proc genMethodError*(rng: var Rand): MethodError =
  ## Random MethodError with randomised optional fields.
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
  methodError(raw, desc)

proc genSetError*(rng: var Rand): SetError =
  ## Random SetError across all 3 variant branches.
  let branch = rng.rand(0 .. 2)
  let desc =
    if rng.rand(0 .. 1) == 0:
      Opt.some("desc-" & $rng.rand(0 .. 99))
    else:
      Opt.none(string)
  case branch
  of 0:
    # invalidProperties variant
    let propCount = rng.rand(0 .. 5)
    var props: seq[string] = @[]
    for i in 0 ..< propCount:
      props.add "prop" & $i
    setErrorInvalidProperties("invalidProperties", props, desc)
  of 1:
    # alreadyExists variant
    let id = parseId(rng.genValidIdStrict(minLen = 1, maxLen = 20)).get()
    setErrorAlreadyExists("alreadyExists", id, desc)
  else:
    # Generic variant
    const rawTypes = ["forbidden", "overQuota", "tooLarge", "notFound", "vendorError"]
    setError(rng.oneOf(rawTypes), desc)

proc genClientError*(rng: var Rand): ClientError =
  ## Random ClientError wrapping either transport or request error.
  if rng.rand(0 .. 1) == 0:
    clientError(rng.genTransportError())
  else:
    clientError(rng.genRequestError())

# ---------------------------------------------------------------------------
# Structured type generators (additional)
# ---------------------------------------------------------------------------

proc genUnsignedInt*(rng: var Rand): UnsignedInt =
  ## Random UnsignedInt in a reasonable range for capability fields.
  parseUnsignedInt(rng.rand(1'i64 .. 100_000_000'i64)).get()

proc genCoreCapabilities*(rng: var Rand): CoreCapabilities =
  ## Random CoreCapabilities with varied UnsignedInt values.
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

proc genServerCapability*(rng: var Rand): ServerCapability =
  ## Random ServerCapability (ckCore or non-ckCore variant).
  if rng.rand(0 .. 2) == 0:
    ServerCapability(
      rawUri: "urn:ietf:params:jmap:core", kind: ckCore, core: rng.genCoreCapabilities()
    )
  else:
    const uris = [
      "urn:ietf:params:jmap:mail", "urn:ietf:params:jmap:submission",
      "https://vendor.example.com/ext",
    ]
    let uri = rng.oneOf(uris)
    ServerCapability(rawUri: uri, kind: parseCapabilityKind(uri), rawData: newJObject())

proc genComparator*(rng: var Rand): Comparator =
  ## Random Comparator with randomised property, ascending, and collation.
  let prop = parsePropertyName(rng.genValidPropertyName()).get()
  let asc = rng.rand(0 .. 1) == 0
  let coll =
    if rng.rand(0 .. 2) == 0:
      Opt.some("i;ascii-casemap")
    else:
      Opt.none(string)
  parseComparator(prop, asc, coll).get()

proc genAddedItem*(rng: var Rand): AddedItem =
  ## Random AddedItem with valid Id and UnsignedInt index.
  let id = parseId(rng.genValidIdStrict(minLen = 1, maxLen = 20)).get()
  let idx = parseUnsignedInt(rng.rand(0'i64 .. 10000'i64)).get()
  AddedItem(id: id, index: idx)

proc genPatchObject*(rng: var Rand, count: int): PatchObject =
  ## Random PatchObject with `count` entries.
  var p = emptyPatch()
  for i in 0 ..< count:
    let path = rng.genPatchPath()
    let val = newJObject()
    p = p.setProp(path, val).get()
  p

proc genValidUriTemplateParametric*(rng: var Rand): string =
  ## Parametric URI template generator that assembles random segments and
  ## {variable} placeholders, more varied than the fixed-string generator.
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
  ## Strings deliberately designed to be rejected by parseId (strict).
  ## Introduces control chars, non-base64url chars, or invalid lengths.
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

{.pop.} # params
{.pop.} # hasDoc
