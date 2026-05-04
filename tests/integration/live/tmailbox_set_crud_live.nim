# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Mailbox/set CRUD (RFC 8621 §2.5) against
## Stalwart. Exercises create / update / destroy plus the structural
## sad path that gives ``mailboxHasChild`` (RFC 8621 §2.5) when a parent
## with surviving children is destroyed without
## ``onDestroyRemoveEmails``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.
##
## Six sequential ``Mailbox/set`` invocations:
##  1. ``Mailbox/get`` → resolve Inbox id (parent for the hierarchy).
##  2. Create ``phase-b parent`` under Inbox.
##  3. Create ``phase-b child`` under the new parent.
##  4. **Sad path:** destroy ``parent`` without
##     ``onDestroyRemoveEmails`` — assert ``mailboxHasChild``.
##  5. Rename ``child`` to ``phase-b renamed``.
##  6. **Cleanup:** destroy ``[child, parent]`` in that order.

import std/tables

import results
import jmap_client
import jmap_client/client
import jmap_client/mail/mailbox as jmailbox
import ./mcapture
import ./mconfig
import ./mlive

block tmailboxSetCrudLive:
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
    let mailAccountId = resolveMailAccountId(session).expect("resolveMailAccountId")

    # --- Step 1: resolve Inbox id ---------------------------------------
    let (b1, mbHandle) = addGet[Mailbox](initRequestBuilder(), mailAccountId)
    let resp1 = client.send(b1).expect("send Mailbox/get")
    let mbResp = resp1.get(mbHandle).expect("Mailbox/get extract")
    var inboxId = Opt.none(Id)
    for node in mbResp.list:
      let mb = Mailbox.fromJson(node).expect("parse Mailbox")
      for role in mb.role:
        if role == roleInbox:
          inboxId = Opt.some(mb.id)
    doAssert inboxId.isSome, "alice's account must have an Inbox role mailbox"
    let inbox = inboxId.get()

    # --- Step 2: create ``phase-b parent`` under Inbox -------------------
    let parentCreate = parseMailboxCreate(
        name = "phase-b parent", parentId = Opt.some(inbox)
      )
      .expect("parseMailboxCreate parent")
    let parentCid = parseCreationId("parentMb").expect("parseCreationId parentMb")
    var parentTbl = initTable[CreationId, MailboxCreate]()
    parentTbl[parentCid] = parentCreate
    let (b2, setHandle1) =
      addMailboxSet(initRequestBuilder(), mailAccountId, create = Opt.some(parentTbl))
    let resp2 = client.send(b2).expect("send Mailbox/set parent")
    let setResp1 = resp2.get(setHandle1).expect("Mailbox/set parent extract")
    var parentId: Id
    var parentOk = false
    setResp1.createResults.withValue(parentCid, outcome):
      doAssert outcome.isOk, "parent create must succeed: " & outcome.error.rawType
      parentId = outcome.unsafeValue.id
      parentOk = true
    do:
      doAssert false, "Mailbox/set parent must report an outcome"
    doAssert parentOk

    # --- Step 3: create ``phase-b child`` under the new parent ----------
    let childCreate = parseMailboxCreate(
        name = "phase-b child", parentId = Opt.some(parentId)
      )
      .expect("parseMailboxCreate child")
    let childCid = parseCreationId("childMb").expect("parseCreationId childMb")
    var childTbl = initTable[CreationId, MailboxCreate]()
    childTbl[childCid] = childCreate
    let (b3, setHandle2) =
      addMailboxSet(initRequestBuilder(), mailAccountId, create = Opt.some(childTbl))
    let resp3 = client.send(b3).expect("send Mailbox/set child")
    let setResp2 = resp3.get(setHandle2).expect("Mailbox/set child extract")
    var childId: Id
    var childOk = false
    setResp2.createResults.withValue(childCid, outcome):
      doAssert outcome.isOk, "child create must succeed: " & outcome.error.rawType
      childId = outcome.unsafeValue.id
      childOk = true
    do:
      doAssert false, "Mailbox/set child must report an outcome"
    doAssert childOk

    # --- Step 4: sad-path destroy parent without onDestroyRemoveEmails --
    let (b4, setHandle3) = addMailboxSet(
      initRequestBuilder(), mailAccountId, destroy = directIds(@[parentId])
    )
    let resp4 = client.send(b4).expect("send Mailbox/set destroy parent")
    captureIfRequested(client, "mailbox-set-has-child-stalwart").expect(
      "captureIfRequested"
    )
    let setResp3 = resp4.get(setHandle3).expect("Mailbox/set destroy parent extract")
    var sawHasChild = false
    setResp3.destroyResults.withValue(parentId, outcome):
      doAssert outcome.isErr,
        "destroying a parent with a surviving child must fail per RFC 8621 §2.5"
      let setErr = outcome.error
      doAssert setErr.errorType == setMailboxHasChild,
        "expected mailboxHasChild, got rawType=" & setErr.rawType
      sawHasChild = true
    do:
      doAssert false, "Mailbox/set destroy must report an outcome for parentId"
    doAssert sawHasChild

    # --- Step 5: update leg — rename child ------------------------------
    let renameUpdate = jmailbox.setName("phase-b renamed")
    let renameSet = initMailboxUpdateSet(@[renameUpdate]).expect("initMailboxUpdateSet")
    let renameUpdates = parseNonEmptyMailboxUpdates(@[(childId, renameSet)]).expect(
        "parseNonEmptyMailboxUpdates"
      )
    let (b5, setHandle4) = addMailboxSet(
      initRequestBuilder(), mailAccountId, update = Opt.some(renameUpdates)
    )
    let resp5 = client.send(b5).expect("send Mailbox/set rename child")
    let setResp4 = resp5.get(setHandle4).expect("Mailbox/set rename child extract")
    var renamed = false
    setResp4.updateResults.withValue(childId, outcome):
      doAssert outcome.isOk, "rename must succeed for child"
      renamed = true
    do:
      doAssert false, "Mailbox/set update must report an outcome for childId"
    doAssert renamed

    # --- Step 6: cleanup — destroy [child, parent] in that order --------
    let (b6, setHandle5) = addMailboxSet(
      initRequestBuilder(), mailAccountId, destroy = directIds(@[childId, parentId])
    )
    let resp6 = client.send(b6).expect("send Mailbox/set cleanup")
    let setResp5 = resp6.get(setHandle5).expect("Mailbox/set cleanup extract")
    var childDestroyed = false
    var parentDestroyed = false
    setResp5.destroyResults.withValue(childId, outcome):
      doAssert outcome.isOk, "child cleanup destroy must succeed"
      childDestroyed = true
    do:
      doAssert false, "cleanup must report an outcome for childId"
    setResp5.destroyResults.withValue(parentId, outcome):
      doAssert outcome.isOk, "parent cleanup destroy must succeed once child gone"
      parentDestroyed = true
    do:
      doAssert false, "cleanup must report an outcome for parentId"
    doAssert childDestroyed and parentDestroyed
    client.close()
