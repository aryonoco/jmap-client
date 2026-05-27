# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only audit of the application-developer-facing seal on the
## library-internal error constructors (A12 / P15). Compiling this file
## proves that ``import jmap_client`` does not expose the raw error
## constructors. App developers receive error values; they do not
## construct them. The Transport-contract producers
## (``transportError`` / ``httpStatusError`` / ``sizeLimitExceeded`` /
## ``classifyTransportException`` / ``classifyException`` /
## ``enforceBodySizeLimit``) remain public by A19 because custom
## ``Transport`` implementations must return a ``TransportError`` on
## failure. See ``docs/design/15-error-surface.md``.

import jmap_client

static:
  # =========================================================================
  # POSITIVE — the public diagnostic surface remains reachable.
  # =========================================================================

  let ce = ClientError(
    kind: cekTransport, transport: TransportError(kind: tekNetwork, detail: "")
  )
  doAssert compiles(ce.kind)
  doAssert compiles(ce.message)
  doAssert compiles($ce)

  # =========================================================================
  # NEGATIVE — library-internal error constructors are unreachable.
  # =========================================================================

  doAssert not declared(validationError)
  doAssert not declared(requestError)
  doAssert not declared(methodError)
  doAssert not declared(setError)
  doAssert not declared(setErrorInvalidProperties)
  doAssert not declared(setErrorAlreadyExists)
  doAssert not declared(setErrorBlobNotFound)
  doAssert not declared(setErrorInvalidEmail)
  doAssert not declared(setErrorTooManyRecipients)
  doAssert not declared(setErrorInvalidRecipients)
  doAssert not declared(setErrorTooLarge)
  doAssert not declared(clientError)
  doAssert not declared(validationToClientError)
  doAssert not declared(validationToClientErrorCtx)
  doAssert not declared(getErrorMethod)
  doAssert not declared(getErrorHandleMismatch)
  doAssert not declared(toValidationError)

  # =========================================================================
  # POSITIVE — Transport-contract producers remain public (A19).
  # =========================================================================

  doAssert declared(transportError)
  doAssert declared(httpStatusError)
  doAssert declared(sizeLimitExceeded)
  doAssert declared(classifyTransportException)
  doAssert declared(classifyException)
  doAssert declared(enforceBodySizeLimit)

  # =========================================================================
  # POSITIVE — total parsers remain public for downstream classification.
  # =========================================================================

  doAssert declared(parseRequestErrorKind)
  doAssert declared(parseMethodErrorKind)
  doAssert declared(parseSetErrorKind)
