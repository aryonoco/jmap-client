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

import results
import jmap_client
import jmap_client/internal/types/envelope
import jmap_client/internal/protocol/dispatch
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tmultiInstanceEnvelopeLive:
  forEachLiveTarget(target):
    let (client, recorder) = initRecordingClient(target)
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")

    # Three Mailbox/get invocations:
    # - call 0: full record (addMailboxGet)
    # - call 1: minimal sparse subset (addPartialMailboxGet)
    # - call 2: counts subset (addPartialMailboxGet)
    let (b1, fullHandle) =
      addMailboxGet(initRequestBuilder(makeBuilderId()), mailAccountId)
    let (b2, sparseHandle) = addPartialMailboxGet(
      b1, mailAccountId, properties = parseNonEmptySeq(@[mgpId, mgpName]).get()
    )
    let (b3, countsHandle) = addPartialMailboxGet(
      b2,
      mailAccountId,
      properties = parseNonEmptySeq(@[mgpId, mgpRole, mgpTotalEmails]).get(),
    )
    let resp = client.send(b3.freeze()).expect(
        "send three-Mailbox/get envelope[" & $target.kind & "]"
      )
    captureIfRequested(
      recorder.lastResponseBody, "multi-instance-envelope-" & $target.kind
    )
      .expect("captureIfRequested multi-instance")

    assertOn target,
      resp.response.methodResponses.len == 3,
      "envelope must carry three responses, got " & $resp.response.methodResponses.len

    # Order preservation: methodResponses[i] must match methodCalls[i].
    assertOn target, resp.response.methodResponses[0].rawName == "Mailbox/get"
    assertOn target, resp.response.methodResponses[1].rawName == "Mailbox/get"
    assertOn target, resp.response.methodResponses[2].rawName == "Mailbox/get"

    # A3.6: all three calls flow through public typed entry points. The full
    # record is ``GetResponse[Mailbox]``; the two sparse projections are
    # ``GetResponse[PartialMailbox]`` — requested properties present
    # (``Opt.some``), unrequested ones absent (``Opt.none``). No internal
    # envelope inspection needed: the typed surface IS the public path now.
    let fullResp =
      resp.get(fullHandle).expectValue("Mailbox/get full extract[" & $target.kind & "]")
    let sparseResp = resp.get(sparseHandle).expectValue(
        "Mailbox/get sparse extract[" & $target.kind & "]"
      )
    let countsResp = resp.get(countsHandle).expectValue(
        "Mailbox/get counts extract[" & $target.kind & "]"
      )

    assertOn target, fullResp.list.len >= 1, "full Mailbox/get must surface mailboxes"
    assertOn target,
      sparseResp.list.len >= 1, "sparse Mailbox/get must surface mailboxes"
    assertOn target,
      countsResp.list.len >= 1, "counts Mailbox/get must surface mailboxes"
    assertOn target,
      fullResp.list.len == sparseResp.list.len,
      "all three /get calls target the same account, list lengths must match"
    assertOn target,
      sparseResp.list.len == countsResp.list.len,
      "all three /get calls target the same account, list lengths must match"

    # Full records flow through Mailbox.fromJson (most fields non-Opt). Sparse
    # projections flow through PartialMailbox.fromJson (all-Opt): the requested
    # properties surface ``Opt.some``, the unrequested ones stay ``Opt.none``.
    for mb in fullResp.list:
      assertOn target, mb.name.len > 0, "full Mailbox.fromJson must populate name"
    for pm in sparseResp.list:
      assertOn target, pm.id.isSome, "sparse PartialMailbox must carry id"
      assertOn target, pm.name.isSome, "sparse PartialMailbox must carry requested name"
      assertOn target,
        pm.myRights.isNone,
        "sparse PartialMailbox must NOT carry myRights (not requested)"
      assertOn target,
        pm.totalEmails.isNone,
        "sparse PartialMailbox must NOT carry totalEmails (not requested)"
    for pm in countsResp.list:
      assertOn target, pm.id.isSome, "counts PartialMailbox must carry id"
      assertOn target,
        pm.totalEmails.isSome, "counts PartialMailbox must carry requested totalEmails"
      assertOn target,
        pm.name.isNone, "counts PartialMailbox must NOT carry name (not requested)"
