# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Internal aggregator for Layer 1 mail type modules. Used only by
## ``jmap_client/mail.nim`` (the public mail hub). Not a public path —
## see H10 internal-boundary lint.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import ./addresses
import ./thread
import ./identity
import ./vacation
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
export mail_errors
export keyword
export mailbox
export mailbox_changes_response
export mail_filters
export headers except parseFromString
export body except parseFromString
export email_blueprint
export email
export email_update
export snippet
export submission_envelope
# ``SmtpReplyViolation`` (with its members) and the ``detect*`` SMTP-reply
# validators are internal parsing primitives projected to ``ValidationError`` by
# the public ``parseSmtpReply`` constructor; they are filtered from the public
# surface (tests reach them via direct import per H10).
export submission_status except
  SmtpReplyViolation, srEmpty, srControlChars, srLineTooShort, srBadReplyCodeDigit1,
  srBadReplyCodeDigit2, srBadReplyCodeDigit3, srBadSeparator, srMultilineCodeMismatch,
  srMultilineContinuation, srMultilineFinalHyphen, srEnhancedMalformedTriple,
  srEnhancedClassInvalid, srEnhancedSubjectOverflow, srEnhancedDetailOverflow,
  srEnhancedMultilineMismatch, detectReplyCodeGrammar, detectSeparator,
  detectClassDigit, detectSubjectInRange, detectDetailInRange, detectConsistentItems
export email_submission
