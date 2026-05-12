# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for Layer 2 framework serialisation: FilterOperator, Comparator,
## Filter[C], and AddedItem.

import std/json
import std/random
import std/strutils

import jmap_client/internal/serialisation/serde_framework
import jmap_client/internal/types/primitives
import jmap_client/internal/types/framework
import jmap_client/internal/types/validation

import ../massertions
import ../mfixtures
import ../mproperty
import ../mserde_fixtures
import ../mtestblock

# =============================================================================
# A. Round-trip tests
# =============================================================================

testCase roundTripFilterOperatorAnd:
  assertOkEq FilterOperator.fromJson(foAnd.toJson()), foAnd

testCase roundTripFilterOperatorOr:
  assertOkEq FilterOperator.fromJson(foOr.toJson()), foOr

testCase roundTripFilterOperatorNot:
  assertOkEq FilterOperator.fromJson(foNot.toJson()), foNot

testCase roundTripComparatorBasic:
  let original = makeComparator()
  let v = Comparator.fromJson(original.toJson()).get()
  doAssert v.property == original.property
  doAssert v.isAscending == original.isAscending
  doAssert v.collation.isNone == original.collation.isNone

testCase roundTripComparatorWithCollation:
  let original = makeComparatorWithCollation()
  let v = Comparator.fromJson(original.toJson()).get()
  doAssert v.property == original.property
  doAssert v.isAscending == original.isAscending
  doAssert v.collation.isSome
  assertEq v.collation.get(), original.collation.get()

testCase roundTripComparatorDescending:
  let original = makeComparator(isAscending = false)
  let v = Comparator.fromJson(original.toJson()).get()
  doAssert not v.isAscending

testCase roundTripFilterCondition:
  let original = makeFilterCondition(42)
  let v = Filter[int].fromJson(original.toJson(), fromIntCondition).get()
  doAssert filterEq(v, original)

testCase roundTripFilterOperatorSingle:
  let original = makeFilterAnd(@[makeFilterCondition(1), makeFilterCondition(2)])
  let v = Filter[int].fromJson(original.toJson(), fromIntCondition).get()
  doAssert filterEq(v, original)

testCase roundTripFilterNestedDepth2:
  let inner = makeFilterOr(@[makeFilterCondition(10), makeFilterCondition(20)])
  let original = makeFilterAnd(@[makeFilterCondition(1), inner, makeFilterCondition(3)])
  let v = Filter[int].fromJson(original.toJson(), fromIntCondition).get()
  doAssert filterEq(v, original)

testCase roundTripAddedItem:
  let original = makeAddedItem()
  let v = AddedItem.fromJson(original.toJson()).get()
  doAssert v.id == original.id
  doAssert v.index == original.index

# =============================================================================
# B. toJson structural correctness
# =============================================================================

testCase filterOperatorToJsonAnd:
  let j = foAnd.toJson()
  doAssert j.kind == JString
  assertEq j.getStr(""), "AND"

testCase filterOperatorToJsonOr:
  let j = foOr.toJson()
  doAssert j.kind == JString
  assertEq j.getStr(""), "OR"

testCase filterOperatorToJsonNot:
  let j = foNot.toJson()
  doAssert j.kind == JString
  assertEq j.getStr(""), "NOT"

testCase comparatorToJsonFieldNames:
  let c = makeComparator()
  let j = c.toJson()
  doAssert j.kind == JObject
  doAssert j{"property"} != nil
  doAssert j{"property"}.kind == JString
  doAssert j{"isAscending"} != nil
  doAssert j{"isAscending"}.kind == JBool
  doAssert j{"collation"}.isNil

testCase comparatorToJsonCollationAbsent:
  let c = parseComparator(makePropertyName(), true, Opt.none(CollationAlgorithm))
  let j = c.toJson()
  doAssert j{"collation"}.isNil, "collation key must be absent when none"

testCase comparatorToJsonCollationPresent:
  let c = makeComparatorWithCollation(collation = CollationUnicodeCasemap)
  let j = c.toJson()
  doAssert j{"collation"} != nil
  assertEq j{"collation"}.getStr(""), "i;unicode-casemap"

testCase filterToJsonCondition:
  let f = makeFilterCondition(99)
  let j = f.toJson()
  doAssert j.kind == JObject
  doAssert j{"value"} != nil
  assertEq j{"value"}.getInt(0), 99

testCase filterToJsonOperator:
  let f = makeFilterAnd(@[makeFilterCondition(1)])
  let j = f.toJson()
  doAssert j.kind == JObject
  doAssert j{"operator"} != nil
  assertEq j{"operator"}.getStr(""), "AND"
  doAssert j{"conditions"} != nil
  doAssert j{"conditions"}.kind == JArray
  assertEq j{"conditions"}.len, 1

testCase addedItemToJsonFieldNames:
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

testCase filterOperatorDeserCustom:
  assertErrContains FilterOperator.fromJson(%"CUSTOM"), "unknown FilterOperator"

testCase filterOperatorDeserEmpty:
  assertErrContains FilterOperator.fromJson(%""), "unknown FilterOperator"

testCase filterOperatorDeserCaseSensitiveLower:
  assertErr FilterOperator.fromJson(%"and")

testCase filterOperatorDeserCaseSensitiveMixed:
  assertErr FilterOperator.fromJson(%"And")

testCase filterOperatorDeserNil:
  const nilNode: JsonNode = nil
  assertErr FilterOperator.fromJson(nilNode)

testCase filterOperatorDeserJNull:
  assertErr FilterOperator.fromJson(newJNull())

testCase filterOperatorDeserWrongKind:
  assertErr FilterOperator.fromJson(%42)

testCase filterOperatorDeserEmptyString:
  ## Empty string falls into the else branch of the case statement,
  ## raising ValidationError with "unknown FilterOperator".
  assertErrContains FilterOperator.fromJson(%""), "unknown FilterOperator"

# --- Comparator ---

testCase comparatorDeserAllFieldsPresent:
  let j =
    %*{"property": "subject", "isAscending": false, "collation": "i;unicode-casemap"}
  let v = Comparator.fromJson(j).get()
  assertEq string(v.property), "subject"
  doAssert not v.isAscending
  doAssert v.collation.isSome
  assertEq v.collation.get(), CollationUnicodeCasemap

testCase comparatorDeserMissingIsAscending:
  let j = %*{"property": "subject"}
  let v = Comparator.fromJson(j).get()
  doAssert v.isAscending, "isAscending must default to true"

testCase comparatorDeserMissingProperty:
  let j = %*{"isAscending": true}
  assertErrContains Comparator.fromJson(j), "property"

testCase comparatorDeserPropertyWrongKind:
  let j = %*{"property": 42, "isAscending": true}
  assertErr Comparator.fromJson(j)

testCase comparatorDeserIsAscendingWrongKind:
  let j = %*{"property": "subject", "isAscending": "yes"}
  assertErrContains Comparator.fromJson(j), "at /isAscending"

testCase comparatorDeserNotObject:
  assertErr Comparator.fromJson(%*[1, 2, 3])

testCase comparatorDeserNil:
  const nilNode: JsonNode = nil
  assertErr Comparator.fromJson(nilNode)

testCase comparatorDeserCollationWrongKindLenient:
  let j = %*{"property": "subject", "collation": 42}
  let v = Comparator.fromJson(j).get()
  doAssert v.collation.isNone, "wrong kind collation should be treated as none"

testCase comparatorRoundTripNoCollation:
  let j = %*{"property": "subject", "isAscending": true}
  let c1 = Comparator.fromJson(j).get()
  doAssert c1.collation.isNone
  let j2 = c1.toJson()
  doAssert j2{"collation"}.isNil, "round-trip must preserve key omission"

# --- Filter ---

testCase filterDeserCondition:
  # A JObject without "operator" key is a condition leaf
  let j = %*{"value": 42}
  let v = Filter[int].fromJson(j, fromIntCondition).get()
  doAssert v.kind == fkCondition

testCase filterDeserConditionNotObject:
  # Non-JObject input rejected by expectKind
  assertErr Filter[int].fromJson(%42, fromIntCondition)

testCase filterDeserOperatorWithConditions:
  let j = %*{"operator": "AND", "conditions": [{"value": 42}, {"value": 99}]}
  let v = Filter[int].fromJson(j, fromIntCondition).get()
  doAssert v.kind == fkOperator
  doAssert v.operator == foAnd
  assertEq v.conditions.len, 2

testCase filterDeserNestedDepth2:
  let j = %*{
    "operator": "OR",
    "conditions": [
      {"operator": "AND", "conditions": [{"value": 1}, {"value": 2}]},
      {"operator": "NOT", "conditions": [{"value": 3}]},
    ],
  }
  let v = Filter[int].fromJson(j, fromIntCondition).get()
  doAssert v.kind == fkOperator
  doAssert v.operator == foOr
  assertEq v.conditions.len, 2

testCase filterDeserEmptyConditions:
  let j = %*{"operator": "AND", "conditions": []}
  let v = Filter[int].fromJson(j, fromIntCondition).get()
  assertEq v.conditions.len, 0

testCase filterDeserMissingConditions:
  let j = %*{"operator": "AND"}
  assertErr Filter[int].fromJson(j, fromIntCondition)

testCase filterOperatorMissingConditionsArray:
  ## JSON with "operator" present but no "conditions" key must return err.
  ## Exercises the ``fieldJArray`` guard on the conditions array.
  let j = %*{"operator": "AND"}
  assertErr Filter[int].fromJson(j, fromIntCondition)

testCase filterDeserCallbackError:
  # Callback receives a string (not JObject), should propagate error
  let j = %*{"operator": "AND", "conditions": ["not-an-object"]}
  assertErr Filter[int].fromJson(j, fromIntCondition)

testCase filterDeserNotObject:
  assertErr Filter[int].fromJson(%*[1, 2, 3], fromIntCondition)

testCase filterDeserNil:
  const nilNode: JsonNode = nil
  assertErr Filter[int].fromJson(nilNode, fromIntCondition)

# --- AddedItem ---

testCase addedItemDeserValid:
  let v = AddedItem.fromJson(%*{"id": "x", "index": 5}).get()
  assertEq string(v.id), "x"

testCase addedItemDeserIndexZero:
  let j = %*{"id": "x", "index": 0}
  discard AddedItem.fromJson(j)

testCase addedItemDeserIndexMax:
  let j = %*{"id": "x", "index": 9007199254740991}
  discard AddedItem.fromJson(j)

testCase addedItemDeserIndexNegative:
  let j = %*{"id": "x", "index": -1}
  assertErr AddedItem.fromJson(j)

testCase addedItemDeserInvalidId:
  let j = %*{"id": "", "index": 5}
  assertErr AddedItem.fromJson(j)

testCase addedItemDeserMissingId:
  let j = %*{"index": 5}
  assertErr AddedItem.fromJson(j)

testCase addedItemDeserMissingIndex:
  let j = %*{"id": "x"}
  assertErr AddedItem.fromJson(j)

testCase addedItemDeserNotObject:
  assertErr AddedItem.fromJson(%*[1, 2, 3])

testCase addedItemDeserNil:
  const nilNode: JsonNode = nil
  assertErr AddedItem.fromJson(nilNode)

# =============================================================================
# C2. Additional edge-case and boundary tests
# =============================================================================

testCase filterDeserNestedDepth3:
  ## AND(OR(NOT(condition))) — verifies recursive parse at depth 3.
  let j = %*{
    "operator": "AND",
    "conditions": [
      {
        "operator": "OR",
        "conditions": [{"operator": "NOT", "conditions": [{"value": 42}]}],
      }
    ],
  }
  let f = Filter[int].fromJson(j, fromIntCondition).get()
  doAssert f.kind == fkOperator
  doAssert f.operator == foAnd
  assertLen f.conditions, 1
  doAssert f.conditions[0].kind == fkOperator
  doAssert f.conditions[0].operator == foOr
  assertLen f.conditions[0].conditions, 1
  doAssert f.conditions[0].conditions[0].kind == fkOperator
  doAssert f.conditions[0].conditions[0].operator == foNot
  assertLen f.conditions[0].conditions[0].conditions, 1
  doAssert f.conditions[0].conditions[0].conditions[0].kind == fkCondition
  doAssert f.conditions[0].conditions[0].conditions[0].condition == 42

testCase comparatorAllFieldsRoundTrip:
  ## Comparator with property + isAscending=false + collation round-trips.
  let c = parseComparator(
    makePropertyName("receivedAt"), false, Opt.some(CollationUnicodeCasemap)
  )
  let v = Comparator.fromJson(c.toJson()).get()
  assertEq string(v.property), "receivedAt"
  doAssert v.isAscending == false
  assertSomeEq v.collation, CollationUnicodeCasemap

testCase addedItemDeserIndexZeroBoundary:
  ## Boundary: index = 0 is valid.
  let j = %*{"id": "item1", "index": 0}
  let v = AddedItem.fromJson(j).get()
  assertEq int64(v.index), 0'i64

testCase addedItemDeserIndexMaxBoundary:
  ## Boundary: index = 2^53-1 is valid.
  let j = %*{"id": "item1", "index": 9007199254740991}
  let v = AddedItem.fromJson(j).get()
  assertEq int64(v.index), 9007199254740991'i64

testCase filterOperatorDeserLowercaseRejected:
  ## "and" (lowercase) must return error — operators are case-sensitive.
  let j = %"and"
  assertErr FilterOperator.fromJson(j)

testCase filterDeserDepth3RoundTrip:
  ## Round-trip test for depth-3 Filter tree.
  let leaf = filterCondition(99)
  let level2 = filterOperator(foNot, @[leaf])
  let level1 = filterOperator(foOr, @[level2])
  let root = filterOperator(foAnd, @[level1])
  let j = root.toJson()
  let v = Filter[int].fromJson(j, fromIntCondition).get()
  doAssert filterEq(v, root), "depth-3 filter round-trip identity violated"

# =============================================================================
# D. Property-based round-trip tests
# =============================================================================

checkProperty "FilterOperator round-trip":
  let ops = [foAnd, foOr, foNot]
  let op = ops[trial mod 3]
  assertOkEq FilterOperator.fromJson(op.toJson()), op

checkProperty "Comparator round-trip":
  let c = rng.genComparator()
  let v = Comparator.fromJson(c.toJson()).get()
  doAssert v.property == c.property
  doAssert v.isAscending == c.isAscending
  doAssert v.collation == c.collation

checkProperty "Filter[int] round-trip":
  let f = rng.genFilter(3)
  let v = Filter[int].fromJson(f.toJson(), fromIntCondition).get()
  doAssert filterEq(v, f), "Filter values differ"

checkProperty "AddedItem round-trip":
  let item = rng.genAddedItem()
  let v = AddedItem.fromJson(item.toJson()).get()
  doAssert v.id == item.id
  doAssert v.index == item.index

# =============================================================================
# Phase 3D: Comparator edge cases
# =============================================================================

testCase comparatorCollationAbsentIsNone:
  ## Comparator JSON without collation field: collation must be none.
  let j = %*{"property": "subject", "isAscending": true}
  let v = Comparator.fromJson(j).get()
  assertNone v.collation

testCase comparatorCollationNullIsNone:
  ## Comparator JSON with "collation": null: collation must be none.
  var j = %*{"property": "subject", "isAscending": true}
  j["collation"] = newJNull()
  let v = Comparator.fromJson(j).get()
  assertNone v.collation
