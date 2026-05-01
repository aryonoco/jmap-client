# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test scaffolds shared across the Phase A and Phase B
## suites. ``mconfig.nim`` stays single-purpose (env contract); this
## module owns the Stalwart-interaction recipes that would otherwise be
## inlined verbatim across multiple test files: resolving Alice's inbox
## via ``Mailbox/get`` and seeding a single text/plain ``Email`` via
## ``Email/set create``.
##
## Helpers return ``Result[T, string]`` so callers can chain ``.expect``
## with the same ergonomics as ``loadLiveTestConfig``. They take a
## ``var JmapClient`` because ``client.send`` requires it.

{.push raises: [].}

import std/tables

import results
import jmap_client
import jmap_client/client

proc resolveInboxId*(
    client: var JmapClient, mailAccountId: AccountId
): Result[Id, string] =
  ## ``Mailbox/get`` → returns the ``Id`` of the mailbox carrying
  ## ``role == roleInbox``. Errors out narratively when the request
  ## fails, the response cannot be extracted, or no inbox-role mailbox
  ## is present.
  let (b, mbHandle) = addGet[Mailbox](initRequestBuilder(), mailAccountId)
  let resp = client.send(b).valueOr:
    return err("Mailbox/get send failed: " & error.message)
  let mbResp = resp.get(mbHandle).valueOr:
    return err("Mailbox/get extract failed: " & error.rawType)
  for node in mbResp.list:
    let mb = Mailbox.fromJson(node).valueOr:
      return err("Mailbox parse failed during inbox lookup")
    for role in mb.role:
      if role == roleInbox:
        return ok(mb.id)
  err("no Mailbox with role==Inbox found in account")

proc seedSimpleEmail*(
    client: var JmapClient,
    mailAccountId: AccountId,
    inbox: Id,
    subject: string,
    creationLabel: string,
): Result[Id, string] =
  ## ``Email/set create`` for a minimal text/plain message addressed
  ## from alice@example.com to herself, filed in ``inbox``. Returns the
  ## server-assigned ``EmailId``. Caller supplies a unique
  ## ``creationLabel`` per seed in the same test (e.g., ``"seedA"``) so
  ## multiple seeds in one ``Email/set`` would not collide — even though
  ## each helper call issues its own request, the label still flows
  ## through ``CreationId`` validation.
  let mailboxIds = parseNonEmptyMailboxIdSet(@[inbox]).valueOr:
    return err("parseNonEmptyMailboxIdSet failed: " & error.message)
  let aliceAddr = parseEmailAddress("alice@example.com", Opt.some("Alice")).valueOr:
    return err("parseEmailAddress failed: " & error.message)
  let partId = parsePartIdFromServer("1").valueOr:
    return err("parsePartIdFromServer failed: " & error.message)
  let textPart = BlueprintBodyPart(
    isMultipart: false,
    leaf: BlueprintLeafPart(
      source: bpsInline,
      partId: partId,
      value: BlueprintBodyValue(value: "Live-test seed body."),
    ),
    contentType: "text/plain",
    extraHeaders: initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue](),
    name: Opt.none(string),
    disposition: Opt.none(ContentDisposition),
    cid: Opt.none(string),
    language: Opt.none(seq[string]),
    location: Opt.none(string),
  )
  let blueprint = parseEmailBlueprint(
    mailboxIds = mailboxIds,
    body = flatBody(textBody = Opt.some(textPart)),
    fromAddr = Opt.some(@[aliceAddr]),
    to = Opt.some(@[aliceAddr]),
    subject = Opt.some(subject),
  ).valueOr:
    return err("parseEmailBlueprint failed: " & $error)
  let cid = parseCreationId(creationLabel).valueOr:
    return err("parseCreationId failed: " & error.message)
  var createTbl = initTable[CreationId, EmailBlueprint]()
  createTbl[cid] = blueprint
  let (b, setHandle) =
    addEmailSet(initRequestBuilder(), mailAccountId, create = Opt.some(createTbl))
  let resp = client.send(b).valueOr:
    return err("Email/set send failed: " & error.message)
  let setResp = resp.get(setHandle).valueOr:
    return err("Email/set extract failed: " & error.rawType)
  var seededId: Id
  var found = false
  setResp.createResults.withValue(cid, outcome):
    let item = outcome.valueOr:
      return err("Email/set create rejected: " & error.rawType)
    seededId = item.id
    found = true
  do:
    return err("Email/set returned no result for creationId " & creationLabel)
  doAssert found
  ok(seededId)
