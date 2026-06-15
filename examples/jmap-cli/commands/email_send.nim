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
##
## Error handling is the headline: every construction call folds onto the one
## ``JmapError`` rail with a single ``.lift``, every pipeline call threads with
## a bare ``?``, and the three method responses (Email/set draft, the implicit
## Email/set move, EmailSubmission/set) are ``MethodOutcome`` data on the ok
## branch. The former ``joinErrs`` flattening and the ``Result[T, string]``
## collapse are gone.

import jmap_client
import std/tables
import ./cli_session

proc firstIdentity(ctx: CliContext): JmapResult[Opt[(Id, string)]] =
  ## Identity/get; the first identity (its id + address) is the From for
  ## sending. ``none`` means no usable identity (or the method errored, already
  ## reported) — a domain condition, never a rail error.
  let (b, h) = ctx.client.newBuilder().addIdentityGet(ctx.mailAccount)
  let dr = ?ctx.client.send(b.freeze())
  let outcome = ?dr.get(h)
  case outcome.kind
  of mokMethodError:
    stderr.writeLine "Identity/get: " & outcome.error.message
    ok(Opt.none((Id, string)))
  of mokValue:
    let resp = outcome.value
    if resp.list.len == 0:
      stderr.writeLine "no identity to send from"
      ok(Opt.none((Id, string)))
    else:
      ok(Opt.some((resp.list[0].id, resp.list[0].email)))

proc resolveRoles(ctx: CliContext): JmapResult[Opt[(Id, Id)]] =
  ## One Mailbox/get, scanned for BOTH the Drafts and Sent roles — sending
  ## needs both, and a single fetch returns the whole list. ``none`` means a
  ## required role (or the whole method) was missing — a domain condition.
  let (b, h) = ctx.client.newBuilder().addMailboxGet(ctx.mailAccount)
  let dr = ?ctx.client.send(b.freeze())
  let outcome = ?dr.get(h)
  case outcome.kind
  of mokMethodError:
    stderr.writeLine "Mailbox/get: " & outcome.error.message
    ok(Opt.none((Id, Id)))
  of mokValue:
    var draftsId = Opt.none(Id)
    var sentId = Opt.none(Id)
    for mb in outcome.value.list:
      for role in mb.role:
        if role.kind == mrDrafts:
          draftsId = Opt.some(mb.id)
        elif role.kind == mrSent:
          sentId = Opt.some(mb.id)
    let drafts = draftsId.valueOr:
      stderr.writeLine "Drafts mailbox not found"
      return ok(Opt.none((Id, Id)))
    let sent = sentId.valueOr:
      stderr.writeLine "Sent mailbox not found"
      return ok(Opt.none((Id, Id)))
    ok(Opt.some((drafts, sent)))

proc buildDraftBlueprint(
    draftsId: Id, fromEmail, toAddress, subject, body: string
): JmapResult[EmailBlueprint] =
  let mboxIds = ?parseNonEmptyMailboxIdSet(@[draftsId]).lift
  let fromA = ?parseEmailAddress(fromEmail).lift
  let toA = ?parseEmailAddress(toAddress).lift
  # No plain-text body helper: hand-build value -> leaf -> part -> flatBody.
  let bodyPartId = ?parsePartIdFromServer("text").lift
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
  # parseEmailBlueprint accumulates onto NonEmptySeq[ValidationError]; `.lift`
  # folds the whole set onto the one rail (no joinErrs flattening).
  let bp = ?parseEmailBlueprint(
    mailboxIds = mboxIds,
    body = draftBody,
    fromAddr = Opt.some(@[fromA]),
    to = Opt.some(@[toA]),
    subject = Opt.some(subject),
  ).lift
  ok(bp)

proc buildSubmissionBlueprint(
    identityId: Id, draftCid: CreationId, fromEmail, toAddress: string
): JmapResult[EmailSubmissionBlueprint] =
  # emailId is a plain Id; the same-request forward-ref is "#<draftCid>",
  # which only the lenient parser accepts (strict parseId rejects '#').
  let emailRef = ?parseIdFromServer("#" & $draftCid).lift
  let fromMb = ?parseRFC5321Mailbox(fromEmail).lift
  let toMb = ?parseRFC5321Mailbox(toAddress).lift
  let fromSa =
    SubmissionAddress(mailbox: fromMb, parameters: Opt.none(SubmissionParams))
  let toSa = SubmissionAddress(mailbox: toMb, parameters: Opt.none(SubmissionParams))
  let rcpts = ?parseNonEmptyRcptList(@[toSa]).lift
  let env = Envelope(mailFrom: reversePath(fromSa), rcptTo: rcpts)
  let subBp = ?parseEmailSubmissionBlueprint(
    identityId = identityId, emailId = emailRef, envelope = Opt.some(env)
  ).lift
  ok(subBp)

proc sendEmail(toAddress, subject, bodyText: string): JmapResult[int] =
  let ctx = ?connect()

  let identity = ?firstIdentity(ctx)
  let (identityId, fromEmail) = identity.valueOr:
    return ok(1) # firstIdentity already explained the absence
  let roles = ?resolveRoles(ctx)
  let (draftsId, sentId) = roles.valueOr:
    return ok(1) # resolveRoles already explained the absence

  let draftCid = ?parseCreationId("draft").lift
  let subCid = ?parseCreationId("sub").lift

  let draftBp = ?buildDraftBlueprint(draftsId, fromEmail, toAddress, subject, bodyText)
  let subBp = ?buildSubmissionBlueprint(identityId, draftCid, fromEmail, toAddress)

  # onSuccessUpdateEmail is keyed by the SUBMISSION cid (not the email cid):
  # on a successful send, move the draft out of Drafts into Sent and drop $draft.
  let draftKw = ?parseKeyword("$draft").lift
  let upd = ?initEmailUpdateSet(
    @[removeFromMailbox(draftsId), addToMailbox(sentId), removeKeyword(draftKw)]
  ).lift
  let onSucc = ?parseNonEmptyOnSuccessUpdateEmail(@[(creationRef(subCid), upd)]).lift

  # One builder, two explicit invocations: Email/set (draft create) then
  # EmailSubmission/set (+ the server's implicit onSuccess Email/set update).
  var emailCreate = initTable[CreationId, EmailBlueprint]()
  emailCreate[draftCid] = draftBp
  var subCreate = initTable[CreationId, EmailSubmissionBlueprint]()
  subCreate[subCid] = subBp

  let b0 = ctx.client.newBuilder()
  let (b1, emailHandle) =
    b0.addEmailSet(ctx.mailAccount, create = Opt.some(emailCreate))
  # addEmailSubmissionAndEmailSet returns a Result wrapping an UNCOPYABLE
  # RequestBuilder, so neither `?` nor `.lift` applies here (both copy the Ok
  # payload): branch explicitly, fold the ValidationError with toJmapError, and
  # MOVE the Ok tuple out.
  var r = b1.addEmailSubmissionAndEmailSet(
    ctx.mailAccount,
    create = Opt.some(subCreate),
    onSuccessUpdateEmail = Opt.some(onSucc),
  )
  if r.isErr:
    return err(r.error.toJmapError)
  let (b2, subHandles) = move(r.value)

  # build -> send -> get, threaded on one `?`; the finaliser is freeze (sink).
  let dr = ?ctx.client.send(freeze(b2))
  let emailOutcome = ?dr.get(emailHandle)
  let subOutcome = ?dr.getBoth(subHandles) # CompoundResults{primary, implicit}

  # Each of the three method responses is a MethodOutcome — server method
  # errors are data, reported here; only dispatch faults rode the rail above.
  case emailOutcome.kind
  of mokMethodError:
    stderr.writeLine "Email/set (draft): " & emailOutcome.error.message
    return ok(1)
  of mokValue:
    for cid, res in emailOutcome.value.createResults:
      if res.isOk:
        echo "draft created ", $cid, " -> ", $res.value.id
      else:
        stderr.writeLine "draft create failed " & $cid & ": " & res.error.message

  case subOutcome.primary.kind
  of mokMethodError:
    stderr.writeLine "EmailSubmission/set: " & subOutcome.primary.error.message
    return ok(1)
  of mokValue:
    for cid, res in subOutcome.primary.value.createResults:
      if res.isOk:
        echo "submission created ", $cid, " -> ", $res.value.id
      else:
        stderr.writeLine "submission failed " & $cid & ": " & res.error.message

  case subOutcome.implicit.kind
  of mokMethodError:
    stderr.writeLine "implicit Email/set (move): " & subOutcome.implicit.error.message
    return ok(1)
  of mokValue:
    for id, res in subOutcome.implicit.value.updateResults:
      if res.isOk:
        echo "moved to Sent: ", $id
      else:
        stderr.writeLine "onSuccess move failed " & $id & ": " & res.error.message
  ok(0)

proc run*(args: seq[string]): int =
  if args.len < 3:
    stderr.writeLine "usage: jmap-cli email send <toAddress> <subject> <bodyText>"
    return 2
  sendEmail(args[0], args[1], args[2]).valueOr:
    stderr.writeLine error.message
    return 1
