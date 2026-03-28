# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based tests for PropertyName, PatchObject, Filter, Comparator.

import std/hashes
import std/json
import std/random

import pkg/results

import jmap_client/envelope
import jmap_client/framework
import jmap_client/identifiers
import jmap_client/primitives
import jmap_client/validation
import ./mproperty

block propParsePropertyNameTotality:
  checkProperty "parsePropertyName never crashes":
    discard parsePropertyName(genArbitraryString(rng))

block propPropertyNameNonEmpty:
  checkProperty "valid PropertyName has len > 0":
    let s = genValidIdStrict(rng)
    let pn = parsePropertyName(s).get()
    doAssert pn.len > 0

block propPatchSetPropMonotonic:
  checkProperty "setProp increases or maintains len":
    let s = genValidIdStrict(rng, minLen = 1, maxLen = 50)
    let p = emptyPatch()
    let r = setProp(p, s, %42)
    doAssert r.isOk
    doAssert r.get().len >= p.len

block propPatchOverwriteIdempotentOnCount:
  checkProperty "overwriting same key keeps len stable":
    let s = genValidIdStrict(rng, minLen = 1, maxLen = 50)
    let p1 = setProp(emptyPatch(), s, %1).get()
    let p2 = setProp(p1, s, %2).get()
    doAssert p1.len == p2.len

block propPatchEmptyPathAlwaysRejected:
  doAssert setProp(emptyPatch(), "", newJNull()).isErr
  doAssert deleteProp(emptyPatch(), "").isErr
  let p = setProp(emptyPatch(), "x", %1).get()
  doAssert setProp(p, "", %2).isErr
  doAssert deleteProp(p, "").isErr

block propFilterConditionLaw:
  checkProperty "filterCondition preserves condition":
    let c = rng.rand(int)
    let f = filterCondition(c)
    doAssert f.kind == fkCondition
    doAssert f.condition == c

block propFilterOperatorLaw:
  checkProperty "filterOperator preserves operator and children":
    let c1 = filterCondition(rng.rand(int))
    let c2 = filterCondition(rng.rand(int))
    let children = @[c1, c2]
    let f = filterOperator[int](foAnd, children)
    doAssert f.kind == fkOperator
    doAssert f.operator == foAnd
    doAssert f.conditions.len == 2

block propReferencableDirectLaw:
  checkProperty "direct preserves value":
    let v = rng.rand(int)
    let r = direct(v)
    doAssert r.kind == rkDirect
    doAssert r.value == v

block propReferencableRefLaw:
  let mcid = parseMethodCallId("c0").get()
  let rref = ResultReference(resultOf: mcid, name: "Foo/get", path: "/ids")
  let r = referenceTo[int](rref)
  doAssert r.kind == rkReference
  doAssert r.reference.resultOf == mcid

block propComparatorDefaults:
  let pn = parsePropertyName("name").get()
  let c = parseComparator(pn).get()
  doAssert c.isAscending == true
  doAssert c.collation.isNone

# --- Additional properties ---

block propPropertyNameRoundTrip:
  checkProperty "$(parsePropertyName(s).get()) == s for valid s":
    let s = genValidPropertyName(rng)
    let r = parsePropertyName(s)
    doAssert r.isOk
    doAssert $r.get() == s

block propPatchCommutativityDisjointKeys:
  checkProperty "setProp on disjoint keys is commutative":
    let k1 = "key_" & $rng.rand(0 .. 999)
    let k2 = "alt_" & $rng.rand(0 .. 999)
    if k1 != k2:
      let v1 = %rng.rand(int)
      let v2 = %rng.rand(int)
      let path1 = setProp(setProp(emptyPatch(), k1, v1).get(), k2, v2).get()
      let path2 = setProp(setProp(emptyPatch(), k2, v2).get(), k1, v1).get()
      doAssert path1.len == path2.len
      doAssert path1.getKey(k1).get() == path2.getKey(k1).get()
      doAssert path1.getKey(k2).get() == path2.getKey(k2).get()

block propPatchImmutability:
  checkProperty "setProp returns new object, original unchanged":
    let s = genValidIdStrict(rng, minLen = 1, maxLen = 30)
    let original = emptyPatch()
    let modified = setProp(original, s, %42)
    doAssert modified.isOk
    doAssert original.len == 0
    doAssert modified.get().len == 1

block propPatchDeletePropIdempotent:
  checkProperty "deleteProp is idempotent on len":
    let key = genValidIdStrict(rng, minLen = 1, maxLen = 30)
    let p = setProp(emptyPatch(), key, %1).get()
    let d1 = deleteProp(p, key).get()
    let d2 = deleteProp(d1, key).get()
    doAssert d1.len == d2.len

# --- PatchObject algebraic properties ---

block propPatchLastWriterWins:
  checkProperty "propPatchLastWriterWins":
    ## For the same key, later write prevails over earlier write.
    let k = genPatchPath(rng)
    let v1 = %rng.rand(0 .. 999)
    let v2 = %rng.rand(1000 .. 1999)
    let direct = emptyPatch().setProp(k, v2).get()
    let overwrite = emptyPatch().setProp(k, v1).get().setProp(k, v2).get()
    doAssert direct.getKey(k).get() == overwrite.getKey(k).get()

block propPatchDeleteThenSetAsymmetry:
  checkProperty "propPatchDeleteThenSetAsymmetry":
    ## delete then set != set then delete.
    let k = genPatchPath(rng)
    let v = %rng.rand(0 .. 999)
    let deleteThenSet = emptyPatch().deleteProp(k).get().setProp(k, v).get()
    let setThenDelete = emptyPatch().setProp(k, v).get().deleteProp(k).get()
    # deleteThenSet: key -> v; setThenDelete: key -> null
    doAssert deleteThenSet.getKey(k).get() == v
    doAssert setThenDelete.getKey(k).get().kind == JNull

block propPropertyNameReflexivity:
  checkProperty "propPropertyNameReflexivity":
    let s = genValidPropertyName(rng)
    let a = parsePropertyName(s).get()
    doAssert a == a

block propPropertyNameEqImpliesHashEq:
  checkProperty "propPropertyNameEqImpliesHashEq":
    let s = genValidPropertyName(rng)
    let a = parsePropertyName(s).get()
    let b = parsePropertyName(s).get()
    doAssert hash(a) == hash(b)

block propPropertyNameDoubleRoundTrip:
  checkProperty "propPropertyNameDoubleRoundTrip":
    let s = genValidPropertyName(rng)
    let first = parsePropertyName(s).get()
    let second = parsePropertyName($first).get()
    doAssert first == second

# --- Filter tree properties ---

block propFilterLeafCountNonNegative:
  checkPropertyN "propFilterLeafCountNonNegative", QuickTrials:
    let f = genFilter(rng, 4)
    proc countLeaves(f: Filter[int]): int =
      ## Counts leaf nodes in a filter tree.
      case f.kind
      of fkCondition:
        1
      of fkOperator:
        var total = 0
        for c in f.conditions:
          total += countLeaves(c)
        total

    doAssert countLeaves(f) >= 0

block propFilterStructuralRecursion:
  checkPropertyN "propFilterStructuralRecursion", QuickTrials:
    ## Every node is either a leaf or an operator.
    let f = genFilter(rng, 3)
    proc verify(f: Filter[int]) =
      ## Recursively verifies all nodes are valid filter kinds.
      case f.kind
      of fkCondition:
        discard
      of fkOperator:
        doAssert f.operator in {foAnd, foOr, foNot}
        for c in f.conditions:
          verify(c)

    verify(f)

# --- AddedItem property tests ---

block propAddedItemFieldPreservation:
  checkProperty "AddedItem preserves id and index through construction":
    let ai = genAddedItem(rng)
    let idStr = genValidIdStrict(rng, minLen = 1, maxLen = 20)
    let id = parseId(idStr).get()
    let idx = parseUnsignedInt(rng.rand(0'i64 .. 10000'i64)).get()
    let item = AddedItem(id: id, index: idx)
    doAssert item.id == id
    doAssert item.index == idx
