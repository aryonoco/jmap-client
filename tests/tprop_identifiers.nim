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
    let s = genValidIdStrict(rng)
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
