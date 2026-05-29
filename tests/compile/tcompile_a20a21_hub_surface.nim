# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only audit of the A20 (``SessionEndpoint``) + A21 (``Credential``)
## public surface. Compiling this file proves that ``import jmap_client``
## exposes the sealed types, their smart constructors, and the new
## two-overload ``initJmapClient`` / ``setCredential`` mutator — while keeping
## the hub-private wire projections (``authorizationHeaderValue``,
## ``asDirectUrl``, ``asDiscoveryDomain``) and the removed legacy entry points
## (``discoverJmapClient``, ``setBearerToken``, ``parseAuthScheme``) out of
## scope. A compile failure here is the canonical signal that the surface has
## drifted. See ``docs/design/14-Nim-API-Principles.md`` P3, P5, P8, P18, P19.

import jmap_client

static:
  # =========================================================================
  # POSITIVE — the sealed types, smart constructors, and mutator are public.
  # =========================================================================

  doAssert declared(AuthScheme)
  doAssert declared(Credential)
  doAssert declared(bearerCredential)
  doAssert declared(basicCredential)
  doAssert declared(SessionEndpoint)
  doAssert declared(SessionEndpointKind)
  doAssert declared(directEndpoint)
  doAssert declared(discoveryEndpoint)
  doAssert declared(setCredential)

  # The discriminators are public fields (strict-objects Rule 3).
  doAssert compiles(bearerCredential("t").get().scheme)
  doAssert compiles(directEndpoint("https://x").get().kind)

  # =========================================================================
  # NEGATIVE — the hub-private wire projections must NOT leak to consumers.
  # =========================================================================

  doAssert not declared(authorizationHeaderValue)
  doAssert not declared(asDirectUrl)
  doAssert not declared(asDiscoveryDomain)

  # =========================================================================
  # NEGATIVE — the legacy entry points are gone (clean cut, no shims).
  # =========================================================================

  doAssert not declared(discoverJmapClient)
  doAssert not declared(setBearerToken)
  doAssert not declared(parseAuthScheme)
