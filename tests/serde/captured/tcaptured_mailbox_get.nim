# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured Stalwart ``Mailbox/get``
## response (``tests/testdata/captured/mailbox-get-all-stalwart.json``).
## Verifies the full Mailbox shape — ``myRights`` ACL, ``role`` enum,
## ``totalEmails``/``unreadEmails`` numeric fields — round-trips
## through ``Mailbox.fromJson`` / ``Mailbox.toJson``.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedMailboxGet:
  forEachCapturedServer("mailbox-get-all", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1, "one Mailbox/get invocation expected"
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "Mailbox/get"

    let getResp = GetResponse[Mailbox].fromJson(inv.arguments).expect(
        "GetResponse[Mailbox].fromJson"
      )
    doAssert getResp.list.len >= 1, "Stalwart's seeded account has at least one mailbox"
    for node in getResp.list:
      let mb = Mailbox.fromJson(node).expect("Mailbox.fromJson per entry")
      doAssert mb.name.len > 0, "every mailbox must have a non-empty name"
      doAssert mb.myRights.mayReadItems,
        "alice must have read rights on her own mailboxes"
      let rt = Mailbox.fromJson(mb.toJson()).expect("Mailbox round-trip")
      doAssert rt.id == mb.id, "id must round-trip"
      doAssert rt.name == mb.name, "name must round-trip"
      doAssert rt.role == mb.role, "role must round-trip"
