# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only audit of the application-developer-facing seal on the
## library-internal error constructors (A12 / P15). Compiling this file
## proves that ``import jmap_client`` does not expose the raw error
## constructors. App developers receive error values; they do not
## construct them. The Transport-contract producers
## (``transportError`` / ``httpStatusError`` / ``sizeLimitExceeded`` /
## ``classifyTransportException`` / ``enforceBodySizeLimit``) remain public by
## A19 because custom ``Transport`` implementations must return a
## ``TransportError`` on failure. See ``docs/design/15-error-surface.md``.

import jmap_client

static:
  # =========================================================================
  # POSITIVE — the public diagnostic surface remains reachable. ``JmapError``
  # is the single consumer rail; its arms are built via the public lifts.
  # =========================================================================

  let je = jmapTransport(transportError(tekNetwork, ""))
  doAssert compiles(je.kind)
  doAssert compiles(je.message)
  doAssert compiles($je)

  # =========================================================================
  # POSITIVE — the sanctioned boundary lifts onto the one rail are public:
  # app developers fold leaf rails into ``JmapError`` (they still do not mint
  # the leaf error values themselves).
  # =========================================================================

  doAssert declared(jmapValidation)
  doAssert declared(jmapTransport)
  doAssert declared(jmapRequest)
  doAssert declared(jmapSession)
  doAssert declared(sessionFault)
  doAssert declared(toJmapError)
  doAssert declared(lift)

  # =========================================================================
  # NEGATIVE — library-internal error constructors are unreachable. This
  # includes the retired rails (ClientError / GetError producers) and the
  # internal-only JmapError arm constructors (misuse / protocol / the
  # MethodOutcome producers are minted by dispatch, not by consumers).
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
  doAssert not declared(jmapMisuse)
  doAssert not declared(jmapProtocol)
  doAssert not declared(protocolMissingCall)
  doAssert not declared(protocolMalformedError)
  doAssert not declared(protocolDecode)
  doAssert not declared(methodValue)
  doAssert not declared(methodFailure)

  # =========================================================================
  # POSITIVE — Transport-contract producers remain public (A19).
  # =========================================================================

  doAssert declared(transportError)
  doAssert declared(httpStatusError)
  doAssert declared(sizeLimitExceeded)
  doAssert declared(classifyTransportException)
  doAssert declared(enforceBodySizeLimit)

  # =========================================================================
  # POSITIVE — total parsers remain public for downstream classification.
  # =========================================================================

  doAssert declared(parseRequestErrorKind)
  doAssert declared(parseMethodErrorKind)
  doAssert declared(parseSetErrorKind)
