# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for Layer 2 framework serialisation: FilterOperator, Comparator,
## Filter[C], PatchObject, and AddedItem.

import std/json
import std/random
import std/strutils
import std/tables

import results

import jmap_client/serde
import jmap_client/serde_framework
import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/framework
import jmap_client/validation

import ./massertions
import ./mfixtures
import ./mproperty

# ---------------------------------------------------------------------------
# Helper definitions
# ---------------------------------------------------------------------------

proc intToJson(c: int): JsonNode {.noSideEffect, raises: [].} =
  ## Serialise an int condition to a JSON object for Filter[int] tests.
  ## Wraps in {"value": N} because Filter.fromJson expects JObject conditions.
  {.cast(noSideEffect).}:
    %*{"value": c}

proc fromIntCondition(
    n: JsonNode
): Result[int, ValidationError] {.noSideEffect, raises: [].} =
  ## Deserialise a JSON object to int for Filter[int] tests.
  ## Expects {"value": N} wrapper matching intToJson.
  checkJsonKind(n, JObject, "int")
  let vNode = n{"value"}
  checkJsonKind(vNode, JInt, "int", "missing or invalid value")
  ok(vNode.getInt(0))

func filterEq(a, b: Filter[int]): bool =
  ## Recursively compare two Filter[int] trees for structural equality.
  if a.kind != b.kind:
    return false
  case a.kind
  of fkCondition:
    a.condition == b.condition
  of fkOperator:
    if a.operator != b.operator:
      return false
    if a.conditions.len != b.conditions.len:
      return false
    for i in 0 ..< a.conditions.len:
      if not filterEq(a.conditions[i], b.conditions[i]):
        return false
    true

# =============================================================================
# A. Round-trip tests
# =============================================================================

block roundTripFilterOperatorAnd:
  assertOkEq FilterOperator.fromJson(foAnd.toJson()), foAnd

block roundTripFilterOperatorOr:
  assertOkEq FilterOperator.fromJson(foOr.toJson()), foOr

block roundTripFilterOperatorNot:
  assertOkEq FilterOperator.fromJson(foNot.toJson()), foNot

block roundTripComparatorBasic:
  let original = makeComparator()
  let rt = Comparator.fromJson(original.toJson())
  assertOk rt
  let v = rt.get()
  doAssert v.property == original.property
  doAssert v.isAscending == original.isAscending
  doAssert v.collation.isNone == original.collation.isNone

block roundTripComparatorWithCollation:
  let original = makeComparatorWithCollation()
  let rt = Comparator.fromJson(original.toJson())
  assertOk rt
  let v = rt.get()
  doAssert v.property == original.property
  doAssert v.isAscending == original.isAscending
  doAssert v.collation.isSome
  assertEq v.collation.get(), original.collation.get()

block roundTripComparatorDescending:
  let original = makeComparator(isAscending = false)
  let rt = Comparator.fromJson(original.toJson())
  assertOk rt
  doAssert not rt.get().isAscending

block roundTripFilterCondition:
  let original = makeFilterCondition(42)
  let rt = Filter[int].fromJson(original.toJson(intToJson), fromIntCondition)
  assertOk rt
  doAssert filterEq(rt.get(), original)

block roundTripFilterOperatorSingle:
  let original = makeFilterAnd(@[makeFilterCondition(1), makeFilterCondition(2)])
  let rt = Filter[int].fromJson(original.toJson(intToJson), fromIntCondition)
  assertOk rt
  doAssert filterEq(rt.get(), original)

block roundTripFilterNestedDepth2:
  let inner = makeFilterOr(@[makeFilterCondition(10), makeFilterCondition(20)])
  let original = makeFilterAnd(@[makeFilterCondition(1), inner, makeFilterCondition(3)])
  let rt = Filter[int].fromJson(original.toJson(intToJson), fromIntCondition)
  assertOk rt
  doAssert filterEq(rt.get(), original)

block roundTripPatchObjectEmpty:
  let original = emptyPatch()
  let rt = PatchObject.fromJson(original.toJson())
  assertOk rt
  assertEq rt.get().len, 0

block roundTripPatchObjectSingleSet:
  {.cast(noSideEffect).}:
    let original = emptyPatch().setProp("name", %"New Name").get()
    let rt = PatchObject.fromJson(original.toJson())
    assertOk rt
    assertEq rt.get().len, 1

block roundTripPatchObjectSingleDelete:
  let original = emptyPatch().deleteProp("role").get()
  let rt = PatchObject.fromJson(original.toJson())
  assertOk rt
  assertEq rt.get().len, 1

block roundTripPatchObjectMixed:
  {.cast(noSideEffect).}:
    var p = emptyPatch()
    p = p.setProp("name", %"Updated").get()
    p = p.deleteProp("role").get()
    p = p.setProp("sortOrder", %42).get()
    let rt = PatchObject.fromJson(p.toJson())
    assertOk rt
    assertEq rt.get().len, 3

block roundTripPatchObjectNestedValues:
  {.cast(noSideEffect).}:
    var p = emptyPatch()
    p = p.setProp("simple", %"text").get()
    p = p.setProp("number", %42).get()
    p = p.setProp("flag", %true).get()
    p = p.setProp("nested", %*{"a": {"b": true}}).get()
    p = p.setProp("array", %*[1, 2, 3]).get()
    p = p.setProp("mixed", %*{"x": 1, "y": [2, 3], "z": {"d": true}}).get()
    let rt = PatchObject.fromJson(p.toJson())
    assertOk rt
    assertEq rt.get().len, 6

block roundTripAddedItem:
  let original = makeAddedItem()
  let rt = AddedItem.fromJson(original.toJson())
  assertOk rt
  let v = rt.get()
  doAssert v.id == original.id
  doAssert v.index == original.index

# =============================================================================
# B. toJson structural correctness
# =============================================================================

block filterOperatorToJsonAnd:
  let j = foAnd.toJson()
  doAssert j.kind == JString
  assertEq j.getStr(""), "AND"

block filterOperatorToJsonOr:
  let j = foOr.toJson()
  doAssert j.kind == JString
  assertEq j.getStr(""), "OR"

block filterOperatorToJsonNot:
  let j = foNot.toJson()
  doAssert j.kind == JString
  assertEq j.getStr(""), "NOT"

block comparatorToJsonFieldNames:
  let c = makeComparator()
  let j = c.toJson()
  doAssert j.kind == JObject
  doAssert j{"property"} != nil
  doAssert j{"property"}.kind == JString
  doAssert j{"isAscending"} != nil
  doAssert j{"isAscending"}.kind == JBool
  doAssert j{"collation"}.isNil

block comparatorToJsonCollationAbsent:
  let c = parseComparator(makePropertyName(), true, Opt.none(string)).get()
  let j = c.toJson()
  doAssert j{"collation"}.isNil, "collation key must be absent when none"

block comparatorToJsonCollationPresent:
  let c = makeComparatorWithCollation(collation = "i;unicode-casemap")
  let j = c.toJson()
  doAssert j{"collation"} != nil
  assertEq j{"collation"}.getStr(""), "i;unicode-casemap"

block filterToJsonCondition:
  let f = makeFilterCondition(99)
  let j = f.toJson(intToJson)
  doAssert j.kind == JObject
  doAssert j{"value"} != nil
  assertEq j{"value"}.getInt(0), 99

block filterToJsonOperator:
  let f = makeFilterAnd(@[makeFilterCondition(1)])
  let j = f.toJson(intToJson)
  doAssert j.kind == JObject
  doAssert j{"operator"} != nil
  assertEq j{"operator"}.getStr(""), "AND"
  doAssert j{"conditions"} != nil
  doAssert j{"conditions"}.kind == JArray
  assertEq j{"conditions"}.len, 1

block patchObjectToJsonFieldNames:
  {.cast(noSideEffect).}:
    var p = emptyPatch()
    p = p.setProp("name", %"val").get()
    p = p.deleteProp("role").get()
    let j = p.toJson()
    doAssert j.kind == JObject
    doAssert j{"name"} != nil
    assertEq j{"name"}.getStr(""), "val"
    doAssert j{"role"} != nil
    doAssert j{"role"}.kind == JNull

block addedItemToJsonFieldNames:
  let item = makeAddedItem()
  let j = item.toJson()
  doAssert j.kind == JObject
  doAssert j{"id"} != nil
  doAssert j{"id"}.kind == JString
  doAssert j{"index"} != nil
  doAssert j{"index"}.kind == JInt

# =============================================================================
# C. Edge-case deserialization
# =============================================================================

# --- FilterOperator ---

block filterOperatorDeserCustom:
  {.cast(noSideEffect).}:
    assertErrContains FilterOperator.fromJson(%"CUSTOM"), "unknown operator"

block filterOperatorDeserEmpty:
  {.cast(noSideEffect).}:
    assertErrContains FilterOperator.fromJson(%""), "unknown operator"

block filterOperatorDeserCaseSensitiveLower:
  {.cast(noSideEffect).}:
    assertErr FilterOperator.fromJson(%"and")

block filterOperatorDeserCaseSensitiveMixed:
  {.cast(noSideEffect).}:
    assertErr FilterOperator.fromJson(%"And")

block filterOperatorDeserNil:
  const nilNode: JsonNode = nil
  assertErr FilterOperator.fromJson(nilNode)

block filterOperatorDeserJNull:
  assertErr FilterOperator.fromJson(newJNull())

block filterOperatorDeserWrongKind:
  {.cast(noSideEffect).}:
    assertErr FilterOperator.fromJson(%42)

# --- Comparator ---

block comparatorDeserAllFieldsPresent:
  {.cast(noSideEffect).}:
    let j =
      %*{"property": "subject", "isAscending": false, "collation": "i;unicode-casemap"}
    let r = Comparator.fromJson(j)
    assertOk r
    let v = r.get()
    assertEq string(v.property), "subject"
    doAssert not v.isAscending
    doAssert v.collation.isSome
    assertEq v.collation.get(), "i;unicode-casemap"

block comparatorDeserMissingIsAscending:
  {.cast(noSideEffect).}:
    let j = %*{"property": "subject"}
    let r = Comparator.fromJson(j)
    assertOk r
    doAssert r.get().isAscending, "isAscending must default to true"

block comparatorDeserMissingProperty:
  {.cast(noSideEffect).}:
    let j = %*{"isAscending": true}
    assertErrContains Comparator.fromJson(j), "missing or invalid property"

block comparatorDeserPropertyWrongKind:
  {.cast(noSideEffect).}:
    let j = %*{"property": 42, "isAscending": true}
    assertErr Comparator.fromJson(j)

block comparatorDeserIsAscendingWrongKind:
  {.cast(noSideEffect).}:
    let j = %*{"property": "subject", "isAscending": "yes"}
    assertErrContains Comparator.fromJson(j), "isAscending must be boolean"

block comparatorDeserNotObject:
  {.cast(noSideEffect).}:
    assertErr Comparator.fromJson(%*[1, 2, 3])

block comparatorDeserNil:
  const nilNode: JsonNode = nil
  assertErr Comparator.fromJson(nilNode)

block comparatorDeserCollationWrongKindLenient:
  {.cast(noSideEffect).}:
    let j = %*{"property": "subject", "collation": 42}
    let r = Comparator.fromJson(j)
    assertOk r
    doAssert r.get().collation.isNone, "wrong kind collation should be treated as none"

block comparatorRoundTripNoCollation:
  {.cast(noSideEffect).}:
    let j = %*{"property": "subject", "isAscending": true}
    let c1 = Comparator.fromJson(j).get()
    doAssert c1.collation.isNone
    let j2 = c1.toJson()
    doAssert j2{"collation"}.isNil, "round-trip must preserve key omission"

# --- Filter ---

block filterDeserCondition:
  {.cast(noSideEffect).}:
    # A JObject without "operator" key is a condition leaf
    let j = %*{"value": 42}
    let r = Filter[int].fromJson(j, fromIntCondition)
    assertOk r
    doAssert r.get().kind == fkCondition

block filterDeserConditionNotObject:
  {.cast(noSideEffect).}:
    # Non-JObject input rejected by checkJsonKind
    let r = Filter[int].fromJson(%42, fromIntCondition)
    assertErr r

block filterDeserOperatorWithConditions:
  {.cast(noSideEffect).}:
    let j = %*{"operator": "AND", "conditions": [{"value": 42}, {"value": 99}]}
    let r = Filter[int].fromJson(j, fromIntCondition)
    assertOk r
    let v = r.get()
    doAssert v.kind == fkOperator
    doAssert v.operator == foAnd
    assertEq v.conditions.len, 2

block filterDeserNestedDepth2:
  {.cast(noSideEffect).}:
    let j = %*{
      "operator": "OR",
      "conditions": [
        {"operator": "AND", "conditions": [{"value": 1}, {"value": 2}]},
        {"operator": "NOT", "conditions": [{"value": 3}]},
      ],
    }
    let r = Filter[int].fromJson(j, fromIntCondition)
    assertOk r
    let v = r.get()
    doAssert v.kind == fkOperator
    doAssert v.operator == foOr
    assertEq v.conditions.len, 2

block filterDeserEmptyConditions:
  {.cast(noSideEffect).}:
    let j = %*{"operator": "AND", "conditions": []}
    let r = Filter[int].fromJson(j, fromIntCondition)
    assertOk r
    assertEq r.get().conditions.len, 0

block filterDeserMissingConditions:
  {.cast(noSideEffect).}:
    let j = %*{"operator": "AND"}
    let r = Filter[int].fromJson(j, fromIntCondition)
    assertErr r

block filterDeserCallbackError:
  {.cast(noSideEffect).}:
    # Callback receives a string (not JObject), should propagate error
    let j = %*{"operator": "AND", "conditions": ["not-an-object"]}
    let r = Filter[int].fromJson(j, fromIntCondition)
    assertErr r

block filterDeserNotObject:
  {.cast(noSideEffect).}:
    assertErr Filter[int].fromJson(%*[1, 2, 3], fromIntCondition)

block filterDeserNil:
  const nilNode: JsonNode = nil
  assertErr Filter[int].fromJson(nilNode, fromIntCondition)

# --- PatchObject ---

block patchObjectDeserSingleSet:
  {.cast(noSideEffect).}:
    let j = %*{"name": "New Name"}
    let r = PatchObject.fromJson(j)
    assertOk r
    assertEq r.get().len, 1

block patchObjectDeserSingleDelete:
  {.cast(noSideEffect).}:
    let j = %*{"role": newJNull()}
    let r = PatchObject.fromJson(j)
    assertOk r
    assertEq r.get().len, 1

block patchObjectDeserNestedMixed:
  {.cast(noSideEffect).}:
    let j = %*{"a": 1, "b": [2, 3], "c": {"d": true}}
    let r = PatchObject.fromJson(j)
    assertOk r
    assertEq r.get().len, 3

block patchObjectDeserMultiple:
  {.cast(noSideEffect).}:
    let j = %*{"a": 1, "b": 2}
    let r = PatchObject.fromJson(j)
    assertOk r
    assertEq r.get().len, 2

block patchObjectDeserEmpty:
  let j = newJObject()
  let r = PatchObject.fromJson(j)
  assertOk r
  assertEq r.get().len, 0

block patchObjectDeserNotObject:
  {.cast(noSideEffect).}:
    assertErr PatchObject.fromJson(%"notobject")

block patchObjectDeserNil:
  const nilNode: JsonNode = nil
  assertErr PatchObject.fromJson(nilNode)

# --- AddedItem ---

block addedItemDeserValid:
  {.cast(noSideEffect).}:
    let j = %*{"id": "x", "index": 5}
    let r = AddedItem.fromJson(j)
    assertOk r
    assertEq string(r.get().id), "x"

block addedItemDeserIndexZero:
  {.cast(noSideEffect).}:
    let j = %*{"id": "x", "index": 0}
    let r = AddedItem.fromJson(j)
    assertOk r

block addedItemDeserIndexMax:
  {.cast(noSideEffect).}:
    let j = %*{"id": "x", "index": 9007199254740991}
    let r = AddedItem.fromJson(j)
    assertOk r

block addedItemDeserIndexNegative:
  {.cast(noSideEffect).}:
    let j = %*{"id": "x", "index": -1}
    assertErr AddedItem.fromJson(j)

block addedItemDeserInvalidId:
  {.cast(noSideEffect).}:
    let j = %*{"id": "", "index": 5}
    assertErr AddedItem.fromJson(j)

block addedItemDeserMissingId:
  {.cast(noSideEffect).}:
    let j = %*{"index": 5}
    assertErr AddedItem.fromJson(j)

block addedItemDeserMissingIndex:
  {.cast(noSideEffect).}:
    let j = %*{"id": "x"}
    assertErr AddedItem.fromJson(j)

block addedItemDeserNotObject:
  {.cast(noSideEffect).}:
    assertErr AddedItem.fromJson(%*[1, 2, 3])

block addedItemDeserNil:
  const nilNode: JsonNode = nil
  assertErr AddedItem.fromJson(nilNode)

# =============================================================================
# D. Property-based round-trip tests
# =============================================================================

checkProperty "FilterOperator round-trip":
  let ops = [foAnd, foOr, foNot]
  let op = ops[trial mod 3]
  assertOkEq FilterOperator.fromJson(op.toJson()), op

checkProperty "Comparator round-trip":
  let c = rng.genComparator()
  let rt = Comparator.fromJson(c.toJson())
  doAssert rt.isOk, "Comparator round-trip failed"
  let v = rt.get()
  doAssert v.property == c.property
  doAssert v.isAscending == c.isAscending
  doAssert v.collation == c.collation

checkProperty "Filter[int] round-trip":
  let f = rng.genFilter(3)
  let rt = Filter[int].fromJson(f.toJson(intToJson), fromIntCondition)
  doAssert rt.isOk, "Filter round-trip failed"
  doAssert filterEq(rt.get(), f), "Filter values differ"

checkProperty "PatchObject round-trip":
  let p = rng.genPatchObject(5)
  let rt = PatchObject.fromJson(p.toJson())
  doAssert rt.isOk, "PatchObject round-trip failed"
  doAssert rt.get().len == p.len, "PatchObject lengths differ"

checkProperty "AddedItem round-trip":
  let item = rng.genAddedItem()
  let rt = AddedItem.fromJson(item.toJson())
  doAssert rt.isOk, "AddedItem round-trip failed"
  let v = rt.get()
  doAssert v.id == item.id
  doAssert v.index == item.index
