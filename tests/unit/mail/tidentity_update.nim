# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for IdentityUpdate setters, initIdentityUpdateSet, and
## parseNonEmptyIdentityUpdates. The uniqueness-by-kind contract states
## that each distinct repeated ``kind`` yields exactly one error
## regardless of occurrence count; the per-id uniqueness contract on the
## outer container applies the same rule to ``Id`` keys.

{.push raises: [].}

import std/tables

import jmap_client/internal/mail/addresses
import jmap_client/internal/mail/identity
import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives

import ../../massertions
import ../../mtestblock

# ============= A. IdentityUpdate setters =============

testCase setNameConstructsCorrectKind:
  let u = setName("Alice")
  assertEq u.kind, iuSetName
  assertEq u.name, "Alice"

testCase setReplyToSomeConstructsCorrectKind:
  let ea = parseEmailAddress("a@example.com", Opt.none(string)).get()
  let u = setReplyTo(Opt.some(@[ea]))
  assertEq u.kind, iuSetReplyTo
  assertSome u.replyTo
  assertEq u.replyTo.get().len, 1

testCase setReplyToClearsWhenNone:
  let u = setReplyTo(Opt.none(seq[EmailAddress]))
  assertEq u.kind, iuSetReplyTo
  assertNone u.replyTo

testCase setBccSomeConstructsCorrectKind:
  let ea = parseEmailAddress("b@example.com", Opt.none(string)).get()
  let u = setBcc(Opt.some(@[ea]))
  assertEq u.kind, iuSetBcc
  assertSome u.bcc

testCase setTextSignatureConstructsCorrectKind:
  let u = setTextSignature("-- \nAlice")
  assertEq u.kind, iuSetTextSignature
  assertEq u.textSignature, "-- \nAlice"

testCase setHtmlSignatureConstructsCorrectKind:
  let u = setHtmlSignature("<p>Alice</p>")
  assertEq u.kind, iuSetHtmlSignature
  assertEq u.htmlSignature, "<p>Alice</p>"

# ============= B. initIdentityUpdateSet =============

testCase initIdentityUpdateSetEmpty:
  let res = initIdentityUpdateSet(@[])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "IdentityUpdateSet"
  assertEq res.error[0].message, "must contain at least one update"
  assertEq res.error[0].value, ""

testCase initIdentityUpdateSetSingleValid:
  assertOk initIdentityUpdateSet(@[setName("Alice")])

testCase initIdentityUpdateSetTwoSameKind:
  let res = initIdentityUpdateSet(@[setName("Alice"), setName("Bob")])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "IdentityUpdateSet"
  assertEq res.error[0].message, "duplicate target property"
  assertEq res.error[0].value, "iuSetName"

testCase initIdentityUpdateSetThreeSameKind:
  ## Three occurrences of the same kind still yield ONE error —
  ## the "each repeated key reported once" contract.
  let res = initIdentityUpdateSet(@[setName("A"), setName("B"), setName("C")])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].value, "iuSetName"

testCase initIdentityUpdateSetTwoDistinctRepeated:
  ## Two distinct repeated kinds → TWO errors, one per distinct
  ## duplicate key.
  let res = initIdentityUpdateSet(
    @[setName("A"), setName("B"), setTextSignature("s1"), setTextSignature("s2")]
  )
  assertErr res
  assertLen res.error, 2
  var seen: set[IdentityUpdateVariantKind] = {}
  for e in res.error:
    assertEq e.typeName, "IdentityUpdateSet"
    assertEq e.message, "duplicate target property"
    if e.value == "iuSetName":
      seen.incl iuSetName
    elif e.value == "iuSetTextSignature":
      seen.incl iuSetTextSignature
  doAssert iuSetName in seen
  doAssert iuSetTextSignature in seen

# ============= C. parseNonEmptyIdentityUpdates =============

testCase parseNonEmptyIdentityUpdatesEmpty:
  let res = parseNonEmptyIdentityUpdates(newSeq[(Id, IdentityUpdateSet)]())
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].typeName, "NonEmptyIdentityUpdates"
  assertEq res.error[0].message, "must contain at least one entry"

testCase parseNonEmptyIdentityUpdatesDuplicateId:
  let id1 = parseId("idt1").get()
  let us1 = initIdentityUpdateSet(@[setName("A")]).get()
  let us2 = initIdentityUpdateSet(@[setName("B")]).get()
  let res = parseNonEmptyIdentityUpdates(@[(id1, us1), (id1, us2)])
  assertErr res
  assertLen res.error, 1
  assertEq res.error[0].message, "duplicate identity id"

testCase parseNonEmptyIdentityUpdatesTwoDistinctIds:
  let id1 = parseId("idt1").get()
  let id2 = parseId("idt2").get()
  let us1 = initIdentityUpdateSet(@[setName("A")]).get()
  let us2 = initIdentityUpdateSet(@[setTextSignature("s")]).get()
  let res = parseNonEmptyIdentityUpdates(@[(id1, us1), (id2, us2)])
  assertOk res
  assertEq Table[Id, IdentityUpdateSet](res.get()).len, 2
