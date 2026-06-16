# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email query [--unread]` — query the Inbox (optionally unread
## only), newest-first, then back-reference the matching ids into a partial
## Email/get for id/sender/subject/preview. The Inbox is resolved by the
## getMailboxes one-shot and matching `mb.isInbox` (the role predicate).
##
## The default path keeps the hand-wired Email/query -> #ids -> partial
## Email/get back-reference on purpose: it documents the typed server-side
## back-reference and the PartialEmail FieldEcho read, neither of which a
## one-shot exposes. `--one-shot` selects the `queryEmails` one-shot instead —
## Email/query -> full-record Email/get folded into one call, read as
## `.query.ids` / `.get.list`.

import jmap_client
import ./cli_session

proc resolveInbox(ctx: CliContext): JmapResult[Opt[Id]] =
  ## getMailboxes scanned for the Inbox role. The one-shot collapses the
  ## Mailbox/get outcome onto the rail (a method error rides through `?`); an
  ## absent Inbox surfaces as `none`, which the caller treats as a soft failure.
  let resp = ?ctx.client.getMailboxes(ctx.mailAccount)
  for mb in resp.list:
    if mb.isInbox: # role predicate — replaces the role.kind == mrInbox idiom
      return ok(Opt.some(mb.id))
  ok(Opt.none(Id))

proc viaOneShot(ctx: CliContext, unreadOnly: bool): JmapResult[int] =
  ## Contrast with the hand-wired back-reference below: the queryEmails one-shot
  ## builds Email/query -> Email/get (FULL Email, not PartialEmail) in ONE call,
  ## collapsing both method outcomes onto the rail, and returns a QueryThenGet
  ## read as `.query.ids` / `.get.list`. `--unread` is honoured here too
  ## (account-wide, since this path does not resolve the Inbox).
  let filter =
    if unreadOnly:
      Opt.some(filterCondition(EmailFilterCondition(notKeyword: Opt.some(kwSeen))))
    else:
      Opt.none(Filter[EmailFilterCondition])
  let qp = limit(parseUnsignedInt(10).get()) # limit window, no field name / Opt wrap
  let res = ?ctx.client.queryEmails(ctx.mailAccount, filter = filter, queryParams = qp)
  echo "query matched ", $res.query.ids.len, ", got ", $res.get.list.len, " emails"
  for e in res.get.list: # full Email — subject is Opt[string]
    echo e.subject.valueOr("(no subject)")
  ok(0)

proc queryInbox(ctx: CliContext, unreadOnly: bool): JmapResult[int] =
  let inbox = ?resolveInbox(ctx)
  let inboxId = inbox.valueOr:
    stderr.writeLine "no Inbox mailbox resolvable"
    return ok(1)

  # Filter: in Inbox, optionally lacking $seen. Every field is Opt-wrapped.
  var cond = EmailFilterCondition(inMailbox: Opt.some(inboxId))
  if unreadOnly:
    cond.notKeyword = Opt.some(kwSeen) # kwSeen: hub-reachable Keyword const
  let filter = filterCondition(cond)
  let sort = @[plainComparator(pspReceivedAt, sdDescending)]
  let qp = limit(parseUnsignedInt(20).get()) # limit window, no field name / Opt wrap

  let (b1, queryH) = ctx.client.newBuilder().addEmailQuery(
      ctx.mailAccount,
      filter = Opt.some(filter),
      sort = Opt.some(sort),
      queryParams = qp,
    )
  # Back-reference Email/query "#ids" into Email/get "ids" (one round-trip).
  let idsRef = reference[seq[Id]](queryH, mnEmailQuery, rpIds)
  let props = parseNonEmptySeq(
      @[egpId, egpThreadId, egpFrom, egpSubject, egpReceivedAt, egpPreview]
    )
    .get()
  let (b2, getH) =
    b1.addPartialEmailGet(ctx.mailAccount, ids = Opt.some(idsRef), properties = props)

  let dr = ?ctx.client.send(b2.freeze())
  let qOutcome = ?dr.get(queryH)
  case qOutcome.kind
  of mokMethodError:
    stderr.writeLine "Email/query: " & qOutcome.error.message
    ok(1)
  of mokValue:
    stderr.writeLine "matched " & $qOutcome.value.ids.len & " ids"
    let gOutcome = ?dr.get(getH)
    case gOutcome.kind
    of mokMethodError:
      stderr.writeLine "Email/get: " & gOutcome.error.message
      ok(1)
    of mokValue:
      for pe in gOutcome.value.list: # pe is PartialEmail
        let idStr =
          if pe.id.isSome:
            $pe.id.get()
          else:
            "(no id)" # Opt[Id]
        let tid =
          if pe.threadId.isSome:
            $pe.threadId.get()
          else:
            "-" # Opt[Id]
        # FieldEcho fields read through the hub `valueOr` — the same call
        # shape as the plain-Opt fields below (`preview`), so the consumer no
        # longer hand-rolls a three-state matcher.
        let subject = pe.subject.valueOr("(no subject)") # FieldEcho[string]
        let fromAddrs = pe.fromAddr.valueOr(@[]) # FieldEcho[seq[EmailAddress]]
        let sender =
          if fromAddrs.len > 0:
            fromAddrs[0].name.valueOr(fromAddrs[0].email)
          else:
            "(no sender)"
        let preview = pe.preview.valueOr("") # Opt[string]
        echo idStr, "  thread=", tid, "  ", sender, "  ", subject, "  ", preview
      ok(0)

proc queryImpl(args: seq[string]): JmapResult[int] =
  let unreadOnly = "--unread" in args
  let ctx = ?connect()
  if "--one-shot" in args:
    viaOneShot(ctx, unreadOnly)
  else:
    queryInbox(ctx, unreadOnly)

proc run*(args: seq[string]): int =
  queryImpl(args).valueOr:
    stderr.writeLine error.message
    return 1
