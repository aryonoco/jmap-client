# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Test-side aggregator for the L2 serde surface. Re-exports every L2
## module the tests legitimately reach via H10 direct imports.
##
## **Test accommodation, not API design.** A1c made the L2 serde surface
## hub-private — application developers never touch it. Tests that
## exercise round-trip serde, captured-fixture replay, or whitebox
## dispatch internals still need the surface; importing this single
## module pulls in the full set without per-file bookkeeping.

{.push raises: [].}

import jmap_client/internal/serialisation/serde
import jmap_client/internal/serialisation/serde_diagnostics
import jmap_client/internal/serialisation/serde_envelope
import jmap_client/internal/serialisation/serde_envelope_emit
import jmap_client/internal/serialisation/serde_envelope_parse
import jmap_client/internal/serialisation/serde_errors
import jmap_client/internal/serialisation/serde_field_echo
import jmap_client/internal/serialisation/serde_framework
import jmap_client/internal/serialisation/serde_helpers
import jmap_client/internal/serialisation/serde_primitives
import jmap_client/internal/serialisation/serde_session

# Mail-serde leaves are also pulled in so tests that construct typed
# response handles (SetResponse[EmailSubmissionCreatedItem, ...] etc.)
# can satisfy the mixin chain at handle-construction time.
import jmap_client/internal/mail/serde_addresses
import jmap_client/internal/mail/serde_body
import jmap_client/internal/mail/serde_email
import jmap_client/internal/mail/serde_email_blueprint
import jmap_client/internal/mail/serde_email_submission
import jmap_client/internal/mail/serde_email_update
import jmap_client/internal/mail/serde_headers
import jmap_client/internal/mail/serde_identity
import jmap_client/internal/mail/serde_identity_update
import jmap_client/internal/mail/serde_keyword
import jmap_client/internal/mail/serde_mail_capabilities
import jmap_client/internal/mail/serde_mail_filters
import jmap_client/internal/mail/serde_mailbox
import jmap_client/internal/mail/serde_snippet
import jmap_client/internal/mail/serde_submission_envelope
import jmap_client/internal/mail/serde_submission_status
import jmap_client/internal/mail/serde_thread
import jmap_client/internal/mail/serde_vacation

export serde
export serde_diagnostics
export serde_envelope
export serde_envelope_emit
export serde_envelope_parse
export serde_errors
export serde_field_echo
export serde_framework
export serde_helpers
export serde_primitives
export serde_session

export serde_addresses
export serde_body
export serde_email
export serde_email_blueprint
export serde_email_submission
export serde_email_update
export serde_headers
export serde_identity
export serde_identity_update
export serde_keyword
export serde_mail_capabilities
export serde_mail_filters
export serde_mailbox
export serde_snippet
export serde_submission_envelope
export serde_submission_status
export serde_thread
export serde_vacation
