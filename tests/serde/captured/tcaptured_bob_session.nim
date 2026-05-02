# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured bob-principal session
## (``tests/testdata/captured/bob-session-stalwart.json``). First non-
## alice principal in the captured fixture suite. Verifies that
## ``Session.fromJson`` projects bob's session shape correctly: a non-
## empty primary-account map, a primary mail account marked
## ``isPersonal=true`` / ``isReadOnly=false``, and round-trip via
## ``Session.toJson``.

{.push raises: [].}

import std/tables

import jmap_client
import ./mloader

block tcapturedBobSession:
  let j = loadCapturedFixture("bob-session-stalwart")
  let sessRes = Session.fromJson(j)
  doAssert sessRes.isOk, "Session.fromJson must succeed on bob's Stalwart capture"
  let s = sessRes.unsafeValue

  doAssert s.accounts.len >= 1,
    "bob's session must advertise at least one account (got " & $s.accounts.len & ")"
  doAssert s.primaryAccounts.len >= 1, "primaryAccounts must include at least one URI"
  doAssert s.username.len > 0, "username must be non-empty"

  var bobMailAccountId: AccountId
  s.primaryAccounts.withValue("urn:ietf:params:jmap:mail", v):
    bobMailAccountId = v
  do:
    doAssert false, "bob's session must advertise a primary mail account"
  let acc = s.findAccount(bobMailAccountId)
  doAssert acc.isSome, "bob's primary mail accountId must resolve in session.accounts"
  doAssert acc.unsafeGet.isPersonal,
    "bob's primary mail account must be marked isPersonal=true"
  doAssert not acc.unsafeGet.isReadOnly,
    "bob's primary mail account must not be read-only"

  let rt = Session.fromJson(s.toJson()).unsafeValue
  doAssert rt.username == s.username, "username must round-trip"
  doAssert rt.accounts.len == s.accounts.len, "accounts.len must round-trip"
