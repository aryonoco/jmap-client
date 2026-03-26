# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Aryan Ameri
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
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
