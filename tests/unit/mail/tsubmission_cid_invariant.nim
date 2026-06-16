# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A6.6 per-call cid invariant tests for ``parseEmailSubmissionSet``.
## RFC 8620 §5.3 ties every ``icrCreation(cid)`` reference in
## ``onSuccessUpdateEmail`` and ``onSuccessDestroyEmail`` to a
## ``CreationId`` appearing as a key in ``create`` on the same call.
## The smart constructor enforces this at construction time, accumulating
## EVERY bad reference onto a ``NonEmptySeq[ValidationError]``; a sealed
## ``EmailSubmissionSetSpec`` results only when the cross-reference holds,
## so the builder that consumes it is total — the failure never reaches
## the wire as a server-side ``SetError(setNotFound)`` round-trip.
##
## Branches:
## 1. ``icrCreation`` with no matching ``create`` key → err(NonEmptySeq)
##    whose head ``value`` field equals the bare creation-id string.
## 2. ``icrCreation`` with matching ``create`` key → ok.
## 3. ``icrDirect`` with no matching ``create`` key → ok (exempt — direct
##    references are server-persisted ids, validated separately).
## 4. ``icrCreation`` in ``onSuccessDestroyEmail`` (the seq-shaped extra)
##    → err (symmetric with the map-shaped extra).
## 5. Multiple bad references across both extras → err accumulating ALL.

{.push raises: [].}

import std/tables

import jmap_client/internal/mail/email_submission
import jmap_client/internal/mail/email_update
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation

import ../../massertions
import ../../mfixtures
import ../../mtestblock

proc makeBlueprint(): EmailSubmissionBlueprint =
  ## Minimal valid blueprint — identityId + emailId are enough; envelope
  ## defaults to none.
  parseEmailSubmissionBlueprint(
    identityId = makeId("idtA"), emailId = directRef(makeId("emailA"))
  )
    .get()

proc makeUpdateSet(): EmailUpdateSet =
  ## Minimal valid update — a single markRead operation.
  initEmailUpdateSet(@[markRead()]).get()

testCase cidInvariantMismatchReturnsValidationError:
  ## Branch 1: onSuccessUpdateEmail keyed by ``creationRef(parseCreationId("Z").get())``
  ## with ``create`` ``Opt.none`` returns ``err`` whose head ``typeName``
  ## is ``"EmailSubmissionSetSpec"`` and head ``value`` equals ``"Z"``.
  let zCid = parseCreationId("Z").get()
  let updateSet = makeUpdateSet()
  let onUpd = parseNonEmptyOnSuccessUpdateEmail(@[(creationRef(zCid), updateSet)]).get()
  let res = parseEmailSubmissionSet(
    create = Opt.none(Table[CreationId, EmailSubmissionBlueprint]),
    onSuccessUpdateEmail = Opt.some(onUpd),
  )
  assertErr res
  let ve = res.error().head
  doAssert ve.typeName == "EmailSubmissionSetSpec"
  doAssert ve.value == "Z"

testCase cidInvariantMatchingCreateReturnsOk:
  ## Branch 2: onSuccessUpdateEmail keyed by ``creationRef(parseCreationId("Z").get())``
  ## with ``create`` carrying a "Z" key returns ``ok``.
  let zCid = parseCreationId("Z").get()
  let updateSet = makeUpdateSet()
  let onUpd = parseNonEmptyOnSuccessUpdateEmail(@[(creationRef(zCid), updateSet)]).get()
  var createTbl = initTable[CreationId, EmailSubmissionBlueprint]()
  createTbl[zCid] = makeBlueprint()
  let res = parseEmailSubmissionSet(
    create = Opt.some(createTbl), onSuccessUpdateEmail = Opt.some(onUpd)
  )
  assertOk res

testCase cidInvariantDirectRefExempt:
  ## Branch 3: onSuccessUpdateEmail keyed by ``directRef(makeId("X"))`` with
  ## ``create`` ``Opt.none`` returns ``ok`` — direct references are
  ## server-persisted ids and exempt from the sibling-cid check (the
  ## constraint applies only to ``icrCreation``).
  let xId = makeId("X")
  let updateSet = makeUpdateSet()
  let onUpd = parseNonEmptyOnSuccessUpdateEmail(@[(directRef(xId), updateSet)]).get()
  let res = parseEmailSubmissionSet(
    create = Opt.none(Table[CreationId, EmailSubmissionBlueprint]),
    onSuccessUpdateEmail = Opt.some(onUpd),
  )
  assertOk res

testCase cidInvariantMismatchInDestroyEmail:
  ## Branch 4: symmetric coverage — the cid invariant must also reject a
  ## mismatched creation ref in ``onSuccessDestroyEmail`` (the seq-shaped
  ## extra), not only in ``onSuccessUpdateEmail`` (the map-shaped extra).
  let zCid = parseCreationId("Z").get()
  let onDst = parseNonEmptyOnSuccessDestroyEmail(@[creationRef(zCid)]).get()
  let res = parseEmailSubmissionSet(
    create = Opt.none(Table[CreationId, EmailSubmissionBlueprint]),
    onSuccessDestroyEmail = Opt.some(onDst),
  )
  assertErr res
  let ve = res.error().head
  doAssert ve.typeName == "EmailSubmissionSetSpec"
  doAssert ve.value == "Z"

testCase cidInvariantMultipleBadRefsAccumulate:
  ## Branch 5: a bad creation ref in EACH extra (``"Y"`` in the update map,
  ## ``"Z"`` in the destroy seq), with ``create`` ``Opt.none``, accumulates
  ## BOTH onto the error rail — the constructor reports every offending
  ## reference, not just the first.
  let yCid = parseCreationId("Y").get()
  let zCid = parseCreationId("Z").get()
  let updateSet = makeUpdateSet()
  let onUpd = parseNonEmptyOnSuccessUpdateEmail(@[(creationRef(yCid), updateSet)]).get()
  let onDst = parseNonEmptyOnSuccessDestroyEmail(@[creationRef(zCid)]).get()
  let res = parseEmailSubmissionSet(
    create = Opt.none(Table[CreationId, EmailSubmissionBlueprint]),
    onSuccessUpdateEmail = Opt.some(onUpd),
    onSuccessDestroyEmail = Opt.some(onDst),
  )
  assertErr res
  let errs = res.error()
  doAssert errs.len == 2
  var sawY = false
  var sawZ = false
  for ve in errs.items:
    doAssert ve.typeName == "EmailSubmissionSetSpec"
    if ve.value == "Y":
      sawY = true
    elif ve.value == "Z":
      sawZ = true
  doAssert sawY and sawZ
