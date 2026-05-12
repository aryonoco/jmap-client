# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Method-level error decode tests for Email/set, Email/copy, and
## Email/import per RFC 8621 §4.6-§4.8, plus the generic SetError
## applicability matrix per F2 §8.11. No source changes — these pin the
## shipped decode semantics at the protocol boundary.

{.push raises: [].}

import std/json
import std/tables

import jmap_client/types
import jmap_client/internal/protocol/methods
import jmap_client/internal/protocol/dispatch
import jmap_client/internal/types/errors
import jmap_client/internal/mail/email
import jmap_client/internal/mail/serde_email
import jmap_client/internal/mail/email_submission
import jmap_client/internal/mail/serde_email_submission

import ../massertions
import ../mfixtures
import ../mtestblock

# ---------------------------------------------------------------------------
# Wire-JSON builders. One per (response-type, slot) axis — the ``errType``
# string passes through untouched so the test can pin both the typed
# variant and the ``rawType`` preservation invariant in the same block.
# ---------------------------------------------------------------------------

proc setNotCreatedJson(errType: string): JsonNode =
  ## EmailSet wire response with one ``notCreated`` entry carrying ``errType``.
  %*{"accountId": "a1", "newState": "s1", "notCreated": {"k1": {"type": errType}}}

proc setNotUpdatedJson(errType: string): JsonNode =
  ## EmailSet wire response with one ``notUpdated`` entry carrying ``errType``.
  %*{"accountId": "a1", "newState": "s1", "notUpdated": {"e1": {"type": errType}}}

proc setNotDestroyedJson(errType: string): JsonNode =
  ## EmailSet wire response with one ``notDestroyed`` entry carrying ``errType``.
  %*{"accountId": "a1", "newState": "s1", "notDestroyed": {"e1": {"type": errType}}}

proc copyNotCreatedJson(errType: string): JsonNode =
  ## EmailCopy wire response with one ``notCreated`` entry carrying ``errType``.
  %*{
    "fromAccountId": "src",
    "accountId": "dst",
    "newState": "s1",
    "notCreated": {"k1": {"type": errType}},
  }

proc importNotCreatedJson(errType: string): JsonNode =
  ## EmailImport wire response with one ``notCreated`` entry carrying ``errType``.
  %*{"accountId": "a1", "newState": "s1", "notCreated": {"k1": {"type": errType}}}

# ===========================================================================
# A. Method-level errors — 7 blocks per F2 §8.4
# ===========================================================================
#
# Each block constructs a Response whose single invocation is the wire
# "error" tag carrying a typed MethodError. ``resp.get(handle)`` matches
# on call-id (the "error" wire tag is a response marker per RFC 8620
# §3.6.1, emitted regardless of the invoked method name) and produces a
# typed ``MethodError`` on the Err rail.

testCase emailSetRequestTooLarge:
  let cid = makeMcid("c0")
  let handle = makeResponseHandle[SetResponse[EmailCreatedItem, PartialEmail]](cid)
  let resp = makeErrorResponse("requestTooLarge", cid)
  let res = makeDispatchedResponse(resp).get(handle)
  doAssert res.isErr
  assertEq res.error.methodErr.errorType, metRequestTooLarge

testCase emailSetStateMismatch:
  let cid = makeMcid("c0")
  let handle = makeResponseHandle[SetResponse[EmailCreatedItem, PartialEmail]](cid)
  let resp = makeErrorResponse("stateMismatch", cid)
  let res = makeDispatchedResponse(resp).get(handle)
  doAssert res.isErr
  assertEq res.error.methodErr.errorType, metStateMismatch

testCase emailCopyFromAccountNotFound:
  let cid = makeMcid("c0")
  let handle = makeResponseHandle[CopyResponse[EmailCreatedItem]](cid)
  let resp = makeErrorResponse("fromAccountNotFound", cid)
  let res = makeDispatchedResponse(resp).get(handle)
  doAssert res.isErr
  assertEq res.error.methodErr.errorType, metFromAccountNotFound

testCase emailCopyFromAccountNotSupportedByMethod:
  let cid = makeMcid("c0")
  let handle = makeResponseHandle[CopyResponse[EmailCreatedItem]](cid)
  let resp = makeErrorResponse("fromAccountNotSupportedByMethod", cid)
  let res = makeDispatchedResponse(resp).get(handle)
  doAssert res.isErr
  assertEq res.error.methodErr.errorType, metFromAccountNotSupportedByMethod

testCase emailCopyStateMismatch:
  let cid = makeMcid("c0")
  let handle = makeResponseHandle[CopyResponse[EmailCreatedItem]](cid)
  let resp = makeErrorResponse("stateMismatch", cid)
  let res = makeDispatchedResponse(resp).get(handle)
  doAssert res.isErr
  assertEq res.error.methodErr.errorType, metStateMismatch

testCase emailImportStateMismatch:
  let cid = makeMcid("c0")
  let handle = makeResponseHandle[EmailImportResponse](cid)
  let resp = makeErrorResponse("stateMismatch", cid)
  let res = makeDispatchedResponse(resp).get(handle)
  doAssert res.isErr
  assertEq res.error.methodErr.errorType, metStateMismatch

testCase emailImportRequestTooLarge:
  let cid = makeMcid("c0")
  let handle = makeResponseHandle[EmailImportResponse](cid)
  let resp = makeErrorResponse("requestTooLarge", cid)
  let res = makeDispatchedResponse(resp).get(handle)
  doAssert res.isErr
  assertEq res.error.methodErr.errorType, metRequestTooLarge

# ===========================================================================
# B. SetError applicability matrix — 25 ✓-cell blocks per F2 §8.11
# ===========================================================================
#
# Each block decodes a wire response carrying one typed SetError in the
# appropriate slot (notCreated / notUpdated / notDestroyed) and asserts
# that the SetError surfaces with the correct ``errorType`` discriminant.
# Method × operation × error-type cell coverage follows §8.11's table.

# --- forbidden (5 cells) ---------------------------------------------------

testCase emailSetForbiddenOnCreate:
  let r = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(setNotCreatedJson("forbidden"))
    .get()
  let k = makeCreationId("k1")
  doAssert k in r.createResults
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setForbidden

testCase emailSetForbiddenOnUpdate:
  let r = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(setNotUpdatedJson("forbidden"))
    .get()
  let id = makeId("e1")
  doAssert id in r.updateResults
  doAssert r.updateResults[id].isErr
  assertEq r.updateResults[id].error.errorType, setForbidden

testCase emailSetForbiddenOnDestroy:
  let r = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(setNotDestroyedJson("forbidden"))
    .get()
  let id = makeId("e1")
  doAssert id in r.destroyResults
  doAssert r.destroyResults[id].isErr
  assertEq r.destroyResults[id].error.errorType, setForbidden

testCase emailCopyForbiddenOnCreate:
  let r = CopyResponse[EmailCreatedItem].fromJson(copyNotCreatedJson("forbidden")).get()
  let k = makeCreationId("k1")
  doAssert k in r.createResults
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setForbidden

testCase emailImportForbiddenOnCreate:
  let r = EmailImportResponse.fromJson(importNotCreatedJson("forbidden")).get()
  let k = makeCreationId("k1")
  doAssert k in r.createResults
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setForbidden

# --- overQuota (4 cells) ---------------------------------------------------

testCase emailSetOverQuotaOnCreate:
  let r = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(setNotCreatedJson("overQuota"))
    .get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setOverQuota

testCase emailSetOverQuotaOnUpdate:
  let r = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(setNotUpdatedJson("overQuota"))
    .get()
  assertEq r.updateResults[makeId("e1")].error.errorType, setOverQuota

testCase emailCopyOverQuotaOnCreate:
  let r = CopyResponse[EmailCreatedItem].fromJson(copyNotCreatedJson("overQuota")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setOverQuota

testCase emailImportOverQuotaOnCreate:
  let r = EmailImportResponse.fromJson(importNotCreatedJson("overQuota")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setOverQuota

# --- tooLarge (4 cells) ----------------------------------------------------

testCase emailSetTooLargeOnCreate:
  let r = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(setNotCreatedJson("tooLarge"))
    .get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setTooLarge

testCase emailSetTooLargeOnUpdate:
  let r = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(setNotUpdatedJson("tooLarge"))
    .get()
  assertEq r.updateResults[makeId("e1")].error.errorType, setTooLarge

testCase emailCopyTooLargeOnCreate:
  let r = CopyResponse[EmailCreatedItem].fromJson(copyNotCreatedJson("tooLarge")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setTooLarge

testCase emailImportTooLargeOnCreate:
  let r = EmailImportResponse.fromJson(importNotCreatedJson("tooLarge")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setTooLarge

# --- rateLimit (3 cells) ---------------------------------------------------

testCase emailSetRateLimitOnCreate:
  let r = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(setNotCreatedJson("rateLimit"))
    .get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setRateLimit

testCase emailCopyRateLimitOnCreate:
  let r = CopyResponse[EmailCreatedItem].fromJson(copyNotCreatedJson("rateLimit")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setRateLimit

testCase emailImportRateLimitOnCreate:
  let r = EmailImportResponse.fromJson(importNotCreatedJson("rateLimit")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setRateLimit

# --- notFound (3 cells) ----------------------------------------------------

testCase emailSetNotFoundOnUpdate:
  let r = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(setNotUpdatedJson("notFound"))
    .get()
  assertEq r.updateResults[makeId("e1")].error.errorType, setNotFound

testCase emailSetNotFoundOnDestroy:
  let r = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(setNotDestroyedJson("notFound"))
    .get()
  assertEq r.destroyResults[makeId("e1")].error.errorType, setNotFound

testCase emailCopyNotFoundOnCreate:
  ## RFC 8621 §4.7 blobId-not-found path.
  let r = CopyResponse[EmailCreatedItem].fromJson(copyNotCreatedJson("notFound")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setNotFound

# --- invalidPatch (1 cell) -------------------------------------------------

testCase emailSetInvalidPatchOnUpdate:
  let r = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(setNotUpdatedJson("invalidPatch"))
    .get()
  assertEq r.updateResults[makeId("e1")].error.errorType, setInvalidPatch

# --- willDestroy (1 cell) --------------------------------------------------

testCase emailSetWillDestroyOnUpdate:
  let r = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(setNotUpdatedJson("willDestroy"))
    .get()
  assertEq r.updateResults[makeId("e1")].error.errorType, setWillDestroy

# --- invalidProperties (4 cells) -------------------------------------------

testCase emailSetInvalidPropertiesOnCreate:
  ## ``SetError.fromJson`` falls back to ``setUnknown`` when the
  ## ``properties`` array is absent — this block includes it so the
  ## ``setInvalidProperties`` variant is preserved end-to-end.
  let node = %*{
    "accountId": "a1",
    "newState": "s1",
    "notCreated": {"k1": {"type": "invalidProperties", "properties": ["subject"]}},
  }
  let r = SetResponse[EmailCreatedItem, PartialEmail].fromJson(node).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setInvalidProperties

testCase emailSetInvalidPropertiesOnUpdate:
  let node = %*{
    "accountId": "a1",
    "newState": "s1",
    "notUpdated": {"e1": {"type": "invalidProperties", "properties": ["from"]}},
  }
  let r = SetResponse[EmailCreatedItem, PartialEmail].fromJson(node).get()
  assertEq r.updateResults[makeId("e1")].error.errorType, setInvalidProperties

testCase emailCopyInvalidPropertiesOnCreate:
  let node = %*{
    "fromAccountId": "src",
    "accountId": "dst",
    "newState": "s1",
    "notCreated": {"k1": {"type": "invalidProperties", "properties": ["mailboxIds"]}},
  }
  let r = CopyResponse[EmailCreatedItem].fromJson(node).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setInvalidProperties

testCase emailImportInvalidPropertiesOnCreate:
  let node = %*{
    "accountId": "a1",
    "newState": "s1",
    "notCreated": {"k1": {"type": "invalidProperties", "properties": ["blobId"]}},
  }
  let r = EmailImportResponse.fromJson(node).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setInvalidProperties

# ===========================================================================
# C. SetError negative — 3 ✗-cell blocks per F2 §8.11
# ===========================================================================
#
# ``setSingleton`` parses (Postel's law on receive) but is never emitted
# by any Part F request-builder API. These three blocks pin the parse
# direction; the corresponding negative-emit pin ("no builder emits
# singleton") lives at the F2 §8.10 coverage-audit layer and is not
# enforceable at the test level without reflection.

testCase emailSetSingletonParsesButNotEmittable:
  let r = SetResponse[EmailCreatedItem, PartialEmail]
    .fromJson(setNotCreatedJson("singleton"))
    .get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setSingleton

testCase emailCopySingletonParsesButNotEmittable:
  let r = CopyResponse[EmailCreatedItem].fromJson(copyNotCreatedJson("singleton")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setSingleton

testCase emailImportSingletonParsesButNotEmittable:
  let r = EmailImportResponse.fromJson(importNotCreatedJson("singleton")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setSingleton

# ===========================================================================
# D. Exhaustiveness probe per F2 §8.11 mandatory note
# ===========================================================================

testCase setErrorApplicabilityExhaustiveFold:
  ## Every ``SetErrorType`` variant is accounted for: ✓ cells in Section B,
  ## ✗ negative cells in Section C, out-of-Part-F variants documented
  ## below. Adding a new variant forces a compile error at this ``case``
  ## until its coverage row is added to the above sections.
  for variant in SetErrorType:
    case variant
    of setForbidden, setOverQuota, setTooLarge, setRateLimit, setNotFound,
        setInvalidPatch, setWillDestroy, setInvalidProperties:
      discard # covered by ✓ cells in Section B
    of setSingleton:
      discard # covered by ✗ cells in Section C
    of setAlreadyExists:
      discard # not in Part F matrix (Mailbox /set only; pinned in tmailbox.nim)
    of setMailboxHasChild, setMailboxHasEmail:
      discard # RFC 8621 §2.3 Mailbox/set — pinned in tmailbox.nim
    of setBlobNotFound, setTooManyKeywords, setTooManyMailboxes, setInvalidEmail:
      discard # RFC 8621 §4.6 Email/set — pinned in tmail_errors.nim
    of setTooManyRecipients, setNoRecipients, setInvalidRecipients,
        setForbiddenMailFrom, setForbiddenFrom, setForbiddenToSend, setCannotUnsend:
      discard # RFC 8621 §7.5 EmailSubmission/set — pinned in tmail_errors.nim
    of setUnknown:
      discard # Postel catch-all — pinned in tserde_errors.nim

# ===========================================================================
# E. EmailSubmission method-level errors — 1 block per G2 §8.4
# ===========================================================================
#
# EmailSubmission/set surfaces the same generic MethodError variants as
# Email/set (requestTooLarge, stateMismatch per RFC 8620 §3.6.1). G23
# committed to no submission-specific MethodError variants, so the
# coverage set is bounded. The block mirrors ``emailSetRequestTooLarge``
# / ``emailSetStateMismatch`` in Section A.

testCase emailSubmissionSetMethodErrorSurface:
  let cid = makeMcid("c0")
  let handle = makeResponseHandle[EmailSubmissionSetResponse](cid)

  # requestTooLarge — RFC 8620 §3.6.1
  let resp1 = makeErrorResponse("requestTooLarge", cid)
  let res1 = makeDispatchedResponse(resp1).get(handle)
  doAssert res1.isErr
  assertEq res1.error.methodErr.errorType, metRequestTooLarge

  # stateMismatch — RFC 8620 §5.3 ifInState conflict
  let resp2 = makeErrorResponse("stateMismatch", cid)
  let res2 = makeDispatchedResponse(resp2).get(handle)
  doAssert res2.isErr
  assertEq res2.error.methodErr.errorType, metStateMismatch

# ===========================================================================
# F. EmailSubmission SetError applicability — 9 ✓-cell blocks per G2 §8.8
# ===========================================================================
#
# Eight submission-specific SetError variants apply to /set create
# (notCreated slot); one — ``setCannotUnsend`` — applies exclusively to
# /set update (notUpdated slot) per RFC 8621 §7.5 ¶6. Wire JSON reuses
# the entity-agnostic setNotCreatedJson / setNotUpdatedJson builders in
# Section preamble. Payload-bearing variants (invalidEmail,
# tooManyRecipients, invalidRecipients, tooLarge) include the mandated
# extra field so the variant parses with its typed discriminant rather
# than falling back to ``setUnknown``.

# --- /set create ✓ cells (8 variants) --------------------------------------

testCase emailSubmissionSetInvalidEmailOnCreate:
  ## RFC 8621 §7.5: wire field is ``properties`` (the typed Nim accessor
  ## ``invalidEmailPropertyNames`` is renamed locally to avoid colliding
  ## with the mail-layer ``invalidEmailProperties`` accessor — see
  ## errors.nim:327).
  let node = %*{
    "accountId": "a1",
    "newState": "s1",
    "notCreated": {"k1": {"type": "invalidEmail", "properties": ["emailId"]}},
  }
  let r =
    SetResponse[EmailSubmissionCreatedItem, PartialEmailSubmission].fromJson(node).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setInvalidEmail

testCase emailSubmissionSetTooManyRecipientsOnCreate:
  ## RFC 8621 §7.5: wire field is ``maxRecipients`` (the typed Nim
  ## accessor is ``maxRecipientCount`` for count-vs-value clarity).
  let node = %*{
    "accountId": "a1",
    "newState": "s1",
    "notCreated": {"k1": {"type": "tooManyRecipients", "maxRecipients": 50}},
  }
  let r =
    SetResponse[EmailSubmissionCreatedItem, PartialEmailSubmission].fromJson(node).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setTooManyRecipients

testCase emailSubmissionSetNoRecipientsOnCreate:
  let r = SetResponse[EmailSubmissionCreatedItem, PartialEmailSubmission]
    .fromJson(setNotCreatedJson("noRecipients"))
    .get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setNoRecipients

testCase emailSubmissionSetInvalidRecipientsOnCreate:
  let node = %*{
    "accountId": "a1",
    "newState": "s1",
    "notCreated": {"k1": {"type": "invalidRecipients", "invalidRecipients": ["bogus@"]}},
  }
  let r =
    SetResponse[EmailSubmissionCreatedItem, PartialEmailSubmission].fromJson(node).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setInvalidRecipients

testCase emailSubmissionSetForbiddenMailFromOnCreate:
  let r = SetResponse[EmailSubmissionCreatedItem, PartialEmailSubmission]
    .fromJson(setNotCreatedJson("forbiddenMailFrom"))
    .get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setForbiddenMailFrom

testCase emailSubmissionSetForbiddenFromOnCreate:
  let r = SetResponse[EmailSubmissionCreatedItem, PartialEmailSubmission]
    .fromJson(setNotCreatedJson("forbiddenFrom"))
    .get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setForbiddenFrom

testCase emailSubmissionSetForbiddenToSendOnCreate:
  let r = SetResponse[EmailSubmissionCreatedItem, PartialEmailSubmission]
    .fromJson(setNotCreatedJson("forbiddenToSend"))
    .get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setForbiddenToSend

testCase emailSubmissionSetTooLargeOnCreate:
  ## RFC 8621 §7.5 SHOULD: wire field is ``maxSize`` (the typed Nim
  ## accessor ``maxSizeOctets`` carries the unit-in-name).
  let node = %*{
    "accountId": "a1",
    "newState": "s1",
    "notCreated": {"k1": {"type": "tooLarge", "maxSize": 1048576}},
  }
  let r =
    SetResponse[EmailSubmissionCreatedItem, PartialEmailSubmission].fromJson(node).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setTooLarge

# --- /set update ✓ cell (1 variant, net-new) -------------------------------

testCase emailSubmissionSetCannotUnsendOnUpdate:
  ## RFC 8621 §7.5 ¶6: server determined unsend impossible after pending →
  ## canceled update attempt. No payload; plain variant. Load-bearing G2 §8.8
  ## test — without it the update-only applicability of setCannotUnsend is
  ## untested at the protocol tier.
  let r = SetResponse[EmailSubmissionCreatedItem, PartialEmailSubmission]
    .fromJson(setNotUpdatedJson("cannotUnsend"))
    .get()
  let id = makeId("e1") # matches the "e1" key in setNotUpdatedJson
  doAssert id in r.updateResults
  doAssert r.updateResults[id].isErr
  assertEq r.updateResults[id].error.errorType, setCannotUnsend

# ===========================================================================
# G. EmailSubmission SetError negative — ✗-cell blocks per G2 §8.8
# ===========================================================================
#
# ``setSingleton`` parses (Postel's law on receive) on any submission /set
# slot but is never emitted by any Part G builder API (there is no
# singleton-shaped submission resource). Two blocks — one per populated
# slot (notCreated, notUpdated) — pin the parse direction. Mirrors
# Section C's ``emailSetSingletonParsesButNotEmittable`` for Email/set.

testCase emailSubmissionSetSingletonParsesButNotEmittableOnCreate:
  let r = SetResponse[EmailSubmissionCreatedItem, PartialEmailSubmission]
    .fromJson(setNotCreatedJson("singleton"))
    .get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setSingleton

testCase emailSubmissionSetSingletonParsesButNotEmittableOnUpdate:
  let r = SetResponse[EmailSubmissionCreatedItem, PartialEmailSubmission]
    .fromJson(setNotUpdatedJson("singleton"))
    .get()
  let id = makeId("e1")
  doAssert id in r.updateResults
  doAssert r.updateResults[id].isErr
  assertEq r.updateResults[id].error.errorType, setSingleton

# ===========================================================================
# H. Submission SetError exhaustiveness probe per G2 §8.8 mandatory note
# ===========================================================================
#
# ``for kind in SetErrorType:`` iteration is mandatory (§8.8 closing note,
# precedent terrors.nim:428). Every ``SetErrorType`` variant is routed to
# its submission-specific coverage row above, cross-entity row in Section
# B/C/D, or documented out-of-scope branch. Adding a new variant forces a
# compile error here until its submission applicability is classified.

testCase emailSubmissionSetErrorApplicabilityExhaustiveFold:
  for variant in SetErrorType:
    case variant
    of setInvalidEmail, setTooManyRecipients, setNoRecipients, setInvalidRecipients,
        setForbiddenMailFrom, setForbiddenFrom, setForbiddenToSend, setTooLarge:
      discard # ✓ EmailSubmission/set create — Section F
    of setCannotUnsend:
      discard # ✓ EmailSubmission/set update — Section F
    of setSingleton:
      discard # ✗ parses-but-not-emittable — Section G
    of setForbidden, setOverQuota, setRateLimit, setNotFound, setInvalidPatch,
        setWillDestroy, setInvalidProperties:
      discard # generic RFC 8620 §5.3 — applicability pinned in Section B (Email)
    of setAlreadyExists, setMailboxHasChild, setMailboxHasEmail:
      discard # Mailbox-scope — not in submission matrix
    of setBlobNotFound, setTooManyKeywords, setTooManyMailboxes:
      discard # Email-scope — not in submission matrix
    of setUnknown:
      discard # Postel catch-all — pinned in tserde_errors.nim
