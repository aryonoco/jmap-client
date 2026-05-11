# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only smoke test for Mail Part F public surface. Every public
## symbol added by Part F must be reachable through a single
## ``import jmap_client``. A compile failure here is the canonical
## signal that a symbol was omitted from the re-export cascade:
## ``jmap_client.nim`` → ``mail.nim`` → ``mail/types.nim`` or
## ``mail/serialisation.nim`` → Layer 1/2 module.
##
## ``declared()`` is used instead of ``compiles()`` because it sidesteps
## overload-resolution ambiguity on generically-named ctors
## (``setName``, ``setRole``, ``setSubject``, …) while still failing
## hard when a symbol is unreachable.

import jmap_client

static:
  # --- Types (16) ---
  # EmailSetResponse/EmailCopyResponse/UpdatedEntry/UpdatedEntryKind were
  # deleted when Email/set migrated to the promoted generic
  # SetResponse[EmailCreatedItem, PartialEmail] / CopyResponse[EmailCreatedItem] in
  # methods.nim (Decision X2/X3).
  doAssert declared(EmailUpdate)
  doAssert declared(EmailUpdateVariantKind)
  doAssert declared(EmailUpdateSet)
  doAssert declared(EmailCreatedItem)
  doAssert declared(SetResponse)
  doAssert declared(CopyResponse)
  doAssert declared(EmailImportResponse)
  doAssert declared(EmailCopyItem)
  doAssert declared(EmailImportItem)
  doAssert declared(NonEmptyEmailImportMap)
  doAssert declared(MailboxUpdate)
  doAssert declared(MailboxUpdateVariantKind)
  doAssert declared(MailboxUpdateSet)
  doAssert declared(VacationResponseUpdate)
  doAssert declared(VacationResponseUpdateVariantKind)
  doAssert declared(VacationResponseUpdateSet)
  doAssert declared(EmailCopyHandles)
  doAssert declared(EmailCopyResults)

  # --- Protocol-primitive Email update ctors (6) ---
  doAssert declared(addKeyword)
  doAssert declared(removeKeyword)
  doAssert declared(setKeywords)
  doAssert declared(addToMailbox)
  doAssert declared(removeFromMailbox)
  doAssert declared(setMailboxIds)

  # --- Domain-named Email update ctors (5) ---
  doAssert declared(markRead)
  doAssert declared(markUnread)
  doAssert declared(markFlagged)
  doAssert declared(markUnflagged)
  doAssert declared(moveToMailbox)

  # --- Set/map ctors (6) ---
  doAssert declared(initEmailUpdateSet)
  doAssert declared(initEmailCopyItem)
  doAssert declared(initEmailImportItem)
  doAssert declared(initNonEmptyEmailImportMap)
  doAssert declared(initMailboxUpdateSet)
  doAssert declared(initVacationResponseUpdateSet)

  # --- /set widening: whole-container update wrappers (4) ---
  doAssert declared(NonEmptyMailboxUpdates)
  doAssert declared(NonEmptyEmailUpdates)
  doAssert declared(parseNonEmptyMailboxUpdates)
  doAssert declared(parseNonEmptyEmailUpdates)

  # --- /set widening: associated-type templates + registration helper (5) ---
  doAssert declared(createType)
  doAssert declared(updateType)
  doAssert declared(setResponseType)
  doAssert declared(registerSettableEntity)
  doAssert declared(addSet)

  # --- /changes widening: associated-type template + extracted leaf (2) ---
  doAssert declared(changesResponseType)
  doAssert declared(MailboxChangesResponse)

  # --- /copy widening: associated-type templates (2) ---
  doAssert declared(copyItemType)
  doAssert declared(copyResponseType)

  # --- /get extras: EmailBodyFetchOptions → seq[(string, JsonNode)] (1) ---
  doAssert declared(toExtras)

  # --- Mailbox update ctors (5) ---
  doAssert declared(setName)
  doAssert declared(setParentId)
  doAssert declared(setRole)
  doAssert declared(setSortOrder)
  doAssert declared(setIsSubscribed)

  # --- VacationResponse update ctors (6) ---
  doAssert declared(setIsEnabled)
  doAssert declared(setFromDate)
  doAssert declared(setToDate)
  doAssert declared(setSubject)
  doAssert declared(setTextBody)
  doAssert declared(setHtmlBody)

  # --- Methods/builders (5) ---
  doAssert declared(addEmailSet)
  doAssert declared(addEmailCopy)
  doAssert declared(addEmailCopyAndDestroy)
  doAssert declared(addEmailImport)
  doAssert declared(getBoth)

  # --- Enum variant (1) ---
  doAssert declared(mnEmailImport)

  # --- Entity resolver (1) ---
  doAssert declared(importMethodName)

  # --- Identity /set widening ---
  doAssert declared(IdentityUpdate)
  doAssert declared(IdentityUpdateVariantKind)
  doAssert declared(IdentityUpdateSet)
  doAssert declared(NonEmptyIdentityUpdates)
  doAssert declared(initIdentityUpdateSet)
  doAssert declared(parseNonEmptyIdentityUpdates)
  doAssert declared(addIdentityGet)
  doAssert declared(addIdentityChanges)
  doAssert declared(addIdentitySet)
  doAssert declared(setReplyTo)
  doAssert declared(setTextSignature)
  doAssert declared(setHtmlSignature)

# Runtime anchor: ``static:`` block above verifies visibility at compile
## time, but Nim's UnusedImport check tracks runtime consumption. A single
## runtime reference through ``mnEmailImport`` (re-exported from
## ``methods_enum`` via ``jmap_client``) pins the import while exercising
## a genuine Part F symbol.
doAssert $mnEmailImport == "Email/import"
