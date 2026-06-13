# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for generic method framework types: PropertyName, Filter, Comparator,
## and AddedItem.

import std/json

import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives
import jmap_client/internal/types/framework

import ../massertions
import ../mtestblock

# --- PropertyName ---

testCase parsePropertyNameEmpty:
  assertErrFields parsePropertyName(""), "PropertyName", "must not be empty", ""

testCase parsePropertyNameValid:
  assertOk parsePropertyName("name")

testCase propertyNameBorrowedOps:
  let a = parsePropertyName("name").get()
  let b = parsePropertyName("name").get()
  let c = parsePropertyName("other").get()
  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "name"
  doAssert hash(a) == hash(b)
  doAssert a.len == 4

# --- FilterOperator ---

testCase filterOperatorStringBacking:
  doAssert $foAnd == "AND"
  doAssert $foOr == "OR"
  doAssert $foNot == "NOT"

# --- Filter[C] ---

testCase filterConditionConstruction:
  let f = filterCondition(42)
  doAssert f.kind == fkCondition
  doAssert f.condition == 42

testCase filterOperatorConstruction:
  let child = filterCondition(1)
  let f = filterAnd(@[child]).get()
  doAssert f.kind == fkOperator
  doAssert f.operator == foAnd
  doAssert f.operands.len == 1

testCase filterRecursiveNesting:
  let inner = filterOr(@[filterCondition(1), filterCondition(2)]).get()
  let outer = filterAnd(@[inner, filterCondition(3)]).get()
  doAssert outer.kind == fkOperator
  doAssert outer.operands.len == 2
  doAssert outer.operands[0].kind == fkOperator

# --- Comparator ---

testCase parseComparatorValid:
  let pn = parsePropertyName("name").get()
  let c = parseComparator(pn)
  doAssert c.direction == sdServerDefault
  doAssert c.collation.isNone

testCase parseComparatorWithCollation:
  let pn = parsePropertyName("name").get()
  let c = parseComparator(pn, collation = Opt.some(CollationUnicodeCasemap))
  doAssert c.collation.isSome
  doAssert c.collation.get() == CollationUnicodeCasemap

testCase parseComparatorNotAscending:
  let pn = parsePropertyName("subject").get()
  let c = parseComparator(pn, direction = sdDescending)
  doAssert c.direction == sdDescending

# --- AddedItem ---

testCase addedItemConstruction:
  let id = parseIdFromServer("abc").get()
  let idx = parseUnsignedInt(0'i64).get()
  let item = initAddedItem(id, idx)
  doAssert $item.id == "abc"
  doAssert item.index.toInt64 == 0'i64

# --- Filter arity tests (B3, RFC 8620 §5.5) ---

testCase filterNotIsSingleChild:
  ## NOT has exactly one child. ``filterNot`` takes a single filter, so a
  ## zero-child or multi-child NOT is not expressible — the arity is in the
  ## constructor's signature, not a runtime check.
  let f = filterNot(filterCondition[int](1))
  doAssert f.kind == fkOperator
  doAssert f.operator == foNot
  doAssert f.operands.len == 1

testCase filterAndOrRejectEmpty:
  ## AND/OR require one or more conditions; an empty operand list is rejected.
  assertErr filterAnd(newSeq[Filter[int]]())
  assertErr filterOr(newSeq[Filter[int]]())

testCase filterAndSingleOperand:
  let f = filterAnd(@[filterCondition[int](42)]).get()
  doAssert f.operands.len == 1

# --- Comparator and AddedItem edge cases ---

testCase addedItemMaxIndex:
  let maxIdx = parseUnsignedInt(MaxUnsignedInt).get()
  let id = parseIdFromServer("test").get()
  let ai = initAddedItem(id, maxIdx)
  doAssert ai.index == maxIdx

testCase parsePropertyNameSingleChar:
  ## parsePropertyName accepts a single-character string.
  let pn = parsePropertyName("x").get()
  assertOk pn
  doAssert $pn == "x"

testCase parsePropertyNameStandard:
  ## parsePropertyName accepts a standard property name.
  let pn = parsePropertyName("subject").get()
  assertOk pn
  doAssert $pn == "subject"

# --- Generic type instantiation: Filter[string] ---

testCase filterConditionString:
  ## filterCondition[string] constructs a leaf node with a string condition.
  let f = filterCondition[string]("hello")
  doAssert f.kind == fkCondition
  doAssert f.condition == "hello"

testCase filterOperatorString:
  ## filterOperator[string] composes string-typed child filters under foAnd.
  let childA = filterCondition[string]("a")
  let childB = filterCondition[string]("b")
  let f = filterAnd(@[childA, childB]).get()
  doAssert f.kind == fkOperator
  doAssert f.operator == foAnd
  assertLen f.operands, 2
  doAssert f.operands[0].kind == fkCondition
  doAssert f.operands[0].condition == "a"
  doAssert f.operands[1].kind == fkCondition
  doAssert f.operands[1].condition == "b"
