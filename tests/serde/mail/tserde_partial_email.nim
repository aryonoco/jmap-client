# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for ``PartialEmail`` (A4 + A3.6 D2/D4). Covers:
##   * absent / null / value three-state distinction for wire-nullable
##     fields (``FieldEcho``);
##   * absent vs value two-state for wire-non-nullable fields (``Opt``);
##   * strict-on-wrong-kind rejection for present fields;
##   * lossless round-trip through ``parse(emit(parse(json))) ==
##     parse(json)``.

import std/json

import jmap_client/internal/mail/email
import jmap_client/internal/mail/serde_email
import jmap_client/internal/types/field_echo
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/primitives
import jmap_client/internal/types/validation

import ../../massertions
import ../../mtestblock

# ============= A. Empty object =============

testCase emptyObject:
  ## Every field absent — ``Opt.none`` for the two-state fields,
  ## ``fekAbsent`` for the three-state fields.
  let node = %*{}
  let res = PartialEmail.fromJson(node)
  assertOk res
  let p = res.get()
  doAssert p.id.isNone
  doAssert p.blobId.isNone
  doAssert p.threadId.isNone
  doAssert p.size.isNone
  doAssert p.subject.kind == fekAbsent
  doAssert p.sentAt.kind == fekAbsent
  doAssert p.fromAddr.kind == fekAbsent
  doAssert p.headers.isNone
  doAssert p.requestedHeaders.isNone

# ============= B. Wire-nullable absent vs null vs value =============

testCase subjectAbsent:
  let node = %*{}
  let p = PartialEmail.fromJson(node).get()
  doAssert p.subject.kind == fekAbsent

testCase subjectNull:
  let node = %*{"subject": nil}
  let p = PartialEmail.fromJson(node).get()
  doAssert p.subject.kind == fekNull

testCase subjectValue:
  let node = %*{"subject": "Hello"}
  let p = PartialEmail.fromJson(node).get()
  doAssert p.subject.kind == fekValue
  doAssert p.subject.value == "Hello"

# ============= C. Wire-non-nullable absent vs value =============

testCase idAbsent:
  let node = %*{}
  let p = PartialEmail.fromJson(node).get()
  doAssert p.id.isNone

testCase idValue:
  let node = %*{"id": "e1"}
  let p = PartialEmail.fromJson(node).get()
  doAssert p.id.isSome
  doAssert p.id.get() == parseIdFromServer("e1").get()

# ============= D. Strict-on-wrong-kind for present fields =============

testCase idWrongKindRejected:
  ## A present ``id`` of the wrong kind (here: integer) surfaces as a
  ## SerdeViolation per A4 D4.
  let node = %*{"id": 42}
  let res = PartialEmail.fromJson(node)
  doAssert res.isErr

testCase subjectWrongKindRejected:
  ## A present ``subject`` of the wrong kind (here: integer) surfaces
  ## as a SerdeViolation.
  let node = %*{"subject": 42}
  let res = PartialEmail.fromJson(node)
  doAssert res.isErr

# ============= E. Round-trip =============

testCase roundTripEmpty:
  let original = %*{}
  let p1 = PartialEmail.fromJson(original).get()
  let emitted = p1.toJson()
  let p2 = PartialEmail.fromJson(emitted).get()
  # Structural equality on field discriminators
  doAssert p1.id.isNone == p2.id.isNone
  doAssert p1.subject.kind == p2.subject.kind

testCase roundTripMixed:
  let original =
    %*{"id": "e1", "subject": nil, "size": 1024, "from": [{"email": "a@example.com"}]}
  let p1 = PartialEmail.fromJson(original).get()
  let emitted = p1.toJson()
  let p2 = PartialEmail.fromJson(emitted).get()
  doAssert p1.id == p2.id
  doAssert p1.subject.kind == p2.subject.kind
  doAssert p1.size == p2.size
  doAssert p1.fromAddr.kind == p2.fromAddr.kind
