# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Entity registration for Thread, Identity, Mailbox, and Email (RFC 8621
## sections 2, 3, 4, 6). VacationResponse and SearchSnippet are deliberately
## NOT registered (Decision A7) — they use custom builder functions in
## ``mail_methods`` instead, keyed directly on the relevant ``MethodName``
## enum variants.
##
## **Per-verb resolvers.** Each entity exposes one ``methodEntity`` tag plus
## one ``<verb>MethodName`` overload per supported verb. Invalid combinations
## (e.g. ``setMethodName(typedesc[Thread])``) fail at the call site with an
## undeclared-identifier compile error instead of at the server.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/json

import ../entity
import ../methods
import ../methods_enum
import ./thread
import ./identity
import ./mailbox
import ./mailbox_changes_response
import ./email
import ./email_update
import ./email_blueprint
import ./email_submission
import ./serde_email_submission
import ./mail_filters
import ./serde_mail_filters
import ../dispatch

# ---------------------------------------------------------------------------
# Thread (RFC 8621 section 3) — supports /get, /changes
# ---------------------------------------------------------------------------

func methodEntity*(T: typedesc[thread.Thread]): MethodEntity =
  ## Entity tag for Thread.
  discard $T # consumed for nimalyzer params rule
  meThread

func getMethodName*(T: typedesc[thread.Thread]): MethodName =
  ## Thread/get method name.
  discard $T
  mnThreadGet

func changesMethodName*(T: typedesc[thread.Thread]): MethodName =
  ## Thread/changes method name.
  discard $T
  mnThreadChanges

func capabilityUri*(T: typedesc[thread.Thread]): string =
  ## Capability URI for Thread methods.
  discard $T
  "urn:ietf:params:jmap:mail"

template changesResponseType*(T: typedesc[thread.Thread]): typedesc =
  ## Associated /changes response type for Thread — the standard
  ## generic ``ChangesResponse[Thread]``.
  discard $T
  ChangesResponse[thread.Thread]

registerJmapEntity(thread.Thread)

# ---------------------------------------------------------------------------
# Identity (RFC 8621 section 6) — supports /get, /changes, /set
# ---------------------------------------------------------------------------

func methodEntity*(T: typedesc[Identity]): MethodEntity =
  ## Entity tag for Identity.
  discard $T
  meIdentity

func getMethodName*(T: typedesc[Identity]): MethodName =
  ## Identity/get method name.
  discard $T
  mnIdentityGet

func changesMethodName*(T: typedesc[Identity]): MethodName =
  ## Identity/changes method name.
  discard $T
  mnIdentityChanges

func setMethodName*(T: typedesc[Identity]): MethodName =
  ## Identity/set method name.
  discard $T
  mnIdentitySet

func capabilityUri*(T: typedesc[Identity]): string =
  ## Capability URI for Identity methods.
  discard $T
  "urn:ietf:params:jmap:submission"

template changesResponseType*(T: typedesc[Identity]): typedesc =
  ## Associated /changes response type for Identity — the standard
  ## generic ``ChangesResponse[Identity]``.
  discard $T
  ChangesResponse[Identity]

template createType*(T: typedesc[Identity]): typedesc =
  ## Associated typed create-value type for Identity/set.
  discard $T
  IdentityCreate

template updateType*(T: typedesc[Identity]): typedesc =
  ## Associated whole-container update algebra for Identity/set.
  discard $T
  NonEmptyIdentityUpdates

template setResponseType*(T: typedesc[Identity]): typedesc =
  ## Associated /set response type for Identity. The wire ``created[cid]``
  ## payload is ``IdentityCreatedItem`` (RFC 8620 §5.3 server-set subset:
  ## ``id`` plus the server-set ``mayDelete``). Stalwart 0.15.5 omits
  ## ``mayDelete`` from this payload, so ``IdentityCreatedItem.mayDelete``
  ## is ``Opt[bool]``. Mirrors the ``EmailCreatedItem`` pattern.
  discard $T
  SetResponse[IdentityCreatedItem]

registerJmapEntity(Identity)
registerSettableEntity(Identity)

# ---------------------------------------------------------------------------
# Mailbox (RFC 8621 section 2) — supports /get, /changes, /set, /query,
# /queryChanges
# ---------------------------------------------------------------------------

func methodEntity*(T: typedesc[Mailbox]): MethodEntity =
  ## Entity tag for Mailbox.
  discard $T
  meMailbox

func getMethodName*(T: typedesc[Mailbox]): MethodName =
  ## Mailbox/get method name.
  discard $T
  mnMailboxGet

func changesMethodName*(T: typedesc[Mailbox]): MethodName =
  ## Mailbox/changes method name.
  discard $T
  mnMailboxChanges

func setMethodName*(T: typedesc[Mailbox]): MethodName =
  ## Mailbox/set method name.
  discard $T
  mnMailboxSet

func queryMethodName*(T: typedesc[Mailbox]): MethodName =
  ## Mailbox/query method name.
  discard $T
  mnMailboxQuery

func queryChangesMethodName*(T: typedesc[Mailbox]): MethodName =
  ## Mailbox/queryChanges method name.
  discard $T
  mnMailboxQueryChanges

func capabilityUri*(T: typedesc[Mailbox]): string =
  ## Capability URI for Mailbox methods.
  discard $T
  "urn:ietf:params:jmap:mail"

template changesResponseType*(T: typedesc[Mailbox]): typedesc =
  ## Associated /changes response type for Mailbox. Uses the extended
  ## ``MailboxChangesResponse`` composition (RFC 8621 §2.2) which carries
  ## the Mailbox-specific ``updatedProperties`` field alongside the
  ## standard ``ChangesResponse[Mailbox]``.
  discard $T
  MailboxChangesResponse

template filterType*(T: typedesc[Mailbox]): typedesc =
  ## Associated filter condition type for Mailbox/query.
  discard $T
  MailboxFilterCondition

template createType*(T: typedesc[Mailbox]): typedesc =
  ## Associated typed create-value type for Mailbox/set.
  discard $T
  MailboxCreate

template updateType*(T: typedesc[Mailbox]): typedesc =
  ## Associated whole-container update algebra for Mailbox/set.
  discard $T
  NonEmptyMailboxUpdates

template setResponseType*(T: typedesc[Mailbox]): typedesc =
  ## Associated /set response type for Mailbox. The wire ``created[cid]``
  ## payload is ``MailboxCreatedItem`` (RFC 8620 §5.3 server-set subset:
  ## ``id`` plus the four count fields and ``myRights``). Stalwart 0.15.5
  ## omits the additional fields from this payload, so all five non-id
  ## fields are ``Opt[T]``. Mirrors the ``IdentityCreatedItem`` and
  ## ``EmailCreatedItem`` patterns.
  discard $T
  SetResponse[MailboxCreatedItem]

registerJmapEntity(Mailbox)
registerQueryableEntity(Mailbox)
registerSettableEntity(Mailbox)

# ---------------------------------------------------------------------------
# Email (RFC 8621 section 4) — supports /get, /changes, /set, /query,
# /queryChanges, /copy
# ---------------------------------------------------------------------------

func methodEntity*(T: typedesc[Email]): MethodEntity =
  ## Entity tag for Email.
  discard $T
  meEmail

func getMethodName*(T: typedesc[Email]): MethodName =
  ## Email/get method name.
  discard $T
  mnEmailGet

func changesMethodName*(T: typedesc[Email]): MethodName =
  ## Email/changes method name.
  discard $T
  mnEmailChanges

func setMethodName*(T: typedesc[Email]): MethodName =
  ## Email/set method name.
  discard $T
  mnEmailSet

func queryMethodName*(T: typedesc[Email]): MethodName =
  ## Email/query method name.
  discard $T
  mnEmailQuery

func queryChangesMethodName*(T: typedesc[Email]): MethodName =
  ## Email/queryChanges method name.
  discard $T
  mnEmailQueryChanges

func copyMethodName*(T: typedesc[Email]): MethodName =
  ## Email/copy method name.
  discard $T
  mnEmailCopy

func importMethodName*(T: typedesc[Email]): MethodName =
  ## Email/import method name.
  discard $T
  mnEmailImport

func capabilityUri*(T: typedesc[Email]): string =
  ## Capability URI for Email methods.
  discard $T
  "urn:ietf:params:jmap:mail"

template changesResponseType*(T: typedesc[Email]): typedesc =
  ## Associated /changes response type for Email — the standard generic
  ## ``ChangesResponse[Email]``.
  discard $T
  ChangesResponse[Email]

template filterType*(T: typedesc[Email]): typedesc =
  ## Associated filter condition type for Email/query.
  discard $T
  EmailFilterCondition

template createType*(T: typedesc[Email]): typedesc =
  ## Associated typed create-value type for Email/set.
  discard $T
  EmailBlueprint

template updateType*(T: typedesc[Email]): typedesc =
  ## Associated whole-container update algebra for Email/set.
  discard $T
  NonEmptyEmailUpdates

template setResponseType*(T: typedesc[Email]): typedesc =
  ## Associated /set response type for Email. The typed ``createResults``
  ## payload is ``EmailCreatedItem`` (server-set fields post-create).
  discard $T
  SetResponse[EmailCreatedItem]

template copyItemType*(T: typedesc[Email]): typedesc =
  ## Associated typed copy-item type for Email/copy.
  discard $T
  EmailCopyItem

template copyResponseType*(T: typedesc[Email]): typedesc =
  ## Associated /copy response type for Email. The typed ``createResults``
  ## payload is ``EmailCreatedItem`` (same shape as /set).
  discard $T
  CopyResponse[EmailCreatedItem]

registerJmapEntity(Email)
registerQueryableEntity(Email)
registerSettableEntity(Email)

# ---------------------------------------------------------------------------
# EmailSubmission (RFC 8621 section 7) — supports /get, /changes, /set,
# /query, /queryChanges
# ---------------------------------------------------------------------------

func methodEntity*(T: typedesc[AnyEmailSubmission]): MethodEntity =
  ## Entity tag for EmailSubmission. Keys on the existential wrapper —
  ## ``EmailSubmission[S: static UndoStatus]`` is generic and cannot be
  ## passed as a bare typedesc (G2/G3 phantom state indexing).
  discard $T
  meEmailSubmission

func getMethodName*(T: typedesc[AnyEmailSubmission]): MethodName =
  ## EmailSubmission/get method name.
  discard $T
  mnEmailSubmissionGet

func changesMethodName*(T: typedesc[AnyEmailSubmission]): MethodName =
  ## EmailSubmission/changes method name.
  discard $T
  mnEmailSubmissionChanges

func setMethodName*(T: typedesc[AnyEmailSubmission]): MethodName =
  ## EmailSubmission/set method name.
  discard $T
  mnEmailSubmissionSet

func queryMethodName*(T: typedesc[AnyEmailSubmission]): MethodName =
  ## EmailSubmission/query method name.
  discard $T
  mnEmailSubmissionQuery

func queryChangesMethodName*(T: typedesc[AnyEmailSubmission]): MethodName =
  ## EmailSubmission/queryChanges method name.
  discard $T
  mnEmailSubmissionQueryChanges

func capabilityUri*(T: typedesc[AnyEmailSubmission]): string =
  ## RFC 8621 §1.3 — EmailSubmission methods are covered by the JMAP
  ## Submission capability (same URI as Identity).
  discard $T
  "urn:ietf:params:jmap:submission"

template changesResponseType*(T: typedesc[AnyEmailSubmission]): typedesc =
  ## Associated /changes response type for EmailSubmission — the standard
  ## generic ``ChangesResponse[AnyEmailSubmission]``.
  discard $T
  ChangesResponse[AnyEmailSubmission]

template filterType*(T: typedesc[AnyEmailSubmission]): typedesc =
  ## Associated filter condition type for EmailSubmission/query.
  discard $T
  EmailSubmissionFilterCondition

template createType*(T: typedesc[AnyEmailSubmission]): typedesc =
  ## Associated typed create-value type for EmailSubmission/set.
  discard $T
  EmailSubmissionBlueprint

template updateType*(T: typedesc[AnyEmailSubmission]): typedesc =
  ## Associated whole-container update algebra for EmailSubmission/set.
  discard $T
  NonEmptyEmailSubmissionUpdates

template setResponseType*(T: typedesc[AnyEmailSubmission]): typedesc =
  ## Associated /set response type for EmailSubmission.
  discard $T
  EmailSubmissionSetResponse

registerJmapEntity(AnyEmailSubmission)
registerQueryableEntity(AnyEmailSubmission)
registerSettableEntity(AnyEmailSubmission)

# ---------------------------------------------------------------------------
# Compound-method participation gates (RFC 8620 §5.4)
# ---------------------------------------------------------------------------

registerCompoundMethod(CopyResponse[EmailCreatedItem], SetResponse[EmailCreatedItem])
registerCompoundMethod(EmailSubmissionSetResponse, SetResponse[EmailCreatedItem])

# ---------------------------------------------------------------------------
# Chainable-method participation gates (RFC 8620 §3.7 back-reference chains)
# ---------------------------------------------------------------------------

registerChainableMethod(QueryResponse[Email])
# ``GetResponse[Email]`` chains OUT to ``Thread/get`` in the RFC 8621
# §4.10 first-login workflow via ``rpListThreadId``.
registerChainableMethod(GetResponse[Email])
# ``GetResponse[Thread]`` chains OUT to ``Email/get`` in the RFC 8621
# §4.10 first-login workflow via ``rpListEmailIds``.
registerChainableMethod(GetResponse[thread.Thread])
