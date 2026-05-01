# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured Stalwart session
## (``tests/testdata/captured/session-stalwart.json``).  Verifies the
## session shape Stalwart 0.15.5 emits — capability set,
## ``coreCapabilities`` ranges, account map, and round-trip through
## ``Session.toJson``.

{.push raises: [].}

import std/sets
import std/tables

import jmap_client
import ./mloader

block tcapturedSession:
  let j = loadCapturedFixture("session-stalwart")
  let sessRes = Session.fromJson(j)
  doAssert sessRes.isOk, "Session.fromJson must succeed on Stalwart capture"
  let s = sessRes.unsafeValue

  doAssert s.capabilities.len >= 4,
    "Stalwart advertises >=4 capabilities (got " & $s.capabilities.len & ")"
  let core = s.coreCapabilities()
  doAssert int64(core.maxSizeUpload) > 0, "maxSizeUpload must be positive"
  doAssert int64(core.maxSizeRequest) > 0, "maxSizeRequest must be positive"
  doAssert int64(core.maxCallsInRequest) > 0, "maxCallsInRequest must be positive"
  doAssert int64(core.maxObjectsInGet) > 0, "maxObjectsInGet must be positive"
  doAssert int64(core.maxObjectsInSet) > 0, "maxObjectsInSet must be positive"
  doAssert core.collationAlgorithms.card >= 1,
    "at least one collation algorithm must be advertised"

  doAssert s.accounts.len >= 1, "session must advertise at least one account"
  doAssert s.primaryAccounts.len >= 1, "primaryAccounts must include at least one URI"
  doAssert s.username.len > 0, "username must be non-empty"

  let rt = Session.fromJson(s.toJson()).unsafeValue
  doAssert rt.username == s.username, "username must round-trip"
  doAssert rt.accounts.len == s.accounts.len, "accounts.len must round-trip"
