# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for Mail Part D Email, ParsedEmail, EmailComparator,
## EmailBodyFetchOptions, and EmailFilterCondition types.
## Covers round-trip identity, totality (never crashes on arbitrary input),
## structural invariants, and field-count correlation.

import std/json
import std/random

import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives
import jmap_client/internal/mail/email
import jmap_client/internal/mail/mail_filters
import jmap_client/internal/mail/serde_email
import jmap_client/internal/mail/serde_mail_filters

import ../mproperty
import ../mfixtures

# =============================================================================
# A. Round-trip identity properties
# =============================================================================

block propRoundTripEmailComparator:
  checkProperty "EmailComparator round-trip: emailComparatorFromJson(toJson(ec)) == ec":
    let ec = rng.genEmailComparator()
    lastInput = $ec.kind
    let j = ec.toJson()
    let rt = emailComparatorFromJson(j).get()
    doAssert emailComparatorEq(rt, ec), "EmailComparator round-trip identity violated"

block propRoundTripEmail:
  checkPropertyN "Email round-trip: emailFromJson(toJson(e)) == e", ThoroughTrials:
    let e = rng.genEmail()
    lastInput = (if e.id.isSome: $e.id.unsafeGet else: "Opt.none")
    let j = e.toJson()
    let rtResult = emailFromJson(j)
    doAssert rtResult.isOk, "Email round-trip fromJson failed"
    doAssert emailEq(rtResult.get(), e), "Email round-trip identity violated"

block propRoundTripPartialEmail:
  checkPropertyN "Partial Email round-trip: emailFromJson(toJson(p)) == p",
    ThoroughTrials:
    let p = rng.genPartialEmail()
    lastInput = (if p.id.isSome: $p.id.unsafeGet else: "Opt.none")
    let j = p.toJson()
    let rtResult = emailFromJson(j)
    doAssert rtResult.isOk, "Partial Email round-trip fromJson failed"
    doAssert emailEq(rtResult.get(), p), "Partial Email round-trip identity violated"

block propRoundTripParsedEmail:
  checkPropertyN "ParsedEmail round-trip: parsedEmailFromJson(toJson(pe)) == pe",
    ThoroughTrials:
    let pe = rng.genParsedEmail()
    lastInput = "parsedEmail"
    let j = pe.toJson()
    let rtResult = parsedEmailFromJson(j)
    doAssert rtResult.isOk, "ParsedEmail round-trip fromJson failed"
    doAssert parsedEmailEq(rtResult.get(), pe),
      "ParsedEmail round-trip identity violated"

# =============================================================================
# B. Totality — never crashes on arbitrary input
# =============================================================================

block propEmailFromJsonTotality:
  checkProperty "emailFromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(3)
    lastInput = $j.kind
    discard emailFromJson(j)

block propParsedEmailFromJsonTotality:
  checkProperty "parsedEmailFromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(3)
    lastInput = $j.kind
    discard parsedEmailFromJson(j)

block propEmailComparatorFromJsonTotality:
  checkProperty "emailComparatorFromJson never crashes on arbitrary JSON":
    let j = rng.genArbitraryJsonNode(2)
    lastInput = $j.kind
    discard emailComparatorFromJson(j)

# =============================================================================
# C. Structural invariant — BodyValueScope determines fetch keys
# =============================================================================

block propEmailBodyFetchOptionsStructural:
  checkPropertyN "EmailBodyFetchOptions: BodyValueScope determines fetch keys",
    QuickTrials:
    let opts = rng.genEmailBodyFetchOptions()
    lastInput = $opts.fetchBodyValues
    let j = opts.toJson()
    case opts.fetchBodyValues
    of bvsNone:
      doAssert j{"fetchTextBodyValues"}.isNil
      doAssert j{"fetchHTMLBodyValues"}.isNil
      doAssert j{"fetchAllBodyValues"}.isNil
    of bvsText:
      doAssert not j{"fetchTextBodyValues"}.isNil
      doAssert j{"fetchHTMLBodyValues"}.isNil
      doAssert j{"fetchAllBodyValues"}.isNil
    of bvsHtml:
      doAssert j{"fetchTextBodyValues"}.isNil
      doAssert not j{"fetchHTMLBodyValues"}.isNil
      doAssert j{"fetchAllBodyValues"}.isNil
    of bvsTextAndHtml:
      doAssert not j{"fetchTextBodyValues"}.isNil
      doAssert not j{"fetchHTMLBodyValues"}.isNil
      doAssert j{"fetchAllBodyValues"}.isNil
    of bvsAll:
      doAssert j{"fetchTextBodyValues"}.isNil
      doAssert j{"fetchHTMLBodyValues"}.isNil
      doAssert not j{"fetchAllBodyValues"}.isNil

# =============================================================================
# D. Field-count correlation — EmailFilterCondition
# =============================================================================

block propEmailFilterConditionFieldCount:
  checkProperty "EmailFilterCondition: toJson field count == isSome field count":
    let fc = rng.genEmailFilterCondition(trial)
    lastInput = "trial " & $trial
    let j = fc.toJson()
    var expectedCount = 0
    if fc.inMailbox.isSome:
      inc expectedCount
    if fc.inMailboxOtherThan.isSome:
      inc expectedCount
    if fc.before.isSome:
      inc expectedCount
    if fc.after.isSome:
      inc expectedCount
    if fc.minSize.isSome:
      inc expectedCount
    if fc.maxSize.isSome:
      inc expectedCount
    if fc.allInThreadHaveKeyword.isSome:
      inc expectedCount
    if fc.someInThreadHaveKeyword.isSome:
      inc expectedCount
    if fc.noneInThreadHaveKeyword.isSome:
      inc expectedCount
    if fc.hasKeyword.isSome:
      inc expectedCount
    if fc.notKeyword.isSome:
      inc expectedCount
    if fc.hasAttachment.isSome:
      inc expectedCount
    if fc.text.isSome:
      inc expectedCount
    if fc.fromAddr.isSome:
      inc expectedCount
    if fc.to.isSome:
      inc expectedCount
    if fc.cc.isSome:
      inc expectedCount
    if fc.bcc.isSome:
      inc expectedCount
    if fc.subject.isSome:
      inc expectedCount
    if fc.body.isSome:
      inc expectedCount
    if fc.header.isSome:
      inc expectedCount
    doAssert j.len == expectedCount,
      "Field count mismatch: json " & $j.len & " vs expected " & $expectedCount
