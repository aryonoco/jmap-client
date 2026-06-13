# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for ``Credential`` — the sealed RFC 6750 Bearer / RFC 7617 Basic
## client credential. Covers construction validation, scheme discriminator,
## the redacting ``$`` (token/password never rendered), arm-dispatched ``==``,
## and the hub-private ``authorizationHeaderValue`` wire projection. Imports
## the internal leaf directly to reach ``authorizationHeaderValue`` (filtered
## from the public hub); ``std/base64`` is the Basic-encoding oracle (tests are
## exempt from the Layer-1 purity pragma).

import std/base64

import jmap_client/internal/types/credential
import jmap_client/internal/types/validation

import ../mtestblock

# --- bearer construction ---

testCase bearerValid:
  let c = bearerCredential("test-token").get()
  doAssert c.scheme == asBearer
  doAssert c.authorizationHeaderValue == "Bearer test-token"

testCase bearerRejectsEmpty:
  let r = bearerCredential("")
  doAssert r.isErr
  doAssert r.error.typeName == "Credential"
  doAssert r.error.reason == "bearer token must not be empty"
  doAssert r.error.value == ""

testCase bearerRejectsControlChar:
  ## CR/LF in the token would enable header injection — the secret never
  ## reaches the error rail, so ``value`` stays empty.
  let r = bearerCredential("tok\r\nEvil")
  doAssert r.isErr
  doAssert r.error.typeName == "Credential"
  doAssert r.error.reason == "bearer token must not contain control characters"
  doAssert r.error.value == ""

# --- basic construction ---

testCase basicValid:
  let c = basicCredential("alice", "alice123").get()
  doAssert c.scheme == asBasic
  doAssert c.authorizationHeaderValue == "Basic " & base64.encode("alice:alice123")

testCase basicPasswordMayContainColon:
  ## RFC 7617 forbids ``:`` in the user-id only; the password is unrestricted.
  let c = basicCredential("alice", "pa:ss").get()
  doAssert c.authorizationHeaderValue == "Basic " & base64.encode("alice:pa:ss")

testCase basicRejectsEmptyUsername:
  let r = basicCredential("", "secret")
  doAssert r.isErr
  doAssert r.error.typeName == "Credential"
  doAssert r.error.reason == "username must not be empty"
  doAssert r.error.value == ""

testCase basicRejectsColonInUsername:
  let r = basicCredential("a:b", "secret")
  doAssert r.isErr
  doAssert r.error.reason == "username must not contain ':'"
  doAssert r.error.value == ""

# --- redacting `$` (decision #10) ---

testCase dollarBearerRedacts:
  doAssert $bearerCredential("super-secret").get() == "Credential(Bearer)"

testCase dollarBasicShowsUsernameOnly:
  doAssert $basicCredential("alice", "alice123").get() ==
    "Credential(Basic, username: alice)"

# --- arm-dispatched equality ---

testCase equalBearers:
  doAssert bearerCredential("t").get() == bearerCredential("t").get()

testCase differingBearersUnequal:
  doAssert bearerCredential("a").get() != bearerCredential("b").get()

testCase bearerNeverEqualsBasic:
  doAssert bearerCredential("alice").get() != basicCredential("alice", "x").get()

testCase equalBasics:
  doAssert basicCredential("alice", "pw").get() == basicCredential("alice", "pw").get()
