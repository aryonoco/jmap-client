# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

discard """
  action: "compile"
"""

## Compile-time smoke test for Part E (RFC 8621 Mail) public-surface
## reachability via ``import jmap_client`` (design §1.5, implementation-9
## Step 28). Every symbol listed under §1.5's module summary for Part E
## is referenced here in a way that forces the Nim compiler to resolve it
## through the top-level re-export chain:
##
##   jmap_client.nim
##     -> jmap_client/mail.nim
##         -> jmap_client/mail/types.nim
##         -> jmap_client/mail/serialisation.nim
##
## A missing ``export`` at any hop surfaces as a compile error here.
##
## ``compiles()`` is deliberately avoided: it suppresses resolution
## failures into a runtime boolean, turning a missing re-export into a
## silent runtime assertion rather than a loud compile break. Instead:
##
## - Type symbols are referenced in a ``static: doAssert declared(...)``
##   block so the check runs at compile time.
## - Functions / templates are checked the same way.
## - UFCS accessors are exercised through a ``proc _touchAccessors(bp:
##   EmailBlueprint) = discard bp.field``, which forces the compiler to
##   resolve each accessor name against a real ``EmailBlueprint`` value —
##   the same path consumers will take.
##
## The file is marked ``action: "compile"`` so testament treats it as a
## pure compile-check; there is no meaningful runtime behaviour to run.

{.push raises: [].}

import std/json

import jmap_client

# -----------------------------------------------------------------------------
# email_blueprint.nim (§3.1–§3.5) — types, constructors, factories.
# -----------------------------------------------------------------------------

static:
  doAssert declared(EmailBlueprint)
  doAssert declared(EmailBlueprintBody)
  doAssert declared(EmailBodyKind)
  doAssert declared(EmailBlueprintConstraint)
  doAssert declared(EmailBlueprintError)
  doAssert declared(EmailBlueprintErrors)
  doAssert declared(BodyPartPath)
  doAssert declared(BodyPartLocation)
  doAssert declared(BodyPartLocationKind)
  doAssert declared(parseEmailBlueprint)
  doAssert declared(flatBody)
  doAssert declared(structuredBody)

proc touchEmailBlueprintAccessors(bp: EmailBlueprint) {.used.} =
  ## Exercises every UFCS accessor enumerated in implementation-9 Step 28.
  ## A missing re-export for any of these would fail to resolve here.
  ## Note: the design-doc accessor spelled "headers" is named
  ## ``extraHeaders`` in the implementation (email_blueprint.nim:722).
  discard bp.mailboxIds
  discard bp.body
  discard bp.fromAddr
  discard bp.subject
  discard bp.to
  discard bp.cc
  discard bp.bcc
  discard bp.replyTo
  discard bp.sender
  discard bp.messageId
  discard bp.inReplyTo
  discard bp.references
  discard bp.receivedAt
  discard bp.keywords
  discard bp.extraHeaders
  discard bp.bodyValues
  discard bp.sentAt
  discard bp.bodyKind

# -----------------------------------------------------------------------------
# serde_email_blueprint.nim — ``toJson`` for EmailBlueprint.
# -----------------------------------------------------------------------------

proc touchEmailBlueprintSerde(bp: EmailBlueprint): JsonNode {.used.} =
  ## Forces ``toJson(EmailBlueprint)`` to resolve through the
  ## serde re-export hub.
  bp.toJson

# -----------------------------------------------------------------------------
# mailbox.nim (§4.2) — NonEmptyMailboxIdSet.
# -----------------------------------------------------------------------------

static:
  doAssert declared(NonEmptyMailboxIdSet)
  doAssert declared(parseNonEmptyMailboxIdSet)

# -----------------------------------------------------------------------------
# headers.nim (§4.3–§4.5) — creation-model header vocabulary.
# -----------------------------------------------------------------------------

static:
  doAssert declared(BlueprintEmailHeaderName)
  doAssert declared(BlueprintBodyHeaderName)
  doAssert declared(BlueprintHeaderMultiValue)
  doAssert declared(parseBlueprintEmailHeaderName)
  doAssert declared(parseBlueprintBodyHeaderName)
  # Seven form-specific helper constructors per §4.5.2.
  doAssert declared(rawMulti)
  doAssert declared(textMulti)
  doAssert declared(addressesMulti)
  doAssert declared(groupedAddressesMulti)
  doAssert declared(messageIdsMulti)
  doAssert declared(dateMulti)
    # Implemented name (singular); plan doc calls it ``datesMulti``.
  doAssert declared(urlsMulti)

# -----------------------------------------------------------------------------
# primitives.nim (§4.6) — NonEmptySeq[T], parseNonEmptySeq[T],
# defineSealedNonEmptySeqOps template.
# -----------------------------------------------------------------------------

static:
  doAssert declared(NonEmptySeq)
  doAssert declared(parseNonEmptySeq)
  doAssert declared(defineSealedNonEmptySeqOps)

proc touchNonEmptySeqInstantiation(xs: NonEmptySeq[string]) {.used.} =
  ## Proves the generic type instantiates through the re-export chain;
  ## the parameter type fails to resolve if ``NonEmptySeq`` didn't come
  ## through the hub.
  discard xs

# -----------------------------------------------------------------------------
# body.nim (§4.1) — BlueprintBodyValue.
# -----------------------------------------------------------------------------

static:
  doAssert declared(BlueprintBodyValue)
