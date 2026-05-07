# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for PropertyName, Filter, Comparator, AddedItem.

import std/json
import std/random
import std/sequtils

import jmap_client/internal/types/envelope
import jmap_client/internal/types/framework
import jmap_client/internal/types/methods_enum
import jmap_client/internal/types/validation
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/primitives
import jmap_client/internal/serialisation/serde_framework
import jmap_client/internal/types/session
import ../mproperty
import ../massertions

block propParsePropertyNameTotality:
  checkProperty "parsePropertyName never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parsePropertyName(s)

block propPropertyNameNonEmpty:
  checkProperty "valid PropertyName has len > 0":
    let s = genValidIdStrict(rng)
    lastInput = s
    let r = parsePropertyName(s)
    if r.isOk:
      doAssert r.get().len > 0

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
  let rref = initResultReference(resultOf = mcid, name = mnEmailGet, path = rpIds)
  let r = referenceTo[int](rref)
  doAssert r.kind == rkReference
  doAssert r.reference.resultOf == mcid

block propComparatorDefaults:
  let pn = parsePropertyName("name").get()
  let c = parseComparator(pn)
  doAssert c.isAscending == true
  doAssert c.collation.isNone

# --- Additional properties ---

block propPropertyNameRoundTrip:
  checkProperty "$(parsePropertyName(s).get()) == s for valid s":
    let s = genValidPropertyName(rng)
    lastInput = s
    let r = parsePropertyName(s).get()
    doAssert $r == s

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
    let idxVal = rng.rand(0'i64 .. 10000'i64)
    let idx = parseUnsignedInt(idxVal).get()
    let item = initAddedItem(id, idx)
    doAssert string(item.id) == idStr
    doAssert int64(item.index) == idxVal

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
    discard parseComparator(pn, asc)

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

# --- Filter well-formedness ---

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
  ## ``UriTemplate`` is a parsed case object with no ``len`` (its parts
  ## count differs from its source length); round-trip via ``$`` for the
  ## source-string size assertion.
  checkProperty "propUriTemplatePostConstructionLen":
    let s = genValidUriTemplateParametric(rng)
    lastInput = s
    let t = parseUriTemplate(s).get()
    doAssert ($t).len > 0
block propPropertyNamePostConstructionLen:
  ## After successful parsePropertyName, the name has non-zero length.
  checkProperty "propPropertyNamePostConstructionLen":
    let s = genArbitraryString(rng, trial)
    lastInput = s
    let r = parsePropertyName(s)
    if r.isOk:
      doAssert r.get().len > 0
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
      doAssert ($c.collation.get()).len > 0

block propAddedItemTotality:
  checkProperty "genAddedItem id in bounds and index non-negative":
    let ai = genAddedItem(rng)
    lastInput = $ai.id
    doAssert ai.id.len >= 1 and ai.id.len <= 255
    doAssert int64(ai.index) >= 0

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
