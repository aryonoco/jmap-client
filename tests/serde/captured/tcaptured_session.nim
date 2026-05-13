# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured session document from
## every configured target (``tests/testdata/captured/session-<server>
## .json``). Verifies the session shape each target emits — capability
## set, ``coreCapabilities`` ranges, account map, and round-trip
## through ``Session.toJson``.

{.push raises: [].}

import std/sets
import std/tables

import jmap_client
import ./mloader
import ../../mtestblock

testCase tcapturedSession:
  forEachCapturedServer("session", j):
    let sessRes = Session.fromJson(j)
    doAssert sessRes.isOk, "Session.fromJson must succeed on captured fixture"
    let s = sessRes.unsafeValue

    doAssert s.capabilities.len >= 4,
      "configured targets advertise >=4 capabilities (got " & $s.capabilities.len & ")"
    let core = s.coreCapabilities()
    # ``maxSizeUpload`` may be 0 to signal "no enforced limit" — Cyrus
    # 3.12.2 reports 0; Stalwart and James both advertise non-zero
    # caps. UnsignedInt is non-negative by construction, so the parse
    # itself is the structural assertion.
    discard core.maxSizeUpload.toInt64
    doAssert core.maxSizeRequest.toInt64 > 0, "maxSizeRequest must be positive"
    doAssert core.maxCallsInRequest.toInt64 > 0, "maxCallsInRequest must be positive"
    doAssert core.maxObjectsInGet.toInt64 > 0, "maxObjectsInGet must be positive"
    doAssert core.maxObjectsInSet.toInt64 > 0, "maxObjectsInSet must be positive"
    # ``collationAlgorithms`` is mandated by RFC 8620 §2 to list the
    # algorithms the server supports — but Cyrus 3.12.2 ships an empty
    # array, expecting the client to default to ``i;ascii-casemap``.
    # Stalwart and James populate it; Cyrus omits. The universal
    # structural contract is that the field parses as a HashSet.
    discard core.collationAlgorithms.card

    doAssert s.accounts.len >= 1, "session must advertise at least one account"
    doAssert s.primaryAccounts.len >= 1, "primaryAccounts must include at least one URI"
    doAssert s.username.len > 0, "username must be non-empty"

    let rt = Session.fromJson(s.toJson()).unsafeValue
    doAssert rt.username == s.username, "username must round-trip"
    doAssert rt.accounts.len == s.accounts.len, "accounts.len must round-trip"
