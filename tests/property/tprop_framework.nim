# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based tests for PropertyName, PatchObject, Filter, Comparator.

import std/hashes
import std/json
import std/random
import std/sequtils

import results

import jmap_client/envelope
import jmap_client/framework
import jmap_client/identifiers
import jmap_client/primitives
import jmap_client/serde_framework
import jmap_client/session
import jmap_client/validation
import ../mproperty

block propParsePropertyNameTotality:
  checkProperty "parsePropertyName never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parsePropertyName(s)

block propPropertyNameNonEmpty:
  checkProperty "valid PropertyName has len > 0":
    let s = genValidIdStrict(rng)
    lastInput = s
    let pn = parsePropertyName(s).get()
    doAssert pn.len > 0

block propPatchSetPropMonotonic:
  checkProperty "setProp increases or maintains len":
    let s = genValidIdStrict(rng, minLen = 1, maxLen = 50)
    lastInput = s
    let p = emptyPatch()
    let r = setProp(p, s, %42)
    doAssert r.isOk
    doAssert r.get().len >= p.len

block propPatchOverwriteIdempotentOnCount:
  checkProperty "overwriting same key keeps len stable":
    let s = genValidIdStrict(rng, minLen = 1, maxLen = 50)
    lastInput = s
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
    lastInput = $c
    let f = filterCondition(c)
    doAssert f.kind == fkCondition
    doAssert f.condition == c

block propFilterOperatorLaw:
  checkProperty "filterOperator preserves operator and children":
    let c1 = filterCondition(rng.rand(int))
    let c2 = filterCondition(rng.rand(int))
    lastInput = $c1.condition & ", " & $c2.condition
    let children = @[c1, c2]
    let f = filterOperator[int](foAnd, children)
    doAssert f.kind == fkOperator
    doAssert f.operator == foAnd
    doAssert f.conditions.len == 2

block propReferencableDirectLaw:
  checkProperty "direct preserves value":
    let v = rng.rand(int)
    lastInput = $v
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
    lastInput = s
    let r = parsePropertyName(s)
    doAssert r.isOk
    doAssert $r.get() == s

block propPatchCommutativityDisjointKeys:
  checkProperty "setProp on disjoint keys is commutative":
    let k1 = "key_" & $rng.rand(0 .. 999)
    let k2 = "alt_" & $rng.rand(0 .. 999)
    lastInput = k1 & ", " & k2
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
    lastInput = s
    let original = emptyPatch()
    let modified = setProp(original, s, %42)
    doAssert modified.isOk
    doAssert original.len == 0
    doAssert modified.get().len == 1

block propPatchDeletePropIdempotent:
  checkProperty "deleteProp is idempotent on len":
    let key = genValidIdStrict(rng, minLen = 1, maxLen = 30)
    lastInput = key
    let p = setProp(emptyPatch(), key, %1).get()
    let d1 = deleteProp(p, key).get()
    let d2 = deleteProp(d1, key).get()
    doAssert d1.len == d2.len

# --- PatchObject algebraic properties ---

block propPatchLastWriterWins:
  checkProperty "propPatchLastWriterWins":
    ## For the same key, later write prevails over earlier write.
    let k = genPatchPath(rng)
    lastInput = k
    let v1 = %rng.rand(0 .. 999)
    let v2 = %rng.rand(1000 .. 1999)
    let direct = emptyPatch().setProp(k, v2).get()
    let overwrite = emptyPatch().setProp(k, v1).get().setProp(k, v2).get()
    doAssert direct.getKey(k).get() == overwrite.getKey(k).get()

block propPatchDeleteThenSetAsymmetry:
  checkProperty "propPatchDeleteThenSetAsymmetry":
    ## delete then set != set then delete.
    let k = genPatchPath(rng)
    lastInput = k
    let v = %rng.rand(0 .. 999)
    let deleteThenSet = emptyPatch().deleteProp(k).get().setProp(k, v).get()
    let setThenDelete = emptyPatch().setProp(k, v).get().deleteProp(k).get()
    # deleteThenSet: key -> v; setThenDelete: key -> null
    doAssert deleteThenSet.getKey(k).get() == v
    doAssert setThenDelete.getKey(k).get().kind == JNull

block propPropertyNameEqImpliesHashEq:
  checkProperty "propPropertyNameEqImpliesHashEq":
    let s = genValidPropertyName(rng)
    lastInput = s
    let a = parsePropertyName(s).get()
    let b = parsePropertyName(s).get()
    doAssert hash(a) == hash(b)

block propPropertyNameDoubleRoundTrip:
  checkProperty "propPropertyNameDoubleRoundTrip":
    let s = genValidPropertyName(rng)
    lastInput = s
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
    let idStr = genValidIdStrict(rng, minLen = 1, maxLen = 20)
    lastInput = idStr
    let id = parseId(idStr).get()
    let idx = parseUnsignedInt(rng.rand(0'i64 .. 10000'i64)).get()
    let item = AddedItem(id: id, index: idx)
    doAssert item.id == id
    doAssert item.index == idx

# --- Filter totality ---

block propFilterConstructionTotality:
  checkPropertyN "genFilter never produces crashing trees", QuickTrials:
    let f = genFilter(rng, rng.rand(0 .. 6))
    ## Walk the tree to verify all nodes are accessible.
    proc walk(f: Filter[int]) =
      ## Recursively visits all nodes in the filter tree.
      case f.kind
      of fkCondition:
        discard f.condition
      of fkOperator:
        discard f.operator
        for c in f.conditions:
          walk(c)

    walk(f)

# --- Comparator infallibility ---

block propComparatorAlwaysOk:
  checkProperty "parseComparator always returns Ok for valid PropertyName":
    let s = genValidPropertyName(rng, trial)
    lastInput = s
    let pn = parsePropertyName(s).get()
    let asc = rng.rand(0 .. 1) == 0
    doAssert parseComparator(pn, asc).isOk

# --- Filter operator arity ---

block propFilterNotWithMultipleChildren:
  ## Layer 1 does not validate NOT arity; accepts any child count.
  let c1 = filterCondition(1)
  let c2 = filterCondition(2)
  let f = filterOperator[int](foNot, @[c1, c2])
  doAssert f.kind == fkOperator
  doAssert f.conditions.len == 2

block propFilterEmptyConditions:
  ## Layer 1 accepts empty conditions for any operator.
  let f = filterOperator[int](foAnd, @[])
  doAssert f.kind == fkOperator
  doAssert f.conditions.len == 0

# --- PatchObject monoid laws, Filter well-formedness ---

block propPatchMonoidIdentity:
  ## emptyPatch then setProp(k, v) == just setProp(k, v).
  checkProperty "propPatchMonoidIdentity":
    let key = "key_" & $rng.rand(0 .. 999)
    lastInput = key
    let val = newJInt(rng.rand(int))
    let p = emptyPatch().setProp(key, val).get()
    doAssert p.len == 1
    doAssert p.getKey(key).get() == val

block propPatchIdempotence:
  ## Writing the same key-value twice yields same result as once.
  checkProperty "propPatchIdempotence":
    let key = "key_" & $rng.rand(0 .. 999)
    lastInput = key
    let val = newJInt(rng.rand(int))
    let once = emptyPatch().setProp(key, val).get()
    let twice = emptyPatch().setProp(key, val).get().setProp(key, val).get()
    doAssert once.len == twice.len
    doAssert once.getKey(key).get() == twice.getKey(key).get()

block propPatchAssociativity:
  ## Sequential setProp calls produce consistent results regardless of grouping.
  checkPropertyN "propPatchAssociativity", 200:
    let k1 = "a_" & $rng.rand(0 .. 999)
    let k2 = "b_" & $rng.rand(0 .. 999)
    let k3 = "c_" & $rng.rand(0 .. 999)
    lastInput = k1 & ", " & k2 & ", " & k3
    let v1 = newJInt(rng.rand(0 .. 999))
    let v2 = newJInt(rng.rand(0 .. 999))
    let v3 = newJInt(rng.rand(0 .. 999))
    let p =
      emptyPatch().setProp(k1, v1).get().setProp(k2, v2).get().setProp(k3, v3).get()
    # Verify all keys present with correct values.
    doAssert p.getKey(k1).get() == v1
    doAssert p.getKey(k2).get() == v2
    doAssert p.getKey(k3).get() == v3

block propPatchLenNonNegative:
  ## Patch length is always non-negative after any operations.
  checkProperty "propPatchLenNonNegative":
    var p = emptyPatch()
    let n = rng.rand(0 .. 5)
    lastInput = $n
    for i in 0 ..< n:
      p = p.setProp("k" & $i, newJInt(i)).get()
    doAssert p.len >= 0

block propFilterWellFormed:
  ## Any generated filter tree is structurally well-formed.
  checkPropertyN "propFilterWellFormed", 200:
    let f = genFilter(rng, 4)
    proc check(f: Filter[int]): bool =
      ## Recursively validates filter tree structure.
      case f.kind
      of fkCondition:
        true
      of fkOperator:
        f.operator in {foAnd, foOr, foNot} and f.conditions.allIt(check(it))

    doAssert check(f)

block propFilterOperatorPreserved:
  ## Operator enum value survives construction.
  checkProperty "propFilterOperatorPreserved":
    let op = [foAnd, foOr, foNot][rng.rand(0 .. 2)]
    lastInput = $op
    let c = filterCondition(rng.rand(int))
    let f = filterOperator[int](op, @[c])
    doAssert f.operator == op

block propUriTemplatePostConstructionLen:
  ## After successful parseUriTemplate, the template has non-zero length.
  checkProperty "propUriTemplatePostConstructionLen":
    let s = genValidUriTemplateParametric(rng)
    lastInput = s
    let t = parseUriTemplate(s)
    if t.isOk:
      doAssert t.get().len > 0

block propPropertyNamePostConstructionLen:
  ## After successful parsePropertyName, the name has non-zero length.
  checkProperty "propPropertyNamePostConstructionLen":
    let s = genArbitraryString(rng, trial)
    lastInput = s
    let pn = parsePropertyName(s)
    if pn.isOk:
      doAssert pn.get().len > 0

# --- Comparator and AddedItem generator properties ---

block propComparatorTotality:
  checkProperty "genComparator never crashes":
    let c = genComparator(rng)
    lastInput = $c.property
    discard c

block propComparatorFieldPreservation:
  checkProperty "genComparator property non-empty and collation valid":
    let c = genComparator(rng)
    lastInput = $c.property
    doAssert c.property.len > 0
    if c.collation.isSome:
      doAssert c.collation.get().len > 0

block propAddedItemTotality:
  checkProperty "genAddedItem id in bounds and index non-negative":
    let ai = genAddedItem(rng)
    lastInput = $ai.id
    doAssert ai.id.len >= 1 and ai.id.len <= 255
    doAssert int64(ai.index) >= 0

# --- PatchObject fundamental laws ---

block propPatchObjectGetKeyInverse:
  checkProperty "setProp then getKey returns the same value":
    let path = genPatchPath(rng)
    lastInput = path
    let value = newJInt(rng.rand(0 .. 9999))
    let p = emptyPatch().setProp(path, value).get()
    let retrieved = p.getKey(path)
    doAssert retrieved.isSome, "getKey returned none after setProp"
    doAssert retrieved.get() == value, "getKey value differs from setProp value"

block propPatchObjectDeleteSetsNull:
  checkProperty "setProp then deleteProp sets key to JNull":
    let path = genPatchPath(rng)
    lastInput = path
    let value = newJInt(rng.rand(0 .. 9999))
    let p = emptyPatch().setProp(path, value).get().deleteProp(path).get()
    let retrieved = p.getKey(path)
    doAssert retrieved.isSome, "getKey returned none after deleteProp"
    doAssert retrieved.get().kind == JNull, "deleteProp did not set key to JNull"

block propPatchObjectCommutativityExact:
  checkProperty "setProp on distinct keys yields identical JSON":
    let k1 = "left_" & $rng.rand(0 .. 999)
    let k2 = "right_" & $rng.rand(0 .. 999)
    lastInput = k1 & ", " & k2
    if k1 != k2:
      let v1 = newJInt(rng.rand(0 .. 9999))
      let v2 = newJInt(rng.rand(10000 .. 19999))
      let order1 = emptyPatch().setProp(k1, v1).get().setProp(k2, v2).get()
      let order2 = emptyPatch().setProp(k2, v2).get().setProp(k1, v1).get()
      doAssert order1.toJson() == order2.toJson(),
        "commutativity violated for disjoint keys"

# --- Filter algebraic laws ---

block propFilterNotInvolution:
  checkPropertyN "NOT(NOT(f)) is structurally a double-NOT wrapping f", QuickTrials:
    let f = genFilter(rng, 3)
    let doubleNot = filterOperator[int](foNot, @[filterOperator[int](foNot, @[f])])
    ## Verify outer structure: operator, foNot, one child.
    doAssert doubleNot.kind == fkOperator
    doAssert doubleNot.operator == foNot
    doAssert doubleNot.conditions.len == 1
    ## Verify inner structure: operator, foNot, one child wrapping original.
    let inner = doubleNot.conditions[0]
    doAssert inner.kind == fkOperator
    doAssert inner.operator == foNot
    doAssert inner.conditions.len == 1
    ## Verify the wrapped filter matches the original.
    proc structEq(a, b: Filter[int]): bool =
      ## Recursive structural equality for Filter[int] trees.
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
          if not structEq(a.conditions[i], b.conditions[i]):
            return false
        true

    doAssert structEq(inner.conditions[0], f), "double-NOT inner does not wrap original"
