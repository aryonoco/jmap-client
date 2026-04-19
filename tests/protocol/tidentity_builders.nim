# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Protocol wire tests for the Identity builders. First-ever contract on
## the Identity/get, Identity/changes, and Identity/set wire shape —
## prior to this file, only the L2 serde of the Identity read model was
## pinned. The three wire-anchor blocks here guard against regressions
## in method-name routing, capability URI emission, and /set argument
## shape.

{.push raises: [].}

import std/json
import std/tables

import jmap_client/types
import jmap_client/builder
import jmap_client/methods_enum
import jmap_client/mail/identity
import jmap_client/mail/identity_builders

import ../massertions
import ../mfixtures

# ===========================================================================
# A. addIdentityGet / addIdentityChanges wire routing
# ===========================================================================

block addIdentityGetRoutesToIdentityGet:
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addIdentityGet(makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnIdentityGet
  doAssert "urn:ietf:params:jmap:submission" in req.`using`

block addIdentityChangesRoutesToIdentityChanges:
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addIdentityChanges(makeAccountId("a1"), makeState("s0"))
  let req = b1.build()
  assertEq req.methodCalls[0].name, mnIdentityChanges

# ===========================================================================
# B. addIdentitySet create-only wire anchor (RFC 8621 §6.3)
# ===========================================================================

block addIdentitySetCreateOnlyEmitsSixFields:
  ## ``IdentityCreate`` has six serialised fields: email, name, replyTo,
  ## bcc, textSignature, htmlSignature. The server-set ``id`` and
  ## ``mayDelete`` are deliberately absent.
  let ic = parseIdentityCreate("alice@example.com", name = "Alice").get()
  var tbl = initTable[CreationId, IdentityCreate]()
  tbl[makeCreationId("k0")] = ic
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addIdentitySet(makeAccountId("a1"), create = Opt.some(tbl))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnIdentitySet
  doAssert "urn:ietf:params:jmap:submission" in req.`using`
  let args = req.methodCalls[0].arguments
  let createObj = args{"create"}
  doAssert createObj != nil and createObj.kind == JObject
  let k0 = createObj{"k0"}
  doAssert k0.kind == JObject
  assertLen k0, 6
  assertEq k0{"email"}.getStr(""), "alice@example.com"
  assertEq k0{"name"}.getStr(""), "Alice"

# ===========================================================================
# C. addIdentitySet update wire anchor
# ===========================================================================

block addIdentitySetUpdateEmitsPerIdPatches:
  let id1 = parseId("idt1").get()
  let id2 = parseId("idt2").get()
  let us1 = initIdentityUpdateSet(@[setName("Alice")]).get()
  let us2 = initIdentityUpdateSet(@[setTextSignature("sig")]).get()
  let wrap = parseNonEmptyIdentityUpdates(@[(id1, us1), (id2, us2)]).get()
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addIdentitySet(makeAccountId("a1"), update = Opt.some(wrap))
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  let updObj = args{"update"}
  doAssert updObj != nil and updObj.kind == JObject
  assertLen updObj, 2
  assertEq updObj{$id1}{"name"}.getStr(""), "Alice"
  assertEq updObj{$id2}{"textSignature"}.getStr(""), "sig"
  assertJsonKeyAbsent args, "create"
  assertJsonKeyAbsent args, "destroy"

# ===========================================================================
# D. addIdentitySet destroy wire anchor
# ===========================================================================

block addIdentitySetDestroyEmitsIdArray:
  let id1 = parseId("idt1").get()
  let id2 = parseId("idt2").get()
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addIdentitySet(makeAccountId("a1"), destroy = directIds(@[id1, id2]))
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  let destroyArr = args{"destroy"}
  doAssert destroyArr != nil and destroyArr.kind == JArray
  assertLen destroyArr, 2
  assertEq destroyArr[0].getStr(""), $id1
  assertEq destroyArr[1].getStr(""), $id2
  assertJsonKeyAbsent args, "create"
  assertJsonKeyAbsent args, "update"
