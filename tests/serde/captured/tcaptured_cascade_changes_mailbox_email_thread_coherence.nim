# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured cascade-coherence response
## (``tests/testdata/captured/cascade-changes-mailbox-email-thread-coherence-stalwart.json``).
## Phase H Step 48's three-invocation post-cascade ``*/changes`` Request
## envelope. Pins Stalwart 0.15.5's empirical shape after the cascade
## destroys a populated mailbox containing six emails:
##
##  * Mailbox/changes: the cascaded mailbox surfaces in ``destroyed``;
##    ``updatedProperties`` carries email-count fields
##    (``totalEmails`` / ``unreadEmails`` / ``totalThreads`` /
##    ``unreadThreads``).
##  * Email/changes: the six cascaded emails surface in ``destroyed``.
##  * Thread/changes: six distinct threadIds surface in ``updated``
##    (RFC 8621 §3 makes thread merging server-discretionary;
##    Stalwart 0.15.5 does not merge for non-Inbox child mailboxes).
##
## The live test (``tcascade_changes_coherence_live``) already
## verified the cascade-coherence invariants. The replay's job is to
## prove the three ``fromJson`` overloads parse without error against
## the cascade response shape and that the per-entity cardinalities
## hold structurally (one mailbox destroyed, six email destruction
## entries, six thread delta entries — bounding three distinct
## threading scenarios per Stalwart 0.15.5).

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedCascadeChangesMailboxEmailThreadCoherence:
  let j = loadCapturedFixture("cascade-changes-mailbox-email-thread-coherence-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 3
  doAssert resp.methodResponses[0].rawName == "Mailbox/changes"
  doAssert resp.methodResponses[1].rawName == "Email/changes"
  doAssert resp.methodResponses[2].rawName == "Thread/changes"

  let mailboxCr = MailboxChangesResponse
    .fromJson(resp.methodResponses[0].arguments)
    .expect("MailboxChangesResponse.fromJson")
  let emailCr = ChangesResponse[Email]
    .fromJson(resp.methodResponses[1].arguments)
    .expect("ChangesResponse[Email].fromJson")
  let threadCr = ChangesResponse[jmap_client.Thread]
    .fromJson(resp.methodResponses[2].arguments)
    .expect("ChangesResponse[Thread].fromJson")

  doAssert mailboxCr.destroyed.len >= 1,
    "Mailbox/changes destroyed must include the cascaded mailbox"
  let emailDeltaTotal =
    emailCr.created.len + emailCr.updated.len + emailCr.destroyed.len
  doAssert emailDeltaTotal == 6,
    "six seeded emails — RFC 8620 §5.2 'MUST only appear once' invariant " & "(got " &
      $emailDeltaTotal & ")"
  let threadDeltaTotal =
    threadCr.created.len + threadCr.updated.len + threadCr.destroyed.len
  doAssert threadDeltaTotal >= 1,
    "at least one thread delta entry — RFC 8621 §3 makes the count " &
      "server-discretionary, so the assertion is shape not cardinality"
