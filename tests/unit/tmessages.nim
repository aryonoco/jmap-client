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
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/primitives
import jmap_client/internal/protocol/jmap_error

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

# --- MethodOutcome (method errors are DATA, not a rail value) -------------

testCase tMethodOutcomeErrorDelegatesToMethodError:
  ## A method-level error rides ``MethodOutcome.mokMethodError``; its
  ## diagnostic is the underlying ``MethodError``'s message (the former
  ## ``GetError`` method arm, now data).
  let me = methodError("serverFail", Opt.some("internal"))
  let outcome = methodFailure[int](me)
  doAssert outcome.kind == mokMethodError
  doAssert outcome.error.message == "serverFail: internal"

# --- JmapError arms (the single consumer rail) ----------------------------

testCase tJmapErrorTransportArm:
  let je = jmapTransport(transportError(tekTimeout, "timed out"))
  doAssert je.message == "timed out"
  doAssert $je == je.message

testCase tJmapErrorRequestArm:
  let re =
    requestError("urn:ietf:params:jmap:error:limit", title = Opt.some("Limit Exceeded"))
  let je = jmapRequest(re)
  doAssert je.message == "Limit Exceeded"

testCase tJmapErrorValidationArm:
  let je =
    jmapValidation(validationError("AccountId", "contains control characters", ""))
  doAssert je.message == "AccountId: contains control characters"

testCase tSessionFaultMessage:
  let sf = sessionFault(sfCapabilityAbsent, ckMail)
  doAssert sf.message ==
    "session does not advertise the urn:ietf:params:jmap:mail capability"
  doAssert jmapSession(sf).message == sf.message

testCase tMisuseMessage:
  let m = misuse(
    initBuilderId(1'u64, 1'u64),
    initBuilderId(1'u64, 2'u64),
    parseMethodCallId("c0").get(),
  )
  doAssert "handle from a different builder" in m.message
  doAssert "callId=c0" in m.message
  doAssert jmapMisuse(
    initBuilderId(1'u64, 1'u64),
    initBuilderId(1'u64, 2'u64),
    parseMethodCallId("c0").get(),
  ).message == m.message

testCase tProtocolFaultMissingCall:
  let pf = protocolMissingCall(parseMethodCallId("c0").get())
  doAssert pf.message == "no response for call ID c0"
  doAssert jmapProtocol(pf).message == pf.message

testCase tProtocolFaultMalformedError:
  let pf = protocolMalformedError(parseMethodCallId("c0").get())
  doAssert pf.message == "malformed error response for call ID c0"

# --- $ delegates to message across every error type ----------------------

testCase tDollarParityAllTypes:
  let ve = validationError("T", "r", "v")
  doAssert $ve == ve.message
  let te = httpStatusError(503, "Service Unavailable")
  doAssert $te == te.message
  let re = requestError("urn:x")
  doAssert $re == re.message
  let je = jmapTransport(te)
  doAssert $je == je.message
  let me = methodError("rt")
  doAssert $me == me.message
  let se = setError("rt")
  doAssert $se == se.message
