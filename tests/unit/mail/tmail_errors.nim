# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit tests for MailSetErrorType enum, parse function, and typed SetError
## accessors (scenarios 56-69 + edge cases).

import std/json

import jmap_client/mail/mail_errors
import jmap_client/validation
import jmap_client/primitives
import jmap_client/errors

import ../../massertions

# --- parseMailSetErrorType ---

block parseAllKnownTypes: # scenario 56
  ## Table-driven: every known mail set error string maps to its expected variant.
  let pairs = [
    ("mailboxHasChild", msetMailboxHasChild),
    ("mailboxHasEmail", msetMailboxHasEmail),
    ("blobNotFound", msetBlobNotFound),
    ("tooManyKeywords", msetTooManyKeywords),
    ("tooManyMailboxes", msetTooManyMailboxes),
    ("invalidEmail", msetInvalidEmail),
    ("tooManyRecipients", msetTooManyRecipients),
    ("noRecipients", msetNoRecipients),
    ("invalidRecipients", msetInvalidRecipients),
    ("forbiddenMailFrom", msetForbiddenMailFrom),
    ("forbiddenFrom", msetForbiddenFrom),
    ("forbiddenToSend", msetForbiddenToSend),
    ("cannotUnsend", msetCannotUnsend),
  ]
  for (raw, expected) in pairs:
    assertEq parseMailSetErrorType(raw), expected

block parseUnknownType: # scenario 57
  assertEq parseMailSetErrorType("someVendorError"), msetUnknown
  assertEq parseMailSetErrorType(""), msetUnknown

block parseEnumNormalization: # scenario 58
  ## parseEnum uses nimIdentNormalize: case-insensitive except first char, ignores underscores.
  assertEq parseMailSetErrorType("mailboxHas_Child"), msetMailboxHasChild
  assertEq parseMailSetErrorType("MailboxHasChild"), msetUnknown

block exhaustiveCaseCompiles: # scenario 59
  ## Verify all variants can be handled in a case statement.
  let t = parseMailSetErrorType("blobNotFound")
  let msg =
    case t
    of msetMailboxHasChild: "a"
    of msetMailboxHasEmail: "b"
    of msetBlobNotFound: "c"
    of msetTooManyKeywords: "d"
    of msetTooManyMailboxes: "e"
    of msetInvalidEmail: "f"
    of msetTooManyRecipients: "g"
    of msetNoRecipients: "h"
    of msetInvalidRecipients: "i"
    of msetForbiddenMailFrom: "j"
    of msetForbiddenFrom: "k"
    of msetForbiddenToSend: "l"
    of msetCannotUnsend: "m"
    of msetUnknown: "n"
  assertEq msg, "c"

# --- Accessor tests ---

block maxRecipientsValid: # scenario 60
  let se = setError("tooManyRecipients", extras = Opt.some(%*{"maxRecipients": 50}))
  assertSomeEq se.maxRecipients, parseUnsignedInt(50).get()

block maxRecipientsAbsent: # scenario 61
  let se = setError("tooManyRecipients")
  assertNone se.maxRecipients

block invalidRecipientAddressesValid: # scenario 62
  let se = setError(
    "invalidRecipients", extras = Opt.some(%*{"invalidRecipients": ["bad@", "worse@"]})
  )
  assertSome se.invalidRecipientAddresses
  assertEq se.invalidRecipientAddresses.get(), @["bad@", "worse@"]

block invalidRecipientAddressesMalformed: # scenario 63
  let se = setError("invalidRecipients", extras = Opt.some(%*{"invalidRecipients": 42}))
  assertNone se.invalidRecipientAddresses

block notFoundBlobIdsValid: # scenario 64
  let se =
    setError("blobNotFound", extras = Opt.some(%*{"notFound": ["blob1", "blob2"]}))
  assertSome se.notFoundBlobIds
  assertLen se.notFoundBlobIds.get(), 2
  assertEq $se.notFoundBlobIds.get()[0], "blob1"

block notFoundBlobIdsMalformed: # scenario 65
  let se = setError("blobNotFound", extras = Opt.some(%*{"notFound": "not-array"}))
  assertNone se.notFoundBlobIds

block maxSizeValid: # scenario 66
  let se = setError("tooLarge", extras = Opt.some(%*{"maxSize": 1000000}))
  assertSomeEq se.maxSize, parseUnsignedInt(1000000).get()

block maxSizeAbsent: # scenario 67
  let se = setError("tooLarge")
  assertNone se.maxSize

block invalidEmailPropertiesValid: # scenario 68
  let se = setError("invalidEmail", extras = Opt.some(%*{"properties": ["from", "to"]}))
  assertSome se.invalidEmailProperties
  assertEq se.invalidEmailProperties.get(), @["from", "to"]

block invalidEmailPropertiesMalformed: # scenario 69
  let se = setError("invalidEmail", extras = Opt.some(%*{"properties": 42}))
  assertNone se.invalidEmailProperties

# --- Additional edge cases ---

block allAccessorsReturnNoneWhenExtrasNone:
  let se = setError("tooLarge")
  assertNone se.maxSize
  assertNone se.maxRecipients
  assertNone se.notFoundBlobIds
  assertNone se.invalidRecipientAddresses
  assertNone se.invalidEmailProperties

block allAccessorsReturnNoneWhenExtrasNotObject:
  let se = setError("tooLarge", extras = Opt.some(newJArray()))
  assertNone se.maxSize
  assertNone se.notFoundBlobIds

block notFoundBlobIdsWithInvalidId:
  ## An empty string is not a valid Id (must be 1-255 octets).
  let se = setError("blobNotFound", extras = Opt.some(%*{"notFound": [""]}))
  assertNone se.notFoundBlobIds

block notFoundBlobIdsWithNonStringElement:
  let se = setError("blobNotFound", extras = Opt.some(%*{"notFound": [42]}))
  assertNone se.notFoundBlobIds

block maxSizeNegative:
  ## Negative values should fail UnsignedInt parsing.
  let se = setError("tooLarge", extras = Opt.some(%*{"maxSize": -1}))
  assertNone se.maxSize

block invalidEmailPropertiesEmptyArray:
  let se = setError("invalidEmail", extras = Opt.some(%*{"properties": []}))
  assertSome se.invalidEmailProperties
  assertLen se.invalidEmailProperties.get(), 0
