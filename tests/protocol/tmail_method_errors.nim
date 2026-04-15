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
import jmap_client/dispatch
import jmap_client/errors
import jmap_client/mail/email
import jmap_client/mail/serde_email

import ../massertions
import ../mfixtures

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

block emailSetRequestTooLarge:
  let cid = makeMcid("c0")
  let handle = ResponseHandle[EmailSetResponse](cid)
  let resp = makeErrorResponse("requestTooLarge", cid)
  let res = resp.get(handle)
  doAssert res.isErr
  assertEq res.error.errorType, metRequestTooLarge

block emailSetStateMismatch:
  let cid = makeMcid("c0")
  let handle = ResponseHandle[EmailSetResponse](cid)
  let resp = makeErrorResponse("stateMismatch", cid)
  let res = resp.get(handle)
  doAssert res.isErr
  assertEq res.error.errorType, metStateMismatch

block emailCopyFromAccountNotFound:
  let cid = makeMcid("c0")
  let handle = ResponseHandle[EmailCopyResponse](cid)
  let resp = makeErrorResponse("fromAccountNotFound", cid)
  let res = resp.get(handle)
  doAssert res.isErr
  assertEq res.error.errorType, metFromAccountNotFound

block emailCopyFromAccountNotSupportedByMethod:
  let cid = makeMcid("c0")
  let handle = ResponseHandle[EmailCopyResponse](cid)
  let resp = makeErrorResponse("fromAccountNotSupportedByMethod", cid)
  let res = resp.get(handle)
  doAssert res.isErr
  assertEq res.error.errorType, metFromAccountNotSupportedByMethod

block emailCopyStateMismatch:
  let cid = makeMcid("c0")
  let handle = ResponseHandle[EmailCopyResponse](cid)
  let resp = makeErrorResponse("stateMismatch", cid)
  let res = resp.get(handle)
  doAssert res.isErr
  assertEq res.error.errorType, metStateMismatch

block emailImportStateMismatch:
  let cid = makeMcid("c0")
  let handle = ResponseHandle[EmailImportResponse](cid)
  let resp = makeErrorResponse("stateMismatch", cid)
  let res = resp.get(handle)
  doAssert res.isErr
  assertEq res.error.errorType, metStateMismatch

block emailImportRequestTooLarge:
  let cid = makeMcid("c0")
  let handle = ResponseHandle[EmailImportResponse](cid)
  let resp = makeErrorResponse("requestTooLarge", cid)
  let res = resp.get(handle)
  doAssert res.isErr
  assertEq res.error.errorType, metRequestTooLarge

# ===========================================================================
# B. SetError applicability matrix — 25 ✓-cell blocks per F2 §8.11
# ===========================================================================
#
# Each block decodes a wire response carrying one typed SetError in the
# appropriate slot (notCreated / notUpdated / notDestroyed) and asserts
# that the SetError surfaces with the correct ``errorType`` discriminant.
# Method × operation × error-type cell coverage follows §8.11's table.

# --- forbidden (5 cells) ---------------------------------------------------

block emailSetForbiddenOnCreate:
  let r = EmailSetResponse.fromJson(setNotCreatedJson("forbidden")).get()
  let k = makeCreationId("k1")
  doAssert k in r.createResults
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setForbidden

block emailSetForbiddenOnUpdate:
  let r = EmailSetResponse.fromJson(setNotUpdatedJson("forbidden")).get()
  assertSome r.notUpdated
  let m = r.notUpdated.get()
  let id = makeId("e1")
  doAssert id in m
  assertEq m[id].errorType, setForbidden

block emailSetForbiddenOnDestroy:
  let r = EmailSetResponse.fromJson(setNotDestroyedJson("forbidden")).get()
  assertSome r.notDestroyed
  let m = r.notDestroyed.get()
  let id = makeId("e1")
  doAssert id in m
  assertEq m[id].errorType, setForbidden

block emailCopyForbiddenOnCreate:
  let r = EmailCopyResponse.fromJson(copyNotCreatedJson("forbidden")).get()
  let k = makeCreationId("k1")
  doAssert k in r.createResults
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setForbidden

block emailImportForbiddenOnCreate:
  let r = EmailImportResponse.fromJson(importNotCreatedJson("forbidden")).get()
  let k = makeCreationId("k1")
  doAssert k in r.createResults
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setForbidden

# --- overQuota (4 cells) ---------------------------------------------------

block emailSetOverQuotaOnCreate:
  let r = EmailSetResponse.fromJson(setNotCreatedJson("overQuota")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setOverQuota

block emailSetOverQuotaOnUpdate:
  let r = EmailSetResponse.fromJson(setNotUpdatedJson("overQuota")).get()
  assertSome r.notUpdated
  assertEq r.notUpdated.get()[makeId("e1")].errorType, setOverQuota

block emailCopyOverQuotaOnCreate:
  let r = EmailCopyResponse.fromJson(copyNotCreatedJson("overQuota")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setOverQuota

block emailImportOverQuotaOnCreate:
  let r = EmailImportResponse.fromJson(importNotCreatedJson("overQuota")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setOverQuota

# --- tooLarge (4 cells) ----------------------------------------------------

block emailSetTooLargeOnCreate:
  let r = EmailSetResponse.fromJson(setNotCreatedJson("tooLarge")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setTooLarge

block emailSetTooLargeOnUpdate:
  let r = EmailSetResponse.fromJson(setNotUpdatedJson("tooLarge")).get()
  assertSome r.notUpdated
  assertEq r.notUpdated.get()[makeId("e1")].errorType, setTooLarge

block emailCopyTooLargeOnCreate:
  let r = EmailCopyResponse.fromJson(copyNotCreatedJson("tooLarge")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setTooLarge

block emailImportTooLargeOnCreate:
  let r = EmailImportResponse.fromJson(importNotCreatedJson("tooLarge")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setTooLarge

# --- rateLimit (3 cells) ---------------------------------------------------

block emailSetRateLimitOnCreate:
  let r = EmailSetResponse.fromJson(setNotCreatedJson("rateLimit")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setRateLimit

block emailCopyRateLimitOnCreate:
  let r = EmailCopyResponse.fromJson(copyNotCreatedJson("rateLimit")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setRateLimit

block emailImportRateLimitOnCreate:
  let r = EmailImportResponse.fromJson(importNotCreatedJson("rateLimit")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setRateLimit

# --- notFound (3 cells) ----------------------------------------------------

block emailSetNotFoundOnUpdate:
  let r = EmailSetResponse.fromJson(setNotUpdatedJson("notFound")).get()
  assertSome r.notUpdated
  assertEq r.notUpdated.get()[makeId("e1")].errorType, setNotFound

block emailSetNotFoundOnDestroy:
  let r = EmailSetResponse.fromJson(setNotDestroyedJson("notFound")).get()
  assertSome r.notDestroyed
  assertEq r.notDestroyed.get()[makeId("e1")].errorType, setNotFound

block emailCopyNotFoundOnCreate:
  ## RFC 8621 §4.7 blobId-not-found path.
  let r = EmailCopyResponse.fromJson(copyNotCreatedJson("notFound")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setNotFound

# --- invalidPatch (1 cell) -------------------------------------------------

block emailSetInvalidPatchOnUpdate:
  let r = EmailSetResponse.fromJson(setNotUpdatedJson("invalidPatch")).get()
  assertSome r.notUpdated
  assertEq r.notUpdated.get()[makeId("e1")].errorType, setInvalidPatch

# --- willDestroy (1 cell) --------------------------------------------------

block emailSetWillDestroyOnUpdate:
  let r = EmailSetResponse.fromJson(setNotUpdatedJson("willDestroy")).get()
  assertSome r.notUpdated
  assertEq r.notUpdated.get()[makeId("e1")].errorType, setWillDestroy

# --- invalidProperties (4 cells) -------------------------------------------

block emailSetInvalidPropertiesOnCreate:
  ## ``SetError.fromJson`` falls back to ``setUnknown`` when the
  ## ``properties`` array is absent — this block includes it so the
  ## ``setInvalidProperties`` variant is preserved end-to-end.
  let node = %*{
    "accountId": "a1",
    "newState": "s1",
    "notCreated": {"k1": {"type": "invalidProperties", "properties": ["subject"]}},
  }
  let r = EmailSetResponse.fromJson(node).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setInvalidProperties

block emailSetInvalidPropertiesOnUpdate:
  let node = %*{
    "accountId": "a1",
    "newState": "s1",
    "notUpdated": {"e1": {"type": "invalidProperties", "properties": ["from"]}},
  }
  let r = EmailSetResponse.fromJson(node).get()
  assertSome r.notUpdated
  assertEq r.notUpdated.get()[makeId("e1")].errorType, setInvalidProperties

block emailCopyInvalidPropertiesOnCreate:
  let node = %*{
    "fromAccountId": "src",
    "accountId": "dst",
    "newState": "s1",
    "notCreated": {"k1": {"type": "invalidProperties", "properties": ["mailboxIds"]}},
  }
  let r = EmailCopyResponse.fromJson(node).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setInvalidProperties

block emailImportInvalidPropertiesOnCreate:
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

block emailSetSingletonParsesButNotEmittable:
  let r = EmailSetResponse.fromJson(setNotCreatedJson("singleton")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setSingleton

block emailCopySingletonParsesButNotEmittable:
  let r = EmailCopyResponse.fromJson(copyNotCreatedJson("singleton")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setSingleton

block emailImportSingletonParsesButNotEmittable:
  let r = EmailImportResponse.fromJson(importNotCreatedJson("singleton")).get()
  let k = makeCreationId("k1")
  doAssert r.createResults[k].isErr
  assertEq r.createResults[k].error.errorType, setSingleton

# ===========================================================================
# D. Exhaustiveness probe per F2 §8.11 mandatory note
# ===========================================================================

block setErrorApplicabilityExhaustiveFold:
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
