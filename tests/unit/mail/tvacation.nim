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
  assertEq res.error[0].typeName, "VacationResponseUpdateSet"
  assertEq res.error[0].message, "must contain at least one update"
  assertEq res.error[0].value, ""

testCase initVacationResponseUpdateSetSingleValid:
  assertOk initVacationResponseUpdateSet(@[setIsEnabled(true)])

testCase initVacationResponseUpdateSetTwoSameKind:
  let res = initVacationResponseUpdateSet(@[setIsEnabled(true), setIsEnabled(false)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "VacationResponseUpdateSet"
  assertEq res.error[0].message, "duplicate target property"
  assertEq res.error[0].value, "vruSetIsEnabled"

testCase initVacationResponseUpdateSetThreeSameKind:
  ## Three occurrences of the same kind still yield ONE error —
  ## the Haskell-style "each repeated key reported once" contract.
  let res = initVacationResponseUpdateSet(
    @[setIsEnabled(true), setIsEnabled(false), setIsEnabled(true)]
  )
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].value, "vruSetIsEnabled"

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
    assertEq e.message, "duplicate target property"
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
