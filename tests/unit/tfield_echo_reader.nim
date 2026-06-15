# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for the ``FieldEcho`` reader API: ``isValue``/``isNull``/``isAbsent``
## predicates, the ``valueOr`` fallback reader, the ``items`` iterator, and the
## ``toOpt`` lossy bridge — exercised across all three RFC 8620 §5.3 echo
## states (``fekValue`` / ``fekAbsent`` / ``fekNull``).

import std/sequtils

import jmap_client/internal/types/field_echo
import jmap_client/internal/types/validation

import ../massertions
import ../mtestblock

# --- valueOr: value vs fallback ---

testCase valueOrYieldsValue:
  assertEq fieldValue(5).valueOr(0), 5

testCase valueOrAbsentFallsBack:
  assertEq fieldAbsent(int).valueOr(0), 0

testCase valueOrNullFallsBack:
  assertEq fieldNull(int).valueOr(0), 0

# --- valueOr: binds fe once; evaluates def only on the fallback arms ---

testCase valueOrBindsEchoOnce:
  ## Guards against the template re-evaluating its ``fe`` argument (a regression
  ## if the ``let f = fe`` binding is dropped): a side-effecting producer must
  ## run exactly once.
  var calls = 0
  proc echoOnce(): FieldEcho[int] =
    inc calls
    fieldValue(5)

  assertEq echoOnce().valueOr(0), 5
  assertEq calls, 1

testCase valueOrDoesNotEvaluateDefOnValue:
  ## The fallback ``def`` is lazy — never evaluated when the value is present.
  var evaluated = false
  proc fallback(): int =
    evaluated = true
    0

  assertEq fieldValue(5).valueOr(fallback()), 5
  assertFalse evaluated, "valueOr must not evaluate def on fekValue"

# --- isValue / isNull / isAbsent: one true per state ---

testCase predicatesForValue:
  let fe = fieldValue(5)
  doAssert fe.isValue
  assertFalse fe.isNull, "fekValue must not report isNull"
  assertFalse fe.isAbsent, "fekValue must not report isAbsent"

testCase predicatesForAbsent:
  let fe = fieldAbsent(int)
  assertFalse fe.isValue, "fekAbsent must not report isValue"
  assertFalse fe.isNull, "fekAbsent must not report isNull"
  doAssert fe.isAbsent

testCase predicatesForNull:
  let fe = fieldNull(int)
  assertFalse fe.isValue, "fekNull must not report isValue"
  doAssert fe.isNull
  assertFalse fe.isAbsent, "fekNull must not report isAbsent"

# --- items iterator: yields once for value, zero times otherwise ---

testCase itemsYieldsOnceForValue:
  let collected = toSeq(fieldValue(5).items)
  assertLen collected, 1
  assertEq collected[0], 5

testCase itemsYieldsNeverForAbsent:
  assertLen toSeq(fieldAbsent(int).items), 0

testCase itemsYieldsNeverForNull:
  assertLen toSeq(fieldNull(int).items), 0

# --- toOpt: some for value, none for both absent and null ---

testCase toOptSomeForValue:
  assertSomeEq fieldValue(5).toOpt, 5

testCase toOptNoneForAbsent:
  assertNone fieldAbsent(int).toOpt

testCase toOptNoneForNull:
  assertNone fieldNull(int).toOpt
