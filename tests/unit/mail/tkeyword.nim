# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for Keyword and KeywordSet (scenarios 1-17).

{.push raises: [].}

import std/hashes
import std/strutils

import jmap_client/internal/mail/keyword
import jmap_client/internal/types/validation

import ../../massertions
import ../../mtestblock

# ============= A. parseKeyword (strict) =============

testCase parseKeywordValid: # scenario 1
  assertOkEq parseKeyword("$flagged"), parseKeyword("$flagged").get()

testCase parseKeywordUppercase: # scenario 2
  assertOkEq parseKeyword("MyCustomFlag"), parseKeyword("mycustomflag").get()

testCase parseKeywordEmpty: # scenario 3
  assertErrFields parseKeyword(""), "Keyword", "length must be 1-255 octets", ""

testCase parseKeywordTooLong: # scenario 4
  let long = 'a'.repeat(256)
  assertErrFields parseKeyword(long), "Keyword", "length must be 1-255 octets", long

testCase parseKeywordSpace: # scenario 5
  assertErrFields parseKeyword("has space"),
    "Keyword", "contains non-printable character", "has space"

testCase parseKeywordForbiddenParen: # scenario 6
  assertErrFields parseKeyword("test("),
    "Keyword", "contains forbidden character", "test("

testCase parseKeywordForbiddenBackslash: # scenario 7
  assertErrFields parseKeyword("test\\"),
    "Keyword", "contains forbidden character", "test\\"

testCase keywordWithTildeAccepted: # F2 §8.3 (F1 §3.2.5 charset)
  assertOk parseKeyword("$has~tilde")

testCase keywordWithSlashAccepted: # F2 §8.3 (F1 §3.2.5 charset)
  assertOk parseKeyword("$has/slash")

testCase keywordWithBothAccepted: # F2 §8.3 (F1 §3.2.5 charset)
  assertOk parseKeyword("$~/")

# ============= B. parseKeywordFromServer (lenient) =============

testCase parseKeywordFromServerForbiddenAccepted: # scenario 8
  assertOkEq parseKeywordFromServer("$Flag(ed)"),
    parseKeywordFromServer("$flag(ed)").get()

testCase parseKeywordFromServerControlChar: # scenario 9
  assertErrFields parseKeywordFromServer("\x01bad"),
    "Keyword", "contains control characters", "\x01bad"

testCase parseKeywordFromServerEmpty: # scenario 10
  assertErrFields parseKeywordFromServer(""),
    "Keyword", "length must be 1-255 octets", ""

# ============= C. System constants =============

testCase systemConstantsValid: # scenario 11
  doAssert kwDraft == parseKeyword("$draft").get()
  doAssert kwSeen == parseKeyword("$seen").get()
  doAssert kwFlagged == parseKeyword("$flagged").get()
  doAssert kwAnswered == parseKeyword("$answered").get()
  doAssert kwForwarded == parseKeyword("$forwarded").get()
  doAssert kwPhishing == parseKeyword("$phishing").get()
  doAssert kwJunk == parseKeyword("$junk").get()
  doAssert kwNotJunk == parseKeyword("$notjunk").get()

# ============= D. Borrowed operations =============

testCase keywordEqualityCaseNormalised: # scenario 12
  let kw1 = parseKeyword("FLAG").get()
  let kw2 = parseKeyword("flag").get()
  assertEq kw1, kw2

testCase keywordHashConsistent: # scenario 13
  let kw1 = parseKeyword("FLAG").get()
  let kw2 = parseKeyword("flag").get()
  doAssert hash(kw1) == hash(kw2), "equal keywords must have equal hashes"

testCase keywordLen: # scenario 14
  let kw = parseKeyword("$flagged").get()
  assertEq kw.len, 8

# ============= E. KeywordSet =============

testCase initKeywordSetTwoKeywords: # scenario 15
  let ks = initKeywordSet(@[kwSeen, kwFlagged])
  assertLen ks, 2
  doAssert kwSeen in ks
  doAssert kwFlagged in ks

testCase initKeywordSetEmpty: # scenario 16
  let ks = initKeywordSet(@[])
  assertLen ks, 0

testCase initKeywordSetDedup: # scenario 17
  let ks = initKeywordSet(@[kwSeen, kwSeen])
  assertLen ks, 1
  doAssert kwSeen in ks
