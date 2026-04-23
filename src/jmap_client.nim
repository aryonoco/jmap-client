# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}
{.experimental: "strictCaseObjects".}

## JMAP client library entry point. Re-exports all Layer 1 types, Layer 2
## serialisation, and Layer 3 protocol logic; will host C ABI exports
## (Layer 5) when the FFI boundary is built.

import jmap_client/types
import jmap_client/serialisation
import jmap_client/protocol
import jmap_client/client
import jmap_client/mail

export types
export serialisation
export protocol
export client
export mail
