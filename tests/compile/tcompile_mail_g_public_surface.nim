# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only smoke test for Mail Part G (RFC 8621 §7 EmailSubmission)
## public surface. Every public symbol added by Part G must be reachable
## through a single ``import jmap_client``. A compile failure here is the
## canonical signal that a symbol was omitted from the re-export cascade:
## ``jmap_client.nim`` → ``mail.nim`` → ``mail/types.nim`` or
## ``mail/serialisation.nim`` or ``mail/submission_builders.nim`` →
## Layer 1/2 module.
##
## ``declared()`` is used instead of ``compiles()`` because it sidesteps
## overload-resolution ambiguity on the three phantom-typed ``toAny``
## arms and on ``getBoth`` (distinct overloads for ``EmailCopyHandles``
## and ``EmailSubmissionHandles``) while still failing hard when a symbol
## is unreachable.

import jmap_client

static:
  # --- RFC 5321 atoms + capability refinement (4) ---
  doAssert declared(RFC5321Mailbox)
  doAssert declared(RFC5321Keyword)
  doAssert declared(OrcptAddrType)
  doAssert declared(SubmissionExtensionMap)

  # --- SMTP parameter payload newtypes and enums (6) ---
  doAssert declared(BodyEncoding)
  doAssert declared(DsnRetType)
  doAssert declared(DsnNotifyFlag)
  doAssert declared(DeliveryByMode)
  doAssert declared(HoldForSeconds)
  doAssert declared(MtPriority)

  # --- SMTP parameter algebra (4) ---
  doAssert declared(SubmissionParamKind)
  doAssert declared(SubmissionParam)
  doAssert declared(SubmissionParamKey)
  doAssert declared(SubmissionParams)

  # --- Envelope composite types (5) ---
  doAssert declared(SubmissionAddress)
  doAssert declared(ReversePathKind)
  doAssert declared(ReversePath)
  doAssert declared(NonEmptyRcptList)
  doAssert declared(Envelope)

  # --- Status types (8) ---
  doAssert declared(UndoStatus)
  doAssert declared(DeliveredState)
  doAssert declared(ParsedDeliveredState)
  doAssert declared(DisplayedState)
  doAssert declared(ParsedDisplayedState)
  doAssert declared(SmtpReply)
  doAssert declared(DeliveryStatus)
  doAssert declared(DeliveryStatusMap)

  # --- Entity phantom-indexed + existential wrapper + creation ref (5) ---
  doAssert declared(EmailSubmission)
  doAssert declared(AnyEmailSubmission)
  doAssert declared(IdOrCreationRefKind)
  doAssert declared(IdOrCreationRef)
  doAssert declared(EmailSubmissionBlueprint)

  # --- Update algebra (4) ---
  doAssert declared(EmailSubmissionUpdate)
  doAssert declared(EmailSubmissionUpdateVariantKind)
  doAssert declared(NonEmptyEmailSubmissionUpdates)
  doAssert declared(NonEmptyIdSeq)

  # --- Query typing (3) ---
  doAssert declared(EmailSubmissionFilterCondition)
  doAssert declared(EmailSubmissionSortProperty)
  doAssert declared(EmailSubmissionComparator)

  # --- /set response shape and compound handles (4) ---
  doAssert declared(EmailSubmissionCreatedItem)
  doAssert declared(EmailSubmissionSetResponse)
  doAssert declared(EmailSubmissionHandles)
  doAssert declared(EmailSubmissionResults)

  # --- Smart constructors / parsers (14) ---
  doAssert declared(parseRFC5321Mailbox)
  doAssert declared(parseRFC5321MailboxFromServer)
  doAssert declared(parseRFC5321Keyword)
  doAssert declared(parseOrcptAddrType)
  doAssert declared(parseHoldForSeconds)
  doAssert declared(parseMtPriority)
  doAssert declared(parseSubmissionParams)
  doAssert declared(parseNonEmptyRcptList)
  doAssert declared(parseNonEmptyRcptListFromServer)
  doAssert declared(parseSmtpReply)
  doAssert declared(parseEmailSubmissionBlueprint)
  doAssert declared(parseNonEmptyEmailSubmissionUpdates)
  doAssert declared(parseNonEmptyIdSeq)
  doAssert declared(parseEmailSubmissionComparator)

  # --- Server-side infallible parsers (2) ---
  doAssert declared(parseDeliveredState)
  doAssert declared(parseDisplayedState)

  # --- Typed parameter constructors (12) ---
  doAssert declared(bodyParam)
  doAssert declared(byParam)
  doAssert declared(envidParam)
  doAssert declared(extensionParam)
  doAssert declared(holdForParam)
  doAssert declared(holdUntilParam)
  doAssert declared(mtPriorityParam)
  doAssert declared(notifyParam)
  doAssert declared(orcptParam)
  doAssert declared(retParam)
  doAssert declared(sizeParam)
  doAssert declared(smtpUtf8Param)

  # --- Infallible constructors + phantom-boundary helpers (8) ---
  doAssert declared(nullReversePath)
  doAssert declared(reversePath)
  doAssert declared(paramKey)
  doAssert declared(toAny)
  doAssert declared(asPending)
  doAssert declared(asFinal)
  doAssert declared(asCanceled)
  doAssert declared(setUndoStatusToCanceled)
  doAssert declared(cancelUpdate)
  doAssert declared(directRef)
  doAssert declared(creationRef)

  # --- Domain helpers on DeliveryStatusMap (2) ---
  doAssert declared(countDelivered)
  doAssert declared(anyFailed)

  # --- onSuccess* NonEmpty extras ---
  doAssert declared(NonEmptyOnSuccessUpdateEmail)
  doAssert declared(NonEmptyOnSuccessDestroyEmail)
  doAssert declared(parseNonEmptyOnSuccessUpdateEmail)
  doAssert declared(parseNonEmptyOnSuccessDestroyEmail)

  # --- L3 method builders (6) ---
  doAssert declared(addEmailSubmissionGet)
  doAssert declared(addEmailSubmissionChanges)
  doAssert declared(addEmailSubmissionQuery)
  doAssert declared(addEmailSubmissionQueryChanges)
  doAssert declared(addEmailSubmissionSet)
  doAssert declared(addEmailSubmissionAndEmailSet)

  # --- Method enum route variants (5) ---
  doAssert declared(mnEmailSubmissionGet)
  doAssert declared(mnEmailSubmissionChanges)
  doAssert declared(mnEmailSubmissionQuery)
  doAssert declared(mnEmailSubmissionQueryChanges)
  doAssert declared(mnEmailSubmissionSet)

# Runtime anchor: the ``static:`` block above verifies visibility at
## compile time, but Nim's UnusedImport check tracks runtime consumption.
## A single runtime reference through ``mnEmailSubmissionSet`` (re-exported
## from ``methods_enum`` via ``jmap_client``) pins the import while
## exercising a genuine Part G symbol.
doAssert $mnEmailSubmissionSet == "EmailSubmission/set"
