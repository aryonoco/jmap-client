# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for Identity entity (scenarios 33-35).

import jmap_client/internal/mail/addresses
import jmap_client/internal/mail/identity
import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives

import ../../massertions
import ../../mtestblock

let ea1 = parseEmailAddress("alice@example.com", Opt.some("Alice")).get()
let ea2 = parseEmailAddress("bob@example.com").get()

# ============= A. parseIdentityCreate =============

testCase parseIdentityCreateAllFields: # scenario 33
  let res = parseIdentityCreate(
    email = "joe@example.com",
    name = "Joe Bloggs",
    replyTo = Opt.some(@[ea1]),
    bcc = Opt.some(@[ea2]),
    textSignature = "-- Joe",
    htmlSignature = "<p>Joe</p>",
  )
  assertOk res
  let ic = res.get()
  assertEq ic.email, "joe@example.com"
  assertEq ic.name, "Joe Bloggs"
  assertSome ic.replyTo
  assertLen ic.replyTo.get(), 1
  assertSome ic.bcc
  assertLen ic.bcc.get(), 1
  assertEq ic.textSignature, "-- Joe"
  assertEq ic.htmlSignature, "<p>Joe</p>"

testCase parseIdentityCreateDefaults: # scenario 34
  let res = parseIdentityCreate("joe@example.com")
  assertOk res
  let ic = res.get()
  assertEq ic.email, "joe@example.com"
  assertEq ic.name, ""
  assertNone ic.replyTo
  assertNone ic.bcc
  assertEq ic.textSignature, ""
  assertEq ic.htmlSignature, ""

testCase parseIdentityCreateEmptyEmail: # scenario 35
  assertErrFields parseIdentityCreate(""),
    "IdentityCreate", "email must not be empty", ""

# ============= B. IdentityCreate field access =============

testCase identityCreateFieldAccess:
  let ic = parseIdentityCreate("x@y.z").get()
  assertEq ic.email, "x@y.z"
  assertEq ic.name, ""
  assertNone ic.replyTo
  assertNone ic.bcc
  assertEq ic.textSignature, ""
  assertEq ic.htmlSignature, ""
