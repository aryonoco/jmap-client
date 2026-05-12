# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for IdentityUpdate, IdentityUpdateSet, and
## NonEmptyIdentityUpdates (RFC 8621 §6 update algebra). Pins the wire
## shape of ``toJson(IdentityUpdate)`` (tuple per variant) and the
## flatten pass that ``toJson(IdentityUpdateSet)`` /
## ``toJson(NonEmptyIdentityUpdates)`` run at the /set boundary.

{.push raises: [].}

import std/json

import jmap_client/internal/mail/addresses
import jmap_client/internal/mail/identity
import jmap_client/internal/mail/serde_addresses
import jmap_client/internal/mail/serde_identity_update
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation

import ../../massertions
import ../../mtestblock

# ============= A. toJson(IdentityUpdate) per-variant tuple =============

testCase setNameEmitsTuple:
  let (key, value) = setName("Alice").toJson()
  assertEq key, "name"
  assertEq value, %"Alice"

testCase setReplyToSomeEmitsArray:
  let ea = parseEmailAddress("a@example.com", Opt.none(string)).get()
  let (key, value) = setReplyTo(Opt.some(@[ea])).toJson()
  assertEq key, "replyTo"
  doAssert value.kind == JArray
  assertEq value.len, 1
  assertEq value[0], ea.toJson()

testCase setReplyToNoneEmitsNull:
  ## RFC 8621 §6 clear-to-null contract: ``Opt.none`` projects to JSON
  ## null, which the server interprets as "reset to the default".
  let (key, value) = setReplyTo(Opt.none(seq[EmailAddress])).toJson()
  assertEq key, "replyTo"
  assertEq value, newJNull()

testCase setBccSomeEmitsArray:
  let ea = parseEmailAddress("b@example.com", Opt.none(string)).get()
  let (key, value) = setBcc(Opt.some(@[ea])).toJson()
  assertEq key, "bcc"
  doAssert value.kind == JArray

testCase setTextSignatureEmitsTuple:
  let (key, value) = setTextSignature("-- Alice").toJson()
  assertEq key, "textSignature"
  assertEq value, %"-- Alice"

testCase setHtmlSignatureEmitsTuple:
  let (key, value) = setHtmlSignature("<p>Alice</p>").toJson()
  assertEq key, "htmlSignature"
  assertEq value, %"<p>Alice</p>"

# ============= B. toJson(IdentityUpdateSet) flatten =============

testCase identityUpdateSetFlattensTuple:
  let us = initIdentityUpdateSet(@[setName("Alice"), setTextSignature("sig")]).get()
  let node = us.toJson()
  doAssert node.kind == JObject
  assertLen node, 2
  assertJsonFieldEq node, "name", %"Alice"
  assertJsonFieldEq node, "textSignature", %"sig"

# ============= C. toJson(NonEmptyIdentityUpdates) envelope =============

testCase nonEmptyIdentityUpdatesEmitsPerIdObject:
  let id1 = parseId("idt1").get()
  let id2 = parseId("idt2").get()
  let us1 = initIdentityUpdateSet(@[setName("Alice")]).get()
  let us2 = initIdentityUpdateSet(@[setTextSignature("s")]).get()
  let wrap = parseNonEmptyIdentityUpdates(@[(id1, us1), (id2, us2)]).get()
  let node = wrap.toJson()
  doAssert node.kind == JObject
  assertLen node, 2
  doAssert node{$id1} != nil, "expected per-id key idt1"
  doAssert node{$id2} != nil, "expected per-id key idt2"
  assertEq node{$id1}{"name"}.getStr(), "Alice"
  assertEq node{$id2}{"textSignature"}.getStr(), "s"
