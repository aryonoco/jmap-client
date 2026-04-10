# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Entity registration tests for Thread, Identity, and Mailbox (RFC 8621
## sections 2, 3, 6). Covers design doc scenarios 68–71, builder
## integration, mixin resolution for queryable entities, negative
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
import jmap_client/mail/mailbox
import jmap_client/mail/mail_filters
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
  let b0 = initRequestBuilder()
  assertNotCompiles(addGet[VacationResponse](b0, makeAccountId()))

block vacationResponseGenericChangesBlocked:
  ## Generic addChanges must not compile for VacationResponse.
  let b0 = initRequestBuilder()
  assertNotCompiles(addChanges[VacationResponse](b0, makeAccountId(), makeState()))

block vacationResponseGenericSetBlocked:
  ## Generic addSet must not compile for VacationResponse.
  let b0 = initRequestBuilder()
  assertNotCompiles(addSet[VacationResponse](b0, makeAccountId()))

# ===========================================================================
# C. Builder integration tests
# ===========================================================================

block addGetThread:
  ## addGet[thread.Thread] produces "Thread/get" with correct capability and accountId.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[thread.Thread](b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "Thread/get"
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  doAssert "urn:ietf:params:jmap:mail" in req.`using`

block addChangesThread:
  ## addChanges[thread.Thread] produces "Thread/changes" with sinceState in args.
  let b0 = initRequestBuilder()
  let (b1, _) = addChanges[thread.Thread](b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "Thread/changes"
  assertEq inv.arguments{"sinceState"}.getStr(""), "s0"

block addGetIdentity:
  ## addGet[Identity] produces "Identity/get" with submission capability.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[Identity](b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "Identity/get"
  doAssert "urn:ietf:params:jmap:submission" in req.`using`

block addChangesIdentity:
  ## addChanges[Identity] produces "Identity/changes".
  let b0 = initRequestBuilder()
  let (b1, _) = addChanges[Identity](b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "Identity/changes"

block addSetIdentity:
  ## addSet[Identity] produces "Identity/set".
  let b0 = initRequestBuilder()
  let (b1, _) = addSet[Identity](b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "Identity/set"

# ===========================================================================
# D. Capability deduplication
# ===========================================================================

block capabilityDedupThread:
  ## Two addGet[thread.Thread] calls register the mail capability only once.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[thread.Thread](b0, makeAccountId())
  let (b2, _) = addGet[thread.Thread](b1, makeAccountId())
  let caps = b2.capabilities
  assertLen caps, 1
  assertEq caps[0], "urn:ietf:params:jmap:mail"

block multipleEntityCapabilities:
  ## addGet[thread.Thread] + addGet[Identity] produces both capability URIs.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[thread.Thread](b0, makeAccountId())
  let (b2, _) = addGet[Identity](b1, makeAccountId())
  let caps = b2.capabilities
  assertLen caps, 2
  doAssert "urn:ietf:params:jmap:mail" in caps
  doAssert "urn:ietf:params:jmap:submission" in caps

# ===========================================================================
# E. Mailbox registration tests (scenarios 68-69)
# ===========================================================================

block mailboxRegistrationCompiles:
  ## Scenario 68: Mailbox registers with registerJmapEntity — implicit pass.
  doAssert true

block mailboxQueryableRegistrationCompiles:
  ## Scenario 69: Mailbox registers with registerQueryableEntity — implicit pass.
  doAssert true

block mailboxOverloadValues:
  ## methodNamespace and capabilityUri return expected values for Mailbox.
  assertEq methodNamespace(Mailbox), "Mailbox"
  assertEq capabilityUri(Mailbox), "urn:ietf:params:jmap:mail"

# ===========================================================================
# F. Mailbox generic builder integration
# ===========================================================================

block addGetMailbox:
  ## addGet[Mailbox] produces "Mailbox/get" with mail capability.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[Mailbox](b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, "Mailbox/get"
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  doAssert "urn:ietf:params:jmap:mail" in req.`using`

block addChangesMailbox:
  ## addChanges[Mailbox] produces "Mailbox/changes".
  let b0 = initRequestBuilder()
  let (b1, _) = addChanges[Mailbox](b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "Mailbox/changes"
  assertEq req.methodCalls[0].arguments{"sinceState"}.getStr(""), "s0"

block addSetMailbox:
  ## addSet[Mailbox] produces "Mailbox/set".
  let b0 = initRequestBuilder()
  let (b1, _) = addSet[Mailbox](b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "Mailbox/set"

# ===========================================================================
# G. Mixin resolution tests (critical — proves filterType + filterConditionToJson resolve)
# ===========================================================================

block addQueryMailboxSingleParam:
  ## Single-parameter addQuery[Mailbox] resolves via mixin. This test
  ## compiling IS the proof that mixin resolution works for filterType
  ## and filterConditionToJson.
  let b0 = initRequestBuilder()
  let (b1, _) = addQuery[Mailbox](b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "Mailbox/query"

block addQueryChangesMailboxSingleParam:
  ## Single-parameter addQueryChanges[Mailbox] resolves via mixin.
  let b0 = initRequestBuilder()
  let (b1, _) = addQueryChanges[Mailbox](b0, makeAccountId("a1"), makeState("qs0"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "Mailbox/queryChanges"

# ===========================================================================
# H. Mailbox capability deduplication
# ===========================================================================

block mailboxCapabilityDedup:
  ## Thread + Mailbox both register "urn:ietf:params:jmap:mail"; verify
  ## the builder deduplicates to exactly one entry.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[thread.Thread](b0, makeAccountId())
  let (b2, _) = addGet[Mailbox](b1, makeAccountId())
  let caps = b2.capabilities
  assertLen caps, 1
  assertEq caps[0], "urn:ietf:params:jmap:mail"
