# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for VacationResponse setters and
## initVacationResponseUpdateSet. The uniqueness-by-kind contract
## states that each distinct repeated ``kind`` yields exactly one
## error regardless of occurrence count.

{.push raises: [].}

import jmap_client/internal/mail/vacation
import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives

import ../../massertions
import ../../mtestblock

# ============= A. VacationResponseUpdate setters =============

testCase setIsEnabledConstructsCorrectKind:
  let u = setIsEnabled(true)
  assertEq u.kind, vruSetIsEnabled
  assertEq u.isEnabled, true

testCase setFromDateConstructsCorrectKind:
  let d = parseUtcDate("2026-04-15T12:00:00Z").get()
  let u = setFromDate(Opt.some(d))
  assertEq u.kind, vruSetFromDate
  assertSomeEq u.fromDate, d

testCase setSubjectClearsWhenNone:
  let u = setSubject(Opt.none(string))
  assertEq u.kind, vruSetSubject
  assertNone u.subject

# ============= B. initVacationResponseUpdateSet =============

testCase initVacationResponseUpdateSetEmpty:
  let res = initVacationResponseUpdateSet(@[])
  assertErr res
  assertLen res.error, 1
  assertEq res.error.head.typeName, "VacationResponseUpdateSet"
  assertEq res.error.head.reason, "must contain at least one update"
  assertEq res.error.head.value, ""

testCase initVacationResponseUpdateSetSingleValid:
  assertOk initVacationResponseUpdateSet(@[setIsEnabled(true)])

testCase initVacationResponseUpdateSetTwoSameKind:
  let res = initVacationResponseUpdateSet(@[setIsEnabled(true), setIsEnabled(false)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error.head.typeName, "VacationResponseUpdateSet"
  assertEq res.error.head.reason, "duplicate target property"
  assertEq res.error.head.value, "vruSetIsEnabled"

testCase initVacationResponseUpdateSetThreeSameKind:
  ## Three occurrences of the same kind still yield ONE error —
  ## the Haskell-style "each repeated key reported once" contract.
  let res = initVacationResponseUpdateSet(
    @[setIsEnabled(true), setIsEnabled(false), setIsEnabled(true)]
  )
  assertErr res
  assertLen res.error, 1
  assertEq res.error.head.value, "vruSetIsEnabled"

testCase initVacationResponseUpdateSetTwoDistinctRepeated:
  ## Two distinct repeated kinds → TWO errors, one per distinct
  ## duplicate key.
  let res = initVacationResponseUpdateSet(
    @[
      setIsEnabled(true),
      setIsEnabled(false),
      setSubject(Opt.some("A")),
      setSubject(Opt.none(string)),
    ]
  )
  assertErr res
  assertLen res.error, 2
  var seen: set[VacationResponseUpdateVariantKind] = {}
  for e in res.error:
    assertEq e.typeName, "VacationResponseUpdateSet"
    assertEq e.reason, "duplicate target property"
    if e.value == "vruSetIsEnabled":
      seen.incl vruSetIsEnabled
    elif e.value == "vruSetSubject":
      seen.incl vruSetSubject
  doAssert vruSetIsEnabled in seen
  doAssert vruSetSubject in seen

# ============= C. Remaining VacationResponseUpdate setters =============

testCase setToDateConstructsCorrectKind:
  let d = parseUtcDate("2026-04-15T12:00:00Z").get()
  let u = setToDate(Opt.some(d))
  assertEq u.kind, vruSetToDate
  assertSomeEq u.toDate, d

testCase setTextBodyClearsWhenNone:
  let u = setTextBody(Opt.none(string))
  assertEq u.kind, vruSetTextBody
  assertNone u.textBody

testCase setHtmlBodyConstructsCorrectKind:
  let u = setHtmlBody(Opt.some("<p>away</p>"))
  assertEq u.kind, vruSetHtmlBody
  assertSomeEq u.htmlBody, "<p>away</p>"

# ============= D. Window-order invariant (B4, RFC 8621 §8) =============

testCase windowBackwardsRejected:
  ## A batch setting both endpoints with from > to is an empty/backwards
  ## window — rejected with one window-order error.
  let early = parseUtcDate("2026-06-01T00:00:00Z").get()
  let late = parseUtcDate("2026-06-30T00:00:00Z").get()
  let res = initVacationResponseUpdateSet(
    @[setFromDate(Opt.some(late)), setToDate(Opt.some(early))]
  )
  assertErr res
  assertLen res.error, 1
  assertEq res.error.head.typeName, "VacationResponseUpdateSet"
  assertEq res.error.head.reason, "window start is after window end"

testCase windowForwardAccepted:
  let early = parseUtcDate("2026-06-01T00:00:00Z").get()
  let late = parseUtcDate("2026-06-30T00:00:00Z").get()
  assertOk initVacationResponseUpdateSet(
    @[setFromDate(Opt.some(early)), setToDate(Opt.some(late))]
  )

testCase windowEqualEndpointsAccepted:
  ## from == to is a degenerate (empty) window, not a contradiction.
  let same = parseUtcDate("2026-06-15T09:30:00Z").get()
  assertOk initVacationResponseUpdateSet(
    @[setFromDate(Opt.some(same)), setToDate(Opt.some(same))]
  )

testCase windowSingleEndpointUnchecked:
  ## A from-only or to-only batch is accepted — the server holds the other
  ## endpoint and is authoritative.
  let d = parseUtcDate("2026-06-15T09:30:00Z").get()
  assertOk initVacationResponseUpdateSet(@[setFromDate(Opt.some(d))])
  assertOk initVacationResponseUpdateSet(@[setToDate(Opt.some(d))])

testCase windowClearedEndpointsAccepted:
  ## Clearing one or both endpoints (Opt.none) carries no window to check.
  assertOk initVacationResponseUpdateSet(
    @[setFromDate(Opt.none(UTCDate)), setToDate(Opt.none(UTCDate))]
  )
  let d = parseUtcDate("2026-06-15T09:30:00Z").get()
  assertOk initVacationResponseUpdateSet(
    @[setFromDate(Opt.some(d)), setToDate(Opt.none(UTCDate))]
  )

testCase windowFractionalSecondsSound:
  ## Soundness against a naive lexical compare: with equal whole-second
  ## prefixes, "…00.5Z" is strictly AFTER "…00Z" on the timeline even though
  ## '.' (0x2E) sorts before 'Z' (0x5A). The window comparator splits the
  ## fixed prefix from the right-zero-padded fraction.
  let whole = parseUtcDate("2026-06-15T12:00:00Z").get()
  let frac = parseUtcDate("2026-06-15T12:00:00.5Z").get()
  # from = .5 (later), to = whole (earlier) → backwards → rejected.
  let backwards = initVacationResponseUpdateSet(
    @[setFromDate(Opt.some(frac)), setToDate(Opt.some(whole))]
  )
  assertErr backwards
  assertEq backwards.error.head.reason, "window start is after window end"
  # from = whole (earlier), to = .5 (later) → forwards → accepted.
  assertOk initVacationResponseUpdateSet(
    @[setFromDate(Opt.some(whole)), setToDate(Opt.some(frac))]
  )

testCase windowAndDuplicateBothReported:
  ## The accumulating contract: a batch that is both backwards-windowed AND
  ## has a duplicate kind surfaces both error classes in one Err pass.
  let early = parseUtcDate("2026-06-01T00:00:00Z").get()
  let late = parseUtcDate("2026-06-30T00:00:00Z").get()
  let res = initVacationResponseUpdateSet(
    @[
      setIsEnabled(true),
      setIsEnabled(false),
      setFromDate(Opt.some(late)),
      setToDate(Opt.some(early)),
    ]
  )
  assertErr res
  assertLen res.error, 2
  var sawDup = false
  var sawWindow = false
  for e in res.error:
    if e.reason == "duplicate target property":
      sawDup = true
    elif e.reason == "window start is after window end":
      sawWindow = true
  doAssert sawDup
  doAssert sawWindow
