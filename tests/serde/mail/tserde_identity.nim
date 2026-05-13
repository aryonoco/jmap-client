# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for Identity entity (scenarios 24-32, 36-37).

import std/json

import jmap_client/internal/mail/addresses
import jmap_client/internal/mail/identity
import jmap_client/internal/mail/serde_addresses
import jmap_client/internal/mail/serde_identity
import jmap_client/internal/serialisation/serde
import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives

import ../../massertions
import ../../mtestblock

let ea1 = parseEmailAddress("alice@example.com", Opt.some("Alice")).get()
let ea2 = parseEmailAddress("bob@example.com").get()

# ============= A. Identity fromJson — full and defaults =============

testCase fromJsonAllFields: # scenario 24
  let node = %*{
    "id": "id1",
    "name": "Joe Bloggs",
    "email": "joe@example.com",
    "replyTo": [{"name": "Alice", "email": "alice@example.com"}],
    "bcc": [{"email": "bob@example.com"}],
    "textSignature": "-- Joe",
    "htmlSignature": "<p>Joe</p>",
    "mayDelete": true,
  }
  let res = Identity.fromJson(node)
  assertOk res
  let ident = res.get()
  assertEq $ident.id, "id1"
  assertEq ident.name, "Joe Bloggs"
  assertEq ident.email, "joe@example.com"
  assertSome ident.replyTo
  assertLen ident.replyTo.get(), 1
  assertEq ident.replyTo.get()[0].email, "alice@example.com"
  assertSomeEq ident.replyTo.get()[0].name, "Alice"
  assertSome ident.bcc
  assertLen ident.bcc.get(), 1
  assertEq ident.bcc.get()[0].email, "bob@example.com"
  assertEq ident.textSignature, "-- Joe"
  assertEq ident.htmlSignature, "<p>Joe</p>"
  assertEq ident.mayDelete, true

testCase fromJsonDefaults: # scenario 25
  let node = %*{"id": "id1", "email": "joe@example.com", "mayDelete": false}
  let res = Identity.fromJson(node)
  assertOk res
  let ident = res.get()
  assertEq ident.name, ""
  assertNone ident.replyTo
  assertNone ident.bcc
  assertEq ident.textSignature, ""
  assertEq ident.htmlSignature, ""

testCase fromJsonNameAbsent: # scenario 26
  let node = %*{"id": "id1", "email": "j@e.c", "mayDelete": false, "textSignature": "x"}
  let res = Identity.fromJson(node)
  assertOk res
  assertEq res.get().name, ""

testCase fromJsonTextSignatureAbsent: # scenario 27
  let node = %*{"id": "id1", "email": "j@e.c", "mayDelete": false, "name": "J"}
  let res = Identity.fromJson(node)
  assertOk res
  assertEq res.get().textSignature, ""

testCase fromJsonHtmlSignatureAbsent: # scenario 28
  let node = %*{"id": "id1", "email": "j@e.c", "mayDelete": false}
  let res = Identity.fromJson(node)
  assertOk res
  assertEq res.get().htmlSignature, ""

testCase fromJsonReplyToNull: # scenario 29
  let node = %*{"id": "id1", "email": "j@e.c", "mayDelete": false, "replyTo": nil}
  let res = Identity.fromJson(node)
  assertOk res
  assertNone res.get().replyTo

testCase fromJsonReplyToWithAddresses: # scenario 30
  let node = %*{
    "id": "id1",
    "email": "j@e.c",
    "mayDelete": false,
    "replyTo": [{"email": "r@e.c", "name": "R"}],
  }
  let res = Identity.fromJson(node)
  assertOk res
  assertSome res.get().replyTo
  assertLen res.get().replyTo.get(), 1
  assertEq res.get().replyTo.get()[0].email, "r@e.c"

# ============= B. Identity round-trip =============

testCase roundTripFull: # scenario 31
  let ident = Identity(
    id: parseIdFromServer("id1").get(),
    name: "Joe",
    email: "joe@example.com",
    replyTo: Opt.some(@[ea1]),
    bcc: Opt.some(@[ea2]),
    textSignature: "-- Joe",
    htmlSignature: "<p>Joe</p>",
    mayDelete: true,
  )
  let roundTripped = Identity.fromJson(ident.toJson()).get()
  assertEq $roundTripped.id, $ident.id
  assertEq roundTripped.name, ident.name
  assertEq roundTripped.email, ident.email
  assertEq roundTripped.textSignature, ident.textSignature
  assertEq roundTripped.htmlSignature, ident.htmlSignature
  assertEq roundTripped.mayDelete, ident.mayDelete
  assertSome roundTripped.replyTo
  assertSome roundTripped.bcc

testCase roundTripMinimal:
  let ident = Identity(
    id: parseIdFromServer("id2").get(),
    name: "",
    email: "min@e.c",
    replyTo: Opt.none(seq[EmailAddress]),
    bcc: Opt.none(seq[EmailAddress]),
    textSignature: "",
    htmlSignature: "",
    mayDelete: false,
  )
  let roundTripped = Identity.fromJson(ident.toJson()).get()
  assertEq roundTripped.name, ""
  assertEq roundTripped.email, "min@e.c"
  assertNone roundTripped.replyTo
  assertNone roundTripped.bcc
  assertEq roundTripped.textSignature, ""
  assertEq roundTripped.htmlSignature, ""

# ============= C. Identity fromJson — validation =============

testCase fromJsonEmptyEmail: # scenario 32
  ## RFC 8621 §6.1 ``Identity.email`` is a ``String`` — no MUST-non-empty
  ## constraint. Cyrus 3.12.2 emits an empty ``email`` for server-default
  ## identities (config-derived); the Postel-receive parser accepts it.
  ## Client-construction validation lives in ``parseIdentityCreate``,
  ## not in the receive parser.
  let node = %*{"id": "id1", "email": "", "mayDelete": false}
  let res = Identity.fromJson(node)
  assertOk res
  assertEq res.get().email, ""

testCase fromJsonNullEmail:
  let node = %*{"id": "id1", "email": nil, "mayDelete": false}
  assertErr Identity.fromJson(node)

testCase fromJsonMissingId:
  let node = %*{"email": "j@e.c", "mayDelete": false}
  assertErr Identity.fromJson(node)

testCase fromJsonMissingEmail:
  let node = %*{"id": "id1", "mayDelete": false}
  assertErr Identity.fromJson(node)

testCase fromJsonMissingMayDelete:
  let node = %*{"id": "id1", "email": "j@e.c"}
  assertErr Identity.fromJson(node)

testCase fromJsonNotObject:
  assertErr Identity.fromJson(%"string")
  assertErr Identity.fromJson(newJArray())

testCase fromJsonReplyToWrongType:
  let node = %*{"id": "id1", "email": "j@e.c", "mayDelete": false, "replyTo": "string"}
  assertErr Identity.fromJson(node)

testCase fromJsonNameWrongType:
  let node = %*{"id": "id1", "email": "j@e.c", "mayDelete": false, "name": 123}
  assertErr Identity.fromJson(node)

testCase fromJsonMayDeleteWrongType:
  let node = %*{"id": "id1", "email": "j@e.c", "mayDelete": "true"}
  assertErr Identity.fromJson(node)

# ============= D. Identity fromJson — nested EmailAddress validation =============

testCase fromJsonReplyToWithInvalidEmail:
  let node =
    %*{"id": "id1", "email": "j@e.c", "mayDelete": false, "replyTo": [{"email": ""}]}
  assertErr Identity.fromJson(node)

testCase fromJsonBccNull:
  let node = %*{"id": "id1", "email": "j@e.c", "mayDelete": false, "bcc": nil}
  let res = Identity.fromJson(node)
  assertOk res
  assertNone res.get().bcc

testCase fromJsonBccWithAddresses:
  let node =
    %*{"id": "id1", "email": "j@e.c", "mayDelete": false, "bcc": [{"email": "a@b.c"}]}
  let res = Identity.fromJson(node)
  assertOk res
  assertSome res.get().bcc
  assertLen res.get().bcc.get(), 1
  assertEq res.get().bcc.get()[0].email, "a@b.c"

testCase fromJsonReplyToAbsent:
  let node = %*{"id": "id1", "email": "j@e.c", "mayDelete": false}
  let res = Identity.fromJson(node)
  assertOk res
  assertNone res.get().replyTo

# ============= E. Identity toJson =============

testCase toJsonReplyToNull:
  let ident = Identity(
    id: parseIdFromServer("id1").get(),
    email: "j@e.c",
    replyTo: Opt.none(seq[EmailAddress]),
    bcc: Opt.none(seq[EmailAddress]),
    mayDelete: false,
  )
  let node = ident.toJson()
  assertJsonFieldEq node, "replyTo", newJNull()

testCase toJsonReplyToWithAddresses:
  let ident = Identity(
    id: parseIdFromServer("id1").get(),
    email: "j@e.c",
    replyTo: Opt.some(@[ea1]),
    bcc: Opt.none(seq[EmailAddress]),
    mayDelete: false,
  )
  let node = ident.toJson()
  let arr = node{"replyTo"}
  doAssert arr != nil, "replyTo field must be present"
  doAssert arr.kind == JArray, "replyTo must be JArray"
  assertLen arr.getElems(@[]), 1
  assertJsonFieldEq arr.getElems(@[])[0], "email", %"alice@example.com"

testCase toJsonBccNull:
  let ident = Identity(
    id: parseIdFromServer("id1").get(),
    email: "j@e.c",
    replyTo: Opt.none(seq[EmailAddress]),
    bcc: Opt.none(seq[EmailAddress]),
    mayDelete: false,
  )
  assertJsonFieldEq ident.toJson(), "bcc", newJNull()

testCase toJsonEmptyStringFields:
  let ident = Identity(
    id: parseIdFromServer("id1").get(),
    name: "",
    email: "j@e.c",
    replyTo: Opt.none(seq[EmailAddress]),
    bcc: Opt.none(seq[EmailAddress]),
    textSignature: "",
    htmlSignature: "",
    mayDelete: false,
  )
  let node = ident.toJson()
  assertJsonFieldEq node, "name", %""
  assertJsonFieldEq node, "textSignature", %""
  assertJsonFieldEq node, "htmlSignature", %""

# ============= F. IdentityCreate toJson =============

testCase toJsonAllFields: # scenario 36
  let ic = parseIdentityCreate(
      email = "joe@example.com",
      name = "Joe",
      replyTo = Opt.some(@[ea1]),
      bcc = Opt.some(@[ea2]),
      textSignature = "-- Joe",
      htmlSignature = "<p>Joe</p>",
    )
    .get()
  let node = ic.toJson()
  assertJsonFieldEq node, "email", %"joe@example.com"
  assertJsonFieldEq node, "name", %"Joe"
  let rt = node{"replyTo"}
  doAssert rt != nil and rt.kind == JArray
  let bc = node{"bcc"}
  doAssert bc != nil and bc.kind == JArray
  assertJsonFieldEq node, "textSignature", %"-- Joe"
  assertJsonFieldEq node, "htmlSignature", %"<p>Joe</p>"

testCase toJsonNoIdNoMayDelete: # scenario 37
  let ic = parseIdentityCreate("j@e.c").get()
  let node = ic.toJson()
  doAssert node{"id"} == nil, "IdentityCreate.toJson must not emit id"
  doAssert node{"mayDelete"} == nil, "IdentityCreate.toJson must not emit mayDelete"

testCase toJsonCreateReplyToNull:
  let ic = parseIdentityCreate("j@e.c").get()
  assertJsonFieldEq ic.toJson(), "replyTo", newJNull()

testCase toJsonCreateBccWithAddresses:
  let ic = parseIdentityCreate("j@e.c", bcc = Opt.some(@[ea2])).get()
  let node = ic.toJson()
  let arr = node{"bcc"}
  doAssert arr != nil and arr.kind == JArray
  assertLen arr.getElems(@[]), 1

testCase toJsonCreateDefaultsEmitted:
  let ic = parseIdentityCreate("j@e.c").get()
  let node = ic.toJson()
  assertJsonFieldEq node, "email", %"j@e.c"
  assertJsonFieldEq node, "name", %""
  assertJsonFieldEq node, "replyTo", newJNull()
  assertJsonFieldEq node, "bcc", newJNull()
  assertJsonFieldEq node, "textSignature", %""
  assertJsonFieldEq node, "htmlSignature", %""
