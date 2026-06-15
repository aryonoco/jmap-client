# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only audit of the A6 handle-brand public surface. Locks the
## P5 (single public layer) and P8 (opaque handles) commitments for the
## lifecycle:
##   ``newBuilder`` → ``add*`` → ``freeze`` → ``send`` → ``handle.get(dr)``
##
## The brand-carrying types (``BuilderId``, ``BuiltRequest``,
## ``DispatchedResponse``, sealed ``ResponseHandle`` / ``NameBoundHandle``)
## must reach application developers through ``import jmap_client``, while
## every raw factory (``initBuilderId``, ``initRequestBuilder``,
## ``initResponseHandle``, ``initNameBoundHandle``, ``initDispatchedResponse``)
## and every raw-access accessor (``response``, ``request``, ``builderId``)
## must remain unreachable. Counterpart at
## ``tcompile_a6_handle_brand_internal_access.nim`` proves they ARE
## reachable via the whitebox internal-import path.

import jmap_client

static:
  # =========================================================================
  # POSITIVE — must be reachable through `import jmap_client`
  # =========================================================================

  doAssert declared(BuilderId)
  doAssert declared(BuiltRequest)
  doAssert declared(DispatchedResponse)
  # A6 brand mismatch is the ``jeMisuse`` arm of the single ``JmapError`` rail
  # carrying a ``Misuse`` payload; ``get`` yields a ``MethodOutcome`` on ok.
  doAssert declared(JmapError)
  doAssert declared(JmapErrorKind)
  doAssert declared(jeMisuse)
  doAssert declared(Misuse)
  doAssert declared(MethodOutcome)
  doAssert declared(newBuilder)
  doAssert declared(freeze)
  doAssert declared(clientBrand)
  doAssert declared(serial)
  doAssert declared(sessionState)
  doAssert declared(createdIds)

  # =========================================================================
  # NEGATIVE — must NOT be reachable through `import jmap_client`
  # =========================================================================

  doAssert not declared(initBuilderId)
  doAssert not declared(initResponseHandle)
  doAssert not declared(initNameBoundHandle)
  doAssert not declared(initDispatchedResponse)
  doAssert not declared(initRequestBuilder)
  doAssert not declared(build)
  doAssert not declared(response)
  doAssert not declared(request)
  doAssert not declared(builderId)
  # A12 — the library-internal misuse producer is hub-private (consumers
  # receive a ``Misuse`` value, they do not mint it).
  doAssert not declared(jmapMisuse)

# Runtime anchor pins the import against UnusedImport warnings.
doAssert $mnCoreEcho == "Core/echo"
