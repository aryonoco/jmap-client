# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for generic method framework types: PropertyName, Filter, Comparator,
## and AddedItem.

import std/json

import jmap_client/validation
import jmap_client/primitives
import jmap_client/framework

import ../massertions

# --- PropertyName ---

block parsePropertyNameEmpty:
  assertErrFields parsePropertyName(""), "PropertyName", "must not be empty", ""

block parsePropertyNameValid:
  assertOk parsePropertyName("name")

block propertyNameBorrowedOps:
  let a = parsePropertyName("name").get()
  let b = parsePropertyName("name").get()
  let c = parsePropertyName("other").get()
  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "name"
  doAssert hash(a) == hash(b)
  doAssert a.len == 4

# --- FilterOperator ---

block filterOperatorStringBacking:
  doAssert $foAnd == "AND"
  doAssert $foOr == "OR"
  doAssert $foNot == "NOT"

# --- Filter[C] ---

block filterConditionConstruction:
  let f = filterCondition(42)
  doAssert f.kind == fkCondition
  doAssert f.condition == 42

block filterOperatorConstruction:
  let child = filterCondition(1)
  let f = filterOperator[int](foAnd, @[child])
  doAssert f.kind == fkOperator
  doAssert f.operator == foAnd
  doAssert f.conditions.len == 1

block filterRecursiveNesting:
  let inner = filterOperator[int](foOr, @[filterCondition(1), filterCondition(2)])
  let outer = filterOperator[int](foAnd, @[inner, filterCondition(3)])
  doAssert outer.kind == fkOperator
  doAssert outer.conditions.len == 2
  doAssert outer.conditions[0].kind == fkOperator

# --- Comparator ---

block parseComparatorValid:
  let pn = parsePropertyName("name").get()
  let c = parseComparator(pn)
  doAssert c.isAscending == true
  doAssert c.collation.isNone

block parseComparatorWithCollation:
  let pn = parsePropertyName("name").get()
  let c = parseComparator(pn, collation = Opt.some("i;unicode-casemap"))
  doAssert c.collation.isSome
  doAssert c.collation.get() == "i;unicode-casemap"

block parseComparatorNotAscending:
  let pn = parsePropertyName("subject").get()
  let c = parseComparator(pn, isAscending = false)
  doAssert c.isAscending == false

# --- AddedItem ---

block addedItemConstruction:
  let id = parseId("abc").get()
  let idx = parseUnsignedInt(0'i64).get()
  let item = initAddedItem(id, idx)
  doAssert string(item.id) == "abc"
  doAssert int64(item.index) == 0'i64

# --- Filter arity tests ---

block filterOperatorNotEmpty:
  # NOT with zero children: structurally valid
  let f = filterOperator[int](foNot, newSeq[Filter[int]]())
  doAssert f.kind == fkOperator

block filterOperatorNotMultiple:
  # NOT with multiple children: RFC semantics = NOR (none must match)
  let a = filterCondition[int](1)
  let b = filterCondition[int](2)
  let c = filterCondition[int](3)
  let f = filterOperator[int](foNot, @[a, b, c])
  doAssert f.conditions.len == 3

block filterOperatorAndSingle:
  let f = filterOperator[int](foAnd, @[filterCondition[int](42)])
  doAssert f.conditions.len == 1

# --- Comparator and AddedItem edge cases ---

block comparatorEmptyCollation:
  let pn = parsePropertyName("subject").get()
  let c = parseComparator(pn, collation = Opt.some(""))
  assertOk c
  doAssert c.collation.isSome

block addedItemMaxIndex:
  let maxIdx = parseUnsignedInt(MaxUnsignedInt).get()
  let id = parseId("test").get()
  let ai = initAddedItem(id, maxIdx)
  doAssert ai.index == maxIdx

block parsePropertyNameSingleChar:
  ## parsePropertyName accepts a single-character string.
  let pn = parsePropertyName("x").get()
  assertOk pn
  doAssert $pn == "x"

block parsePropertyNameStandard:
  ## parsePropertyName accepts a standard property name.
  let pn = parsePropertyName("subject").get()
  assertOk pn
  doAssert $pn == "subject"

# --- Generic type instantiation: Filter[string] ---

block filterConditionString:
  ## filterCondition[string] constructs a leaf node with a string condition.
  let f = filterCondition[string]("hello")
  doAssert f.kind == fkCondition
  doAssert f.condition == "hello"

block filterOperatorString:
  ## filterOperator[string] composes string-typed child filters under foAnd.
  let childA = filterCondition[string]("a")
  let childB = filterCondition[string]("b")
  let f = filterOperator[string](foAnd, @[childA, childB])
  doAssert f.kind == fkOperator
  doAssert f.operator == foAnd
  assertLen f.conditions, 2
  doAssert f.conditions[0].kind == fkCondition
  doAssert f.conditions[0].condition == "a"
  doAssert f.conditions[1].kind == fkCondition
  doAssert f.conditions[1].condition == "b"
