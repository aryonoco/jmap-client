# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for the RFC 8621 mail-specific SetError variants and the
## mail-layer typed accessors (scenarios 56-69 + edge cases).
## ``MailSetErrorType`` is gone — mail variants live in the central
## ``SetErrorType`` and are parsed via ``parseSetErrorType``.

import std/json

import jmap_client/internal/mail/mail_errors
import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/errors

import ../../massertions
import ../../mtestblock

# --- parseSetErrorType (mail-specific variants) ---

testCase parseAllKnownTypes: # scenario 56
  ## Table-driven: every known mail set error string maps to its expected variant.
  let pairs = [
    ("mailboxHasChild", setMailboxHasChild),
    ("mailboxHasEmail", setMailboxHasEmail),
    ("blobNotFound", setBlobNotFound),
    ("tooManyKeywords", setTooManyKeywords),
    ("tooManyMailboxes", setTooManyMailboxes),
    ("invalidEmail", setInvalidEmail),
    ("tooManyRecipients", setTooManyRecipients),
    ("noRecipients", setNoRecipients),
    ("invalidRecipients", setInvalidRecipients),
    ("forbiddenMailFrom", setForbiddenMailFrom),
    ("forbiddenFrom", setForbiddenFrom),
    ("forbiddenToSend", setForbiddenToSend),
    ("cannotUnsend", setCannotUnsend),
  ]
  for (raw, expected) in pairs:
    assertEq parseSetErrorType(raw), expected

testCase parseUnknownType: # scenario 57
  assertEq parseSetErrorType("someVendorError"), setUnknown
  assertEq parseSetErrorType(""), setUnknown

testCase parseEnumNormalization: # scenario 58
  ## parseEnum uses nimIdentNormalize: case-insensitive except first char, ignores underscores.
  assertEq parseSetErrorType("mailboxHas_Child"), setMailboxHasChild
  assertEq parseSetErrorType("MailboxHasChild"), setUnknown

# --- Accessor tests ---

testCase maxRecipientsValid: # scenario 60
  let se = setErrorTooManyRecipients("tooManyRecipients", parseUnsignedInt(50).get())
  assertSomeEq se.maxRecipients, parseUnsignedInt(50).get()

testCase maxRecipientsAbsent: # scenario 61
  let se = setError("tooManyRecipients")
  assertNone se.maxRecipients

testCase invalidRecipientAddressesValid: # scenario 62
  let se = setErrorInvalidRecipients("invalidRecipients", @["bad@", "worse@"])
  assertSome se.invalidRecipientAddresses
  assertEq se.invalidRecipientAddresses.get(), @["bad@", "worse@"]

testCase invalidRecipientAddressesMalformed: # scenario 63
  # Missing payload falls back to setUnknown via defensive setError.
  let se = setError("invalidRecipients", extras = Opt.some(%*{"invalidRecipients": 42}))
  assertNone se.invalidRecipientAddresses

testCase notFoundBlobIdsValid: # scenario 64
  let se = setErrorBlobNotFound(
    "blobNotFound", @[parseBlobId("blob1").get(), parseBlobId("blob2").get()]
  )
  assertSome se.notFoundBlobIds
  assertLen se.notFoundBlobIds.get(), 2
  assertEq $se.notFoundBlobIds.get()[0], "blob1"

testCase notFoundBlobIdsMalformed: # scenario 65
  let se = setError("blobNotFound", extras = Opt.some(%*{"notFound": "not-array"}))
  assertNone se.notFoundBlobIds

testCase maxSizeValid: # scenario 66
  let se = setErrorTooLarge("tooLarge", Opt.some(parseUnsignedInt(1000000).get()))
  assertSomeEq se.maxSize, parseUnsignedInt(1000000).get()

testCase maxSizeAbsent: # scenario 67
  let se = setError("tooLarge")
  assertNone se.maxSize

testCase invalidEmailPropertiesValid: # scenario 68
  let se = setErrorInvalidEmail("invalidEmail", @["from", "to"])
  assertSome se.invalidEmailProperties
  assertEq se.invalidEmailProperties.get(), @["from", "to"]

testCase invalidEmailPropertiesMalformed: # scenario 69
  let se = setError("invalidEmail", extras = Opt.some(%*{"properties": 42}))
  assertNone se.invalidEmailProperties

# --- Additional edge cases ---

testCase allAccessorsReturnNoneWhenExtrasNone:
  let se = setError("tooLarge")
  assertNone se.maxSize
  assertNone se.maxRecipients
  assertNone se.notFoundBlobIds
  assertNone se.invalidRecipientAddresses
  assertNone se.invalidEmailProperties

testCase allAccessorsReturnNoneOnWrongVariant:
  let se = setError("forbidden")
  assertNone se.maxSize
  assertNone se.notFoundBlobIds

testCase invalidEmailPropertiesEmptyArray:
  let se = setErrorInvalidEmail("invalidEmail", @[])
  assertSome se.invalidEmailProperties
  assertLen se.invalidEmailProperties.get(), 0
