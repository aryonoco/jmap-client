# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for AccountId, JmapState, MethodCallId, CreationId.

import std/random
import std/sequtils

import jmap_client/internal/types/identifiers
import jmap_client/internal/types/validation
import ../mproperty

block propParseAccountIdTotality:
  checkProperty "parseAccountId never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseAccountId(s)

block propParseJmapStateTotality:
  checkProperty "parseJmapState never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseJmapState(s)

block propParseMethodCallIdTotality:
  checkProperty "parseMethodCallId never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseMethodCallId(s)

block propParseCreationIdTotality:
  checkProperty "parseCreationId never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseCreationId(s)

block propParseAccountIdMaliciousTotality:
  checkProperty "parseAccountId never crashes on malicious input":
    let s = genMaliciousString(rng, trial)
    lastInput = s
    discard parseAccountId(s)

block propParseJmapStateMaliciousTotality:
  checkProperty "parseJmapState never crashes on malicious input":
    let s = genMaliciousString(rng, trial)
    lastInput = s
    discard parseJmapState(s)

block propParseMethodCallIdMaliciousTotality:
  checkProperty "parseMethodCallId never crashes on malicious input":
    let s = genMaliciousString(rng, trial)
    lastInput = s
    discard parseMethodCallId(s)

block propParseCreationIdMaliciousTotality:
  checkProperty "parseCreationId never crashes on malicious input":
    let s = genMaliciousString(rng, trial)
    lastInput = s
    discard parseCreationId(s)

block propParseJmapStateLongArbitraryTotality:
  checkProperty "parseJmapState never crashes on long arbitrary input":
    let s = genLongArbitraryString(rng, trial)
    lastInput = s
    discard parseJmapState(s)

block propParseMethodCallIdLongArbitraryTotality:
  checkProperty "parseMethodCallId never crashes on long arbitrary input":
    let s = genLongArbitraryString(rng, trial)
    lastInput = s
    discard parseMethodCallId(s)

block propAccountIdDollarRoundTrip:
  checkProperty "$(parseAccountId(s).get()) == s":
    let s = genValidIdStrict(rng)
    lastInput = s
    doAssert $(parseAccountId(s).get()) == s

block propAccountIdLengthBounds:
  checkProperty "valid AccountId has len in 1..255":
    let s = genValidIdStrict(rng)
    lastInput = s
    let a = parseAccountId(s).get()
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
    let c = parseCreationId(s).get()
    doAssert string(c)[0] != '#'

block propJmapStateNonEmpty:
  checkProperty "valid JmapState is non-empty":
    let s = genValidIdStrict(rng)
    lastInput = s
    let st = parseJmapState(s).get()
    doAssert $st != ""

block propMethodCallIdNonEmpty:
  checkProperty "valid MethodCallId is non-empty":
    let s = genValidIdStrict(rng)
    lastInput = s
    let m = parseMethodCallId(s).get()
    doAssert $m != ""

block propCreationIdNonEmpty:
  checkProperty "valid CreationId is non-empty":
    let s = genValidIdStrict(rng)
    lastInput = s
    let c = parseCreationId(s).get()
    doAssert $c != ""

block propAccountIdEqImpliesHashEq:
  checkProperty "a == b implies hash(a) == hash(b)":
    let s = genValidIdStrict(rng)
    lastInput = s
    let a = parseAccountId(s).get()
    let b = parseAccountId(s).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

# --- Missing round-trip properties ---

block propJmapStateRoundTrip:
  checkProperty "$(parseJmapState(s).get()) == s":
    let s = genValidJmapState(rng)
    lastInput = s
    doAssert $(parseJmapState(s).get()) == s

block propMethodCallIdRoundTrip:
  checkProperty "$(parseMethodCallId(s).get()) == s":
    let s = genValidMethodCallId(rng)
    lastInput = s
    doAssert $(parseMethodCallId(s).get()) == s

block propCreationIdRoundTrip:
  checkProperty "$(parseCreationId(s).get()) == s":
    let s = genValidCreationId(rng)
    lastInput = s
    doAssert $(parseCreationId(s).get()) == s

# --- JmapState invariant ---

block propJmapStateNoControlChars:
  checkProperty "valid JmapState contains no control chars":
    let s = genValidJmapState(rng)
    lastInput = s
    let st = parseJmapState(s).get()
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
    discard parseMethodCallId(s).get()

# --- Hash consistency ---

block propJmapStateEqImpliesHashEq:
  checkProperty "propJmapStateEqImpliesHashEq":
    let s = genValidJmapState(rng)
    lastInput = s
    let a = parseJmapState(s).get()
    let b = parseJmapState(s).get()
    doAssert hash(a) == hash(b)

block propMethodCallIdEqImpliesHashEq:
  checkProperty "propMethodCallIdEqImpliesHashEq":
    let s = genValidMethodCallId(rng)
    lastInput = s
    let a = parseMethodCallId(s).get()
    let b = parseMethodCallId(s).get()
    doAssert hash(a) == hash(b)

block propCreationIdEqImpliesHashEq:
  checkProperty "propCreationIdEqImpliesHashEq":
    let s = genValidCreationId(rng)
    lastInput = s
    let a = parseCreationId(s).get()
    let b = parseCreationId(s).get()
    doAssert hash(a) == hash(b)

# --- Double round-trip equality ---

block propAccountIdDoubleRoundTrip:
  checkProperty "propAccountIdDoubleRoundTrip":
    let s = genValidAccountId(rng)
    lastInput = s
    let first = parseAccountId(s).get()
    let second = parseAccountId($first).get()
    doAssert first == second

block propJmapStateDoubleRoundTrip:
  checkProperty "propJmapStateDoubleRoundTrip":
    let s = genValidJmapState(rng)
    lastInput = s
    let first = parseJmapState(s).get()
    let second = parseJmapState($first).get()
    doAssert first == second

block propMethodCallIdDoubleRoundTrip:
  checkProperty "propMethodCallIdDoubleRoundTrip":
    let s = genValidMethodCallId(rng)
    lastInput = s
    let first = parseMethodCallId(s).get()
    let second = parseMethodCallId($first).get()
    doAssert first == second

block propCreationIdDoubleRoundTrip:
  checkProperty "propCreationIdDoubleRoundTrip":
    let s = genValidCreationId(rng)
    lastInput = s
    let first = parseCreationId(s).get()
    let second = parseCreationId($first).get()
    doAssert first == second

# --- Error preservation ---

block propAccountIdErrorPreservesValue:
  checkProperty "propAccountIdErrorPreservesValue":
    let s = genArbitraryString(rng)
    lastInput = s
    let r = parseAccountId(s)
    if r.isErr:
      doAssert r.error.value == s

block propCreationIdHashPrefixAlwaysRejected:
  checkPropertyN "propCreationIdHashPrefixAlwaysRejected", QuickTrials:
    ## Any non-empty string starting with '#' must be rejected.
    let tail = genArbitraryString(rng)
    let s = "#" & tail
    lastInput = s
    if s.len > 0:
      doAssert parseCreationId(s).isErr

# --- Equivalence substitution ---

block propAccountIdSubstitution:
  checkProperty "propAccountIdSubstitution":
    let s = genValidLenientString(rng, minLen = 1, maxLen = 255)
    lastInput = s
    let a = parseAccountId(s).get()
    let b = parseAccountId(s).get()
    doAssert $(a) == $(b)
    doAssert hash(a) == hash(b)
block propJmapStateSubstitution:
  checkProperty "propJmapStateSubstitution":
    let s = genValidLenientString(rng, minLen = 1, maxLen = 10000)
    lastInput = s
    let a = parseJmapState(s).get()
    let b = parseJmapState(s).get()
    doAssert $(a) == $(b)
    doAssert hash(a) == hash(b)
block propParseAccountIdIdempotence:
  checkProperty "propParseAccountIdIdempotence":
    let s = genValidLenientString(rng, minLen = 1, maxLen = 255)
    lastInput = s
    let r1 = parseAccountId(s)
    let r2 = parseAccountId(s)
    doAssert r1.isOk == r2.isOk
    if r1.isOk:
      doAssert r1.get() == r2.get()

block propParseCreationIdIdempotence:
  checkProperty "propParseCreationIdIdempotence":
    let s = genValidCreationId(rng)
    lastInput = s
    let first = parseCreationId(s).get()
    let second = parseCreationId(s).get()
    doAssert first == second
