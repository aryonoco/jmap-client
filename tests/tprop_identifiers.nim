# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based tests for AccountId, JmapState, MethodCallId, CreationId.

import std/hashes
import std/random
import std/sequtils

import pkg/results

import jmap_client/identifiers
import jmap_client/validation
import ./mproperty

block propParseAccountIdTotality:
  checkProperty "parseAccountId never crashes":
    discard parseAccountId(genArbitraryString(rng))

block propParseJmapStateTotality:
  checkProperty "parseJmapState never crashes":
    discard parseJmapState(genArbitraryString(rng))

block propParseMethodCallIdTotality:
  checkProperty "parseMethodCallId never crashes":
    discard parseMethodCallId(genArbitraryString(rng))

block propParseCreationIdTotality:
  checkProperty "parseCreationId never crashes":
    discard parseCreationId(genArbitraryString(rng))

block propAccountIdDollarRoundTrip:
  checkProperty "$(parseAccountId(s).get()) == s":
    let s = genValidIdStrict(rng)
    doAssert $(parseAccountId(s).get()) == s

block propAccountIdLengthBounds:
  checkProperty "valid AccountId has len in 1..255":
    let s = genValidIdStrict(rng)
    let a = parseAccountId(s).get()
    doAssert a.len >= 1 and a.len <= 255

block propAccountIdNoControlChars:
  checkProperty "valid AccountId chars >= space and != DEL":
    let s = genValidIdStrict(rng)
    doAssert s.allIt(it >= ' ' and it != '\x7F')

block propCreationIdNoLeadingHash:
  checkProperty "valid CreationId does not start with #":
    let s = genValidCreationId(rng)
    let c = parseCreationId(s).get()
    doAssert string(c)[0] != '#'

block propJmapStateNonEmpty:
  checkProperty "valid JmapState is non-empty":
    let s = genValidIdStrict(rng)
    let st = parseJmapState(s).get()
    doAssert $st != ""

block propMethodCallIdNonEmpty:
  checkProperty "valid MethodCallId is non-empty":
    let s = genValidIdStrict(rng)
    let m = parseMethodCallId(s).get()
    doAssert $m != ""

block propCreationIdNonEmpty:
  checkProperty "valid CreationId is non-empty":
    let s = genValidIdStrict(rng)
    let c = parseCreationId(s).get()
    doAssert $c != ""

block propAccountIdEqImpliesHashEq:
  checkProperty "a == b implies hash(a) == hash(b)":
    let s = genValidIdStrict(rng)
    let a = parseAccountId(s).get()
    let b = parseAccountId(s).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

# --- Missing round-trip properties ---

block propJmapStateRoundTrip:
  checkProperty "$(parseJmapState(s).get()) == s":
    let s = genValidJmapState(rng)
    doAssert $(parseJmapState(s).get()) == s

block propMethodCallIdRoundTrip:
  checkProperty "$(parseMethodCallId(s).get()) == s":
    let s = genValidMethodCallId(rng)
    doAssert $(parseMethodCallId(s).get()) == s

block propCreationIdRoundTrip:
  checkProperty "$(parseCreationId(s).get()) == s":
    let s = genValidCreationId(rng)
    doAssert $(parseCreationId(s).get()) == s

# --- JmapState invariant ---

block propJmapStateNoControlChars:
  checkProperty "valid JmapState contains no control chars":
    let s = genValidJmapState(rng)
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
    doAssert parseMethodCallId(s).isOk

# --- Equivalence relation and hash consistency ---

block propAccountIdReflexivity:
  checkProperty "propAccountIdReflexivity":
    let s = genValidAccountId(rng)
    let a = parseAccountId(s).get()
    doAssert a == a

block propJmapStateReflexivity:
  checkProperty "propJmapStateReflexivity":
    let s = genValidJmapState(rng)
    let a = parseJmapState(s).get()
    doAssert a == a

block propMethodCallIdReflexivity:
  checkProperty "propMethodCallIdReflexivity":
    let s = genValidMethodCallId(rng)
    let a = parseMethodCallId(s).get()
    doAssert a == a

block propCreationIdReflexivity:
  checkProperty "propCreationIdReflexivity":
    let s = genValidCreationId(rng)
    let a = parseCreationId(s).get()
    doAssert a == a

block propJmapStateEqImpliesHashEq:
  checkProperty "propJmapStateEqImpliesHashEq":
    let s = genValidJmapState(rng)
    let a = parseJmapState(s).get()
    let b = parseJmapState(s).get()
    doAssert hash(a) == hash(b)

block propMethodCallIdEqImpliesHashEq:
  checkProperty "propMethodCallIdEqImpliesHashEq":
    let s = genValidMethodCallId(rng)
    let a = parseMethodCallId(s).get()
    let b = parseMethodCallId(s).get()
    doAssert hash(a) == hash(b)

block propCreationIdEqImpliesHashEq:
  checkProperty "propCreationIdEqImpliesHashEq":
    let s = genValidCreationId(rng)
    let a = parseCreationId(s).get()
    let b = parseCreationId(s).get()
    doAssert hash(a) == hash(b)

# --- Double round-trip equality ---

block propAccountIdDoubleRoundTrip:
  checkProperty "propAccountIdDoubleRoundTrip":
    let s = genValidAccountId(rng)
    let first = parseAccountId(s).get()
    let second = parseAccountId($first).get()
    doAssert first == second

block propJmapStateDoubleRoundTrip:
  checkProperty "propJmapStateDoubleRoundTrip":
    let s = genValidJmapState(rng)
    let first = parseJmapState(s).get()
    let second = parseJmapState($first).get()
    doAssert first == second

block propMethodCallIdDoubleRoundTrip:
  checkProperty "propMethodCallIdDoubleRoundTrip":
    let s = genValidMethodCallId(rng)
    let first = parseMethodCallId(s).get()
    let second = parseMethodCallId($first).get()
    doAssert first == second

block propCreationIdDoubleRoundTrip:
  checkProperty "propCreationIdDoubleRoundTrip":
    let s = genValidCreationId(rng)
    let first = parseCreationId(s).get()
    let second = parseCreationId($first).get()
    doAssert first == second
