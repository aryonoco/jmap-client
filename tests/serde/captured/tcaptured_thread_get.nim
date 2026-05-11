# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Thread/get`` response
## (``tests/testdata/captured/thread-get-stalwart.json``).  Verifies
## that ``Thread.fromJson`` accepts a Stalwart-shaped Thread record
## with at least one ``emailIds`` entry, and round-trips through
## ``Thread.toJson``.

{.push raises: [].}

import jmap_client
import jmap_client/internal/mail/thread as jthread
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedThreadGet:
  forEachCapturedServer("thread-get", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "Thread/get"
    let getResp = GetResponse[jthread.Thread].fromJson(inv.arguments).expect(
        "GetResponse[Thread].fromJson"
      )
    doAssert getResp.list.len == 1,
      "expected one Thread record (got " & $getResp.list.len & ")"
    let t = jthread.Thread.fromJson(getResp.list[0]).expect("Thread.fromJson")
    doAssert string(t.id).len > 0, "Thread.id must be non-empty"
    doAssert t.emailIds.len >= 1,
      "RFC 8621 §3 invariant — Thread.emailIds must carry at least one entry"
    let rt = jthread.Thread.fromJson(t.toJson()).expect("Thread round-trip")
    doAssert rt.id == t.id, "Thread.id must round-trip"
    doAssert rt.emailIds == t.emailIds, "Thread.emailIds must round-trip"
