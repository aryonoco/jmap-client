# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Whitebox counterpart to ``tcompile_a6_handle_brand_surface.nim``.
## Proves that the A6 raw factories and hub-private accessors ARE reachable
## via direct ``import jmap_client/internal/...`` paths used by tests under
## ``tests/`` and by internal cross-module callers (``client.nim``, mail
## builders, etc.). Without this audit, the hub-filter approach risks
## quietly walling off symbols that internal callers depend on.

import jmap_client/internal/types/identifiers
import jmap_client/internal/types/errors
import jmap_client/internal/protocol/builder
import jmap_client/internal/protocol/dispatch

static:
  doAssert declared(initBuilderId)
  doAssert declared(initResponseHandle)
  doAssert declared(initNameBoundHandle)
  doAssert declared(initDispatchedResponse)
  doAssert declared(initRequestBuilder)
  doAssert declared(response)
  doAssert declared(request)
  doAssert declared(builderId)

# Runtime anchor — constructs a BuilderId via the internal factory and
# pins the import against UnusedImport warnings.
let id = initBuilderId(0'u64, 0'u64)
doAssert id == initBuilderId(0'u64, 0'u64)
doAssert id.clientBrand == 0'u64
doAssert id.serial == 0'u64
