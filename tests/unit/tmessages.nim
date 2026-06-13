# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Unit pins for the A12 canonical ``message()`` projection on every
## error type. Locks the per-variant format string; the
## ``tests/wire_contract/error-messages.txt`` snapshot + H15 lint pin
## the corpus, this file pins the format rule per-variant.

import std/strutils

import jmap_client
import jmap_client/internal/types/validation
import jmap_client/internal/types/errors
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/primitives

import ../mtestblock

# --- ValidationError -------------------------------------------------------

testCase tValidationErrorMessage:
  let ve = validationError("AccountId", "contains control characters", "abc\x01")
  doAssert ve.message == "AccountId: contains control characters"
  doAssert $ve == ve.message
  # Redaction (D4): the value MUST NOT be in the projection.
  doAssert "abc" notin ve.message

# --- TransportError --------------------------------------------------------

testCase tTransportErrorMessageHttp:
  let te = httpStatusError(503, "Service Unavailable")
  doAssert te.message == "HTTP 503: Service Unavailable"
  doAssert $te == te.message

testCase tTransportErrorMessageNetwork:
  let te = transportError(tekNetwork, "connection refused")
  doAssert te.message == "connection refused"
  doAssert $te == te.message

testCase tTransportErrorMessageTls:
  let te = transportError(tekTls, "certificate verify failed")
  doAssert te.message == "certificate verify failed"

testCase tTransportErrorMessageTimeout:
  let te = transportError(tekTimeout, "operation timed out")
  doAssert te.message == "operation timed out"

# --- MethodError -----------------------------------------------------------

testCase tMethodErrorMessageWithDescription:
  let me = methodError("serverFail", Opt.some("internal error"))
  doAssert me.message == "serverFail: internal error"
  doAssert $me == me.message

testCase tMethodErrorMessageWithoutDescription:
  let me = methodError("serverFail")
  doAssert me.message == "serverFail"

testCase tMethodErrorMessageEmptyDescription:
  let me = methodError("serverFail", Opt.some(""))
  doAssert me.message == "serverFail"

# --- SetError --------------------------------------------------------------

testCase tSetErrorInvalidProperties:
  let se = setErrorInvalidProperties("invalidProperties", @["from", "to"])
  doAssert se.message == "invalidProperties: from, to"

testCase tSetErrorAlreadyExists:
  let id = parseId("abc123").get()
  let se = setErrorAlreadyExists("alreadyExists", id)
  doAssert se.message == "alreadyExists: abc123"

testCase tSetErrorBlobNotFound:
  let b1 = parseBlobId("blob-1").get()
  let b2 = parseBlobId("blob-2").get()
  let se = setErrorBlobNotFound("blobNotFound", @[b1, b2])
  doAssert se.message == "blobNotFound: blob-1, blob-2"

testCase tSetErrorInvalidEmail:
  let se = setErrorInvalidEmail("invalidEmail", @["headers", "subject"])
  doAssert se.message == "invalidEmail: headers, subject"

testCase tSetErrorTooManyRecipients:
  let cap = parseUnsignedInt(100'i64).get()
  let se = setErrorTooManyRecipients("tooManyRecipients", cap)
  doAssert se.message == "tooManyRecipients: max=100"

testCase tSetErrorInvalidRecipients:
  let se = setErrorInvalidRecipients("invalidRecipients", @["bad@", "@example"])
  doAssert se.message == "invalidRecipients: bad@, @example"

testCase tSetErrorTooLargeWithCap:
  let cap = parseUnsignedInt(1048576'i64).get()
  let se = setErrorTooLarge("tooLarge", Opt.some(cap))
  doAssert se.message == "tooLarge: maxSize=1048576 octets"

testCase tSetErrorTooLargeNoCap:
  let se = setErrorTooLarge("tooLarge")
  doAssert se.message == "tooLarge"

testCase tSetErrorPayloadlessWithDescription:
  let se = setError("forbidden", Opt.some("not allowed"))
  doAssert se.message == "forbidden: not allowed"

testCase tSetErrorPayloadlessWithoutDescription:
  let se = setError("forbidden")
  doAssert se.message == "forbidden"

# --- GetError delegates to MethodError ------------------------------------

testCase tGetErrorMethodDelegatesToMethodError:
  let me = methodError("serverFail", Opt.some("internal"))
  let ge = getErrorMethod(me)
  doAssert ge.message == me.message
  doAssert ge.message == "serverFail: internal"

# --- ClientError -----------------------------------------------------------

testCase tClientErrorMessageTransport:
  let ce = clientError(transportError(tekTimeout, "timed out"))
  doAssert ce.message == "timed out"

testCase tClientErrorMessageRequest:
  let re =
    requestError("urn:ietf:params:jmap:error:limit", title = Opt.some("Limit Exceeded"))
  let ce = clientError(re)
  doAssert ce.message == "Limit Exceeded"

# --- $ delegates to message across every error type ----------------------

testCase tDollarParityAllTypes:
  let ve = validationError("T", "r", "v")
  doAssert $ve == ve.message
  let te = httpStatusError(503, "Service Unavailable")
  doAssert $te == te.message
  let re = requestError("urn:x")
  doAssert $re == re.message
  let ce = clientError(te)
  doAssert $ce == ce.message
  let me = methodError("rt")
  doAssert $me == me.message
  let se = setError("rt")
  doAssert $se == se.message
