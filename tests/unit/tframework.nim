# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for generic method framework types: PropertyName, Filter, Comparator,
## PatchObject, and AddedItem.

import std/options
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
  let c = parseComparator(pn, collation = some("i;unicode-casemap"))
  doAssert c.collation.isSome
  doAssert c.collation.get() == "i;unicode-casemap"

block parseComparatorNotAscending:
  let pn = parsePropertyName("subject").get()
  let c = parseComparator(pn, isAscending = false)
  doAssert c.isAscending == false

# --- PatchObject ---

block emptyPatchLen:
  doAssert emptyPatch().len == 0

block setPropEmptyPath:
  assertErrFields setProp(emptyPatch(), "", newJNull()),
    "PatchObject", "path must not be empty", ""

block setPropValid:
  let p = setProp(emptyPatch(), "name", %"Alice").get()
  doAssert p.len == 1

block deletePropValid:
  let p = deleteProp(emptyPatch(), "addresses/0").get()
  doAssert p.len == 1

block deletePropEmptyPath:
  assertErrFields deleteProp(emptyPatch(), ""),
    "PatchObject", "path must not be empty", ""

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
  doAssert string(item.id) == "abc"
  doAssert int64(item.index) == 0'i64

# --- Adversarial edge cases ---

block setPropSlashOnlyPath:
  assertOk setProp(emptyPatch(), "/", %"val")

block setPropOverwriteSameKey:
  let p1 = setProp(emptyPatch(), "name", %"Alice").get()
  let p2 = setProp(p1, "name", %"Bob").get()
  doAssert p2.len == 1

block setPropThenDeleteSameKey:
  let p1 = setProp(emptyPatch(), "name", %"Alice").get()
  let p2 = deleteProp(p1, "name").get()
  doAssert p2.len == 1

block patchObjectManyEntries:
  var p = emptyPatch()
  for i in 0 ..< 100:
    p = setProp(p, "path" & $i, %i).get()
  doAssert p.len == 100

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

# --- PatchObject edge cases ---

block patchObjectTildeEscapePath:
  # RFC 6901 tilde escaping: stored as-is (no path parsing at Layer 1)
  let r = emptyPatch().setProp("a~0b", %"val").get()
  assertEq r.len, 1

block patchObjectDoubleslashPath:
  assertOk emptyPatch().setProp("//", %"val")

block patchObjectNulInPath:
  assertOk emptyPatch().setProp("a\x00b", %"val")

# --- Comparator and AddedItem edge cases ---

block comparatorEmptyCollation:
  let pn = parsePropertyName("subject").get()
  let c = parseComparator(pn, collation = some(""))
  assertOk c
  doAssert c.collation.isSome

block addedItemMaxIndex:
  let maxIdx = parseUnsignedInt(MaxUnsignedInt).get()
  let id = parseId("test").get()
  let ai = AddedItem(id: id, index: maxIdx)
  doAssert ai.index == maxIdx

# --- PatchObject.getKey round-trip ---

block patchObjectGetKeyAbsent:
  # getKey on an empty patch for any key returns isNone
  let p = emptyPatch()
  assertNone p.getKey("anything")
  assertNone p.getKey("name")
  assertNone p.getKey("")

block patchObjectSetPropThenGetKey:
  # setProp then getKey verifying actual JSON value content
  let p = setProp(emptyPatch(), "name", %"Alice").get()
  let got = p.getKey("name")
  assertSome got
  doAssert got.get().getStr() == "Alice"

block patchObjectDeletePropThenGetKey:
  # deleteProp then getKey returns JSON null
  let p = deleteProp(emptyPatch(), "addr/0").get()
  let got = p.getKey("addr/0")
  assertSome got
  doAssert got.get().kind == JNull

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
