# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured three-leg
## ``Mailbox/get`` envelope with distinct property subsets per leg
## (``tests/testdata/captured/multi-instance-envelope-stalwart.json``).
##
## RFC 8620 §3.6 mandates ``methodResponses`` order mirrors
## ``methodCalls`` order.  Stalwart 0.15.5 is RFC-conformant on
## both axes — order preservation and per-leg property filtering.
## Verifies the wire shape parses through ``envelope.Response.fromJson``
## and that each leg's property subset matches what the call
## requested (sparse legs carry only requested fields plus ``id``).

{.push raises: [].}

import std/json

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedMultiInstanceEnvelope:
  forEachCapturedServer("multi-instance-envelope", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 3,
      "envelope must carry the three-leg chain; got " & $resp.methodResponses.len
    for inv in resp.methodResponses:
      doAssert inv.rawName == "Mailbox/get",
        "every leg must be Mailbox/get; got " & inv.rawName

    # Leg 0 — full record: every Mailbox property present.
    let fullList = resp.methodResponses[0].arguments{"list"}
    doAssert not fullList.isNil and fullList.kind == JArray
    doAssert fullList.len >= 1
    doAssert fullList[0].hasKey("myRights"), "full leg must carry myRights"
    doAssert fullList[0].hasKey("name"), "full leg must carry name"
    discard Mailbox.fromJson(fullList[0]).expect("Mailbox.fromJson full record")

    # Leg 1 — sparse {id, name}: ``properties`` filter respected.
    let sparseList = resp.methodResponses[1].arguments{"list"}
    doAssert not sparseList.isNil and sparseList.kind == JArray
    doAssert sparseList.len >= 1
    doAssert sparseList[0].hasKey("id")
    doAssert sparseList[0].hasKey("name")
    doAssert not sparseList[0].hasKey("myRights"),
      "sparse leg must omit non-requested properties (RFC 8621 §2.1)"

    # Leg 2 — counts {id, role, totalEmails}: same filter respected.
    let countsList = resp.methodResponses[2].arguments{"list"}
    doAssert not countsList.isNil and countsList.kind == JArray
    doAssert countsList.len >= 1
    doAssert countsList[0].hasKey("id")
    doAssert countsList[0].hasKey("totalEmails")
    doAssert not countsList[0].hasKey("name"),
      "counts leg must omit non-requested properties"
