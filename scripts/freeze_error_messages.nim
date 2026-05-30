# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Regenerator for the H15 error-message snapshot. Enumerates the 38
## representative error values in declaration order, projects each via
## ``message()``, and writes the locked-format snapshot to stdout. The
## ``just freeze-error-messages`` recipe redirects stdout onto
## ``tests/wire_contract/error-messages.txt``.
##
## Determinism: no Tables iteration, no Rand, no environment reads. The
## samples are a literal sequence of (label, value) pairs in declaration
## order. The H15 lint inlines the same sequence verbatim so the two
## cannot diverge on the source-of-truth definition.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/validation
import jmap_client/internal/types/errors
import jmap_client/internal/types/identifiers

proc emit(label, message: string) =
  echo "[" & label & "]"
  echo "  " & message

proc main() =
  echo "# H15 error-message snapshot — locked by tests/lint/h15_error_message_snapshot.nim"
  echo "# Regenerate with: just freeze-error-messages"
  echo "# Update PR label: [ERR-MSG-CHANGE]"
  echo ""

  # --- ValidationError ----------------------------------------------------
  echo "## ValidationError"
  let ve1 = validationError("AccountId", "contains control characters", "")
  emit("validationError(\"AccountId\", \"contains control characters\", \"\")", ve1.message)
  let ve2 = validationError("Id", "length must be 1-255 octets", "")
  emit("validationError(\"Id\", \"length must be 1-255 octets\", \"\")", ve2.message)
  let ve3 = validationError("UnsignedInt", "must be non-negative", "-1")
  emit("validationError(\"UnsignedInt\", \"must be non-negative\", \"-1\")", ve3.message)
  let ve4 = validationError("Keyword", "contains forbidden character", "")
  emit("validationError(\"Keyword\", \"contains forbidden character\", \"\")", ve4.message)
  let ve5 = validationError("Account", "name contains control characters", "bad\x01name")
  emit("validationError(\"Account\", \"name contains control characters\", \"bad\\x01name\")", ve5.message)
  let ve6 = validationError("ServerCapability", "ckCore requires CoreCapabilities", "urn:ietf:params:jmap:core")
  emit("validationError(\"ServerCapability\", \"ckCore requires CoreCapabilities\", \"urn:ietf:params:jmap:core\")", ve6.message)
  let ve7 = validationError("AccountCapabilityEntry", "ckMail requires MailAccountCapabilities", "urn:ietf:params:jmap:mail")
  emit("validationError(\"AccountCapabilityEntry\", \"ckMail requires MailAccountCapabilities\", \"urn:ietf:params:jmap:mail\")", ve7.message)
  let ve8 = validationError("AccountCapabilityEntry", "ckSubmission requires SubmissionAccountCapabilities", "urn:ietf:params:jmap:submission")
  emit("validationError(\"AccountCapabilityEntry\", \"ckSubmission requires SubmissionAccountCapabilities\", \"urn:ietf:params:jmap:submission\")", ve8.message)
  let ve9 = validationError("MailAccountCapabilities", "maxMailboxesPerEmail must be >= 1", "0")
  emit("validationError(\"MailAccountCapabilities\", \"maxMailboxesPerEmail must be >= 1\", \"0\")", ve9.message)
  let ve10 = validationError("MailAccountCapabilities", "maxSizeMailboxName must be >= 100", "99")
  emit("validationError(\"MailAccountCapabilities\", \"maxSizeMailboxName must be >= 100\", \"99\")", ve10.message)
  echo ""

  # --- TransportError -----------------------------------------------------
  echo "## TransportError"
  let te1 = transportError(tekNetwork, "connection refused")
  emit("transportError(tekNetwork, \"connection refused\")", te1.message)
  let te2 = transportError(tekTls, "certificate verify failed")
  emit("transportError(tekTls, \"certificate verify failed\")", te2.message)
  let te3 = transportError(tekTimeout, "operation timed out")
  emit("transportError(tekTimeout, \"operation timed out\")", te3.message)
  let te4 = httpStatusError(503, "Service Unavailable")
  emit("httpStatusError(503, \"Service Unavailable\")", te4.message)
  echo ""

  # --- RequestError -------------------------------------------------------
  echo "## RequestError"
  let re1 = requestError(
    "urn:ietf:params:jmap:error:unknownCapability",
    detail = Opt.some("missing urn:ietf:params:jmap:contacts"),
  )
  emit(
    "requestError(\"urn:ietf:params:jmap:error:unknownCapability\", detail = Opt.some(\"missing urn:ietf:params:jmap:contacts\"))",
    re1.message,
  )
  let re2 =
    requestError("urn:ietf:params:jmap:error:notJSON", title = Opt.some("Not JSON"))
  emit(
    "requestError(\"urn:ietf:params:jmap:error:notJSON\", title = Opt.some(\"Not JSON\"))",
    re2.message,
  )
  let re3 = requestError("urn:ietf:params:jmap:error:notRequest")
  emit("requestError(\"urn:ietf:params:jmap:error:notRequest\")", re3.message)
  let re4 = requestError(
    "urn:ietf:params:jmap:error:limit",
    title = Opt.some("Limit Exceeded"),
    detail = Opt.some("maxCallsInRequest=500"),
  )
  emit(
    "requestError(\"urn:ietf:params:jmap:error:limit\", title = Opt.some(\"Limit Exceeded\"), detail = Opt.some(\"maxCallsInRequest=500\"))",
    re4.message,
  )
  let re5 = requestError("urn:example:vendor:custom")
  emit("requestError(\"urn:example:vendor:custom\")", re5.message)
  echo ""

  # --- MethodError --------------------------------------------------------
  echo "## MethodError"
  let me1 = methodError("serverFail", Opt.some("internal error"))
  emit("methodError(\"serverFail\", Opt.some(\"internal error\"))", me1.message)
  let me2 = methodError("invalidArguments", Opt.some("missing field 'accountId'"))
  emit(
    "methodError(\"invalidArguments\", Opt.some(\"missing field 'accountId'\"))",
    me2.message,
  )
  let me3 = methodError("accountNotFound", Opt.some("no account 'A1'"))
  emit("methodError(\"accountNotFound\", Opt.some(\"no account 'A1'\"))", me3.message)
  let me4 = methodError("forbidden")
  emit("methodError(\"forbidden\")", me4.message)
  let me5 = methodError("stateMismatch")
  emit("methodError(\"stateMismatch\")", me5.message)
  let me6 = methodError("serverFail", Opt.some(""))
  emit("methodError(\"serverFail\", Opt.some(\"\"))", me6.message)
  echo ""

  # --- SetError -----------------------------------------------------------
  echo "## SetError"
  let se1 = setErrorInvalidProperties("invalidProperties", @["from", "to"])
  emit(
    "setErrorInvalidProperties(\"invalidProperties\", @[\"from\", \"to\"])", se1.message
  )
  let se2 = setErrorAlreadyExists("alreadyExists", parseId("abc123").get())
  emit("setErrorAlreadyExists(\"alreadyExists\", parseId(\"abc123\").get())", se2.message)
  let se3 = setErrorBlobNotFound(
    "blobNotFound", @[parseBlobId("blob-1").get(), parseBlobId("blob-2").get()]
  )
  emit(
    "setErrorBlobNotFound(\"blobNotFound\", @[parseBlobId(\"blob-1\").get(), parseBlobId(\"blob-2\").get()])",
    se3.message,
  )
  let se4 = setErrorInvalidEmail("invalidEmail", @["headers", "subject"])
  emit("setErrorInvalidEmail(\"invalidEmail\", @[\"headers\", \"subject\"])", se4.message)
  let se5 =
    setErrorTooManyRecipients("tooManyRecipients", parseUnsignedInt(100'i64).get())
  emit(
    "setErrorTooManyRecipients(\"tooManyRecipients\", parseUnsignedInt(100).get())",
    se5.message,
  )
  let se6 = setErrorInvalidRecipients("invalidRecipients", @["bad@", "@example"])
  emit(
    "setErrorInvalidRecipients(\"invalidRecipients\", @[\"bad@\", \"@example\"])",
    se6.message,
  )
  let se7 = setErrorTooLarge("tooLarge", Opt.some(parseUnsignedInt(1048576'i64).get()))
  emit(
    "setErrorTooLarge(\"tooLarge\", Opt.some(parseUnsignedInt(1048576).get()))",
    se7.message,
  )
  let se8 = setError("forbidden", Opt.some("not allowed"))
  emit("setError(\"forbidden\", Opt.some(\"not allowed\"))", se8.message)
  let se9 = setError("overQuota")
  emit("setError(\"overQuota\")", se9.message)
  echo ""

  # --- ClientError --------------------------------------------------------
  echo "## ClientError"
  let ce1 = clientError(httpStatusError(503, "Service Unavailable"))
  emit("clientError(httpStatusError(503, \"Service Unavailable\"))", ce1.message)
  let ce2 = clientError(
    requestError("urn:ietf:params:jmap:error:limit", title = Opt.some("Limit Exceeded"))
  )
  emit(
    "clientError(requestError(\"urn:ietf:params:jmap:error:limit\", title = Opt.some(\"Limit Exceeded\")))",
    ce2.message,
  )
  echo ""

  # --- GetError -----------------------------------------------------------
  echo "## GetError"
  let ge1 = getErrorMethod(methodError("serverFail", Opt.some("internal")))
  emit("getErrorMethod(methodError(\"serverFail\", Opt.some(\"internal\")))", ge1.message)
  let ge2 = getErrorHandleMismatch(
    initBuilderId(1'u64, 1'u64),
    initBuilderId(1'u64, 2'u64),
    parseMethodCallId("c0").get(),
  )
  emit(
    "getErrorHandleMismatch(initBuilderId(1'u64, 1'u64), initBuilderId(1'u64, 2'u64), parseMethodCallId(\"c0\").get())",
    ge2.message,
  )

when isMainModule:
  main()
