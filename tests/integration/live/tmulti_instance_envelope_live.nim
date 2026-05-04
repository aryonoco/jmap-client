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
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig

block tmultiInstanceEnvelopeLive:
  let cfgRes = loadLiveTestConfig()
  if cfgRes.isOk:
    let cfg = cfgRes.get()
    var client = initJmapClient(
        sessionUrl = cfg.sessionUrl,
        bearerToken = cfg.aliceToken,
        authScheme = cfg.authScheme,
      )
      .expect("initJmapClient")
    let session = client.fetchSession().expect("fetchSession")
    var mailAccountId: AccountId
    session.primaryAccounts.withValue("urn:ietf:params:jmap:mail", v):
      mailAccountId = v
    do:
      doAssert false, "session must advertise a primary mail account"

    # Three Mailbox/get invocations with distinct property subsets:
    # - call 0: full record (no properties filter)
    # - call 1: minimal sparse subset
    # - call 2: counts subset
    let (b1, fullHandle) = addGet[Mailbox](initRequestBuilder(), mailAccountId)
    let (b2, sparseHandle) =
      addGet[Mailbox](b1, mailAccountId, properties = Opt.some(@["id", "name"]))
    let (b3, countsHandle) = addGet[Mailbox](
      b2, mailAccountId, properties = Opt.some(@["id", "role", "totalEmails"])
    )
    let resp = client.send(b3).expect("send three-Mailbox/get envelope")
    captureIfRequested(client, "multi-instance-envelope-stalwart").expect(
      "captureIfRequested multi-instance"
    )

    doAssert resp.methodResponses.len == 3,
      "envelope must carry three responses, got " & $resp.methodResponses.len

    # Order preservation: methodResponses[i] must match methodCalls[i].
    doAssert resp.methodResponses[0].rawName == "Mailbox/get"
    doAssert resp.methodResponses[1].rawName == "Mailbox/get"
    doAssert resp.methodResponses[2].rawName == "Mailbox/get"

    # Each handle resolves its own response, even though all three
    # invocations share the same method name.
    let fullResp = resp.get(fullHandle).expect("Mailbox/get full extract")
    let sparseResp = resp.get(sparseHandle).expect("Mailbox/get sparse extract")
    let countsResp = resp.get(countsHandle).expect("Mailbox/get counts extract")

    doAssert fullResp.list.len >= 1, "full Mailbox/get must surface mailboxes"
    doAssert sparseResp.list.len >= 1, "sparse Mailbox/get must surface mailboxes"
    doAssert countsResp.list.len >= 1, "counts Mailbox/get must surface mailboxes"
    doAssert fullResp.list.len == sparseResp.list.len,
      "all three /get calls target the same account, list lengths must match"
    doAssert sparseResp.list.len == countsResp.list.len,
      "all three /get calls target the same account, list lengths must match"

    # Library contract: full records parse through Mailbox.fromJson.
    # Sparse responses (RFC 8621 §2.1 ``properties`` filter) carry
    # only the requested properties plus ``id`` — Stalwart 0.15.5
    # respects this strictly, returning ``{id, name}`` for call 1
    # and ``{id, role, totalEmails}`` for call 2.  Mailbox.fromJson
    # is a full-record parser (most fields non-Opt per RFC 8621
    # §2.1), so sparse projection is verified at the JsonNode level
    # — fields requested are present, fields not requested are
    # absent.  The library's typed surface targets full records;
    # consumers that need sparse support extract fields directly.
    for node in fullResp.list:
      discard Mailbox.fromJson(node).expect("Mailbox.fromJson full record")
    doAssert sparseResp.list.len > 0
    for node in sparseResp.list:
      doAssert node.kind == JObject, "sparse Mailbox record must be JObject"
      doAssert node.hasKey("id"), "sparse record must carry id"
      doAssert node.hasKey("name"), "sparse record must carry the requested name"
      doAssert not node.hasKey("myRights"),
        "sparse record must NOT carry myRights (not requested)"
    doAssert countsResp.list.len > 0
    for node in countsResp.list:
      doAssert node.kind == JObject, "counts Mailbox record must be JObject"
      doAssert node.hasKey("id"), "counts record must carry id"
      doAssert node.hasKey("totalEmails"),
        "counts record must carry the requested totalEmails"
      doAssert not node.hasKey("name"),
        "counts record must NOT carry name (not requested)"

    client.close()
