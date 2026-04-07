# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for Thread entity (scenarios 13-17 + sealed field safety).

import jmap_client/mail/thread
import jmap_client/validation
import jmap_client/primitives

import ../../massertions

let id = parseId("t1").get()
let e1 = parseId("e1").get()
let e2 = parseId("e2").get()
let e3 = parseId("e3").get()

# ============= A. parseThread =============

block parseThreadSingleEmailId: # scenario 13
  let res = parseThread(id, @[e1])
  assertOk res
  assertLen res.get().emailIds, 1

block parseThreadMultipleEmailIds: # scenario 14
  let res = parseThread(id, @[e1, e2, e3])
  assertOk res
  assertLen res.get().emailIds, 3

block parseThreadEmptyEmailIds: # scenario 15
  assertErrFields parseThread(id, @[]),
    "Thread", "emailIds must contain at least one Id", ""

# ============= B. Accessors =============

block idAccessor: # scenario 16
  let t = parseThread(id, @[e1, e2]).get()
  assertEq t.id, id

block emailIdsAccessor: # scenario 17
  let t = parseThread(id, @[e1, e2, e3]).get()
  assertEq t.emailIds, @[e1, e2, e3]

# ============= C. Sealed field safety =============

block sealedFieldsRejectNamedConstruction: # replaces scenario 22
  assertNotCompiles(thread.Thread(rawId: id, rawEmailIds: @[e1]))

block sealedFieldsRejectDirectAccess: # replaces scenario 23
  let t = parseThread(id, @[e1]).get()
  assertNotCompiles(t.rawId)
  assertNotCompiles(t.rawEmailIds)

block seqThreadOperationsWork: # validates requiresInit drop
  var ts: seq[thread.Thread] = @[]
  let t = parseThread(id, @[e1]).get()
  ts.add(t)
  assertLen ts, 1
  assertEq ts[0].id, id
