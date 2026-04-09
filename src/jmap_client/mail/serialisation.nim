# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Re-export hub for all Layer 2 mail serialisation modules. Import this
## single module to access every mail toJson/fromJson pair.

{.push raises: [].}

import ./serde_addresses
import ./serde_thread
import ./serde_identity
import ./serde_vacation
import ./serde_mail_capabilities
import ./serde_keyword
import ./serde_mailbox
import ./serde_mail_filters
import ./serde_headers
import ./serde_body

export serde_addresses
export serde_thread
export serde_identity
export serde_vacation
export serde_mail_capabilities
export serde_keyword
export serde_mailbox
export serde_mail_filters
export serde_headers
export serde_body
