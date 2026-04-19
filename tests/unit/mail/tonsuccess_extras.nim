# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit + serde tests for NonEmptyOnSuccessUpdateEmail and
## NonEmptyOnSuccessDestroyEmail (RFC 8621 §7.5 ¶3 compound extras).
## Empty/duplicate rejection contracts mirror the existing NonEmpty*
## smart constructors; the arm-distinctness block pins the
## ``IdOrCreationRef`` arm-dispatched ``==`` / ``hash`` behaviour that
## duplicate detection depends on. Serde blocks lock the wire shape of
## ``toJson`` on both distinct types.

{.push raises: [].}

import std/json

import jmap_client/identifiers
import jmap_client/primitives
import jmap_client/validation
import jmap_client/mail/email_submission
import jmap_client/mail/email_update
import jmap_client/mail/serde_email_submission

import ../../massertions

# ============= A. Empty rejection =============

block parseNonEmptyOnSuccessUpdateEmailRejectsEmpty:
  let res =
    parseNonEmptyOnSuccessUpdateEmail(newSeq[(IdOrCreationRef, EmailUpdateSet)]())
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "NonEmptyOnSuccessUpdateEmail"
  assertEq res.error[0].message, "must contain at least one entry"

block parseNonEmptyOnSuccessDestroyEmailRejectsEmpty:
  let res = parseNonEmptyOnSuccessDestroyEmail(newSeq[IdOrCreationRef]())
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "NonEmptyOnSuccessDestroyEmail"
  assertEq res.error[0].message, "must contain at least one entry"

# ============= B. Duplicate rejection =============

block parseNonEmptyOnSuccessUpdateEmailRejectsDuplicateKey:
  let k = directRef(parseId("m-abc").get())
  let us = initEmailUpdateSet(@[markRead()]).get()
  let res = parseNonEmptyOnSuccessUpdateEmail(@[(k, us), (k, us)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].message, "duplicate id or creation reference"

block parseNonEmptyOnSuccessDestroyEmailRejectsDuplicateElement:
  let r = directRef(parseId("m-abc").get())
  let res = parseNonEmptyOnSuccessDestroyEmail(@[r, r])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].message, "duplicate id or creation reference"

# ============= C. Arm-distinctness — directRef vs creationRef =============

block parseNonEmptyOnSuccessUpdateEmailAcceptsArmDistinctSamePayload:
  ## ``IdOrCreationRef`` ``==`` / ``hash`` mix in the discriminator
  ## ordinal, so ``directRef(Id("x"))`` and ``creationRef(CreationId("x"))``
  ## hash into different buckets and compare unequal. This block pins
  ## that contract — regression would make them collide in the Table
  ## and surface as a spurious "duplicate id or creation reference"
  ## error here.
  let kDirect = directRef(parseId("x").get())
  let kCreation = creationRef(parseCreationId("x").get())
  let us = initEmailUpdateSet(@[markRead()]).get()
  let res = parseNonEmptyOnSuccessUpdateEmail(@[(kDirect, us), (kCreation, us)])
  assertOk res

block parseNonEmptyOnSuccessDestroyEmailAcceptsArmDistinctSamePayload:
  let rDirect = directRef(parseId("x").get())
  let rCreation = creationRef(parseCreationId("x").get())
  let res = parseNonEmptyOnSuccessDestroyEmail(@[rDirect, rCreation])
  assertOk res

# ============= D. Happy path single entry =============

block parseNonEmptyOnSuccessUpdateEmailHappyPath:
  let k = directRef(parseId("m-1").get())
  let us = initEmailUpdateSet(@[markRead()]).get()
  assertOk parseNonEmptyOnSuccessUpdateEmail(@[(k, us)])

block parseNonEmptyOnSuccessDestroyEmailHappyPath:
  let r = directRef(parseId("m-1").get())
  assertOk parseNonEmptyOnSuccessDestroyEmail(@[r])

# ============= E. Serde — NonEmptyOnSuccessUpdateEmail wire shape =========

block toJsonNonEmptyOnSuccessUpdateEmailDirectKey:
  ## Direct-id key on the wire is the Id verbatim; the patch subtree
  ## matches what ``EmailUpdateSet.toJson`` would emit directly.
  let k = directRef(parseId("m-1").get())
  let us = initEmailUpdateSet(@[markRead()]).get()
  let v = parseNonEmptyOnSuccessUpdateEmail(@[(k, us)]).get()
  let node = v.toJson()
  doAssert node.kind == JObject
  assertLen node, 1
  doAssert node{"m-1"} != nil, "expected direct-id key 'm-1'"
  assertEq node{"m-1"}{"keywords/$seen"}, newJBool(true)

block toJsonNonEmptyOnSuccessUpdateEmailCreationKey:
  ## Creation-id key on the wire gets a ``#`` prefix per RFC 8620 §5.3.
  let k = creationRef(parseCreationId("c-1").get())
  let us = initEmailUpdateSet(@[markRead()]).get()
  let v = parseNonEmptyOnSuccessUpdateEmail(@[(k, us)]).get()
  let node = v.toJson()
  doAssert node{"#c-1"} != nil, "expected creation-ref key '#c-1'"

# ============= F. Serde — NonEmptyOnSuccessDestroyEmail wire shape ========

block toJsonNonEmptyOnSuccessDestroyEmailEmitsWireKeyArray:
  let rDirect = directRef(parseId("m-1").get())
  let rCreation = creationRef(parseCreationId("c-1").get())
  let v = parseNonEmptyOnSuccessDestroyEmail(@[rDirect, rCreation]).get()
  let node = v.toJson()
  doAssert node.kind == JArray
  assertLen node, 2
  assertEq node[0].getStr(""), "m-1"
  assertEq node[1].getStr(""), "#c-1"
