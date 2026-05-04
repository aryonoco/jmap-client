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
import jmap_client/mail/email
import jmap_client/mail/mail_filters
import jmap_client/mail/serde_mail_filters
import jmap_client/mail/mail_entities
import jmap_client/mail/mail_builders
import jmap_client/mail/email_submission
import jmap_client/mail/serde_email_submission

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
  ## methodEntity and capabilityUri return expected values for Thread.
  assertEq methodEntity(thread.Thread), meThread
  assertEq capabilityUri(thread.Thread), "urn:ietf:params:jmap:mail"

block identityOverloadValues:
  ## methodEntity and capabilityUri return expected values for Identity.
  assertEq methodEntity(Identity), meIdentity
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
  assertEq inv.name, mnThreadGet
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  doAssert "urn:ietf:params:jmap:mail" in req.`using`

block addChangesThread:
  ## addChanges[thread.Thread] produces "Thread/changes" with sinceState in args.
  let b0 = initRequestBuilder()
  let (b1, _) = addChanges[thread.Thread](b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, mnThreadChanges
  assertEq inv.arguments{"sinceState"}.getStr(""), "s0"

block addGetIdentity:
  ## addGet[Identity] produces "Identity/get" with submission capability.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[Identity](b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, mnIdentityGet
  doAssert "urn:ietf:params:jmap:submission" in req.`using`

block addChangesIdentity:
  ## addChanges[Identity] produces "Identity/changes".
  let b0 = initRequestBuilder()
  let (b1, _) = addChanges[Identity](b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnIdentityChanges

# ===========================================================================
# D. Capability deduplication
# ===========================================================================

block capabilityDedupThread:
  ## Two addGet[thread.Thread] calls register the mail capability only
  ## once. ``urn:ietf:params:jmap:core`` is pre-declared by
  ## ``initRequestBuilder`` (RFC 8620 §3.2), so the resulting set carries
  ## both core and mail.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[thread.Thread](b0, makeAccountId())
  let (b2, _) = addGet[thread.Thread](b1, makeAccountId())
  let caps = b2.capabilities
  assertLen caps, 2
  doAssert "urn:ietf:params:jmap:core" in caps
  doAssert "urn:ietf:params:jmap:mail" in caps

block multipleEntityCapabilities:
  ## addGet[thread.Thread] + addGet[Identity] produces both entity
  ## capability URIs alongside the pre-declared core URI.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[thread.Thread](b0, makeAccountId())
  let (b2, _) = addGet[Identity](b1, makeAccountId())
  let caps = b2.capabilities
  assertLen caps, 3
  doAssert "urn:ietf:params:jmap:core" in caps
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
  ## methodEntity and capabilityUri return expected values for Mailbox.
  assertEq methodEntity(Mailbox), meMailbox
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
  assertEq inv.name, mnMailboxGet
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  doAssert "urn:ietf:params:jmap:mail" in req.`using`

block addChangesMailbox:
  ## addChanges[Mailbox] produces "Mailbox/changes".
  let b0 = initRequestBuilder()
  let (b1, _) = addChanges[Mailbox](b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnMailboxChanges
  assertEq req.methodCalls[0].arguments{"sinceState"}.getStr(""), "s0"

block addMailboxSetMethodName:
  ## addMailboxSet produces "Mailbox/set".
  let b0 = initRequestBuilder()
  let (b1, _) = addMailboxSet(b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnMailboxSet

# ===========================================================================
# G. Mixin resolution tests (critical — proves filterType + toJson resolve)
# ===========================================================================

block addQueryMailboxSingleParam:
  ## Single-parameter addQuery[Mailbox] resolves via mixin. This test
  ## compiling IS the proof that mixin resolution works for ``filterType``
  ## (template returning ``typedesc``) and the leaf condition's ``toJson``
  ## (called via ``Filter[C].toJson``'s own ``mixin toJson``).
  let b0 = initRequestBuilder()
  let (b1, _) = addQuery[Mailbox](b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnMailboxQuery

block addQueryChangesMailboxSingleParam:
  ## Single-parameter addQueryChanges[Mailbox] resolves via mixin.
  let b0 = initRequestBuilder()
  let (b1, _) = addQueryChanges[Mailbox](b0, makeAccountId("a1"), makeState("qs0"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnMailboxQueryChanges

# ===========================================================================
# H. Mailbox capability deduplication
# ===========================================================================

block mailboxCapabilityDedup:
  ## Thread + Mailbox both register "urn:ietf:params:jmap:mail"; verify
  ## the builder deduplicates to exactly one mail entry, while the
  ## pre-declared core URI remains alongside it.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[thread.Thread](b0, makeAccountId())
  let (b2, _) = addGet[Mailbox](b1, makeAccountId())
  let caps = b2.capabilities
  assertLen caps, 2
  doAssert "urn:ietf:params:jmap:core" in caps
  doAssert "urn:ietf:params:jmap:mail" in caps

# ===========================================================================
# I. Email registration tests
# ===========================================================================

block emailRegistrationCompiles:
  ## Email registers with registerJmapEntity — implicit pass.
  doAssert true

block emailQueryableRegistrationCompiles:
  ## Email registers with registerQueryableEntity — implicit pass.
  doAssert true

block emailOverloadValues:
  ## methodEntity and capabilityUri return expected values for Email.
  assertEq methodEntity(Email), meEmail
  assertEq capabilityUri(Email), "urn:ietf:params:jmap:mail"

# ===========================================================================
# J. Email generic builder integration
# ===========================================================================

block addGetEmail:
  ## addGet[Email] produces "Email/get" with correct accountId and capability.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[Email](b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, mnEmailGet
  assertEq inv.arguments{"accountId"}.getStr(""), "a1"
  doAssert "urn:ietf:params:jmap:mail" in req.`using`

block addChangesEmail:
  ## addChanges[Email] produces "Email/changes" with sinceState (D17).
  let b0 = initRequestBuilder()
  let (b1, _) = addChanges[Email](b0, makeAccountId("a1"), makeState("s0"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  let inv = req.methodCalls[0]
  assertEq inv.name, mnEmailChanges
  assertEq inv.arguments{"sinceState"}.getStr(""), "s0"

block addEmailSetMethodName:
  ## addEmailSet produces "Email/set".
  let b0 = initRequestBuilder()
  let (b1, _) = addEmailSet(b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnEmailSet

# ===========================================================================
# K. Email mixin resolution tests
# ===========================================================================

block addQueryEmailSingleParam:
  ## Single-parameter addQuery[Email] resolves via mixin — produces "Email/query".
  let b0 = initRequestBuilder()
  let (b1, _) = addQuery[Email](b0, makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnEmailQuery

block addQueryChangesEmailSingleParam:
  ## Single-parameter addQueryChanges[Email] resolves via mixin.
  let b0 = initRequestBuilder()
  let (b1, _) = addQueryChanges[Email](b0, makeAccountId("a1"), makeState("qs0"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnEmailQueryChanges

# ===========================================================================
# L. Email capability deduplication
# ===========================================================================

block emailThreadCapabilityDedup:
  ## Thread + Email both register "urn:ietf:params:jmap:mail"; verify
  ## the builder deduplicates to exactly one mail entry, with core
  ## pre-declared alongside.
  let b0 = initRequestBuilder()
  let (b1, _) = addGet[thread.Thread](b0, makeAccountId())
  let (b2, _) = addGet[Email](b1, makeAccountId())
  let caps = b2.capabilities
  assertLen caps, 2
  doAssert "urn:ietf:params:jmap:core" in caps
  doAssert "urn:ietf:params:jmap:mail" in caps

# ===========================================================================
# M. EmailSubmission entity registration (G2 §8.4)
# ===========================================================================

block emailSubmissionEntityRegisteredWithSubmissionCapability:
  ## G2 §8.4: anchor the ``AnyEmailSubmission`` registration surface — entity
  ## tag, capability URI, and every ``EmailSubmission/*`` method name — plus
  ## a smoke probe that ``toJson(EmailSubmissionFilterCondition)`` resolves.
  ## Mirrors ``mailboxOverloadValues`` / ``emailOverloadValues`` /
  ## ``identityOverloadValues`` above. The phantom-indexed ``EmailSubmission[S]``
  ## cannot serve as a typedesc argument (G2/G3), so registration is keyed on
  ## the existential wrapper ``AnyEmailSubmission`` per mail_entities.nim:291.
  assertEq methodEntity(AnyEmailSubmission), meEmailSubmission
  assertEq capabilityUri(AnyEmailSubmission), "urn:ietf:params:jmap:submission"
  assertEq getMethodName(AnyEmailSubmission), mnEmailSubmissionGet
  assertEq changesMethodName(AnyEmailSubmission), mnEmailSubmissionChanges
  assertEq setMethodName(AnyEmailSubmission), mnEmailSubmissionSet
  assertEq queryMethodName(AnyEmailSubmission), mnEmailSubmissionQuery
  assertEq queryChangesMethodName(AnyEmailSubmission), mnEmailSubmissionQueryChanges

  # toJson(EmailSubmissionFilterCondition) surface — all fields Opt.none
  # serialises to `{}`; we only pin that the call resolves and produces a
  # JSON object (actual sparse-emission semantics are pinned in
  # tserde_email_submission.nim `filterConditionAllFieldsPopulated`).
  let filter = EmailSubmissionFilterCondition()
  let jn = filter.toJson()
  doAssert jn.kind == JObject
