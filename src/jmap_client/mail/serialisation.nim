# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Re-export hub for all Layer 2 mail serialisation modules. Import this
## single module to access every mail toJson/fromJson pair.

{.push raises: [], noSideEffect.}

import ./serde_addresses
import ./serde_thread
import ./serde_identity
import ./serde_identity_update
import ./serde_vacation
import ./serde_mail_capabilities
import ./serde_keyword
import ./serde_mailbox
import ./mailbox_changes_response
import ./serde_mail_filters
import ./serde_headers
import ./serde_body
import ./serde_email_blueprint
import ./serde_email
import ./serde_email_update
import ./serde_snippet
import ./serde_submission_envelope
import ./serde_submission_status
import ./serde_email_submission

export serde_addresses
export serde_thread
export serde_identity
export serde_identity_update
export serde_vacation
export serde_mail_capabilities
export serde_keyword
export serde_mailbox
export mailbox_changes_response
export serde_mail_filters
export serde_headers
export serde_body
export serde_email_blueprint
export serde_email
export serde_email_update
export serde_snippet
export serde_submission_envelope
export serde_submission_status
export serde_email_submission
