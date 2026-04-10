# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Re-export hub for all Layer 1 mail modules. Import this single module to
## access the complete RFC 8621 mail type vocabulary.

{.push raises: [], noSideEffect.}

import ./addresses
import ./thread
import ./identity
import ./vacation
import ./mail_capabilities
import ./mail_errors
import ./keyword
import ./mailbox
import ./mail_filters
import ./headers
import ./body
import ./email
import ./snippet

export addresses
export thread
export identity
export vacation
export mail_capabilities
export mail_errors
export keyword
export mailbox
export mail_filters
export headers
export body
export email
export snippet
