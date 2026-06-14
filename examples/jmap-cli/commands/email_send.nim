# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email send <toAddress> <subject> <bodyText>` — create a draft
## Email and submit it in ONE request, moving it to Sent on success. This
## is the gnarliest public path. Three things the API forces on the caller,
## each a recorded finding:
##
##  1. No plain-text body shorthand: the body is hand-built through the
##     4-layer chain BlueprintBodyValue -> BlueprintLeafPart{bpsInline} ->
##     BlueprintBodyPart{text/plain} -> flatBody. The inline partId can only
##     be minted via parsePartIdFromServer (a receive-side-named parser).
##  2. addEmailSubmissionAndEmailSet does NOT create the email — its `create`
##     is the submission table only. The draft is created by a SEPARATE
##     addEmailSet(create=...) on the SAME builder; the "AndEmailSet" is the
##     server's IMPLICIT onSuccess Email/set (an update). One request = three
##     method calls.
##  3. EmailSubmissionBlueprint.emailId is a plain Id with no typed
##     forward-reference, so the same-request link to the draft is smuggled
##     via parseIdFromServer("#" & $draftCid) (strict parseId rejects '#').

import jmap_client
import std/tables
import ./cli_session

template joinErrs(errs: untyped): string =
  ## Render any of the library's several error accumulators (seq[ValidationError],
  ## EmailBlueprintErrors, ...) — each iterable with a per-element `message` — to
  ## one string. The hub provides no aggregate render-to-string helper.
  block:
    var s = ""
    for e in errs:
      s.add(e.message & "; ")
    s

proc firstIdentity(ctx: CliContext): Result[(Id, string), string] =
  let (b, h) = ctx.client.newBuilder().addIdentityGet(ctx.mailAccount)
  let dr = ctx.client.send(b.freeze()).valueOr:
    return err("send failed: " & error.message)
  let resp = dr.get(h).valueOr:
    return err("Identity/get failed: " & error.message)
  if resp.list.len == 0:
    return err("no identity to send from")
  ok((resp.list[0].id, resp.list[0].email))

proc resolveRole(ctx: CliContext, want: MailboxRoleKind): Result[Id, string] =
  let (b, h) = ctx.client.newBuilder().addMailboxGet(ctx.mailAccount)
  let dr = ctx.client.send(b.freeze()).valueOr:
    return err("send failed: " & error.message)
  let resp = dr.get(h).valueOr:
    return err("Mailbox/get failed: " & error.message)
  for mb in resp.list:
    for role in mb.role:
      if role.kind == want:
        return ok(mb.id)
  err("mailbox role not found: " & $want)

proc buildDraftBlueprint(
    draftsId: Id, fromEmail, toAddress, subject, body: string
): Result[EmailBlueprint, string] =
  let mboxIds = parseNonEmptyMailboxIdSet(@[draftsId]).valueOr:
    return err("mailbox id set: " & error.message)
  let fromA = parseEmailAddress(fromEmail).valueOr:
    return err("from address: " & error.message)
  let toA = parseEmailAddress(toAddress).valueOr:
    return err("to address: " & error.message)
  # No plain-text body helper: hand-build value -> leaf -> part -> flatBody.
  let bodyPartId = parsePartIdFromServer("text").valueOr:
    return err("part id: " & error.message)
  let textLeaf = BlueprintLeafPart(
    source: bpsInline, partId: bodyPartId, value: BlueprintBodyValue(value: body)
  )
  let textPart = BlueprintBodyPart(
    # contentType MUST be exactly "text/plain" or parseEmailBlueprint rejects
    # with ebcTextBodyNotTextPlain.
    contentType: "text/plain",
    isMultipart: false,
    leaf: textLeaf,
  )
  let draftBody = flatBody(textBody = Opt.some(textPart))
  let bp = parseEmailBlueprint(
    mailboxIds = mboxIds,
    body = draftBody,
    fromAddr = Opt.some(@[fromA]),
    to = Opt.some(@[toA]),
    subject = Opt.some(subject),
  ).valueOr:
    return err("blueprint rejected: " & joinErrs(error)) # EmailBlueprintErrors rail
  ok(bp)

proc buildSubmissionBlueprint(
    identityId: Id, draftCid: CreationId, fromEmail, toAddress: string
): Result[EmailSubmissionBlueprint, string] =
  # emailId is a plain Id; the same-request forward-ref is "#<draftCid>",
  # which only the lenient parser accepts (strict parseId rejects '#').
  let emailRef = parseIdFromServer("#" & $draftCid).valueOr:
    return err("email forward-ref: " & error.message)
  let fromMb = parseRFC5321Mailbox(fromEmail).valueOr:
    return err("RFC5321 from: " & error.message)
  let toMb = parseRFC5321Mailbox(toAddress).valueOr:
    return err("RFC5321 to: " & error.message)
  let fromSa = SubmissionAddress(mailbox: fromMb, parameters: Opt.none(SubmissionParams))
  let toSa = SubmissionAddress(mailbox: toMb, parameters: Opt.none(SubmissionParams))
  let rcpts = parseNonEmptyRcptList(@[toSa]).valueOr:
    return err("rcpt list: " & joinErrs(error))
  let env = Envelope(mailFrom: reversePath(fromSa), rcptTo: rcpts)
  let subBp = parseEmailSubmissionBlueprint(
    identityId = identityId, emailId = emailRef, envelope = Opt.some(env)
  ).valueOr:
    return err("submission blueprint: " & joinErrs(error))
  ok(subBp)

proc run*(args: seq[string]): int =
  if args.len < 3:
    stderr.writeLine "usage: jmap-cli email send <toAddress> <subject> <bodyText>"
    return 2
  let toAddress = args[0]
  let subject = args[1]
  let bodyText = args[2]
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1
  let (identityId, fromEmail) = firstIdentity(ctx).valueOr:
    stderr.writeLine error
    return 1
  let draftsId = resolveRole(ctx, mrDrafts).valueOr:
    stderr.writeLine error
    return 1
  let sentId = resolveRole(ctx, mrSent).valueOr:
    stderr.writeLine error
    return 1

  let draftCid = parseCreationId("draft").valueOr:
    stderr.writeLine "creation id: " & error.message
    return 1
  let subCid = parseCreationId("sub").valueOr:
    stderr.writeLine "creation id: " & error.message
    return 1

  let draftBp = buildDraftBlueprint(draftsId, fromEmail, toAddress, subject, bodyText).valueOr:
    stderr.writeLine error
    return 1
  let subBp = buildSubmissionBlueprint(identityId, draftCid, fromEmail, toAddress).valueOr:
    stderr.writeLine error
    return 1

  # onSuccessUpdateEmail is keyed by the SUBMISSION cid (not the email cid):
  # on a successful send, move the draft out of Drafts into Sent and drop $draft.
  let draftKw = parseKeyword("$draft").valueOr:
    stderr.writeLine "keyword: " & error.message
    return 1
  let upd = initEmailUpdateSet(
    @[removeFromMailbox(draftsId), addToMailbox(sentId), removeKeyword(draftKw)]
  ).valueOr:
    stderr.writeLine "onSuccess update set: " & joinErrs(error)
    return 1
  let onSucc = parseNonEmptyOnSuccessUpdateEmail(@[(creationRef(subCid), upd)]).valueOr:
    stderr.writeLine "onSuccess: " & joinErrs(error)
    return 1

  # One builder, two explicit invocations: Email/set (draft create) then
  # EmailSubmission/set (+ the server's implicit onSuccess Email/set update).
  var emailCreate = initTable[CreationId, EmailBlueprint]()
  emailCreate[draftCid] = draftBp
  var subCreate = initTable[CreationId, EmailSubmissionBlueprint]()
  subCreate[subCid] = subBp

  let b0 = ctx.client.newBuilder()
  let (b1, emailHandle) = b0.addEmailSet(ctx.mailAccount, create = Opt.some(emailCreate))
  # addEmailSubmissionAndEmailSet returns a Result wrapping an UNCOPYABLE
  # RequestBuilder, so the Ok tuple is moved, never .get()'d.
  var r = b1.addEmailSubmissionAndEmailSet(
    ctx.mailAccount, create = Opt.some(subCreate), onSuccessUpdateEmail = Opt.some(onSucc)
  )
  if r.isErr:
    stderr.writeLine "compound builder rejected: " & r.error.message
    return 1
  let (b2, subHandles) = move(r.value)

  let dr = ctx.client.send(freeze(b2)).valueOr: # finaliser is freeze (sink), not build
    stderr.writeLine "send failed: " & error.message
    return 1
  let emailRes = dr.get(emailHandle).valueOr:
    stderr.writeLine "Email/set (draft) failed: " & error.message
    return 1
  let subRes = dr.getBoth(subHandles).valueOr: # CompoundResults{primary, implicit}
    stderr.writeLine "EmailSubmission extraction failed: " & error.message
    return 1

  for cid, res in emailRes.createResults:
    if res.isOk:
      echo "draft created ", $cid, " -> ", $res.value.id
    else:
      stderr.writeLine "draft create failed " & $cid & ": " & res.error.message
  for cid, res in subRes.primary.createResults:
    if res.isOk:
      echo "submission created ", $cid, " -> ", $res.value.id
    else:
      stderr.writeLine "submission failed " & $cid & ": " & res.error.message
  for id, res in subRes.implicit.updateResults:
    if res.isOk:
      echo "moved to Sent: ", $id
    else:
      stderr.writeLine "onSuccess move failed " & $id & ": " & res.error.message
  return 0
