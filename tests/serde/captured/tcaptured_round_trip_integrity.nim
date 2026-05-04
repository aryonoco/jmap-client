# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Meta-test: parser-side round-trip integrity over every committed
## Stalwart fixture.  For each fixture, picks the right parser
## (``Session.fromJson``, ``RequestError.fromJson``, or
## ``envelope.Response.fromJson``) and asserts the typed shape
## re-emits via ``toJson()`` without raising.
##
## Out of scope: byte-equal equality after re-emission.  Server
## maps ordering, whitespace, and server-keyed maps with no client-
## side smart constructor diverge from canonical formatting; the
## structural invariant is what matters.  The contract verified
## here is: the parser projects every committed wire shape into
## the typed surface AND the typed surface re-emits without
## raising.  Phase J Step 73 capstone.

{.push raises: [].}

import jmap_client
import ./mloader

template roundtripResponse(name: static string) =
  ## Round-trip a Response-shape fixture.
  block:
    let j = loadCapturedFixture(name)
    let parsed =
      envelope.Response.fromJson(j).expect("envelope.Response.fromJson " & name)
    discard parsed.toJson()

template roundtripSession(name: static string) =
  ## Round-trip a Session-shape fixture.
  block:
    let j = loadCapturedFixture(name)
    let parsed = Session.fromJson(j).expect("Session.fromJson " & name)
    discard parsed.toJson()

template roundtripRequestError(name: static string) =
  ## Round-trip an RFC 7807 problem-details fixture.
  block:
    let j = loadCapturedFixture(name)
    let parsed = RequestError.fromJson(j).expect("RequestError.fromJson " & name)
    discard parsed.toJson()

block tcapturedRoundTripIntegrity:
  # Session-shape fixtures.
  roundtripSession("session-stalwart")
  roundtripSession("bob-session-stalwart")

  # RFC 7807 problem-details fixtures (request-layer rejections).
  roundtripRequestError("request-error-limit-stalwart")
  roundtripRequestError("request-error-not-json-stalwart")
  roundtripRequestError("request-error-not-request-stalwart")
  roundtripRequestError("request-error-unknown-capability-stalwart")
  roundtripRequestError("server-enforcement-max-calls-in-request-stalwart")
  roundtripRequestError("server-enforcement-max-objects-in-get-stalwart")
  roundtripRequestError("server-enforcement-max-size-request-stalwart")

  # SetError-shape fixtures (per-item errors carried inside Set
  # responses; the Set responses themselves go through
  # roundtripResponse below — the SetError fixtures here test the
  # standalone SetError shape exposed at the wire level).  None at
  # this commit; reserved for future captures.

  # Response envelope fixtures — covers all /jmap/api responses.
  roundtripResponse("bob-inbox-after-alice-delivery-stalwart")
  roundtripResponse("cascade-changes-mailbox-email-thread-coherence-stalwart")
  roundtripResponse("combined-changes-mailbox-thread-email-stalwart")
  roundtripResponse("core-echo-stalwart")
  roundtripResponse("created-ids-envelope-stalwart")
  roundtripResponse("email-changes-bogus-state-stalwart")
  roundtripResponse("email-changes-max-changes-stalwart")
  roundtripResponse("email-copy-destroy-original-rejected-stalwart")
  roundtripResponse("email-copy-intra-rejected-stalwart")
  roundtripResponse("email-get-body-properties-all-stalwart")
  roundtripResponse("email-get-cross-account-rejected-stalwart")
  roundtripResponse("email-get-header-forms-extended-stalwart")
  roundtripResponse("email-get-max-body-value-bytes-truncated-stalwart")
  roundtripResponse("email-header-forms-stalwart")
  roundtripResponse("email-import-from-blob-stalwart")
  roundtripResponse("email-import-no-dedup-stalwart")
  roundtripResponse("email-multipart-alternative-stalwart")
  roundtripResponse("email-multipart-mixed-attachment-stalwart")
  roundtripResponse("email-parse-rfc822-stalwart")
  roundtripResponse("email-query-advanced-filter-stalwart")
  roundtripResponse("email-query-advanced-sort-stalwart")
  roundtripResponse("email-query-changes-filter-mismatch-stalwart")
  roundtripResponse("email-query-changes-no-total-stalwart")
  roundtripResponse("email-query-changes-with-total-stalwart")
  roundtripResponse("email-query-collapse-threads-stalwart")
  roundtripResponse("email-query-pagination-anchor-not-found-stalwart")
  roundtripResponse("email-query-pagination-anchor-offset-stalwart")
  roundtripResponse("email-query-pagination-position-stalwart")
  roundtripResponse("email-query-with-snippets-stalwart")
  roundtripResponse("email-querychanges-up-to-id-stalwart")
  roundtripResponse("email-set-state-mismatch-stalwart")
  roundtripResponse("email-submission-changes-stalwart")
  roundtripResponse("email-submission-destroy-canceled-stalwart")
  roundtripResponse("email-submission-filter-completeness-stalwart")
  roundtripResponse("email-submission-get-delivery-status-stalwart")
  roundtripResponse("email-submission-multi-recipient-delivery-stalwart")
  roundtripResponse("email-submission-on-success-destroy-stalwart")
  roundtripResponse("email-submission-on-success-update-stalwart")
  roundtripResponse("email-submission-query-changes-stalwart")
  roundtripResponse("email-submission-query-changes-with-filter-stalwart")
  roundtripResponse("email-submission-query-filter-sort-stalwart")
  roundtripResponse("email-submission-set-baseline-stalwart")
  roundtripResponse("email-submission-set-canceled-stalwart")
  roundtripResponse("identity-changes-bogus-state-stalwart")
  roundtripResponse("identity-changes-with-updates-stalwart")
  roundtripResponse("identity-set-update-stalwart")
  roundtripResponse("mailbox-changes-bogus-state-stalwart")
  roundtripResponse("mailbox-get-all-stalwart")
  roundtripResponse("mailbox-query-changes-no-total-stalwart")
  roundtripResponse("mailbox-query-changes-with-filter-stalwart")
  roundtripResponse("mailbox-query-changes-with-total-stalwart")
  roundtripResponse("mailbox-query-filter-sort-stalwart")
  roundtripResponse("mailbox-set-destroy-with-emails-stalwart")
  roundtripResponse("mailbox-set-has-child-stalwart")
  roundtripResponse("method-error-invalid-result-reference-stalwart")
  roundtripResponse("method-error-unknown-method-stalwart")
  roundtripResponse("method-error-unsupported-filter-stalwart")
  roundtripResponse("method-error-unsupported-sort-stalwart")
  roundtripResponse("combined-adversarial-round-trip-stalwart")
  roundtripResponse("multi-instance-envelope-stalwart")
  roundtripResponse("notfound-rail-get-stalwart")
  roundtripResponse("patch-object-deep-paths-stalwart")
  roundtripResponse("postels-law-receive-adversarial-mime-stalwart")
  roundtripResponse("result-reference-deep-path-stalwart")
  roundtripResponse("set-error-blob-not-found-stalwart")
  roundtripResponse("set-error-invalid-patch-stalwart")
  roundtripResponse("set-error-invalid-properties-stalwart")
  roundtripResponse("set-error-not-found-stalwart")
  roundtripResponse("thread-changes-bogus-state-stalwart")
  roundtripResponse("thread-get-stalwart")
  roundtripResponse("thread-keyword-filter-stalwart")
  roundtripResponse("vacation-get-singleton-stalwart")
  roundtripResponse("vacation-set-all-arms-stalwart")
