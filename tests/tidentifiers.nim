# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Tests for AccountId, JmapState, MethodCallId, and CreationId smart constructors.

import std/hashes
import std/strutils

import pkg/results

import jmap_client/identifiers

# --- parseAccountId ---

block parseAccountIdEmpty:
  doAssert parseAccountId("").isErr

block parseAccountIdValid:
  let result = parseAccountId("A13824")
  doAssert result.isOk

block parseAccountIdTooLong:
  doAssert parseAccountId('a'.repeat(256)).isErr

block parseAccountIdMaxLength:
  let result = parseAccountId('a'.repeat(255))
  doAssert result.isOk

block parseAccountIdMinLength:
  let result = parseAccountId("x")
  doAssert result.isOk

block parseAccountIdControlChar:
  doAssert parseAccountId("abc\x00def").isErr

# --- parseJmapState ---

block parseJmapStateEmpty:
  doAssert parseJmapState("").isErr

block parseJmapStateValid:
  let result = parseJmapState("75128aab4b1b")
  doAssert result.isOk

block parseJmapStateControlChar:
  doAssert parseJmapState("abc\x00def").isErr

# --- parseMethodCallId ---

block parseMethodCallIdEmpty:
  doAssert parseMethodCallId("").isErr

block parseMethodCallIdValid:
  let result = parseMethodCallId("c1")
  doAssert result.isOk

# --- parseCreationId ---

block parseCreationIdEmpty:
  doAssert parseCreationId("").isErr

block parseCreationIdHashPrefix:
  doAssert parseCreationId("#abc").isErr

block parseCreationIdValid:
  let result = parseCreationId("abc")
  doAssert result.isOk

# --- Borrowed ops: AccountId ---

block accountIdBorrowedOps:
  let a = parseAccountId("A13824").get()
  let b = parseAccountId("A13824").get()
  let c = parseAccountId("B99921").get()

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "A13824"
  doAssert hash(a) == hash(b)
  doAssert a.len == 6

# --- Borrowed ops: JmapState, MethodCallId, CreationId ---

block jmapStateBorrowedOps:
  let a = parseJmapState("75128aab4b1b").get()
  let b = parseJmapState("75128aab4b1b").get()
  let c = parseJmapState("different").get()

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "75128aab4b1b"
  doAssert hash(a) == hash(b)
  doAssert not compiles(a.len)

block methodCallIdBorrowedOps:
  let a = parseMethodCallId("c1").get()
  let b = parseMethodCallId("c1").get()
  let c = parseMethodCallId("c2").get()

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "c1"
  doAssert hash(a) == hash(b)
  doAssert not compiles(a.len)

block creationIdBorrowedOps:
  let a = parseCreationId("abc").get()
  let b = parseCreationId("abc").get()
  let c = parseCreationId("xyz").get()

  doAssert a == b
  doAssert not (a == c)
  doAssert $a == "abc"
  doAssert hash(a) == hash(b)
  doAssert not compiles(a.len)
