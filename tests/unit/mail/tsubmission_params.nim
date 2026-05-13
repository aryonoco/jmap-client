# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for the typed SMTP-parameter algebra
## (``SubmissionParam``, ``SubmissionParamKey``, ``SubmissionParams``)
## per G2 §8.7 matrix. Pins one ``block`` per ``SubmissionParamKind``
## variant (valid representative + invalid-boundary representative where
## one exists at unit tier), the NOTIFY mutual-exclusion rule, the
## ``SubmissionParamKey`` identity matrix (12² discriminator
## enumeration plus the extension-name partition), ``paramKey``
## derivation totality, and three fixed insertion sequences asserting
## ``toJson(SubmissionParams)`` preserves wire-key order.
##
## Source-side under test: ``src/jmap_client/mail/submission_param.nim``
## (G1 §2.3–2.4). Eleven of twelve smart constructors are unconditional
## — payload validation is pushed up into ``MtPriority``,
## ``RFC5321Keyword``, ``OrcptAddrType``, ``UTCDate``, ``UnsignedInt``,
## ``JmapInt``; value-level invalid-boundary tests therefore exercise
## the upstream parsers, not the param constructors. Closed-enum
## payloads (``BodyEncoding``, ``DsnRetType``, ``DeliveryByMode``)
## have no value-level invalid path — wire-side rejection is owned by
## Step 12 (serde tests).

{.push raises: [].}

import std/algorithm
import std/json
import std/sugar
import std/tables

import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation
import jmap_client/internal/mail/submission_atoms
import jmap_client/internal/mail/submission_param
import jmap_client/internal/mail/serde_submission_envelope

import ../../massertions
import ../../mfixtures
import ../../mtestblock

proc keysOf(j: JsonNode): seq[string] =
  ## Extracts JSON object field names in insertion order. ``JObject.fields``
  ## is ``OrderedTable[string, JsonNode]`` under ``std/json``, so ``pairs``
  ## iteration preserves the order in which keys were inserted by
  ## ``toJson(SubmissionParams)``. Test-file scope only — operates on
  ## ``JsonNode``, not on a domain type, so it does not belong in
  ## ``mfixtures``.
  result = @[]
  for k, _ in j.fields.pairs:
    result.add(k)

# ===========================================================================
# §A. Per-variant matrix — one block per SubmissionParamKind
# ===========================================================================

testCase submissionParamBodyValidEncodings:
  # G2 §8.7 row spkBody. ``BodyEncoding`` is a closed enum
  # (submission_param.nim:33-39) — the param constructor is
  # unconditional (line 168) and there is no value-level invalid path.
  # Wire-side rejection of unknown tokens like ``"BASE64"`` is owned by
  # Step 12 (serde tests).
  for e in [beSevenBit, beEightBitMime, beBinaryMime]:
    let p = bodyParam(e)
    doAssert p.kind == spkBody
    doAssert p.bodyEncoding == e

testCase submissionParamSmtpUtf8Nullary:
  # G2 §8.7 row spkSmtpUtf8. Nullary variant (case object arm at
  # submission_param.nim:138-139 is ``discard``); the discriminator IS
  # the entire payload. ``smtpUtf8Param()`` is unconditional.
  let p = smtpUtf8Param()
  doAssert p.kind == spkSmtpUtf8

testCase submissionParamSizeAcceptsZeroAndUpperBound:
  # G2 §8.7 row spkSize. ``sizeParam`` is unconditional; payload bounds
  # are enforced by upstream ``parseUnsignedInt`` (primitives.nim:88-91).
  # Boundary literal: ``"must be non-negative"`` at primitives.nim:89
  # for negative input.
  let zero = parseUnsignedInt(0)
  assertOk zero
  let p0 = sizeParam(zero.get())
  doAssert p0.kind == spkSize
  assertEq p0.sizeOctets.toInt64, 0'i64
  # 2^53 - 1 — the JSON-safe upper bound enforced at primitives.nim:91.
  let upper = parseUnsignedInt(9007199254740991'i64)
  assertOk upper
  let pHi = sizeParam(upper.get())
  doAssert pHi.kind == spkSize
  assertEq pHi.sizeOctets.toInt64, 9007199254740991'i64
  let bad = parseUnsignedInt(-1)
  assertErr bad
  assertEq bad.error.typeName, "UnsignedInt"
  assertEq bad.error.message, "must be non-negative"

testCase submissionParamEnvidStoresInputBytesUnchanged:
  # G2 §8.7 row spkEnvid. ``envidParam`` is unconditional and stores
  # decoded bytes verbatim (submission_param.nim:176-180 — xtext wire
  # encoding belongs to serde, design §7.2 / G27). No value-level
  # validation at L1; emptiness and xtext shape are owned by Step 12.
  let p = envidParam("envid-1")
  doAssert p.kind == spkEnvid
  assertEq p.envid, "envid-1"

testCase submissionParamRetFullAndHdrs:
  # G2 §8.7 row spkRet. ``DsnRetType`` is a closed enum
  # (submission_param.nim:41-46) — ``retParam`` is unconditional. No
  # value-level invalid path; wire-side rejection of unknown tokens
  # is owned by Step 12.
  for t in [retFull, retHdrs]:
    let p = retParam(t)
    doAssert p.kind == spkRet
    doAssert p.retType == t

testCase submissionParamNotifyValidShapes:
  # G2 §8.7 row spkNotify (valid representatives only — mutex and
  # empty-set rejection live in §B). Three RFC 3461 §4.1 wire-legal
  # combinations: any non-empty subset of SUCCESS/FAILURE/DELAY, and
  # the singleton {NEVER}.
  let r1 = notifyParam({dnfSuccess})
  assertOk r1
  doAssert r1.get().kind == spkNotify
  doAssert r1.get().notifyFlags == {dnfSuccess}
  let r2 = notifyParam({dnfFailure, dnfDelay})
  assertOk r2
  doAssert r2.get().notifyFlags == {dnfFailure, dnfDelay}
  let r3 = notifyParam({dnfNever})
  assertOk r3
  doAssert r3.get().notifyFlags == {dnfNever}

testCase submissionParamOrcptParserPath:
  # G2 §8.7 row spkOrcpt. ``orcptParam`` is unconditional; the
  # addr-type atom is gated by upstream ``parseOrcptAddrType``
  # (submission_atoms.nim:149-153). Boundary literal: ``"must not be
  # empty"`` at submission_atoms.nim:132 (oatEmpty branch).
  let at = parseOrcptAddrType("rfc822")
  assertOk at
  let p = orcptParam(at.get(), "alice@example.com")
  doAssert p.kind == spkOrcpt
  assertEq $p.orcptAddrType, "rfc822"
  assertEq p.orcptOrigRecipient, "alice@example.com"
  let bad = parseOrcptAddrType("")
  assertErr bad
  assertEq bad.error.typeName, "OrcptAddrType"
  assertEq bad.error.message, "must not be empty"

testCase submissionParamHoldForInfallibleWrap:
  # G2 §8.7 row spkHoldFor. ``parseHoldForSeconds`` is infallible by
  # design (submission_param.nim:78-84 docstring) — ``UnsignedInt``
  # already enforces the JSON-safe bound at its own constructor, so
  # the typed wrap has nothing left to reject. Coverage of the
  # upstream ``UnsignedInt`` boundary lives in §A3.
  let secs = parseHoldForSeconds(parseUnsignedInt(600).get())
  assertOk secs
  let p = holdForParam(secs.get())
  doAssert p.kind == spkHoldFor
  assertEq p.holdFor.toInt64, 600'i64

testCase submissionParamHoldUntilParserPath:
  # G2 §8.7 row spkHoldUntil. ``holdUntilParam`` is unconditional;
  # the absolute-time payload is gated by upstream ``parseUtcDate``
  # (primitives.nim:271-278). Empty input triggers ``dvTooShort``
  # (raw.len < 20 at primitives.nim:217); boundary literal:
  # ``"too short for RFC 3339 date-time"`` at primitives.nim:241.
  let d = parseUtcDate("2026-01-15T09:00:00Z")
  assertOk d
  let p = holdUntilParam(d.get())
  doAssert p.kind == spkHoldUntil
  assertEq $p.holdUntil, "2026-01-15T09:00:00Z"
  let bad = parseUtcDate("")
  assertErr bad
  assertEq bad.error.typeName, "UTCDate"
  assertEq bad.error.message, "too short for RFC 3339 date-time"

testCase submissionParamByDeadlineAndMode:
  # G2 §8.7 row spkBy. ``byParam`` is unconditional. ``DeliveryByMode``
  # (submission_param.nim:57-64) is a closed enum — wire-side rejection
  # of unknown mode suffixes is owned by Step 12. Cover all four valid
  # modes here.
  let deadline = parseJmapInt(123)
  assertOk deadline
  for m in [dbmReturn, dbmNotify, dbmReturnTrace, dbmNotifyTrace]:
    let p = byParam(deadline.get(), m)
    doAssert p.kind == spkBy
    doAssert p.byMode == m
    assertEq p.byDeadline.toInt64, 123'i64

testCase submissionParamMtPriorityRangeBoundary:
  # G2 §8.7 row spkMtPriority. Validation lives in upstream
  # ``parseMtPriority`` (submission_param.nim:99-103); the param
  # constructor ``mtPriorityParam`` is unconditional. Boundary literal:
  # ``"must be in range -9..9"`` at submission_param.nim:102.
  for raw in [-9, 0, 9]:
    let mp = parseMtPriority(raw)
    assertOk mp
    let p = mtPriorityParam(mp.get())
    doAssert p.kind == spkMtPriority
    assertEq p.mtPriority.toInt, raw
  for raw in [-10, 10]:
    let res = parseMtPriority(raw)
    assertErr res
    assertEq res.error.typeName, "MtPriority"
    assertEq res.error.message, "must be in range -9..9"
    assertEq res.error.value, $raw

testCase submissionParamExtensionWithKeywordAndOptValue:
  # G2 §8.7 row spkExtension. ``extensionParam`` is unconditional; the
  # keyword name is gated by upstream ``parseRFC5321Keyword``
  # (submission_atoms.nim:95-101). Empty input triggers
  # ``kvLengthOutOfRange`` (length 0 < 1 at submission_atoms.nim:87);
  # boundary literal: ``"length must be 1-64 octets"`` at
  # submission_atoms.nim:78.
  let kwRes = parseRFC5321Keyword("X-VENDOR-FOO")
  assertOk kwRes
  let kw = kwRes.get()
  let pWith = extensionParam(kw, Opt.some("bar"))
  doAssert pWith.kind == spkExtension
  assertEq $pWith.extName, "X-VENDOR-FOO"
  doAssert pWith.extValue.isSome
  assertEq pWith.extValue.get(), "bar"
  let pNone = extensionParam(kw, Opt.none(string))
  doAssert pNone.kind == spkExtension
  doAssert pNone.extValue.isNone
  let bad = parseRFC5321Keyword("")
  assertErr bad
  assertEq bad.error.typeName, "RFC5321Keyword"
  assertEq bad.error.message, "length must be 1-64 octets"

# ===========================================================================
# §B. NOTIFY mutual-exclusion and empty-set rejection
# ===========================================================================

testCase submissionParamNotifyMutualExclusionAndEmptyRejection:
  # Grep-locked literals from submission_param.nim:201-214 (notifyParam):
  #   typeName = "SubmissionParam"
  #   emptyMsg = "NOTIFY flags must not be empty"   (line 206)
  #   mutexMsg = "NOTIFY=NEVER is mutually exclusive with SUCCESS/FAILURE/DELAY"
  #              (line 211)
  block:
    let res = notifyParam({})
    assertErr res
    assertEq res.error.typeName, "SubmissionParam"
    assertEq res.error.message, "NOTIFY flags must not be empty"
  block:
    let res = notifyParam({dnfNever, dnfSuccess})
    assertErr res
    assertEq res.error.typeName, "SubmissionParam"
    assertEq res.error.message,
      "NOTIFY=NEVER is mutually exclusive with SUCCESS/FAILURE/DELAY"
  block:
    let res = notifyParam({dnfNever, dnfFailure})
    assertErr res
    assertEq res.error.message,
      "NOTIFY=NEVER is mutually exclusive with SUCCESS/FAILURE/DELAY"
  block:
    let res = notifyParam({dnfNever, dnfDelay})
    assertErr res
    assertEq res.error.message,
      "NOTIFY=NEVER is mutually exclusive with SUCCESS/FAILURE/DELAY"
  block:
    let res = notifyParam({dnfNever, dnfSuccess, dnfFailure, dnfDelay})
    assertErr res
    assertEq res.error.message,
      "NOTIFY=NEVER is mutually exclusive with SUCCESS/FAILURE/DELAY"

# ===========================================================================
# §C. SubmissionParamKey identity enumeration
# ===========================================================================

testCase submissionParamKeyIdentityDiscriminatorMatrix:
  # 144-cell enumeration of SubmissionParamKind × SubmissionParamKind.
  # Native enum fold per G2 §8.8 mandatory note (precedent
  # tests/unit/terrors.nim — ``for kind in SetErrorType:``). paramKey
  # collapses 11 nullary arms to a kind-only key; spkExtension carries
  # an RFC5321Keyword name. With makeSubmissionParam returning a fixed
  # default extension name ("X-TEST" per mfixtures.nim:2049) for
  # spkExtension, two same-kind invocations produce equal keys via
  # case-folded RFC5321Keyword equality; different kinds produce
  # distinct keys.
  for k1 in SubmissionParamKind:
    for k2 in SubmissionParamKind:
      let key1 = paramKey(makeSubmissionParam(k1))
      let key2 = paramKey(makeSubmissionParam(k2))
      if k1 == k2:
        assertSubmissionParamKeyEq key1, key2
      else:
        doAssert key1 != key2,
          "expected distinct keys for distinct kinds: " & $k1 & " vs " & $k2

testCase submissionParamKeyExtensionNamePartitions:
  # Within spkExtension, distinct keyword names ⇒ distinct keys; the
  # case-folded equality on RFC5321Keyword (submission_atoms.nim:51-54)
  # ⇒ "X-FOO" and "x-foo" yield the same key. The carried Opt[string]
  # value is irrelevant — paramKey projects only the discriminator and
  # the keyword name (submission_param.nim:313-323).
  let kwUpper = parseRFC5321Keyword("X-FOO")
  assertOk kwUpper
  let kwOther = parseRFC5321Keyword("X-BAR")
  assertOk kwOther
  let kwLower = parseRFC5321Keyword("x-foo")
  assertOk kwLower
  let p1 = extensionParam(kwUpper.get(), Opt.none(string))
  let p2 = extensionParam(kwOther.get(), Opt.none(string))
  let pLower = extensionParam(kwLower.get(), Opt.some("v"))
  doAssert paramKey(p1) != paramKey(p2)
  assertSubmissionParamKeyEq paramKey(p1), paramKey(pLower)

# ===========================================================================
# §D. paramKey derivation totality
# ===========================================================================

testCase paramKeyDerivationTotality:
  # For every SubmissionParamKind, paramKey returns a key whose
  # discriminator matches the input. Pattern 6 derived-not-stored:
  # paramKey is the single source of truth for parameter identity
  # (submission_param.nim:313-323).
  for kind in SubmissionParamKind:
    let p = makeSubmissionParam(kind)
    let k = paramKey(p)
    doAssert k.kind == kind,
      "paramKey discriminator drift: input " & $kind & ", output " & $k.kind

# ===========================================================================
# §E. SubmissionParams.toJson preserves insertion order
# ===========================================================================

testCase submissionParamsToJsonPreservesDeclarationOrder:
  # Sequence 1: all 11 well-known variants in SubmissionParamKind
  # declaration order (BODY → MT-PRIORITY).
  # toJson(SubmissionParams) iterates the underlying OrderedTable
  # (serde_submission_envelope.nim:369-383); that table preserves
  # insertion order. JsonNode.fields is also OrderedTable under
  # std/json, so the wire JsonNode's key order chains through.
  let items = collect:
    for kind in SubmissionParamKind:
      if kind != spkExtension:
        makeSubmissionParam(kind)
  let res = parseSubmissionParams(items)
  assertOk res
  let j = toJson(res.get())
  assertEq keysOf(j),
    @[
      "BODY", "SMTPUTF8", "SIZE", "ENVID", "RET", "NOTIFY", "ORCPT", "HOLDFOR",
      "HOLDUNTIL", "BY", "MT-PRIORITY",
    ]

testCase submissionParamsToJsonPreservesReverseOrder:
  # Sequence 2: reverse declaration order (MT-PRIORITY → BODY).
  # Build forward via the native enum iterator (avoids the
  # ``SubmissionParamKind(int)`` round-trip that --warningAsError:
  # AnyEnumConv rejects), then reverse the resulting seq with
  # std/algorithm.reverse.
  var items: seq[SubmissionParam] = @[]
  for k in SubmissionParamKind:
    if k != spkExtension:
      items.add(makeSubmissionParam(k))
  items.reverse()
  let res = parseSubmissionParams(items)
  assertOk res
  assertEq keysOf(toJson(res.get())),
    @[
      "MT-PRIORITY", "BY", "HOLDUNTIL", "HOLDFOR", "ORCPT", "NOTIFY", "RET", "ENVID",
      "SIZE", "SMTPUTF8", "BODY",
    ]

testCase submissionParamsToJsonPreservesShuffledOrderWithExtension:
  # Sequence 3: interleaved with the open-world variant at a known
  # position. Verifies that spkExtension renders as its keyword name
  # ("X-VENDOR-FOO") rather than the discriminator label "EXTENSION"
  # — the case branch at serde_submission_envelope.nim:377 takes
  # ``$key.extName`` for spkExtension.
  let extNameRes = parseRFC5321Keyword("X-VENDOR-FOO")
  assertOk extNameRes
  let extName = extNameRes.get()
  let items = @[
    makeSubmissionParam(spkSize),
    makeSubmissionParam(spkBody),
    extensionParam(extName, Opt.some("bar")),
    makeSubmissionParam(spkRet),
    makeSubmissionParam(spkNotify),
  ]
  let res = parseSubmissionParams(items)
  assertOk res
  assertEq keysOf(toJson(res.get())), @["SIZE", "BODY", "X-VENDOR-FOO", "RET", "NOTIFY"]
