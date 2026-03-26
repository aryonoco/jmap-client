# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri
#

## jmap-client — Cross-platform JMAP client library
## Exports a C ABI for use from C/C++ via FFI

import jmap_client/[types, errors]

export types, errors

proc jmapInit*(): cint {.exportc: "jmap_init", cdecl, dynlib.} =
  ## Initialise the JMAP client library. Call once before any other function.
  NimMain()
  return 0

proc jmapCleanup*(): cint {.exportc: "jmap_cleanup", cdecl, dynlib.} =
  ## Clean up the JMAP client library. Call once when done.
  GC_FullCollect()
  return 0
