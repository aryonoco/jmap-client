# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured combined ``Mailbox/changes``
## + ``Thread/changes`` + ``Email/changes`` response
## (``tests/testdata/captured/combined-changes-mailbox-thread-email-stalwart.json``).
## Phase H Step 47's three-invocation Request envelope. Verifies that
## the dispatch-layer demux extracts three heterogeneous typed
## responses from one envelope:
##
##  * ``Mailbox/changes`` → ``MailboxChangesResponse`` (RFC 8621 §2.2
##    extended response with ``updatedProperties: Opt[seq[string]]``).
##  * ``Thread/changes`` → ``ChangesResponse[jmap_client.Thread]``.
##  * ``Email/changes``  → ``ChangesResponse[Email]``.
##
## The live test (``tcombined_changes_live``) already verifies the
## per-arm cardinalities; the replay's job is to prove the three
## ``fromJson`` overloads parse without error against Stalwart 0.15.5's
## empirical wire shape.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedCombinedChangesMailboxThreadEmail:
  let j = loadCapturedFixture("combined-changes-mailbox-thread-email-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 3
  doAssert resp.methodResponses[0].rawName == "Mailbox/changes"
  doAssert resp.methodResponses[1].rawName == "Thread/changes"
  doAssert resp.methodResponses[2].rawName == "Email/changes"

  discard MailboxChangesResponse.fromJson(resp.methodResponses[0].arguments).expect(
      "MailboxChangesResponse.fromJson"
    )
  discard ChangesResponse[jmap_client.Thread]
    .fromJson(resp.methodResponses[1].arguments)
    .expect("ChangesResponse[Thread].fromJson")
  discard ChangesResponse[Email].fromJson(resp.methodResponses[2].arguments).expect(
      "ChangesResponse[Email].fromJson"
    )
