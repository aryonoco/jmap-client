# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for ``EmailSubmissionUpdate`` (value-level shape) and
## ``NonEmptyEmailSubmissionUpdates`` (non-empty + unique-Id rails).
## Pins three bright lines for the RFC 8621 §7.5 ¶3 "pending → canceled"
## update algebra: (1) the nullary ``setUndoStatusToCanceled()``
## constructor's discriminator shape, (2) the empty-input rejection
## literal, (3) the duplicate-``Id`` rejection literal. Compile-time
## phantom enforcement of "only usPending may cancel" lives in
## ``temail_submission.nim:78-91``; this file covers the value level.

{.push raises: [].}

import std/tables

import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation
import jmap_client/internal/mail/email_submission

import ../../massertions
import ../../mfixtures

block setUndoStatusToCanceledValueShape:
  # The nullary ``setUndoStatusToCanceled()`` constructor returns an
  # ``EmailSubmissionUpdate`` whose discriminator is
  # ``esuSetUndoStatusToCanceled``. Since the variant carries no fields
  # (see ``email_submission.nim:170-177`` — case object with ``discard``
  # arm), the discriminator IS the payload; pinning it is the entire
  # value-level contract. Sibling block
  # ``cancelUpdateProducesSetUndoStatusToCanceled`` in
  # ``temail_submission.nim`` pins the same shape via the
  # phantom-typed ``cancelUpdate`` wrapper; this block pins the direct
  # protocol-primitive call site.
  let u = setUndoStatusToCanceled()
  doAssert u.kind == esuSetUndoStatusToCanceled

block parseUpdatesRejectsEmpty:
  # Grep-locked literals from ``email_submission.nim:230-231``:
  #   typeName = "NonEmptyEmailSubmissionUpdates"
  #   emptyMsg = "must contain at least one entry"
  # Empty input is rejected with a single accumulating error.
  let res = parseNonEmptyEmailSubmissionUpdates(newSeq[(Id, EmailSubmissionUpdate)]())
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "NonEmptyEmailSubmissionUpdates"
  assertEq res.error[0].message, "must contain at least one entry"

block parseUpdatesRejectsDuplicateId:
  # Grep-locked literal from ``email_submission.nim:232``:
  #   dupMsg = "duplicate submission id"
  # A pair of entries sharing the same ``Id`` key surfaces exactly ONE
  # error — ``validateUniqueByIt`` reports each repeated id once
  # regardless of occurrence count (email_submission.nim:225-226).
  let id = makeId("sub-dup")
  let u = setUndoStatusToCanceled()
  let res = parseNonEmptyEmailSubmissionUpdates(@[(id, u), (id, u)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "NonEmptyEmailSubmissionUpdates"
  assertEq res.error[0].message, "duplicate submission id"

block parseUpdatesHappyPathSingleEntry:
  # Happy path: one valid ``(Id, EmailSubmissionUpdate)`` pair parses
  # to a ``NonEmptyEmailSubmissionUpdates`` whose inner table contains
  # exactly the input entry. Distinct-wrap unwrap via
  # ``Table[Id, EmailSubmissionUpdate](res.get())`` cast — same pattern
  # used by ``serde_email_submission.nim`` toJson. Iteration (not
  # ``Table.[]`` subscript) keeps this safe under ``raises: []``.
  let id = makeId("sub-1")
  let u = setUndoStatusToCanceled()
  let res = parseNonEmptyEmailSubmissionUpdates(@[(id, u)])
  assertOk res
  var count = 0
  for (k, v) in Table[Id, EmailSubmissionUpdate](res.get()).pairs:
    assertEq k, id
    doAssert v.kind == esuSetUndoStatusToCanceled
    inc count
  assertEq count, 1
