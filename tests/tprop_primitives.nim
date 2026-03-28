# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based tests for Id, UnsignedInt, JmapInt, Date, and UTCDate.

import std/hashes
import std/random
import std/sequtils

import pkg/results

import jmap_client/primitives
import jmap_client/validation
import ./mproperty

# --- Totality: never crashes ---

block propParseIdTotality:
  checkProperty "parseId never crashes":
    let s = genArbitraryString(rng)
    discard parseId(s)

block propParseIdFromServerTotality:
  checkProperty "parseIdFromServer never crashes":
    let s = genArbitraryString(rng)
    discard parseIdFromServer(s)

block propParseUnsignedIntTotality:
  checkProperty "parseUnsignedInt never crashes":
    let n = rng.rand(int64)
    discard parseUnsignedInt(n)

block propParseJmapIntTotality:
  checkProperty "parseJmapInt never crashes":
    let n = rng.rand(int64)
    discard parseJmapInt(n)

block propParseDateTotality:
  checkProperty "parseDate never crashes":
    let s = genArbitraryString(rng)
    discard parseDate(s)

block propParseUtcDateTotality:
  checkProperty "parseUtcDate never crashes":
    let s = genArbitraryString(rng)
    discard parseUtcDate(s)

# --- Round-trip and invariants ---

block propIdDollarRoundTrip:
  checkProperty "$(parseId(s).get()) == s":
    let s = genValidIdStrict(rng)
    doAssert $(parseId(s).get()) == s

block propIdStrictImpliesLenient:
  checkProperty "parseId ok implies parseIdFromServer ok":
    let s = genValidIdStrict(rng)
    doAssert parseId(s).isOk
    doAssert parseIdFromServer(s).isOk

block propIdLengthBounds:
  checkProperty "valid Id has len in 1..255":
    let s = genValidIdStrict(rng)
    let id = parseId(s).get()
    doAssert id.len >= 1 and id.len <= 255

block propIdCharsetInvariant:
  checkProperty "valid strict Id chars are in Base64UrlChars":
    let s = genValidIdStrict(rng)
    doAssert s.allIt(it in Base64UrlChars)

block propUnsignedIntRange:
  checkProperty "valid UnsignedInt in [0, MaxUnsignedInt]":
    let n = genValidUnsignedInt(rng)
    let u = parseUnsignedInt(n).get()
    doAssert int64(u) >= 0
    doAssert int64(u) <= MaxUnsignedInt

block propJmapIntRange:
  checkProperty "valid JmapInt in [MinJmapInt, MaxJmapInt]":
    let n = genValidJmapInt(rng)
    let j = parseJmapInt(n).get()
    doAssert int64(j) >= MinJmapInt
    doAssert int64(j) <= MaxJmapInt

block propJmapIntNegationInvolution:
  checkProperty "-(-x) == x":
    let n = genValidJmapInt(rng)
    let x = parseJmapInt(n).get()
    doAssert -(-x) == x

block propJmapIntNegationZero:
  let z = parseJmapInt(0).get()
  doAssert -z == z

# --- Equality/hash ---

block propIdEqImpliesHashEq:
  checkProperty "a == b implies hash(a) == hash(b)":
    let s = genValidIdStrict(rng)
    let a = parseId(s).get()
    let b = parseId(s).get()
    doAssert a == b
    doAssert hash(a) == hash(b)

block propUnsignedIntOrderConsistency:
  checkProperty "(a < b) matches int64 order":
    let na = genValidUnsignedInt(rng)
    let nb = genValidUnsignedInt(rng)
    let a = parseUnsignedInt(na).get()
    let b = parseUnsignedInt(nb).get()
    doAssert (a < b) == (na < nb)

block propIdFromServerDollarRoundTrip:
  checkProperty "$(parseIdFromServer(s).get()) == s":
    let s = genValidIdStrict(rng)
    doAssert $(parseIdFromServer(s).get()) == s

block propErrorPreservesValue:
  checkProperty "error.value == input for failing parseId":
    let s = genArbitraryString(rng)
    let r = parseId(s)
    if r.isErr:
      doAssert r.error.value == s
