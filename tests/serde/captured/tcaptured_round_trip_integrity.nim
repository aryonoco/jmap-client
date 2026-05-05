# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Meta-test: parser-side round-trip integrity over every committed
## fixture (Stalwart and James).  For each fixture, picks the right
## parser (``Session.fromJson``, ``RequestError.fromJson``, or
## ``envelope.Response.fromJson``) and asserts the typed shape
## re-emits via ``toJson()`` without raising.
##
## Out of scope: byte-equal equality after re-emission.  Server
## maps ordering, whitespace, and server-keyed maps with no client-
## side smart constructor diverge from canonical formatting; the
## structural invariant is what matters.  The contract verified
## here is: the parser projects every committed wire shape into
## the typed surface AND the typed surface re-emits without
## raising.  Phase J Step 73 capstone, extended in Phase K to cover
## both Stalwart 0.15.5 and Apache James 3.9 captures.

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

  # ---- James 3.9 captures --------------------------------------------------

  # Session-shape fixtures.
  roundtripSession("session-james")
  roundtripSession("bob-session-james")

  # RFC 7807 problem-details fixtures (request-layer rejections).
  roundtripRequestError("request-error-limit-james")
  roundtripRequestError("request-error-not-json-james")
  roundtripRequestError("request-error-not-request-james")
  roundtripRequestError("request-error-unknown-capability-james")
  roundtripRequestError("server-enforcement-max-calls-in-request-james")
  roundtripRequestError("server-enforcement-max-objects-in-get-james")
  roundtripRequestError("server-enforcement-max-size-request-james")

  # Response envelope fixtures.
  roundtripResponse("bob-inbox-after-alice-delivery-james")
  roundtripResponse("cascade-changes-mailbox-email-thread-coherence-james")
  roundtripResponse("combined-adversarial-round-trip-james")
  roundtripResponse("combined-changes-mailbox-thread-email-james")
  roundtripResponse("core-echo-james")
  roundtripResponse("created-ids-envelope-james")
  roundtripResponse("email-changes-bogus-state-james")
  roundtripResponse("email-changes-max-changes-james")
  roundtripResponse("email-copy-destroy-original-rejected-james")
  roundtripResponse("email-copy-intra-rejected-james")
  roundtripResponse("email-get-cross-account-rejected-james")
  roundtripResponse("email-get-header-forms-extended-james")
  roundtripResponse("email-get-max-body-value-bytes-truncated-james")
  roundtripResponse("email-header-forms-james")
  roundtripResponse("email-multipart-alternative-james")
  roundtripResponse("email-query-advanced-sort-james")
  roundtripResponse("email-query-changes-filter-mismatch-james")
  roundtripResponse("email-query-changes-no-total-james")
  roundtripResponse("email-query-changes-with-total-james")
  roundtripResponse("email-query-collapse-threads-james")
  roundtripResponse("email-query-pagination-anchor-not-found-james")
  roundtripResponse("email-query-pagination-anchor-offset-james")
  roundtripResponse("email-query-pagination-position-james")
  roundtripResponse("email-query-with-snippets-james")
  roundtripResponse("email-querychanges-up-to-id-james")
  roundtripResponse("email-set-state-mismatch-james")
  roundtripResponse("email-submission-multi-recipient-delivery-james")
  roundtripResponse("email-submission-on-success-destroy-james")
  roundtripResponse("email-submission-on-success-update-james")
  roundtripResponse("email-submission-set-baseline-james")
  roundtripResponse("identity-changes-bogus-state-james")
  roundtripResponse("identity-changes-with-updates-james")
  roundtripResponse("identity-set-update-james")
  roundtripResponse("mailbox-changes-bogus-state-james")
  roundtripResponse("mailbox-get-all-james")
  roundtripResponse("mailbox-query-filter-sort-james")
  roundtripResponse("mailbox-set-destroy-with-emails-james")
  roundtripResponse("mailbox-set-has-child-james")
  roundtripResponse("method-error-invalid-result-reference-james")
  roundtripResponse("method-error-unknown-method-james")
  roundtripResponse("method-error-unsupported-filter-james")
  roundtripResponse("method-error-unsupported-sort-james")
  roundtripResponse("multi-instance-envelope-james")
  roundtripResponse("notfound-rail-get-james")
  roundtripResponse("patch-object-deep-paths-james")
  roundtripResponse("result-reference-deep-path-james")
  roundtripResponse("set-error-blob-not-found-james")
  roundtripResponse("set-error-invalid-patch-james")
  roundtripResponse("set-error-invalid-properties-james")
  roundtripResponse("set-error-not-found-james")
  roundtripResponse("thread-changes-bogus-state-james")
  roundtripResponse("thread-get-james")
  roundtripResponse("thread-keyword-filter-james")
  roundtripResponse("vacation-get-singleton-james")
  roundtripResponse("vacation-set-all-arms-james")

  # ---- Cyrus 3.12.2 captures -----------------------------------------------

  # Session-shape fixtures.
  roundtripSession("session-cyrus")
  roundtripSession("bob-session-cyrus")

  # RFC 7807 problem-details fixtures (request-layer rejections). The
  # vacation-* entries are unknownCapability rejections — Cyrus's test
  # image disables vacation via ``imapd.conf: jmap_vacation: no``, so
  # the URN is absent from the session capabilities map and any request
  # that injects it into ``using`` (every VacationResponse/{get,set}
  # call) trips the request-level guard.
  roundtripRequestError("request-error-limit-cyrus")
  roundtripRequestError("request-error-not-json-cyrus")
  roundtripRequestError("request-error-not-request-cyrus")
  roundtripRequestError("request-error-unknown-capability-cyrus")
  roundtripRequestError("server-enforcement-max-calls-in-request-cyrus")
  roundtripRequestError("server-enforcement-max-objects-in-get-cyrus")
  roundtripRequestError("server-enforcement-max-size-request-cyrus")
  roundtripRequestError("vacation-get-singleton-cyrus")
  roundtripRequestError("vacation-set-all-arms-cyrus")

  # Response envelope fixtures.
  roundtripResponse("bob-inbox-after-alice-delivery-cyrus")
  roundtripResponse("cascade-changes-mailbox-email-thread-coherence-cyrus")
  roundtripResponse("combined-adversarial-round-trip-cyrus")
  roundtripResponse("combined-changes-mailbox-thread-email-cyrus")
  roundtripResponse("core-echo-cyrus")
  roundtripResponse("created-ids-envelope-cyrus")
  roundtripResponse("email-changes-bogus-state-cyrus")
  roundtripResponse("email-changes-max-changes-cyrus")
  roundtripResponse("email-copy-destroy-original-rejected-cyrus")
  roundtripResponse("email-copy-intra-rejected-cyrus")
  roundtripResponse("email-get-body-properties-all-cyrus")
  roundtripResponse("email-get-cross-account-rejected-cyrus")
  roundtripResponse("email-get-header-forms-extended-cyrus")
  roundtripResponse("email-get-max-body-value-bytes-truncated-cyrus")
  roundtripResponse("email-header-forms-cyrus")
  roundtripResponse("email-import-from-blob-cyrus")
  roundtripResponse("email-multipart-alternative-cyrus")
  roundtripResponse("email-multipart-mixed-attachment-cyrus")
  roundtripResponse("email-parse-rfc822-cyrus")
  roundtripResponse("email-query-advanced-filter-cyrus")
  roundtripResponse("email-query-advanced-sort-cyrus")
  roundtripResponse("email-query-changes-filter-mismatch-cyrus")
  roundtripResponse("email-query-changes-no-total-cyrus")
  roundtripResponse("email-query-changes-with-total-cyrus")
  roundtripResponse("email-query-collapse-threads-cyrus")
  roundtripResponse("email-query-pagination-anchor-not-found-cyrus")
  roundtripResponse("email-query-pagination-anchor-offset-cyrus")
  roundtripResponse("email-query-pagination-position-cyrus")
  roundtripResponse("email-query-with-snippets-cyrus")
  roundtripResponse("email-querychanges-up-to-id-cyrus")
  roundtripResponse("email-set-state-mismatch-cyrus")
  roundtripResponse("email-submission-changes-cyrus")
  roundtripResponse("email-submission-destroy-canceled-cyrus")
  roundtripResponse("email-submission-get-delivery-status-cyrus")
  roundtripResponse("email-submission-multi-recipient-delivery-cyrus")
  roundtripResponse("email-submission-on-success-destroy-cyrus")
  roundtripResponse("email-submission-on-success-update-cyrus")
  roundtripResponse("email-submission-query-changes-cyrus")
  roundtripResponse("email-submission-set-baseline-cyrus")
  roundtripResponse("email-submission-set-canceled-cyrus")
  roundtripResponse("identity-changes-bogus-state-cyrus")
  roundtripResponse("identity-changes-with-updates-cyrus")
  roundtripResponse("identity-set-update-cyrus")
  roundtripResponse("mailbox-changes-bogus-state-cyrus")
  roundtripResponse("mailbox-get-all-cyrus")
  roundtripResponse("mailbox-query-changes-no-total-cyrus")
  roundtripResponse("mailbox-query-changes-with-filter-cyrus")
  roundtripResponse("mailbox-query-changes-with-total-cyrus")
  roundtripResponse("mailbox-query-filter-sort-cyrus")
  roundtripResponse("mailbox-set-destroy-with-emails-cyrus")
  roundtripResponse("mailbox-set-has-child-cyrus")
  roundtripResponse("method-error-invalid-result-reference-cyrus")
  roundtripResponse("method-error-unknown-method-cyrus")
  roundtripResponse("method-error-unsupported-filter-cyrus")
  roundtripResponse("method-error-unsupported-sort-cyrus")
  roundtripResponse("multi-instance-envelope-cyrus")
  roundtripResponse("notfound-rail-get-cyrus")
  roundtripResponse("patch-object-deep-paths-cyrus")
  roundtripResponse("postels-law-receive-adversarial-mime-cyrus")
  roundtripResponse("result-reference-deep-path-cyrus")
  roundtripResponse("set-error-blob-not-found-cyrus")
  roundtripResponse("set-error-invalid-patch-cyrus")
  roundtripResponse("set-error-invalid-properties-cyrus")
  roundtripResponse("set-error-not-found-cyrus")
  roundtripResponse("thread-changes-bogus-state-cyrus")
  roundtripResponse("thread-get-cyrus")
  roundtripResponse("thread-keyword-filter-cyrus")
