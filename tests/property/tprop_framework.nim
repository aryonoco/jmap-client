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
import ../mtestblock

testCase propParsePropertyNameTotality:
  checkProperty "parsePropertyName never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parsePropertyName(s)

testCase propPropertyNameNonEmpty:
  checkProperty "valid PropertyName has len > 0":
    let s = genValidIdStrict(rng)
    lastInput = s
    let r = parsePropertyName(s)
    if r.isOk:
      doAssert r.get().len > 0

testCase propFilterConditionLaw:
  checkProperty "filterCondition preserves condition":
    let c = rng.rand(int)
    lastInput = $c
    let f = filterCondition(c)
    doAssert f.kind == fkCondition
    doAssert f.condition == c

testCase propFilterOperatorLaw:
  checkProperty "filterOperator preserves operator and children":
    let c1 = filterCondition(rng.rand(int))
    let c2 = filterCondition(rng.rand(int))
    lastInput = $c1.condition & ", " & $c2.condition
    let children = @[c1, c2]
    let f = filterAnd(children).get()
    doAssert f.kind == fkOperator
    doAssert f.operator == foAnd
    doAssert f.operands.len == 2

testCase propReferencableDirectLaw:
  checkProperty "direct preserves value":
    let v = rng.rand(int)
    lastInput = $v
    let r = direct(v)
    doAssert r.kind == rkDirect
    doAssert r.asDirect.get() == v

testCase propReferencableRefLaw:
  let mcid = parseMethodCallId("c0").get()
  let rref = initResultReference(resultOf = mcid, name = mnEmailGet, path = rpIds)
  let r = referenceTo[int](rref)
  doAssert r.kind == rkReference
  doAssert r.asReference.get().resultOf == mcid

testCase propComparatorDefaults:
  let pn = parsePropertyName("name").get()
  let c = parseComparator(pn)
  doAssert c.direction == sdServerDefault
  doAssert c.collation.isNone

# --- Additional properties ---

testCase propPropertyNameRoundTrip:
  checkProperty "$(parsePropertyName(s).get()) == s for valid s":
    let s = genValidPropertyName(rng)
    lastInput = s
    let r = parsePropertyName(s).get()
    doAssert $r == s

testCase propPropertyNameEqImpliesHashEq:
  checkProperty "propPropertyNameEqImpliesHashEq":
    let s = genValidPropertyName(rng)
    lastInput = s
    let a = parsePropertyName(s).get()
    let b = parsePropertyName(s).get()
    doAssert hash(a) == hash(b)

testCase propPropertyNameDoubleRoundTrip:
  checkProperty "propPropertyNameDoubleRoundTrip":
    let s = genValidPropertyName(rng)
    lastInput = s
    let first = parsePropertyName(s).get()
    let second = parsePropertyName($first).get()
    doAssert first == second

# --- Filter tree properties ---

testCase propFilterStructuralRecursion:
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
        for c in f.operands:
          verify(c)

    verify(f)

# --- AddedItem property tests ---

testCase propAddedItemFieldPreservation:
  checkProperty "AddedItem preserves id and index through construction":
    let idStr = genValidIdStrict(rng, minLen = 1, maxLen = 20)
    lastInput = idStr
    let id = parseId(idStr).get()
    let idxVal = rng.rand(0'i64 .. 10000'i64)
    let idx = parseUnsignedInt(idxVal).get()
    let item = initAddedItem(id, idx)
    doAssert $item.id == idStr
    doAssert item.index.toInt64 == idxVal

# --- Filter totality ---

testCase propFilterConstructionTotality:
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
        for c in f.operands:
          walk(c)

    walk(f)

# --- Comparator infallibility ---

testCase propComparatorAlwaysOk:
  checkProperty "parseComparator always returns Ok for valid PropertyName":
    let s = genValidPropertyName(rng, trial)
    lastInput = s
    let pn = parsePropertyName(s).get()
    let direction = rng.oneOf([sdServerDefault, sdAscending, sdDescending])
    discard parseComparator(pn, direction)

# --- Filter operator arity (B3, RFC 8620 §5.5) ---

testCase propFilterNotIsSingleChild:
  ## NOT has exactly one child — ``filterNot`` is single-argument, so a
  ## multi-child NOT cannot be constructed.
  let f = filterNot(filterCondition(1))
  doAssert f.kind == fkOperator
  doAssert f.operands.len == 1

testCase propFilterEmptyConditionsRejected:
  ## AND/OR reject an empty operand list (one or more required).
  assertErr filterAnd(newSeq[Filter[int]]())
  assertErr filterOr(newSeq[Filter[int]]())

# --- Filter well-formedness ---

testCase propFilterWellFormed:
  ## Any generated filter tree is structurally well-formed.
  checkPropertyN "propFilterWellFormed", 200:
    let f = genFilter(rng, 4)
    proc check(f: Filter[int]): bool =
      ## Recursively validates filter tree structure.
      case f.kind
      of fkCondition:
        true
      of fkOperator:
        f.operator in {foAnd, foOr, foNot} and f.operands.allIt(check(it))

    doAssert check(f)

testCase propFilterOperatorPreserved:
  ## Operator enum value survives construction. Each operator routes through
  ## its dedicated single-arity constructor.
  checkProperty "propFilterOperatorPreserved":
    let op = [foAnd, foOr, foNot][rng.rand(0 .. 2)]
    lastInput = $op
    let c = filterCondition(rng.rand(int))
    let f =
      case op
      of foNot:
        filterNot(c)
      of foAnd:
        filterAnd(@[c]).get()
      of foOr:
        filterOr(@[c]).get()
    doAssert f.operator == op

testCase propUriTemplatePostConstructionLen:
  ## After successful parseUriTemplate, the template has non-zero length.
  ## ``UriTemplate`` is a parsed case object with no ``len`` (its parts
  ## count differs from its source length); round-trip via ``$`` for the
  ## source-string size assertion.
  checkProperty "propUriTemplatePostConstructionLen":
    let s = genValidUriTemplateParametric(rng)
    lastInput = s
    let t = parseUriTemplate(s).get()
    doAssert ($t).len > 0
testCase propPropertyNamePostConstructionLen:
  ## After successful parsePropertyName, the name has non-zero length.
  checkProperty "propPropertyNamePostConstructionLen":
    let s = genArbitraryString(rng, trial)
    lastInput = s
    let r = parsePropertyName(s)
    if r.isOk:
      doAssert r.get().len > 0
# --- Comparator and AddedItem generator properties ---

testCase propComparatorTotality:
  checkProperty "genComparator never crashes":
    let c = genComparator(rng)
    lastInput = $c.property
    discard c

testCase propComparatorFieldPreservation:
  checkProperty "genComparator property non-empty and collation valid":
    let c = genComparator(rng)
    lastInput = $c.property
    doAssert c.property.len > 0
    if c.collation.isSome:
      doAssert ($c.collation.get()).len > 0

testCase propAddedItemTotality:
  checkProperty "genAddedItem id in bounds and index non-negative":
    let ai = genAddedItem(rng)
    lastInput = $ai.id
    doAssert ai.id.len >= 1 and ai.id.len <= 255
    doAssert ai.index.toInt64 >= 0

# --- Filter algebraic laws ---

testCase propFilterNotInvolution:
  checkPropertyN "NOT(NOT(f)) is structurally a double-NOT wrapping f", QuickTrials:
    let f = genFilter(rng, 3)
    let doubleNot = filterNot(filterNot(f))
    ## Verify outer structure: operator, foNot, one child.
    doAssert doubleNot.kind == fkOperator
    doAssert doubleNot.operator == foNot
    doAssert doubleNot.operands.len == 1
    ## Verify inner structure: operator, foNot, one child wrapping original.
    let inner = doubleNot.operands[0]
    doAssert inner.kind == fkOperator
    doAssert inner.operator == foNot
    doAssert inner.operands.len == 1
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
        if a.operands.len != b.operands.len:
          return false
        for i in 0 ..< a.operands.len:
          if not structEq(a.operands[i], b.operands[i]):
            return false
        true

    doAssert structEq(inner.operands[0], f), "double-NOT inner does not wrap original"
