# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for Keyword and KeywordSet (scenarios 18-22).

{.push raises: [].}

import std/json

import jmap_client/mail/keyword
import jmap_client/mail/serde_keyword
import jmap_client/serde
import jmap_client/validation

import ../../massertions

# ============= A. KeywordSet toJson =============

block toJsonWithKeywords: # scenario 18
  let ks = initKeywordSet(@[kwSeen, kwFlagged])
  let node = ks.toJson()
  doAssert node.kind == JObject
  assertJsonFieldEq node, "$seen", newJBool(true)
  assertJsonFieldEq node, "$flagged", newJBool(true)
  assertLen node, 2

block toJsonEmpty: # scenario 19
  let ks = initKeywordSet(@[])
  let node = ks.toJson()
  doAssert node.kind == JObject
  assertLen node, 0

# ============= B. KeywordSet fromJson =============

block fromJsonValid: # scenario 20
  let res = KeywordSet.fromJson(%*{"$seen": true})
  assertOk res
  let ks = res.get()
  assertLen ks, 1
  doAssert kwSeen in ks

block fromJsonFalseValue: # scenario 21
  ## Explicit ``false`` for any keyword value is rejected structurally via
  ## ``svkEnumNotRecognised`` at the offending path.
  let res = KeywordSet.fromJson(%*{"$seen": false})
  doAssert res.isErr
  doAssert res.error.kind == svkEnumNotRecognised
  doAssert res.error.rawValue == "false"
  doAssert $res.error.path == "/$seen"

# ============= C. KeywordSet round-trip =============

block roundTrip: # scenario 22
  let original = initKeywordSet(@[kwSeen, kwFlagged, kwDraft])
  let roundTripped = KeywordSet.fromJson(original.toJson()).get()
  assertLen roundTripped, 3
  doAssert kwSeen in roundTripped
  doAssert kwFlagged in roundTripped
  doAssert kwDraft in roundTripped
