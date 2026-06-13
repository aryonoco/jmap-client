# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Companion to tcompile_a12_error_constructor_surface: proves that the
## library-internal error constructors filtered off the hub remain
## reachable via direct H10-permitted imports of the defining modules.
## Tests under tests/ may reach internal modules directly; the seal in
## the sibling file applies to the application-developer-facing hub.

import jmap_client/internal/types/validation
import jmap_client/internal/types/errors

static:
  doAssert compiles(validationError("T", "r", "v"))
  doAssert compiles(requestError("urn:x"))
  doAssert compiles(methodError("rt"))
  doAssert compiles(setError("rt"))
  doAssert compiles(clientError(transportError(tekNetwork, "")))
  doAssert compiles(getErrorMethod(methodError("rt")))
