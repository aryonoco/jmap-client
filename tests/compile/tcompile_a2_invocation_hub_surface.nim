# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only audit of the application-developer-facing seal on the
## ``Invocation`` wire type (A2, tightened by A30b). After A30b the entire
## ``Invocation`` type — not merely its ``arguments`` accessor — is
## hub-internal: ``import jmap_client`` exposes neither the type, its
## constructors, nor its accessors. Application developers build requests
## via ``RequestBuilder`` and read typed responses via the dispatcher;
## ``BuiltRequest.toJson`` is the only wire-shape diagnostic seam. Positive
## accessor coverage lives in ``tcompile_a2_invocation_internal_access.nim``
## (which imports the envelope leaf). A compile failure here is the canonical
## signal that the demotion has drifted. See
## ``docs/design/14-Nim-API-Principles.md`` P5, P8, P15, P19.

import std/json

import jmap_client

static:
  # =========================================================================
  # NEGATIVE — the whole Invocation wire type is hub-internal (A30b).
  # =========================================================================

  doAssert not declared(Invocation)
  doAssert not declared(initInvocation)
  doAssert not declared(parseInvocation)

  # The raw JsonNode accessor and any JsonNode-shaped setter must NOT be
  # reachable at the hub (P19).
  doAssert not declared(arguments)
  doAssert not declared(withArguments)

# Runtime anchor — `declared()` probes do not count as "use" for Nim's
# UnusedImport check. Pin `jmap_client` and `std/json`.
discard newJObject()
