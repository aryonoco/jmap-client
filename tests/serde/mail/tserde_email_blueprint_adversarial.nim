# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Adversarial serde tests for ``EmailBlueprint`` (scenarios 98-98f,
## 103-104c per design docs/design/10-mail-e-design.md §6.4.1 and §6.4.5).
## Scenarios 99-100e (§6.4.2), 101-101c (§6.4.3), and 102-102d (§6.4.4)
## live in ``tests/stress/tadversarial_blueprint.nim`` and
## ``tests/compliance/tffi_panic_surface.nim`` per implementation-9.md
## Steps 22-23.

{.push raises: [].}

import std/json
import std/strutils
import std/tables

import jmap_client/internal/mail/body
import jmap_client/internal/mail/email_blueprint
import jmap_client/internal/mail/headers
import jmap_client/internal/mail/serde_email_blueprint
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation

import ../../massertions
import ../../mfixtures

# =============================================================================
# A. Body header-name NUL and non-ASCII rejection (§6.4.1)
# =============================================================================

block bodyHeaderNameTrailingNul: # scenario 98
  ## Trailing NUL byte must be rejected by the printable-ASCII rule,
  ## not the exact-name match — pins rule order so a reserved-name
  ## side-channel cannot leak via the error message.
  let res = parseBlueprintBodyHeaderName("Content-Transfer-Encoding\x00")
  assertErr res
  assertErrContains res, "non-printable byte"

block bodyHeaderNameNulPositionMirror: # scenario 98a
  ## NUL byte at three different positions (start, middle, end) must each
  ## be rejected by the printable-ASCII rule — proves the check is
  ## position-agnostic, not an endpoint-only test.
  let cases =
    @["\x00Content-Transfer-Encoding", "Content-\x00Transfer-Encoding", "X-Custom\x00"]
  for raw in cases:
    let res = parseBlueprintBodyHeaderName(raw)
    assertErr res
    assertErrContains res, "non-printable byte"

block bodyHeaderNameOverlongUtf8Colon: # scenario 98b
  ## Overlong-UTF-8 encoding of U+003A (colon) as \xC0\xBA must be
  ## rejected by the printable-ASCII rule — both bytes 0xC0 and 0xBA
  ## sit outside 0x21..0x7E, so rejection happens before any name
  ## match or colon check.
  let res = parseBlueprintBodyHeaderName("Content-Transfer-Encoding" & "\xC0\xBA")
  assertErr res
  assertErrContains res, "non-printable byte"

# =============================================================================
# B. Email header-name NUL/DEL/locale/homoglyph (§6.4.1)
# =============================================================================

block emailHeaderNameTurkishDotlessI: # scenario 98c
  ## U+012C LATIN CAPITAL LETTER I WITH BREVE (UTF-8: \xC4\xAC) cannot
  ## smuggle a Content-* look-alike past the printable-ASCII gate.
  ## The embedded ``doAssert`` pins that ``toLowerAscii`` is byte-level
  ## locale-independent — a homoglyph-bypass regression gate.
  let res = parseBlueprintEmailHeaderName("X-\xC4\xAC")
  assertErr res
  assertErrContains res, "non-printable byte"
  doAssert "\xC4\xAC".toLowerAscii == "\xC4\xAC"

block emailHeaderNameNulDelPositionMirror: # scenario 98d
  ## NUL at three positions plus DEL (0x7F) at the tail. All four must
  ## be rejected by the character-check rule — not the ``content-``
  ## prefix predicate — so the error message cannot leak whether the
  ## name WOULD have matched the reserved prefix.
  let cases = @["Content-Type\x00", "\x00Content-Type", "x-cus\x00tom", "x-custom\x7F"]
  for raw in cases:
    let res = parseBlueprintEmailHeaderName(raw)
    assertErr res
    assertErrContains res, "non-printable byte"

block turkishLocaleInvariance: # scenario 98e
  ## Under LC_CTYPE=tr_TR.UTF-8 the parser's ``toLowerAscii`` must
  ## continue to behave byte-identically. Regression gate — fires if
  ## the implementation ever reaches for ``std/unicode.toLower``.
  let inputs = @[
    "CONTENT-TYPE", "X-Custom", "content-transfer-encoding",
    "Content-Transfer-Encoding", "X-\xC4\xB0",
  ]
  var emailBaseline = newSeq[(bool, string)]()
  var bodyBaseline = newSeq[(bool, string)]()
  for raw in inputs:
    let er = parseBlueprintEmailHeaderName(raw)
    emailBaseline.add(
      if er.isErr:
        (false, er.error.message)
      else:
        (true, string(er.get()))
    )
    let br = parseBlueprintBodyHeaderName(raw)
    bodyBaseline.add(
      if br.isErr:
        (false, br.error.message)
      else:
        (true, string(br.get()))
    )
  withLocale("tr_TR.UTF-8"):
    for i, raw in inputs:
      let er = parseBlueprintEmailHeaderName(raw)
      let ePair =
        if er.isErr:
          (false, er.error.message)
        else:
          (true, string(er.get()))
      doAssert ePair == emailBaseline[i],
        "locale altered email-name parse of '" & raw & "'"
      let br = parseBlueprintBodyHeaderName(raw)
      let bPair =
        if br.isErr:
          (false, br.error.message)
        else:
          (true, string(br.get()))
      doAssert bPair == bodyBaseline[i],
        "locale altered body-name parse of '" & raw & "'"

block emailHeaderNameHomoglyphPrefixBypass: # scenario 98f
  ## Three homoglyph attacks against the ``from`` prefix — ZERO WIDTH
  ## SPACE, LATIN SMALL LETTER F WITH HOOK, LATIN SMALL LETTER I WITH
  ## TILDE. Each carries at least one byte outside 0x21..0x7E, so the
  ## printable-ASCII rule rejects them before any normalisation path
  ## could synthesise a collision with the legitimate ``from`` entry.
  let cases = @["FROM\xE2\x80\x8B", "\xC6\x92rom", "\xC4\xA8rom"]
  for raw in cases:
    let res = parseBlueprintEmailHeaderName(raw)
    assertErr res
    assertErrContains res, "non-printable byte"

# =============================================================================
# C. Structural-boundary serde survival (§6.4.5)
# =============================================================================

block spineDepth128Stable: # scenario 103
  ## A depth-128 multipart spine (``MaxBodyPartDepth``) must serialise
  ## to a byte-stable JSON under repeated invocation. Pins the
  ## recursion bound declared in ``serde_body.nim:29`` and guards
  ## against stack exhaustion at the design-declared maximum.
  let spine = makeSpineBodyPart(128, bplInline)
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(spine)
    )
    .get()
  let a = bp.toJson()
  let b = bp.toJson()
  doAssert $a == $b, "depth-128 spine toJson is not byte-stable"

block bodyValuesBreadthDepthHarvest: # scenario 103a
  ## A 5-level multipart spine with 128 distributed inline leaves.
  ## 124 leaves populate the innermost multipart; four outer levels
  ## each contribute one additional leaf. Pins the ``bodyValues``
  ## harvest is bounded in BOTH dimensions (depth AND breadth) — the
  ## derived accessor must project every inline leaf, regardless of
  ## how the tree is shaped.
  var innermostLeaves = newSeq[BlueprintBodyPart]()
  for i in 1 .. 124:
    innermostLeaves.add makeBlueprintBodyPartInline(
      partId = parsePartIdFromServer($i).get()
    )
  let level1 = makeBlueprintBodyPartMultipart(subParts = innermostLeaves)
  let level2 = makeBlueprintBodyPartMultipart(
    subParts = @[
      makeBlueprintBodyPartInline(partId = parsePartIdFromServer("125").get()), level1
    ]
  )
  let level3 = makeBlueprintBodyPartMultipart(
    subParts = @[
      makeBlueprintBodyPartInline(partId = parsePartIdFromServer("126").get()), level2
    ]
  )
  let level4 = makeBlueprintBodyPartMultipart(
    subParts = @[
      makeBlueprintBodyPartInline(partId = parsePartIdFromServer("127").get()), level3
    ]
  )
  let root = makeBlueprintBodyPartMultipart(
    subParts = @[
      makeBlueprintBodyPartInline(partId = parsePartIdFromServer("128").get()), level4
    ]
  )
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(root)
    )
    .get()
  let obj = bp.toJson()
  let values = obj{"bodyValues"}
  doAssert values != nil, "bodyValues must be present when inline leaves exist"
  assertEq values.len, 128

# =============================================================================
# D. Serde coverage and dedup safety (§6.4.5)
# =============================================================================

block fullBlueprintConvenienceKeys: # scenario 104
  ## ``makeFullEmailBlueprint`` populates every convenience field and
  ## one ``extraHeaders`` entry. Pins the full wire surface: the
  ## eleven RFC 5322 convenience keys, plus ``keywords``,
  ## ``receivedAt``, ``bodyValues``, and the composed ``x-marker``
  ## header key.
  let obj = makeFullEmailBlueprint().toJson()
  for key in [
    "from", "to", "cc", "bcc", "replyTo", "sender", "subject", "sentAt", "messageId",
    "inReplyTo", "references", "keywords", "receivedAt", "bodyValues",
  ]:
    doAssert obj{key} != nil, "expected '" & key & "' key present"
  assertJsonHasHeaderKey(obj, "x-marker", hfText)

block serdeInjectivity: # scenario 104a
  ## Two blueprints identical except for ONE additional ``extraHeaders``
  ## entry must produce byte-distinct JSON. Pinned example of property
  ## 91 (ThoroughTrials) — serialisation is injective on aggregate
  ## state.
  var extraA = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  extraA[makeBlueprintEmailHeaderName("x-marker-a")] = makeBhmvRawSingle("value-a")
  var extraB = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  extraB[makeBlueprintEmailHeaderName("x-marker-a")] = makeBhmvRawSingle("value-a")
  extraB[makeBlueprintEmailHeaderName("x-marker-b")] = makeBhmvRawSingle("value-b")
  let bpA = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), extraHeaders = extraA
    )
    .get()
  let bpB = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), extraHeaders = extraB
    )
    .get()
  doAssert $bpA.toJson() != $bpB.toJson(),
    "blueprints differing by one header must serialise distinctly"

block intraTableDedupLastWriteWins: # scenario 104b
  ## Insert ``"From"`` then ``"from"`` into the same Table. Smart
  ## constructor lowercases both, so the keys are byte-equal and V2
  ## overwrites V1. The emitted JSON must carry exactly one ``from``
  ## header entry whose value is V2. Pins canonical-key dedup at
  ## wire-emission time — hfRaw omits the ``:asRaw`` suffix per
  ## ``composeHeaderKey``, so the bare ``"header:from"`` key is
  ## expected.
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  let k1 = parseBlueprintEmailHeaderName("From").get()
  let k2 = parseBlueprintEmailHeaderName("from").get()
  extra[k1] = makeBhmvRawSingle("V1")
  extra[k2] = makeBhmvRawSingle("V2")
  assertEq extra.len, 1
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), extraHeaders = extra
    )
    .get()
  let obj = bp.toJson()
  var fromKeyCount = 0
  for key in obj.keys:
    if key == "header:from" or key.startsWith("header:from:"):
      fromKeyCount.inc
  assertEq fromKeyCount, 1
  assertJsonStringEquals(obj, "header:from", "V2")

# =============================================================================
# E. JSON-injection resistance (§6.4.5)
# =============================================================================

block jsonInjectionViaSubject: # scenario 104c
  ## A crafted subject that would break out of the JSON string context
  ## if naive concatenation were used must be safely escaped by
  ## ``std/json``. Pins that ``%`` delegates to the stdlib escape
  ## logic — the injected tokens cannot synthesise siblings on the
  ## top-level object.
  const maliciousSubject = "\"],\"mailboxIds\":{\"evil\":true},\"zzz\":[\""
  let bp = parseEmailBlueprint(
      mailboxIds = makeNonEmptyMailboxIdSet(), subject = Opt.some(maliciousSubject)
    )
    .get()
  let obj = bp.toJson()
  let roundtrip = parseJson($obj)
  var subjectCount = 0
  for key in obj.keys:
    if key == "subject":
      subjectCount.inc
  assertEq subjectCount, 1
  let mailboxes = obj{"mailboxIds"}
  doAssert mailboxes != nil, "mailboxIds must be present"
  doAssert mailboxes.kind == JObject, "mailboxIds must be a JObject, not smuggled"
  doAssert mailboxes{"evil"} == nil, "injected 'evil' key must not appear"
  assertJsonStringEquals(roundtrip, "subject", maliciousSubject)
