# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## JMAP client library entry point. Re-exports all Layer 1 types; will host
## C ABI exports (Layer 5) when the FFI boundary is built.

import jmap_client/types

export types
