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
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
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
import jmap_client/internal/mail/mailbox as jmailbox
import ./mcapture
import ./mconfig
import ./mlive

block tmailboxSetCrudLive:
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

    # --- Step 1: resolve Inbox id ---------------------------------------
    let (b1, mbHandle) = addGet[Mailbox](initRequestBuilder(), mailAccountId)
    let resp1 = client.send(b1).expect("send Mailbox/get[" & $target.kind & "]")
    let mbResp = resp1.get(mbHandle).expect("Mailbox/get extract[" & $target.kind & "]")
    var inboxId = Opt.none(Id)
    for mb in mbResp.list:
      for role in mb.role:
        if role == roleInbox:
          inboxId = Opt.some(mb.id)
    assertOn target, inboxId.isSome, "alice's account must have an Inbox role mailbox"
    let inbox = inboxId.get()

    # --- Step 2: create ``phase-b parent`` under Inbox -------------------
    let parentCreate = parseMailboxCreate(
        name = "phase-b parent", parentId = Opt.some(inbox)
      )
      .expect("parseMailboxCreate parent[" & $target.kind & "]")
    let parentCid = parseCreationId("parentMb").expect(
        "parseCreationId parentMb[" & $target.kind & "]"
      )
    var parentTbl = initTable[CreationId, MailboxCreate]()
    parentTbl[parentCid] = parentCreate
    let (b2, setHandle1) =
      addMailboxSet(initRequestBuilder(), mailAccountId, create = Opt.some(parentTbl))
    let resp2 = client.send(b2).expect("send Mailbox/set parent[" & $target.kind & "]")
    let setResp1 =
      resp2.get(setHandle1).expect("Mailbox/set parent extract[" & $target.kind & "]")
    var parentId: Id
    var parentOk = false
    setResp1.createResults.withValue(parentCid, outcome):
      assertOn target,
        outcome.isOk, "parent create must succeed: " & outcome.error.rawType
      parentId = outcome.unsafeValue.id
      parentOk = true
    do:
      assertOn target, false, "Mailbox/set parent must report an outcome"
    assertOn target, parentOk

    # --- Step 3: create ``phase-b child`` under the new parent ----------
    let childCreate = parseMailboxCreate(
        name = "phase-b child", parentId = Opt.some(parentId)
      )
      .expect("parseMailboxCreate child[" & $target.kind & "]")
    let childCid =
      parseCreationId("childMb").expect("parseCreationId childMb[" & $target.kind & "]")
    var childTbl = initTable[CreationId, MailboxCreate]()
    childTbl[childCid] = childCreate
    let (b3, setHandle2) =
      addMailboxSet(initRequestBuilder(), mailAccountId, create = Opt.some(childTbl))
    let resp3 = client.send(b3).expect("send Mailbox/set child[" & $target.kind & "]")
    let setResp2 =
      resp3.get(setHandle2).expect("Mailbox/set child extract[" & $target.kind & "]")
    var childId: Id
    var childOk = false
    setResp2.createResults.withValue(childCid, outcome):
      assertOn target,
        outcome.isOk, "child create must succeed: " & outcome.error.rawType
      childId = outcome.unsafeValue.id
      childOk = true
    do:
      assertOn target, false, "Mailbox/set child must report an outcome"
    assertOn target, childOk

    # --- Step 4: sad-path destroy parent without onDestroyRemoveEmails --
    let (b4, setHandle3) = addMailboxSet(
      initRequestBuilder(), mailAccountId, destroy = directIds(@[parentId])
    )
    let resp4 =
      client.send(b4).expect("send Mailbox/set destroy parent[" & $target.kind & "]")
    captureIfRequested(client, "mailbox-set-has-child-" & $target.kind).expect(
      "captureIfRequested"
    )
    let setResp3 = resp4.get(setHandle3).expect(
        "Mailbox/set destroy parent extract[" & $target.kind & "]"
      )
    var sawHasChild = false
    setResp3.destroyResults.withValue(parentId, outcome):
      assertOn target,
        outcome.isErr,
        "destroying a parent with a surviving child must fail per RFC 8621 §2.5"
      let setErr = outcome.error
      assertOn target,
        setErr.errorType == setMailboxHasChild,
        "expected mailboxHasChild, got rawType=" & setErr.rawType
      sawHasChild = true
    do:
      assertOn target, false, "Mailbox/set destroy must report an outcome for parentId"
    assertOn target, sawHasChild

    # --- Step 5: update leg — rename child ------------------------------
    let renameUpdate = jmailbox.setName("phase-b renamed")
    let renameSet = initMailboxUpdateSet(@[renameUpdate]).expect(
        "initMailboxUpdateSet[" & $target.kind & "]"
      )
    let renameUpdates = parseNonEmptyMailboxUpdates(@[(childId, renameSet)]).expect(
        "parseNonEmptyMailboxUpdates"
      )
    let (b5, setHandle4) = addMailboxSet(
      initRequestBuilder(), mailAccountId, update = Opt.some(renameUpdates)
    )
    let resp5 =
      client.send(b5).expect("send Mailbox/set rename child[" & $target.kind & "]")
    let setResp4 = resp5.get(setHandle4).expect(
        "Mailbox/set rename child extract[" & $target.kind & "]"
      )
    var renamed = false
    setResp4.updateResults.withValue(childId, outcome):
      assertOn target, outcome.isOk, "rename must succeed for child"
      renamed = true
    do:
      assertOn target, false, "Mailbox/set update must report an outcome for childId"
    assertOn target, renamed

    # --- Step 6: cleanup — destroy child first, then parent in a second
    # Mailbox/set call. RFC 8620 §5.3 specifies in-order processing of
    # destroy[] within a single set, but James 3.9 batches the
    # ``mailboxHasChild`` validation up-front and rejects the parent
    # destroy regardless of whether a sibling destroy in the same call
    # would have removed the child first. Two separate invocations
    # sidestep the divergence and exercise the contract correctly on
    # both servers — the protocol contract is "child then parent",
    # not "atomic batch".
    let (b6a, setHandleChild) = addMailboxSet(
      initRequestBuilder(), mailAccountId, destroy = directIds(@[childId])
    )
    let resp6a =
      client.send(b6a).expect("send Mailbox/set destroy child[" & $target.kind & "]")
    let setResp6a = resp6a.get(setHandleChild).expect(
        "Mailbox/set destroy child extract[" & $target.kind & "]"
      )
    var childDestroyed = false
    setResp6a.destroyResults.withValue(childId, outcome):
      assertOn target, outcome.isOk, "child cleanup destroy must succeed"
      childDestroyed = true
    do:
      assertOn target, false, "cleanup must report an outcome for childId"

    let (b6b, setHandleParent) = addMailboxSet(
      initRequestBuilder(), mailAccountId, destroy = directIds(@[parentId])
    )
    let resp6b =
      client.send(b6b).expect("send Mailbox/set destroy parent[" & $target.kind & "]")
    let setResp6b = resp6b.get(setHandleParent).expect(
        "Mailbox/set destroy parent extract[" & $target.kind & "]"
      )
    var parentDestroyed = false
    setResp6b.destroyResults.withValue(parentId, outcome):
      assertOn target,
        outcome.isOk, "parent cleanup destroy must succeed once child gone"
      parentDestroyed = true
    do:
      assertOn target, false, "cleanup must report an outcome for parentId"
    assertOn target, childDestroyed and parentDestroyed
    client.close()
