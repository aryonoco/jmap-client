# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for AccountId, JmapState, MethodCallId, CreationId.

import std/random
import std/sequtils

import jmap_client/identifiers
import jmap_client/validation
import ../mproperty

block propParseAccountIdTotality:
  checkProperty "parseAccountId never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    try:
      discard parseAccountId(s)
    except ValidationError:
      discard

block propParseJmapStateTotality:
  checkProperty "parseJmapState never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    try:
      discard parseJmapState(s)
    except ValidationError:
      discard

block propParseMethodCallIdTotality:
  checkProperty "parseMethodCallId never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    try:
      discard parseMethodCallId(s)
    except ValidationError:
      discard

block propParseCreationIdTotality:
  checkProperty "parseCreationId never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    try:
      discard parseCreationId(s)
    except ValidationError:
      discard

block propParseAccountIdMaliciousTotality:
  checkProperty "parseAccountId never crashes on malicious input":
    let s = genMaliciousString(rng, trial)
    lastInput = s
    try:
      discard parseAccountId(s)
    except ValidationError:
      discard

block propParseJmapStateMaliciousTotality:
  checkProperty "parseJmapState never crashes on malicious input":
    let s = genMaliciousString(rng, trial)
    lastInput = s
    try:
      discard parseJmapState(s)
    except ValidationError:
      discard

block propParseMethodCallIdMaliciousTotality:
  checkProperty "parseMethodCallId never crashes on malicious input":
    let s = genMaliciousString(rng, trial)
    lastInput = s
    try:
      discard parseMethodCallId(s)
    except ValidationError:
      discard

block propParseCreationIdMaliciousTotality:
  checkProperty "parseCreationId never crashes on malicious input":
    let s = genMaliciousString(rng, trial)
    lastInput = s
    try:
      discard parseCreationId(s)
    except ValidationError:
      discard

block propParseJmapStateLongArbitraryTotality:
  checkProperty "parseJmapState never crashes on long arbitrary input":
    let s = genLongArbitraryString(rng, trial)
    lastInput = s
    try:
      discard parseJmapState(s)
    except ValidationError:
      discard

block propParseMethodCallIdLongArbitraryTotality:
  checkProperty "parseMethodCallId never crashes on long arbitrary input":
    let s = genLongArbitraryString(rng, trial)
    lastInput = s
    try:
      discard parseMethodCallId(s)
    except ValidationError:
      discard

block propAccountIdDollarRoundTrip:
  checkProperty "$(parseAccountId(s)) == s":
    let s = genValidIdStrict(rng)
    lastInput = s
    doAssert $(parseAccountId(s)) == s

block propAccountIdLengthBounds:
  checkProperty "valid AccountId has len in 1..255":
    let s = genValidIdStrict(rng)
    lastInput = s
    let a = parseAccountId(s)
    doAssert a.len >= 1 and a.len <= 255

block propAccountIdNoControlChars:
  checkProperty "valid AccountId chars >= space and != DEL":
    let s = genValidIdStrict(rng)
    lastInput = s
    doAssert s.allIt(it >= ' ' and it != '\x7F')

block propCreationIdNoLeadingHash:
  checkProperty "valid CreationId does not start with #":
    let s = genValidCreationId(rng)
    lastInput = s
    let c = parseCreationId(s)
    doAssert string(c)[0] != '#'

block propJmapStateNonEmpty:
  checkProperty "valid JmapState is non-empty":
    let s = genValidIdStrict(rng)
    lastInput = s
    let st = parseJmapState(s)
    doAssert $st != ""

block propMethodCallIdNonEmpty:
  checkProperty "valid MethodCallId is non-empty":
    let s = genValidIdStrict(rng)
    lastInput = s
    let m = parseMethodCallId(s)
    doAssert $m != ""

block propCreationIdNonEmpty:
  checkProperty "valid CreationId is non-empty":
    let s = genValidIdStrict(rng)
    lastInput = s
    let c = parseCreationId(s)
    doAssert $c != ""

block propAccountIdEqImpliesHashEq:
  checkProperty "a == b implies hash(a) == hash(b)":
    let s = genValidIdStrict(rng)
    lastInput = s
    let a = parseAccountId(s)
    let b = parseAccountId(s)
    doAssert a == b
    doAssert hash(a) == hash(b)

# --- Missing round-trip properties ---

block propJmapStateRoundTrip:
  checkProperty "$(parseJmapState(s)) == s":
    let s = genValidJmapState(rng)
    lastInput = s
    doAssert $(parseJmapState(s)) == s

block propMethodCallIdRoundTrip:
  checkProperty "$(parseMethodCallId(s)) == s":
    let s = genValidMethodCallId(rng)
    lastInput = s
    doAssert $(parseMethodCallId(s)) == s

block propCreationIdRoundTrip:
  checkProperty "$(parseCreationId(s)) == s":
    let s = genValidCreationId(rng)
    lastInput = s
    doAssert $(parseCreationId(s)) == s

# --- JmapState invariant ---

block propJmapStateNoControlChars:
  checkProperty "valid JmapState contains no control chars":
    let s = genValidJmapState(rng)
    lastInput = s
    let st = parseJmapState(s)
    let str = $st
    for c in str:
      doAssert c >= ' ' and c != '\x7F'

# --- MethodCallId permissiveness ---

block propMethodCallIdAcceptsControlChars:
  checkProperty "MethodCallId with control chars is Ok":
    var s = newString(5)
    for i in 0 ..< 5:
      s[i] = rng.genControlChar()
    lastInput = s
    discard parseMethodCallId(s)

# --- Hash consistency ---

block propJmapStateEqImpliesHashEq:
  checkProperty "propJmapStateEqImpliesHashEq":
    let s = genValidJmapState(rng)
    lastInput = s
    let a = parseJmapState(s)
    let b = parseJmapState(s)
    doAssert hash(a) == hash(b)

block propMethodCallIdEqImpliesHashEq:
  checkProperty "propMethodCallIdEqImpliesHashEq":
    let s = genValidMethodCallId(rng)
    lastInput = s
    let a = parseMethodCallId(s)
    let b = parseMethodCallId(s)
    doAssert hash(a) == hash(b)

block propCreationIdEqImpliesHashEq:
  checkProperty "propCreationIdEqImpliesHashEq":
    let s = genValidCreationId(rng)
    lastInput = s
    let a = parseCreationId(s)
    let b = parseCreationId(s)
    doAssert hash(a) == hash(b)

# --- Double round-trip equality ---

block propAccountIdDoubleRoundTrip:
  checkProperty "propAccountIdDoubleRoundTrip":
    let s = genValidAccountId(rng)
    lastInput = s
    let first = parseAccountId(s)
    let second = parseAccountId($first)
    doAssert first == second

block propJmapStateDoubleRoundTrip:
  checkProperty "propJmapStateDoubleRoundTrip":
    let s = genValidJmapState(rng)
    lastInput = s
    let first = parseJmapState(s)
    let second = parseJmapState($first)
    doAssert first == second

block propMethodCallIdDoubleRoundTrip:
  checkProperty "propMethodCallIdDoubleRoundTrip":
    let s = genValidMethodCallId(rng)
    lastInput = s
    let first = parseMethodCallId(s)
    let second = parseMethodCallId($first)
    doAssert first == second

block propCreationIdDoubleRoundTrip:
  checkProperty "propCreationIdDoubleRoundTrip":
    let s = genValidCreationId(rng)
    lastInput = s
    let first = parseCreationId(s)
    let second = parseCreationId($first)
    doAssert first == second

# --- Error preservation ---

block propAccountIdErrorPreservesValue:
  checkProperty "propAccountIdErrorPreservesValue":
    let s = genArbitraryString(rng)
    lastInput = s
    try:
      discard parseAccountId(s)
    except ValidationError as e:
      doAssert e.value == s

block propCreationIdHashPrefixAlwaysRejected:
  checkPropertyN "propCreationIdHashPrefixAlwaysRejected", QuickTrials:
    ## Any non-empty string starting with '#' must be rejected.
    let tail = genArbitraryString(rng)
    let s = "#" & tail
    lastInput = s
    if s.len > 0:
      doAssertRaises(ref ValidationError):
        discard parseCreationId(s)

# --- Equivalence substitution ---

block propAccountIdSubstitution:
  checkProperty "propAccountIdSubstitution":
    let s = genValidLenientString(rng, minLen = 1, maxLen = 255)
    lastInput = s
    try:
      let a = parseAccountId(s)
      let b = parseAccountId(s)
      doAssert $(a) == $(b)
      doAssert hash(a) == hash(b)
    except ValidationError:
      discard

block propJmapStateSubstitution:
  checkProperty "propJmapStateSubstitution":
    let s = genValidLenientString(rng, minLen = 1, maxLen = 10000)
    lastInput = s
    try:
      let a = parseJmapState(s)
      let b = parseJmapState(s)
      doAssert $(a) == $(b)
      doAssert hash(a) == hash(b)
    except ValidationError:
      discard

block propParseAccountIdIdempotence:
  checkProperty "propParseAccountIdIdempotence":
    let s = genValidLenientString(rng, minLen = 1, maxLen = 255)
    lastInput = s
    var firstOk = true
    var secondOk = true
    var first, second: AccountId
    try:
      first = parseAccountId(s)
    except ValidationError:
      firstOk = false
    try:
      second = parseAccountId(s)
    except ValidationError:
      secondOk = false
    doAssert firstOk == secondOk
    if firstOk:
      doAssert first == second

block propParseCreationIdIdempotence:
  checkProperty "propParseCreationIdIdempotence":
    let s = genValidCreationId(rng)
    lastInput = s
    let first = parseCreationId(s)
    let second = parseCreationId(s)
    doAssert first == second
