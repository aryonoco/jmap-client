# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based tests for PropertyName, PatchObject, Filter, Comparator.

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
