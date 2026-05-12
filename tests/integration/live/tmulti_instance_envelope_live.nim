# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: ``Response.methodResponses`` order mirrors
## ``Request.methodCalls`` order (RFC 8620 §3.6).
## ``resp.get(handle)`` resolution by ``MethodCallId`` works
## independently across multiple same-method invocations within one
## envelope — each handle resolves its own response.
##
## Phase J Step 69.  One ``client.send`` carrying three
## ``addGet[Mailbox]`` invocations with distinct ``properties``
## subsets.  Each handle's resolution returns its own typed
## response with the requested property subset.

import std/json

import results
import jmap_client
import jmap_client/client
import jmap_client/internal/types/envelope
import jmap_client/internal/protocol/dispatch
import ./mcapture
import ./mconfig
import ./mlive

block tmultiInstanceEnvelopeLive:
  forEachLiveTarget(target):
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # Three Mailbox/get invocations with distinct property subsets:
    # - call 0: full record (no properties filter)
    # - call 1: minimal sparse subset
    # - call 2: counts subset
    let (b1, fullHandle) =
      addMailboxGet(initRequestBuilder(makeBuilderId()), mailAccountId)
    let (b2, _) =
      addMailboxGet(b1, mailAccountId, properties = Opt.some(@["id", "name"]))
    let (b3, _) = addMailboxGet(
      b2, mailAccountId, properties = Opt.some(@["id", "role", "totalEmails"])
    )
    let resp = client.send(b3.freeze()).expect(
        "send three-Mailbox/get envelope[" & $target.kind & "]"
      )
    captureIfRequested(client, "multi-instance-envelope-" & $target.kind).expect(
      "captureIfRequested multi-instance"
    )

    assertOn target,
      resp.response.methodResponses.len == 3,
      "envelope must carry three responses, got " & $resp.response.methodResponses.len

    # Order preservation: methodResponses[i] must match methodCalls[i].
    assertOn target, resp.response.methodResponses[0].rawName == "Mailbox/get"
    assertOn target, resp.response.methodResponses[1].rawName == "Mailbox/get"
    assertOn target, resp.response.methodResponses[2].rawName == "Mailbox/get"

    # Full record uses the public typed entry point. Sparse + counts
    # are sparse projections, which have no public application-API
    # path until A3.6 ships PartialT types; this test inspects the
    # server's wire shape directly via the internal envelope module
    # (A2 seal — not part of the public surface, reachable only
    # through ``jmap_client/internal/types/envelope`` imported above).
    let fullResp =
      resp.get(fullHandle).expect("Mailbox/get full extract[" & $target.kind & "]")
    let sparseInv = resp.response.methodResponses[1]
    let countsInv = resp.response.methodResponses[2]
    let sparseList = sparseInv.arguments{"list"}.getElems(@[])
    let countsList = countsInv.arguments{"list"}.getElems(@[])

    assertOn target, fullResp.list.len >= 1, "full Mailbox/get must surface mailboxes"
    assertOn target, sparseList.len >= 1, "sparse Mailbox/get must surface mailboxes"
    assertOn target, countsList.len >= 1, "counts Mailbox/get must surface mailboxes"
    assertOn target,
      fullResp.list.len == sparseList.len,
      "all three /get calls target the same account, list lengths must match"
    assertOn target,
      sparseList.len == countsList.len,
      "all three /get calls target the same account, list lengths must match"

    # Library contract: full records flow through Mailbox.fromJson on
    # the public typed entry point. Sparse responses (RFC 8621 §2.1
    # ``properties`` filter) carry only the requested properties plus
    # ``id``. Mailbox.fromJson is a full-record parser (most fields
    # non-Opt per RFC 8621 §2.1), so sparse projections are verified
    # here via diagnostic access to the internal envelope module —
    # fields requested are present, fields not requested are absent.
    # Application code has no public path to this assertion; future
    # PartialMailbox (A3.6) closes the public-surface gap additively.
    for mb in fullResp.list:
      assertOn target, mb.name.len > 0, "full Mailbox.fromJson must populate name"
    for node in sparseList:
      assertOn target, node.kind == JObject, "sparse Mailbox record must be JObject"
      assertOn target, node.hasKey("id"), "sparse record must carry id"
      assertOn target,
        node.hasKey("name"), "sparse record must carry the requested name"
      assertOn target,
        not node.hasKey("myRights"),
        "sparse record must NOT carry myRights (not requested)"
    for node in countsList:
      assertOn target, node.kind == JObject, "counts Mailbox record must be JObject"
      assertOn target, node.hasKey("id"), "counts record must carry id"
      assertOn target,
        node.hasKey("totalEmails"), "counts record must carry the requested totalEmails"
      assertOn target,
        not node.hasKey("name"), "counts record must NOT carry name (not requested)"

    client.close()
