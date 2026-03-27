# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for generic method framework types: PropertyName, Filter, Comparator,
## PatchObject, and AddedItem.

import std/hashes
import std/json

import pkg/results

import jmap_client/primitives
import jmap_client/framework

# --- PropertyName ---

block parsePropertyNameEmpty:
  doAssert parsePropertyName("").isErr

block parsePropertyNameValid:
  doAssert parsePropertyName("name").isOk

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
  let result = parseComparator(pn)
  doAssert result.isOk
  let c = result.get()
  doAssert c.isAscending == true
  doAssert c.collation.isNone

block parseComparatorWithCollation:
  let pn = parsePropertyName("name").get()
  let result = parseComparator(pn, collation = Opt.some("i;unicode-casemap"))
  doAssert result.isOk
  let c = result.get()
  doAssert c.collation.isSome
  doAssert c.collation.get() == "i;unicode-casemap"

block parseComparatorNotAscending:
  let pn = parsePropertyName("subject").get()
  let result = parseComparator(pn, isAscending = false)
  doAssert result.isOk
  doAssert result.get().isAscending == false

# --- PatchObject ---

block emptyPatchLen:
  doAssert emptyPatch().len == 0

block setPropEmptyPath:
  doAssert setProp(emptyPatch(), "", newJNull()).isErr

block setPropValid:
  let result = setProp(emptyPatch(), "name", %"Alice")
  doAssert result.isOk
  doAssert result.get().len == 1

block deletePropValid:
  let result = deleteProp(emptyPatch(), "addresses/0")
  doAssert result.isOk
  doAssert result.get().len == 1

block deletePropEmptyPath:
  doAssert deleteProp(emptyPatch(), "").isErr

block chainedSetProp:
  let p1 = setProp(emptyPatch(), "name", %"Alice").get()
  let p2 = setProp(p1, "age", %30).get()
  doAssert p2.len == 2

block patchObjectImmutability:
  let original = emptyPatch()
  let modified = setProp(original, "name", %"Alice").get()
  doAssert original.len == 0
  doAssert modified.len == 1

block patchObjectNoBorrowedOps:
  doAssert not compiles(emptyPatch() == emptyPatch())
  doAssert not compiles($emptyPatch())
  doAssert not compiles(hash(emptyPatch()))

# --- AddedItem ---

block addedItemConstruction:
  let id = parseId("abc").get()
  let idx = parseUnsignedInt(0'i64).get()
  let item = AddedItem(id: id, index: idx)
  doAssert item.id == id
  doAssert item.index == idx
