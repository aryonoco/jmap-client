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
import ./mailbox_changes_response
import ./mail_filters
import ./headers
import ./body
import ./email_blueprint
import ./email
import ./email_update
import ./snippet
import ./submission_envelope
import ./submission_status
import ./email_submission

export addresses
export thread
export identity
export vacation
export mail_capabilities
export mail_errors
export keyword
export mailbox
export mailbox_changes_response
export mail_filters
export headers
export body
export email_blueprint
export email
export email_update
export snippet
export submission_envelope
export submission_status
export email_submission
