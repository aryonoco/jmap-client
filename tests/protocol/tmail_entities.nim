# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Entity registration tests for Thread and Identity (RFC 8621 sections 3, 6).
## Covers design doc scenarios 70–71, builder integration, negative
## compile-time safety for VacationResponse (Decision A7), and capability
## deduplication.

{.push raises: [].}

import std/json
import std/tables

import jmap_client/types
import jmap_client/serialisation
import jmap_client/entity
import jmap_client/methods
import jmap_client/dispatch
import jmap_client/builder
import jmap_client/mail/thread
import jmap_client/mail/identity
import jmap_client/mail/vacation
import jmap_client/mail/mail_entities

import ../massertions
import ../mfixtures

# ===========================================================================
# A. Positive registration tests
# ===========================================================================

block threadRegistrationCompiles:
  ## Scenario 70: Thread registers with registerJmapEntity — implicit pass.
  doAssert true

block identityRegistrationCompiles:
  ## Scenario 71: Identity registers with registerJmapEntity — implicit pass.
  doAssert true

block threadOverloadValues:
  ## methodNamespace and capabilityUri return expected values for Thread.
  assertEq methodNamespace(thread.Thread), "Thread"
  assertEq capabilityUri(thread.Thread), "urn:ietf:params:jmap:mail"

block identityOverloadValues:
  ## methodNamespace and capabilityUri return expected values for Identity.
  assertEq methodNamespace(Identity), "Identity"
  assertEq capabilityUri(Identity), "urn:ietf:params:jmap:submission"

# ===========================================================================
# B. Negative compile-time tests (Decision A7)
# ===========================================================================

block vacationResponseNotRegisterable:
  ## VacationResponse has no framework overloads — registration must fail.
  assertNotCompiles(registerJmapEntity(VacationResponse))

block vacationResponseGenericGetBlocked:
  ## Generic addGet must not compile for VacationResponse.
  var b = initRequestBuilder()
  assertNotCompiles(addGet[VacationResponse](b, makeAccountId()))

block vacationResponseGenericChangesBlocked:
  ## Generic addChanges must not compile for VacationResponse.
  var b = initRequestBuilder()
  assertNotCompiles(addChanges[VacationResponse](b, makeAccountId(), makeState()))

block vacationResponseGenericSetBlocked:
  ## Generic addSet must not compile for VacationResponse.
  var b = initRequestBuilder()
  assertNotCompiles(addSet[VacationResponse](b, makeAccountId()))

# ===========================================================================
# C. Builder integration tests
# ===========================================================================

block addGetThread:
  ## addGet[thread.Thread] produces "Thread/get" with correct capability and accountId.
  var b = initRequestBuilder()
  discard addGet[thread.Thread](b, makeAccountId("a1"))
  let req = b.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "Thread/get"
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  doAssert "urn:ietf:params:jmap:mail" in req.`using`

block addChangesThread:
  ## addChanges[thread.Thread] produces "Thread/changes" with sinceState in args.
  var b = initRequestBuilder()
  discard addChanges[thread.Thread](b, makeAccountId("a1"), makeState("s0"))
  let req = b.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "Thread/changes"
  assertEq inv.arguments{"sinceState"}.getStr(""), "s0"

block addGetIdentity:
  ## addGet[Identity] produces "Identity/get" with submission capability.
  var b = initRequestBuilder()
  discard addGet[Identity](b, makeAccountId("a1"))
  let req = b.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "Identity/get"
  doAssert "urn:ietf:params:jmap:submission" in req.`using`

block addChangesIdentity:
  ## addChanges[Identity] produces "Identity/changes".
  var b = initRequestBuilder()
  discard addChanges[Identity](b, makeAccountId("a1"), makeState("s0"))
  let req = b.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "Identity/changes"

block addSetIdentity:
  ## addSet[Identity] produces "Identity/set".
  var b = initRequestBuilder()
  discard addSet[Identity](b, makeAccountId("a1"))
  let req = b.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "Identity/set"

# ===========================================================================
# D. Capability deduplication
# ===========================================================================

block capabilityDedupThread:
  ## Two addGet[thread.Thread] calls register the mail capability only once.
  var b = initRequestBuilder()
  discard addGet[thread.Thread](b, makeAccountId())
  discard addGet[thread.Thread](b, makeAccountId())
  let caps = b.capabilities
  assertLen caps, 1
  assertEq caps[0], "urn:ietf:params:jmap:mail"

block multipleEntityCapabilities:
  ## addGet[thread.Thread] + addGet[Identity] produces both capability URIs.
  var b = initRequestBuilder()
  discard addGet[thread.Thread](b, makeAccountId())
  discard addGet[Identity](b, makeAccountId())
  let caps = b.capabilities
  assertLen caps, 2
  doAssert "urn:ietf:params:jmap:mail" in caps
  doAssert "urn:ietf:params:jmap:submission" in caps
