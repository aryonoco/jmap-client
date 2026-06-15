# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Companion to tcompile_a12_error_constructor_surface: proves that the
## library-internal error constructors filtered off the hub remain
## reachable via direct H10-permitted imports of the defining modules.
## Tests under tests/ may reach internal modules directly; the seal in
## the sibling file applies to the application-developer-facing hub.

import jmap_client/internal/types/validation
import jmap_client/internal/types/errors
import jmap_client/internal/protocol/jmap_error

static:
  doAssert compiles(validationError("T", "r", "v"))
  doAssert compiles(requestError("urn:x"))
  doAssert compiles(methodError("rt"))
  doAssert compiles(setError("rt"))
  # The internal-only ``JmapError`` arm constructors and the ``MethodOutcome``
  # producers (filtered off the hub) remain reachable via the defining module.
  doAssert declared(jmapMisuse)
  doAssert declared(jmapProtocol)
  doAssert declared(protocolMissingCall)
  doAssert declared(protocolMalformedError)
  doAssert declared(protocolDecode)
  doAssert declared(methodValue)
  doAssert declared(methodFailure)
