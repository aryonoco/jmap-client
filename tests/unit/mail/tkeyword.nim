# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for Keyword and KeywordSet (scenarios 1-17).

{.push raises: [].}

import std/hashes
import std/strutils

import jmap_client/internal/mail/keyword
import jmap_client/internal/types/validation

import ../../massertions

# ============= A. parseKeyword (strict) =============

block parseKeywordValid: # scenario 1
  assertOkEq parseKeyword("$flagged"), Keyword("$flagged")

block parseKeywordUppercase: # scenario 2
  assertOkEq parseKeyword("MyCustomFlag"), Keyword("mycustomflag")

block parseKeywordEmpty: # scenario 3
  assertErrFields parseKeyword(""), "Keyword", "length must be 1-255 octets", ""

block parseKeywordTooLong: # scenario 4
  let long = 'a'.repeat(256)
  assertErrFields parseKeyword(long), "Keyword", "length must be 1-255 octets", long

block parseKeywordSpace: # scenario 5
  assertErrFields parseKeyword("has space"),
    "Keyword", "contains non-printable character", "has space"

block parseKeywordForbiddenParen: # scenario 6
  assertErrFields parseKeyword("test("),
    "Keyword", "contains forbidden character", "test("

block parseKeywordForbiddenBackslash: # scenario 7
  assertErrFields parseKeyword("test\\"),
    "Keyword", "contains forbidden character", "test\\"

block keywordWithTildeAccepted: # F2 §8.3 (F1 §3.2.5 charset)
  assertOk parseKeyword("$has~tilde")

block keywordWithSlashAccepted: # F2 §8.3 (F1 §3.2.5 charset)
  assertOk parseKeyword("$has/slash")

block keywordWithBothAccepted: # F2 §8.3 (F1 §3.2.5 charset)
  assertOk parseKeyword("$~/")

# ============= B. parseKeywordFromServer (lenient) =============

block parseKeywordFromServerForbiddenAccepted: # scenario 8
  assertOkEq parseKeywordFromServer("$Flag(ed)"), Keyword("$flag(ed)")

block parseKeywordFromServerControlChar: # scenario 9
  assertErrFields parseKeywordFromServer("\x01bad"),
    "Keyword", "contains control characters", "\x01bad"

block parseKeywordFromServerEmpty: # scenario 10
  assertErrFields parseKeywordFromServer(""),
    "Keyword", "length must be 1-255 octets", ""

# ============= C. System constants =============

block systemConstantsValid: # scenario 11
  doAssert kwDraft == Keyword("$draft")
  doAssert kwSeen == Keyword("$seen")
  doAssert kwFlagged == Keyword("$flagged")
  doAssert kwAnswered == Keyword("$answered")
  doAssert kwForwarded == Keyword("$forwarded")
  doAssert kwPhishing == Keyword("$phishing")
  doAssert kwJunk == Keyword("$junk")
  doAssert kwNotJunk == Keyword("$notjunk")

# ============= D. Borrowed operations =============

block keywordEqualityCaseNormalised: # scenario 12
  let kw1 = parseKeyword("FLAG").get()
  let kw2 = parseKeyword("flag").get()
  assertEq kw1, kw2

block keywordHashConsistent: # scenario 13
  let kw1 = parseKeyword("FLAG").get()
  let kw2 = parseKeyword("flag").get()
  doAssert hash(kw1) == hash(kw2), "equal keywords must have equal hashes"

block keywordLen: # scenario 14
  let kw = parseKeyword("$flagged").get()
  assertEq kw.len, 8

# ============= E. KeywordSet =============

block initKeywordSetTwoKeywords: # scenario 15
  let ks = initKeywordSet(@[kwSeen, kwFlagged])
  assertLen ks, 2
  doAssert kwSeen in ks
  doAssert kwFlagged in ks

block initKeywordSetEmpty: # scenario 16
  let ks = initKeywordSet(@[])
  assertLen ks, 0

block initKeywordSetDedup: # scenario 17
  let ks = initKeywordSet(@[kwSeen, kwSeen])
  assertLen ks, 1
  doAssert kwSeen in ks
