# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: lenient receive parsers
## (``parseUtcDateFromServer``, lenient ``EmailAddress.fromJson``,
## ``*FromServer`` variants, ``Opt[T]`` field handling) tolerate
## the diverse wire shapes Stalwart produces from real-world MIME
## input.  ``Email.fromJson`` succeeds even when the underlying
## RFC 5322 source contained encoded-words, fractional-second
## dates, or control-char artefacts that the client-side smart
## constructors would reject.
##
## Phase J Step 73.  Mirrors Phase E27's ``temail_import_from_blob_live``
## idiom: seed an outer email with a ``message/rfc822`` attachment,
## extract the attached BlobId, and ``Email/import`` it.  Stalwart
## parses the imported message and the read-back exercise the
## lenient-receive parsers across whatever shape Stalwart returns.

import std/json
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tpostelsLawReceiveLive:
  forEachLiveTarget(target):
    # James 3.9 compatibility: skipped on James.
    # Reason: exercises inline-bodyValues attachments (partId-referenced bodyValues per RFC 8621 §4.6); James 3.9 requires blob-uploaded attachments (`attachments[].blobId`) and rejects inline ones with invalidArguments. The library does not yet expose the JMAP `/upload` endpoint (RFC 8620 §6.1) — that is a deliberately deferred library scope (no blob/push). Tests revisit James once `uploadBlob` lands.
    # Replay coverage for the Stalwart wire shape is preserved via
    # captured ``-stalwart`` fixtures.
    if target.kind == ltkJames:
      continue
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )

    # Step 1: seed an outer email with a message/rfc822 attachment.
    # The inner message exercises lenient parsing through Stalwart's
    # MIME parser path.
    let aliceAddr = buildAliceAddr()
    let outerId = seedForwardedEmail(
        client,
        mailAccountId,
        inbox,
        outerSubject = "phase-j 73 outer carrier",
        innerSubject = "phase-j 73 inner",
        innerFrom = aliceAddr,
        innerBody = "Phase J 73 lenient-receive test body.",
        creationLabel = "phase-j-73-outer",
      )
      .expect("seedForwardedEmail[" & $target.kind & "]")

    # Step 2: extract the attached message's BlobId.
    let attachmentBlobId = getFirstAttachmentBlobId(client, mailAccountId, outerId)
      .expect("getFirstAttachmentBlobId[" & $target.kind & "]")

    # Step 3: Email/import the attached blob into the inbox.
    let mailboxIds = parseNonEmptyMailboxIdSet(@[inbox]).expect(
        "parseNonEmptyMailboxIdSet[" & $target.kind & "]"
      )
    let importItem =
      initEmailImportItem(blobId = attachmentBlobId, mailboxIds = mailboxIds)
    let importCid =
      parseCreationId("phaseJ73import").expect("parseCreationId[" & $target.kind & "]")
    let importMap = initNonEmptyEmailImportMap(@[(importCid, importItem)]).expect(
        "initNonEmptyEmailImportMap"
      )
    let (bImp, importHandle) =
      addEmailImport(initRequestBuilder(), mailAccountId, emails = importMap)
    let respImp = client.send(bImp).expect("send Email/import[" & $target.kind & "]")
    let importResp =
      respImp.get(importHandle).expect("Email/import extract[" & $target.kind & "]")
    var importedEmailId: Id
    var imported = false
    importResp.createResults.withValue(importCid, outcome):
      assertOn target,
        outcome.isOk, "Email/import must succeed; got " & outcome.error.rawType
      importedEmailId = outcome.unsafeValue.id
      imported = true
    do:
      assertOn target, false, "Email/import must report a create outcome"
    assertOn target, imported

    # Step 4: read back via Email/get and capture the wire shape.
    let (bGet, getHandle) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[importedEmailId]),
      properties =
        Opt.some(@["id", "from", "receivedAt", "subject", "keywords", "mailboxIds"]),
    )
    let respGet =
      client.send(bGet).expect("send Email/get import readback[" & $target.kind & "]")
    captureIfRequested(client, "postels-law-receive-adversarial-mime-" & $target.kind)
      .expect("captureIfRequested postel's law")
    let getResp =
      respGet.get(getHandle).expect("Email/get extract[" & $target.kind & "]")
    assertOn target, getResp.list.len == 1
    let email = Email.fromJson(getResp.list[0]).expect(
        "Email.fromJson lenient[" & $target.kind & "]"
      )

    # The lenient parser must surface every requested field as
    # populated even when the underlying MIME has unusual encoding.
    assertOn target, email.id.isSome
    assertOn target,
      email.receivedAt.isSome, "Stalwart fills receivedAt for imported messages"
    assertOn target,
      email.fromAddr.isSome and email.fromAddr.unsafeGet.len >= 1,
      "imported email's From header must round-trip"
    assertOn target, email.subject.isSome, "imported email's Subject must round-trip"

    # Step 5: empty-vs-null table parser tolerance.  Email/get a
    # second email (the seed) that has no keywords set; Email.fromJson
    # must accept whatever wire shape (``{}`` or absent) Stalwart
    # emits for the empty case.  Library contract: empty / null /
    # absent all project to the same empty Table[Keyword, bool].
    let (bGet2, getHandle2) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[outerId, importedEmailId]),
      properties = Opt.some(@["id", "keywords", "mailboxIds"]),
    )
    let respGet2 = client.send(bGet2).expect(
        "send Email/get keywords readback[" & $target.kind & "]"
      )
    let getResp2 =
      respGet2.get(getHandle2).expect("Email/get extract[" & $target.kind & "]")
    assertOn target, getResp2.list.len == 2
    for node in getResp2.list:
      # Wire shape may be {} or null for empty keywords; the parser
      # tolerates both per Postel's law.
      let kwNode = node{"keywords"}
      if not kwNode.isNil:
        assertOn target,
          kwNode.kind in {JObject, JNull},
          "keywords wire shape must be JObject or JNull; got " & $kwNode.kind
      let parsed =
        Email.fromJson(node).expect("Email.fromJson tolerant[" & $target.kind & "]")
      assertOn target, parsed.id.isSome

    # Cleanup: destroy outer + imported emails so re-runs are
    # idempotent.
    let (bClean, cleanHandle) = addEmailSet(
      initRequestBuilder(),
      mailAccountId,
      destroy = directIds(@[outerId, importedEmailId]),
    )
    let respClean =
      client.send(bClean).expect("send Email/set cleanup[" & $target.kind & "]")
    let cleanResp = respClean.get(cleanHandle).expect(
        "Email/set cleanup extract[" & $target.kind & "]"
      )
    for id in @[outerId, importedEmailId]:
      cleanResp.destroyResults.withValue(id, outcome):
        assertOn target, outcome.isOk, "cleanup destroy must succeed"
      do:
        assertOn target, false, "cleanup must report an outcome for each seed"

    client.close()
