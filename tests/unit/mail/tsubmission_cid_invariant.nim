# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A6.6 per-call cid invariant tests for ``addEmailSubmissionAndEmailSet``.
## RFC 8620 §5.3 ties every ``icrCreation(cid)`` reference in
## ``onSuccessUpdateEmail`` and ``onSuccessDestroyEmail`` to a
## ``CreationId`` appearing as a key in ``create`` on the same call.
## The builder boundary enforces this at construction time via
## ``validateOnSuccessCids``; failure surfaces as ``ValidationError``
## before any wire serialisation, instead of as a server-side
## ``SetError(setNotFound)`` round-trip.
##
## Three branches:
## 1. ``icrCreation`` with no matching ``create`` key → err(ValidationError)
##    whose ``value`` field equals the bare creation-id string.
## 2. ``icrCreation`` with matching ``create`` key → ok.
## 3. ``icrDirect`` with no matching ``create`` key → ok (exempt — direct
##    references are server-persisted ids, validated separately).

{.push raises: [].}

import std/tables

import jmap_client/internal/mail/email_submission
import jmap_client/internal/mail/email_update
import jmap_client/internal/mail/submission_builders
import jmap_client/internal/protocol/builder
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/validation

import ../../massertions
import ../../mfixtures

proc makeBlueprint(): EmailSubmissionBlueprint =
  ## Minimal valid blueprint — identityId + emailId are enough; envelope
  ## defaults to none.
  parseEmailSubmissionBlueprint(identityId = makeId("idtA"), emailId = makeId("emailA"))
    .get()

proc makeUpdateSet(): EmailUpdateSet =
  ## Minimal valid update — a single markRead operation.
  initEmailUpdateSet(@[markRead()]).get()

block cidInvariantMismatchReturnsValidationError:
  ## Branch 1: onSuccessUpdateEmail keyed by ``icrCreation(CreationId("Z"))``
  ## with ``create`` ``Opt.none`` (or matching no "Z" key) returns
  ## ``err(ValidationError)`` whose ``value`` field equals ``"Z"``.
  let zCid = parseCreationId("Z").get()
  let updateSet = makeUpdateSet()
  let onUpd = parseNonEmptyOnSuccessUpdateEmail(@[(creationRef(zCid), updateSet)]).get()
  let b0 = initRequestBuilder(makeBuilderId())
  let res = b0.addEmailSubmissionAndEmailSet(
    accountId = makeAccountId("acct1"),
    create = Opt.none(Table[CreationId, EmailSubmissionBlueprint]),
    onSuccessUpdateEmail = Opt.some(onUpd),
  )
  assertErr res
  let ve = res.error()
  doAssert ve.typeName == "addEmailSubmissionAndEmailSet"
  doAssert ve.value == "Z"

block cidInvariantMatchingCreateReturnsOk:
  ## Branch 2: onSuccessUpdateEmail keyed by ``icrCreation(CreationId("Z"))``
  ## with ``create`` carrying a "Z" key returns ``ok``.
  let zCid = parseCreationId("Z").get()
  let updateSet = makeUpdateSet()
  let onUpd = parseNonEmptyOnSuccessUpdateEmail(@[(creationRef(zCid), updateSet)]).get()
  var createTbl = initTable[CreationId, EmailSubmissionBlueprint]()
  createTbl[zCid] = makeBlueprint()
  let b0 = initRequestBuilder(makeBuilderId())
  let res = b0.addEmailSubmissionAndEmailSet(
    accountId = makeAccountId("acct1"),
    create = Opt.some(createTbl),
    onSuccessUpdateEmail = Opt.some(onUpd),
  )
  assertOk res

block cidInvariantDirectRefExempt:
  ## Branch 3: onSuccessUpdateEmail keyed by ``icrDirect(Id("X"))`` with
  ## ``create`` ``Opt.none`` returns ``ok`` — direct references are
  ## server-persisted ids and exempt from the sibling-cid check (the
  ## constraint applies only to ``icrCreation``).
  let xId = makeId("X")
  let updateSet = makeUpdateSet()
  let onUpd = parseNonEmptyOnSuccessUpdateEmail(@[(directRef(xId), updateSet)]).get()
  let b0 = initRequestBuilder(makeBuilderId())
  let res = b0.addEmailSubmissionAndEmailSet(
    accountId = makeAccountId("acct1"),
    create = Opt.none(Table[CreationId, EmailSubmissionBlueprint]),
    onSuccessUpdateEmail = Opt.some(onUpd),
  )
  assertOk res

block cidInvariantMismatchInDestroyEmail:
  ## Symmetric coverage: the cid invariant must also reject mismatched
  ## creation refs in ``onSuccessDestroyEmail`` (the seq-shaped extra),
  ## not only in ``onSuccessUpdateEmail`` (the map-shaped extra).
  let zCid = parseCreationId("Z").get()
  let onDst = parseNonEmptyOnSuccessDestroyEmail(@[creationRef(zCid)]).get()
  let b0 = initRequestBuilder(makeBuilderId())
  let res = b0.addEmailSubmissionAndEmailSet(
    accountId = makeAccountId("acct1"),
    create = Opt.none(Table[CreationId, EmailSubmissionBlueprint]),
    onSuccessDestroyEmail = Opt.some(onDst),
  )
  assertErr res
  let ve = res.error()
  doAssert ve.typeName == "addEmailSubmissionAndEmailSet"
  doAssert ve.value == "Z"
