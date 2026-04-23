# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for Mail Part G (EmailSubmission).
##
## Nine groups A–I pin the G1-decision set at randomised coverage:
##   * A — ``parseRFC5321Mailbox`` totality (G6, ``DefaultTrials``)
##   * B — strict/lenient superset (G7, ``DefaultTrials``)
##   * C — ``SubmissionParams.toJson`` preserves insertion order
##         (G8a, ``DefaultTrials``)
##   * D — ``paramKey`` identity algebra — biconditional (G8a,
##         ``DefaultTrials``)
##   * E — ``AnyEmailSubmission.fromJson`` state dispatch (G2/G10-G11
##         phantom-sealing, ``DefaultTrials``). Pivoted from the design's
##         round-trip shape because ``serde_email_submission`` documents
##         ``AnyEmailSubmission`` as ``fromJson``-only (module header).
##   * F — ``cancelUpdate`` produces ``esuSetUndoStatusToCanceled`` (G17
##         value-level companion to the compile-time rejection in
##         ``temail_submission.nim``, ``QuickTrials``).
##   * G — ``parseNonEmptyEmailSubmissionUpdates`` duplicate-Id rejection
##         (G17, ``DefaultTrials``)
##   * H — ``parseDeliveredState`` / ``parseDisplayedState`` ``rawBacking``
##         byte-equality (G10/G11 catch-all, ``DefaultTrials``)
##   * I — ``parseSmtpReply`` digit-grammar boundary scan
##         (G12, ``DefaultTrials``)
##
## File runs under ``just test-full`` only — see ``tests/testament_skip.txt``
## non-joinable section (precedent: ``tprop_mail_e.nim``).

import std/json
import std/random
import std/tables

import results

import jmap_client/identifiers
import jmap_client/mail/email_submission
import jmap_client/mail/serde_email_submission
import jmap_client/mail/serde_submission_envelope
import jmap_client/mail/submission_atoms
import jmap_client/mail/submission_mailbox
import jmap_client/mail/submission_param
import jmap_client/mail/submission_status
import jmap_client/primitives

import ../massertions
import ../mfixtures
import ../mproperty

# =============================================================================
# A — parseRFC5321Mailbox totality
# =============================================================================

block propRFC5321MailboxTotality: # A
  ## Property: ``parseRFC5321Mailbox`` is total — every ``string`` input
  ## returns ``Ok`` xor ``Err``, never panicking. ``Result[_, _]`` encodes
  ## the disjunction at the type level; the assertion is operational —
  ## completion without panic constitutes the proof.
  ##
  ## Edge-bias by trial band:
  ##   * trial 0..7  — ``genRFC5321Mailbox`` edge-biased valid shapes
  ##   * trial 8..15 — ``genInvalidRFC5321Mailbox`` adversaries
  ##   * trial >= 16 — coin flip between the two generators in random mode
  checkProperty "parseRFC5321Mailbox: totality on valid and invalid inputs":
    let raw =
      if trial >= 0 and trial <= 7:
        $rng.genRFC5321Mailbox(trial)
      elif trial >= 8 and trial <= 15:
        rng.genInvalidRFC5321Mailbox(trial - 8)
      elif rng.rand(0 .. 1) == 0:
        $rng.genRFC5321Mailbox(-1)
      else:
        rng.genInvalidRFC5321Mailbox(-1)
    lastInput = raw
    let parsed = parseRFC5321Mailbox(raw)
    doAssert parsed.isOk or parsed.isErr,
      "parseRFC5321Mailbox neither Ok nor Err — totality violated"

# =============================================================================
# B — parseRFC5321Mailbox strict/lenient superset
# =============================================================================

block propRFC5321MailboxStrictLenientSuperset: # B
  ## Property: bounded strict ⊆ lenient (Postel's law, G7). For inputs
  ## within the common length ceiling (``raw.len <= 255``), every
  ## strict-accepted input is also lenient-accepted:
  ## ``strict.isErr or lenient.isOk``.
  ##
  ## The bound is load-bearing. Strict caps local-part ≤ 64 and domain
  ## ≤ 255 (RFC 5321 §4.5.3.1.1/.2), with no *total* cap — so strict
  ## accepts inputs up to ~320 octets (``user@long-domain``). Lenient
  ## caps total ≤ 255 (RFC 8621 server-surface pragmatic cap via
  ## ``detectLenientToken``). Outside the 255-octet intersection the
  ## two parsers legitimately diverge: strict may accept a long-but-
  ## grammatical mailbox that lenient rejects on length alone — not a
  ## superset violation, a deliberate design asymmetry. Within 255
  ## octets the superset holds.
  checkProperty "parseRFC5321Mailbox strict-Ok implies lenient-Ok (≤255 octets)":
    let raw =
      if trial >= 0 and trial <= 7:
        $rng.genRFC5321Mailbox(trial)
      elif trial >= 8 and trial <= 15:
        rng.genInvalidRFC5321Mailbox(trial - 8)
      elif rng.rand(0 .. 1) == 0:
        $rng.genRFC5321Mailbox(-1)
      else:
        rng.genInvalidRFC5321Mailbox(-1)
    lastInput = raw
    if raw.len <= 255:
      let strict = parseRFC5321Mailbox(raw)
      let lenient = parseRFC5321MailboxFromServer(raw)
      doAssert strict.isErr or lenient.isOk,
        "strict Ok but lenient Err violates bounded superset for input: " & raw

# =============================================================================
# C — SubmissionParams.toJson preserves OrderedTable insertion order
# =============================================================================

func wireKeyOf(key: SubmissionParamKey): string =
  ## Mirrors the wire-key transform in ``toJson(SubmissionParams)``
  ## (serde_submission_envelope.nim). Used to build the expected
  ## insertion-ordered wire-key sequence from the backing OrderedTable.
  case key.kind
  of spkExtension:
    $key.extName
  of spkBody, spkSmtpUtf8, spkSize, spkEnvid, spkRet, spkNotify, spkOrcpt, spkHoldFor,
      spkHoldUntil, spkBy, spkMtPriority:
    $key.kind

block propSubmissionParamsInsertionOrderRoundTrip: # C
  ## Property: ``toJson(SubmissionParams)`` emits wire keys in the
  ## OrderedTable's insertion order — the backing structure's contract
  ## (``OrderedTable`` preserves insertion order) must survive
  ## stringification. Pins the G8a decision that ``SubmissionParams`` is
  ## order-preserving rather than hash-collapsing.
  checkProperty "SubmissionParams.toJson preserves OrderedTable insertion order":
    let sp = rng.genSubmissionParams(trial)
    lastInput = $sp
    var expected: seq[string] = @[]
    for key in (OrderedTable[SubmissionParamKey, SubmissionParam](sp)).keys:
      expected.add(wireKeyOf(key))
    let wire = sp.toJson()
    var actual: seq[string] = @[]
    for k, _ in wire.pairs:
      actual.add(k)
    doAssert expected == actual,
      "wire key order diverged from OrderedTable: expected=" & $expected & " got=" &
        $actual

# =============================================================================
# D — SubmissionParamKey identity algebra (biconditional)
# =============================================================================

block propSubmissionParamKeyIdentity: # D
  ## Property: ``paramKey(p1) == paramKey(p2)`` iff ``p1.kind == p2.kind``
  ## and — for the ``spkExtension`` arm — ``p1.extName == p2.extName``.
  ## Biconditional: both forward (equal keys imply shared discriminants)
  ## and reverse (shared discriminants imply equal keys). Pins the G8a
  ## decision that ``SubmissionParamKey`` is the identity projection —
  ## discriminator plus one open-world name, nothing more.
  checkProperty "paramKey(p1) == paramKey(p2) iff kinds match + extName match":
    let p1 = rng.genSubmissionParam(trial mod 15)
    let p2 = rng.genSubmissionParam((trial + 1) mod 15)
    lastInput = "(" & $p1.kind & ", " & $p2.kind & ")"
    let k1 = paramKey(p1)
    let k2 = paramKey(p2)
    let kindsMatch = p1.kind == p2.kind
    let extsMatch =
      if p1.kind == spkExtension and p2.kind == spkExtension:
        p1.extName == p2.extName
      else:
        true
    let keysEq = submissionParamKeyEq(k1, k2)
    if keysEq:
      doAssert kindsMatch and extsMatch,
        "paramKey equal but kinds/extName diverge: " & $p1.kind & " vs " & $p2.kind
    else:
      doAssert (not kindsMatch) or (not extsMatch),
        "paramKey unequal but kinds and extNames match: " & $p1.kind

# =============================================================================
# E — AnyEmailSubmission.fromJson state dispatch (pivoted from round-trip)
# =============================================================================

block propAnyEmailSubmissionStateDispatch: # E
  ## Property: ``AnyEmailSubmission.fromJson(wire)`` dispatches to the
  ## phantom branch named by the wire ``undoStatus`` token, and the
  ## three Pattern-A sealed accessors (``asPending``, ``asFinal``,
  ## ``asCanceled``) produce a mutually-exclusive Some/None triple —
  ## exactly one accessor yields ``Opt.some``.
  ##
  ## Pivot from the design §8.2.1 Group E "round-trip" formulation:
  ## ``serde_email_submission`` documents ``AnyEmailSubmission`` as
  ## ``fromJson``-only (module header lines 13-18). The invariant is
  ## preserved by replacing round-trip with parse-only dispatch — wire
  ## JSON is built directly from a random ``UndoStatus`` so the
  ## expected state arm is known before parsing.
  checkProperty "AnyEmailSubmission.fromJson dispatches to undoStatus arm":
    let status = rng.genUndoStatus()
    let wireStr =
      case status
      of usPending: "pending"
      of usFinal: "final"
      of usCanceled: "canceled"
    lastInput = "undoStatus=" & wireStr & " trial=" & $trial
    let wire = %*{
      "id": "es-" & $trial,
      "identityId": "iden-" & $trial,
      "emailId": "email-" & $trial,
      "threadId": "thr-" & $trial,
      "undoStatus": wireStr,
      "sendAt": "2026-01-01T00:00:00Z",
      "dsnBlobIds": [],
      "mdnBlobIds": [],
    }
    let parsed = AnyEmailSubmission.fromJson(wire)
    assertOk parsed
    let back = parsed.unsafeGet()
    doAssert back.state == status,
      "state arm mismatch: expected " & $status & " got " & $back.state
    case status
    of usPending:
      assertSome back.asPending()
      assertNone back.asFinal()
      assertNone back.asCanceled()
    of usFinal:
      assertNone back.asPending()
      assertSome back.asFinal()
      assertNone back.asCanceled()
    of usCanceled:
      assertNone back.asPending()
      assertNone back.asFinal()
      assertSome back.asCanceled()

# =============================================================================
# F — cancelUpdate(EmailSubmission[usPending]).kind is esuSetUndoStatusToCanceled
# =============================================================================

block propCancelUpdateKindInvariant: # F
  ## Property: ``cancelUpdate`` applied to any ``EmailSubmission[usPending]``
  ## produces an ``EmailSubmissionUpdate`` with
  ## ``kind == esuSetUndoStatusToCanceled``. Value-level companion to the
  ## compile-time rejection (``assertNotCompiles`` block in
  ## ``temail_submission.nim``). Uses ``QuickTrials`` because the predicate
  ## is trivially cheap (one ctor + one ``==``) and the only variation
  ## comes from the shared-field content, not the branch dispatch.
  checkPropertyN "cancelUpdate(EmailSubmission[usPending]).kind is canceled",
    QuickTrials:
    let s = genEmailSubmission[usPending](rng, trial)
    lastInput = "sub=" & $s.id
    let upd = cancelUpdate(s)
    doAssert upd.kind == esuSetUndoStatusToCanceled,
      "cancelUpdate produced wrong variant: " & $upd.kind

# =============================================================================
# G — NonEmptyEmailSubmissionUpdates rejects duplicate Id keys
# =============================================================================

block propNonEmptyEmailSubmissionUpdatesDuplicateId: # G
  ## Property: if the input ``openArray`` contains a duplicate ``Id`` key,
  ## ``parseNonEmptyEmailSubmissionUpdates`` returns ``Err`` with at least
  ## one accumulated ``ValidationError``. Pins the G17 decision that the
  ## non-empty, dup-free update map is a smart constructor over
  ## ``openArray`` (not a silent-shadow ``Table`` constructor).
  ##
  ## Edge-bias:
  ##   * trial 0 — early duplicate (positions 0, 1)
  ##   * trial 1 — late duplicate (positions n-2, n-1)
  ##   * trial 2 — triple occurrence of a single Id
  ##   * trial 3 — interleaved cluster of two duplicated Ids
  ##   * trial >= 4 — random: 2..8 entries with one planted duplicate
  checkProperty "parseNonEmptyEmailSubmissionUpdates rejects duplicate Ids":
    let idA = Id("sub-a")
    let idB = Id("sub-b")
    let idC = Id("sub-c")
    let u = rng.genEmailSubmissionUpdate(-1)
    var pairs: seq[(Id, EmailSubmissionUpdate)] = @[]
    case trial
    of 0:
      pairs = @[(idA, u), (idA, u), (idB, u)]
    of 1:
      pairs = @[(idA, u), (idB, u), (idC, u), (idC, u)]
    of 2:
      pairs = @[(idA, u), (idA, u), (idA, u), (idB, u)]
    of 3:
      pairs = @[(idA, u), (idB, u), (idA, u), (idB, u), (idA, u)]
    else:
      let size = rng.rand(2 .. 8)
      let dupId = Id("dup-" & $rng.rand(0 .. 999))
      pairs = newSeq[(Id, EmailSubmissionUpdate)](size)
      for i in 0 ..< size:
        pairs[i] = (Id("k-" & $i), u)
      let pos = rng.rand(1 ..< size)
      pairs[0] = (dupId, u)
      pairs[pos] = (dupId, u)
    lastInput = "pairs=" & $pairs.len
    let res = parseNonEmptyEmailSubmissionUpdates(pairs)
    assertErr res
    doAssert res.error.len >= 1,
      "expected >=1 validation error on duplicate Id; got " & $res.error.len

# =============================================================================
# H — ParsedDeliveredState / ParsedDisplayedState rawBacking byte-equality
# =============================================================================

block propParsedDeliveredStateRawBackingRoundTrip: # H
  ## Property: for every input ``raw``, ``parseDeliveredState(raw).rawBacking``
  ## and ``parseDisplayedState(raw).rawBacking`` are byte-exactly equal to
  ## ``raw``. Pins the G10/G11 decision that the ``dsOther``/``dpOther``
  ## catch-all variants preserve the anomalous token losslessly — the
  ## entire purpose of ``rawBacking`` is to survive unknown-value reads
  ## without dropping data.
  ##
  ## Both parsers are TOTAL (no ``Result``) per
  ## ``submission_status.nim:292,305`` — the catch-all arm guarantees
  ## this. The test exercises the byte-equality post-condition.
  ##
  ## Edge-bias:
  ##   * 0..3 — four RFC-defined ``DeliveredState`` values
  ##   * 4    — one ``DisplayedState`` value (cross-feed)
  ##   * 5..6 — unknown catch-all tokens
  ##   * >=7  — random alphabetic token, length 1..12
  checkProperty "parseDeliveredState/parseDisplayedState preserve rawBacking":
    let raw =
      case trial
      of 0:
        "queued"
      of 1:
        "yes"
      of 2:
        "no"
      of 3:
        "unknown"
      of 4:
        "partial"
      of 5:
        "deferred"
      of 6:
        "pending"
      else:
        let n = rng.rand(1 .. 12)
        var buf = newStringOfCap(n)
        for _ in 0 ..< n:
          buf.add(char(rng.rand(int('a') .. int('z'))))
        buf
    lastInput = raw
    let d = parseDeliveredState(raw)
    doAssert d.rawBacking == raw,
      "DeliveredState rawBacking lost bytes: expected=" & raw & " got=" & d.rawBacking
    let p = parseDisplayedState(raw)
    doAssert p.rawBacking == raw,
      "DisplayedState rawBacking lost bytes: expected=" & raw & " got=" & p.rawBacking

# =============================================================================
# I — parseSmtpReply digit-boundary scan (RFC 5321 §4.2 grammar)
# =============================================================================

block propParseSmtpReplyDigitBoundary: # I
  ## Property: ``parseSmtpReply`` accepts iff the Reply-code obeys
  ## RFC 5321 §4.2 digit ranges (``d1 in 2..5``, ``d2 in 0..5``,
  ## ``d3 in 0..9``) AND the separator/multi-line structure is
  ## well-formed. Pins the G12 decision that the SMTP Reply grammar is
  ## enforced at the parser surface rather than deferred to consumers.
  ##
  ## Edge-bias trials 0..8 hit the grammar boundary values directly
  ## (below/at/above each digit range, bare final code, multi-line
  ## happy path, multi-line wrong-separator). Random digit sampling
  ## from trial 9 onward widens the quantification; the expected
  ## outcome is computed from the digit ranges.
  checkProperty "parseSmtpReply accepts iff RFC 5321 §4.2 grammar holds":
    type Expect = enum
      exOk
      exErr

    let (raw, expect) =
      case trial
      of 0:
        ("199 text", exErr)
      # d1 = 1, below 2..5
      of 1:
        ("200 text", exOk)
      # d1 = 2 (low boundary)
      of 2:
        ("559 text", exOk)
      # d1 = 5 (high boundary for d1)
      of 3:
        ("650 text", exErr)
      # d1 = 6, above 2..5
      of 4:
        ("260 text", exErr)
      # d2 = 6, above 0..5
      of 5:
        ("259 text", exOk)
      # d2 = 5 (high for d2), d3 = 9 (high for d3)
      of 6:
        ("250", exOk)
      # bare code — submission_status.nim:174-177 accepts
      of 7:
        ("250-ok\r\n250 done", exOk)
      # multi-line happy
      of 8:
        ("250 ok\r\n250 done", exErr)
      # non-final missing '-'
      else:
        let d1 = char(rng.rand(int('0') .. int('9')))
        let d2 = char(rng.rand(int('0') .. int('9')))
        let d3 = char(rng.rand(int('0') .. int('9')))
        let s = $d1 & $d2 & $d3 & " ok"
        let ok = (d1 in {'2' .. '5'}) and (d2 in {'0' .. '5'}) and (d3 in {'0' .. '9'})
        (s, if ok: exOk else: exErr)
    lastInput = raw
    let r = parseSmtpReply(raw)
    case expect
    of exOk:
      assertOk r
    of exErr:
      assertErr r
