# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only audit of the mail hub's public surface (A1d).
##
## The audit asserts BOTH presence (must be reachable through
## ``import jmap_client`` / ``import jmap_client/convenience``) and
## absence (must NOT be reachable). After A1d the mail hub commits to
## exactly one surface — typed entity records, smart constructors, the
## typed per-entity builders, typed handles, and the opt-in convenience
## combinators. Mail-entity wire ser/de and the entity-registration
## overloads are L2/L3 implementation detail, hub-private.
##
## A compile failure here is the canonical signal that ``mail.nim`` (or a
## builder module) has re-leaked serde or registration scaffolding onto
## the public surface — see ``docs/design/14-Nim-API-Principles.md`` P5,
## P19.
##
## Entity-registration overloads are probed with ``when compiles(X(Email))``
## rather than ``when declared(X)``: ``capabilityUri`` is also a hub-public
## ``capabilities.nim`` overload over ``CapabilityKind``, so a bare
## ``declared`` probe cannot discriminate the mail ``typedesc`` overload.

import std/json

import jmap_client
import jmap_client/convenience

static:
  # ===========================================================================
  # POSITIVE — must be reachable through the hub
  # ===========================================================================

  # --- Entity records (7) ---
  doAssert declared(Email)
  doAssert declared(Mailbox)
  doAssert declared(Thread)
  doAssert declared(Identity)
  doAssert declared(VacationResponse)
  doAssert declared(AnyEmailSubmission)
  doAssert declared(SearchSnippet)

  # --- Partial three-state echo types (6) ---
  doAssert declared(PartialEmail)
  doAssert declared(PartialMailbox)
  doAssert declared(PartialThread)
  doAssert declared(PartialIdentity)
  doAssert declared(PartialVacationResponse)
  doAssert declared(PartialEmailSubmission)

  # --- Response types (3) ---
  doAssert declared(EmailParseResponse)
  doAssert declared(SearchSnippetGetResponse)
  doAssert declared(MailboxChangesResponse)

  # --- Smart constructors + update-variant constructors (representative) ---
  doAssert declared(parseEmailBlueprint)
  doAssert declared(addKeyword)
  doAssert declared(markRead)
  doAssert declared(moveToMailbox)
  doAssert declared(initEmailUpdateSet)
  doAssert declared(initMailboxUpdateSet)
  doAssert declared(setName)
  doAssert declared(setIsEnabled)
  doAssert declared(initIdentityUpdateSet)
  doAssert declared(parseEmailSubmissionBlueprint)

  # --- Typed per-entity method builders ---
  doAssert declared(addMailboxGet)
  doAssert declared(addMailboxQuery)
  doAssert declared(addMailboxQueryChanges)
  doAssert declared(addMailboxChanges)
  doAssert declared(addMailboxSet)
  doAssert declared(addEmailGet)
  doAssert declared(addEmailGetByRef)
  doAssert declared(addEmailQuery)
  doAssert declared(addEmailQueryChanges)
  doAssert declared(addEmailChanges)
  doAssert declared(addEmailSet)
  doAssert declared(addEmailImport)
  doAssert declared(addThreadGet)
  doAssert declared(addThreadChanges)
  doAssert declared(addVacationResponseGet)
  doAssert declared(addVacationResponseSet)
  doAssert declared(addSearchSnippetGet)
  doAssert declared(addEmailQueryWithSnippets)
  doAssert declared(addEmailQueryWithThreads)
  doAssert declared(addEmailCopy)
  doAssert declared(addEmailCopyAndDestroy)
  doAssert declared(addIdentityGet)
  doAssert declared(addIdentityChanges)
  doAssert declared(addIdentitySet)
  doAssert declared(addEmailSubmissionGet)
  doAssert declared(addEmailSubmissionChanges)
  doAssert declared(addEmailSubmissionQuery)
  doAssert declared(addEmailSubmissionQueryChanges)
  doAssert declared(addEmailSubmissionSet)
  doAssert declared(addEmailSubmissionAndEmailSet)

  # --- Typed sparse partial-get builders (A3.6) ---
  doAssert declared(addPartialMailboxGet)
  doAssert declared(addPartialThreadGet)
  doAssert declared(addPartialThreadGetByRef)
  doAssert declared(addPartialIdentityGet)
  doAssert declared(addPartialEmailSubmissionGet)
  doAssert declared(addPartialVacationResponseGet)
  doAssert declared(addPartialEmailGet)
  doAssert declared(addPartialEmailGetByRef)

  # --- Typed get-property selectors (A3.6): types, a const, a parser ---
  doAssert declared(MailboxGetProperty)
  doAssert declared(ThreadGetProperty)
  doAssert declared(IdentityGetProperty)
  doAssert declared(EmailSubmissionGetProperty)
  doAssert declared(VacationResponseGetProperty)
  doAssert declared(EmailGetProperty)
  doAssert declared(EmailBodyProperty)
  doAssert declared(mgpId)
  doAssert declared(egpId)
  doAssert declared(ebpPartId)
  doAssert declared(parseMailboxGetProperty)
  doAssert declared(parseEmailGetProperty)
  doAssert declared(parseEmailBodyProperty)
  doAssert declared(emailGetHeader)
  doAssert declared(emailBodyHeader)

  # --- Back-reference primitive (dispatch.nim) ---
  doAssert declared(reference)

  # --- Per-entity convenience wrappers (8) + paired extraction ---
  doAssert declared(addEmailQueryThenGet)
  doAssert declared(addMailboxQueryThenGet)
  doAssert declared(addEmailSubmissionQueryThenGet)
  doAssert declared(addEmailChangesToGet)
  doAssert declared(addIdentityChangesToGet)
  doAssert declared(addThreadChangesToGet)
  doAssert declared(addEmailSubmissionChangesToGet)
  doAssert declared(addMailboxChangesToGet)
  doAssert declared(getBoth)
  doAssert declared(QueryGetHandles)
  doAssert declared(ChangesGetHandles)
  doAssert declared(MailboxChangesGetHandles)
  doAssert declared(MailboxChangesGetResults)

  # ===========================================================================
  # NEGATIVE — entity-registration overloads are hub-private (mail_entities)
  # ===========================================================================

  when compiles(methodEntity(Email)):
    {.error: "methodEntity(Email) reachable through hub".}
  when compiles(getMethodName(Email)):
    {.error: "getMethodName(Email) reachable through hub".}
  when compiles(setMethodName(Email)):
    {.error: "setMethodName(Email) reachable through hub".}
  when compiles(queryMethodName(Email)):
    {.error: "queryMethodName(Email) reachable through hub".}
  when compiles(queryChangesMethodName(Email)):
    {.error: "queryChangesMethodName(Email) reachable through hub".}
  when compiles(changesMethodName(Email)):
    {.error: "changesMethodName(Email) reachable through hub".}
  when compiles(copyMethodName(Email)):
    {.error: "copyMethodName(Email) reachable through hub".}
  when compiles(importMethodName(Email)):
    {.error: "importMethodName(Email) reachable through hub".}
  when compiles(capabilityUri(Email)):
    {.error: "capabilityUri(Email) reachable through hub".}
  when compiles(filterType(Email)):
    {.error: "filterType(Email) reachable through hub".}
  when compiles(createType(Email)):
    {.error: "createType(Email) reachable through hub".}
  when compiles(updateType(Email)):
    {.error: "updateType(Email) reachable through hub".}
  when compiles(setResponseType(Email)):
    {.error: "setResponseType(Email) reachable through hub".}
  when compiles(copyItemType(Email)):
    {.error: "copyItemType(Email) reachable through hub".}
  when compiles(copyResponseType(Email)):
    {.error: "copyResponseType(Email) reachable through hub".}
  when compiles(changesResponseType(Email)):
    {.error: "changesResponseType(Email) reachable through hub".}

  # ===========================================================================
  # NEGATIVE — mail-entity ser/de is hub-private (P19)
  # ===========================================================================

  # Entity / Partial / response fromJson — typed records arrive via
  # ``dr.get(handle)``; an application developer never parses raw JSON.
  when compiles(Email.fromJson(newJObject())):
    {.error: "Email.fromJson reachable through hub".}
  when compiles(Mailbox.fromJson(newJObject())):
    {.error: "Mailbox.fromJson reachable through hub".}
  when compiles(jmap_client.Thread.fromJson(newJObject())):
    {.error: "Thread.fromJson reachable through hub".}
  when compiles(Identity.fromJson(newJObject())):
    {.error: "Identity.fromJson reachable through hub".}
  when compiles(VacationResponse.fromJson(newJObject())):
    {.error: "VacationResponse.fromJson reachable through hub".}
  when compiles(AnyEmailSubmission.fromJson(newJObject())):
    {.error: "AnyEmailSubmission.fromJson reachable through hub".}
  when compiles(SearchSnippet.fromJson(newJObject())):
    {.error: "SearchSnippet.fromJson reachable through hub".}
  when compiles(PartialEmail.fromJson(newJObject())):
    {.error: "PartialEmail.fromJson reachable through hub".}
  when compiles(PartialMailbox.fromJson(newJObject())):
    {.error: "PartialMailbox.fromJson reachable through hub".}
  when compiles(PartialThread.fromJson(newJObject())):
    {.error: "PartialThread.fromJson reachable through hub".}
  when compiles(PartialIdentity.fromJson(newJObject())):
    {.error: "PartialIdentity.fromJson reachable through hub".}
  when compiles(PartialVacationResponse.fromJson(newJObject())):
    {.error: "PartialVacationResponse.fromJson reachable through hub".}
  when compiles(PartialEmailSubmission.fromJson(newJObject())):
    {.error: "PartialEmailSubmission.fromJson reachable through hub".}
  when compiles(EmailParseResponse.fromJson(newJObject())):
    {.error: "EmailParseResponse.fromJson reachable through hub".}
  when compiles(SearchSnippetGetResponse.fromJson(newJObject())):
    {.error: "SearchSnippetGetResponse.fromJson reachable through hub".}
  when compiles(MailboxChangesResponse.fromJson(newJObject())):
    {.error: "MailboxChangesResponse.fromJson reachable through hub".}

  # toJson — the typed builders are the construction path.
  when compiles(default(EmailBlueprint).toJson()):
    {.error: "EmailBlueprint.toJson reachable through hub".}

  # Named internal mail-serde helpers — hub-private leaf functions.
  when declared(emailFromJson):
    {.error: "emailFromJson reachable through hub".}
  when declared(parsedEmailFromJson):
    {.error: "parsedEmailFromJson reachable through hub".}
  when declared(emailComparatorFromJson):
    {.error: "emailComparatorFromJson reachable through hub".}
  when declared(emitBodyFetchOptions):
    {.error: "emitBodyFetchOptions reachable through hub".}
  when declared(searchSnippetFromJson):
    {.error: "searchSnippetFromJson reachable through hub".}
  when declared(idOrCreationRefWireKey):
    {.error: "idOrCreationRefWireKey reachable through hub".}
  when declared(emailParseResponseFromJson):
    {.error: "emailParseResponseFromJson reachable through hub".}
  when declared(searchSnippetGetResponseFromJson):
    {.error: "searchSnippetGetResponseFromJson reachable through hub".}

# Runtime anchors — `declared()` / `when` probes do not count as "use"
# for Nim's UnusedImport check. Reference one symbol from each import at
# runtime to pin `jmap_client`, `jmap_client/convenience` and `std/json`.
discard sizeof(Email)
discard sizeof(EmailParseResponse)
discard sizeof(MailboxChangesGetHandles)
discard sizeof(QueryGetHandles[Email])
discard newJObject()
