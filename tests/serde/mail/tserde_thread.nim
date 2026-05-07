# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for Thread entity (scenarios 18-21 + edge cases).

import std/json

import jmap_client/internal/mail/thread
import jmap_client/internal/mail/serde_thread
import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives

import ../../massertions

let id = parseId("t1").get()
let e1 = parseId("e1").get()
let e2 = parseId("e2").get()
let e3 = parseId("e3").get()

# ============= A. toJson =============

block toJsonStructure: # scenario 18
  let t = parseThread(id, @[e1, e2]).get()
  let node = t.toJson()
  assertJsonFieldEq node, "id", %"t1"
  let arr = node{"emailIds"}
  doAssert arr != nil, "emailIds field must be present"
  doAssert arr.kind == JArray, "emailIds must be JArray"
  assertLen arr.getElems(@[]), 2
  assertEq arr.getElems(@[])[0], %"e1"
  assertEq arr.getElems(@[])[1], %"e2"

# ============= B. fromJson =============

block fromJsonValidSingle: # scenario 19
  let node = %*{"id": "t1", "emailIds": ["e1"]}
  let res = thread.Thread.fromJson(node)
  assertOk res
  assertEq res.get().id, id
  assertLen res.get().emailIds, 1
  assertEq res.get().emailIds[0], e1

block fromJsonValidMultipleOrder: # scenario 20
  let node = %*{"id": "t1", "emailIds": ["e1", "e2", "e3"]}
  let res = thread.Thread.fromJson(node)
  assertOk res
  assertEq res.get().emailIds, @[e1, e2, e3]

block fromJsonEmptyEmailIds: # scenario 21
  let node = %*{"id": "t1", "emailIds": []}
  assertErr thread.Thread.fromJson(node)

# ============= C. Round-trip =============

block roundTripSingle:
  let original = parseThread(id, @[e1]).get()
  let roundTripped = thread.Thread.fromJson(original.toJson()).get()
  assertEq roundTripped.id, original.id
  assertEq roundTripped.emailIds, original.emailIds

block roundTripMultiple:
  let original = parseThread(id, @[e1, e2, e3]).get()
  let roundTripped = thread.Thread.fromJson(original.toJson()).get()
  assertEq roundTripped.id, original.id
  assertEq roundTripped.emailIds, original.emailIds

# ============= D. fromJson edge cases =============

block fromJsonNotObject:
  let node = %"string"
  assertErr thread.Thread.fromJson(node)

block fromJsonMissingId:
  let node = %*{"emailIds": ["e1"]}
  assertErr thread.Thread.fromJson(node)

block fromJsonMissingEmailIds:
  let node = %*{"id": "t1"}
  assertErr thread.Thread.fromJson(node)

block fromJsonEmailIdsNotArray:
  let node = %*{"id": "t1", "emailIds": "x"}
  assertErr thread.Thread.fromJson(node)

block fromJsonInvalidElement:
  let node = %*{"id": "t1", "emailIds": [42]}
  assertErr thread.Thread.fromJson(node)

block fromJsonNullId:
  let node = %*{"id": nil, "emailIds": ["e1"]}
  assertErr thread.Thread.fromJson(node)

block fromJsonNullEmailIds:
  let node = %*{"id": "t1", "emailIds": nil}
  assertErr thread.Thread.fromJson(node)
