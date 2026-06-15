# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email query [--unread]` — query the Inbox (optionally unread
## only), newest-first, then back-reference the matching ids into a partial
## Email/get for id/sender/subject/preview. The Inbox is resolved by
## fetching mailboxes and matching `role.kind == mrInbox`.
##
## (`--via-convenience` selects the opt-in combinator path; this module also
## owns the hand-wired Email/query -> #ids -> Email/get back-reference.)

import jmap_client
import jmap_client/convenience # opt-in; NOT re-exported by `import jmap_client`
import ./cli_session

proc resolveInbox(ctx: CliContext): JmapResult[Opt[Id]] =
  ## Mailbox/get scanned for the Inbox role. A dispatch fault rides the rail; a
  ## method error is reported here and surfaces as `none` (no Inbox resolvable),
  ## which the caller treats as a soft failure.
  let (b, h) = ctx.client.newBuilder().addMailboxGet(ctx.mailAccount)
  let dr = ?ctx.client.send(b.freeze())
  let outcome = ?dr.get(h)
  case outcome.kind
  of mokMethodError:
    stderr.writeLine "Mailbox/get: " & outcome.error.message
    ok(Opt.none(Id))
  of mokValue:
    for mb in outcome.value.list:
      for role in mb.role: # Opt[MailboxRole] unwrap
        if role.kind == mrInbox:
          return ok(Opt.some(mb.id))
    ok(Opt.none(Id))

proc viaConvenience(ctx: CliContext, unreadOnly: bool): JmapResult[int] =
  ## Contrast with the hand-wired back-reference below: the opt-in convenience
  ## combinator builds Email/query -> Email/get (FULL Email, not PartialEmail)
  ## in ONE call and ONE getBoth. `--unread` is honoured here too (account-wide,
  ## since this path does not resolve the Inbox).
  let filter =
    if unreadOnly:
      Opt.some(filterCondition(EmailFilterCondition(notKeyword: Opt.some(kwSeen))))
    else:
      Opt.none(Filter[EmailFilterCondition])
  let qp = QueryParams(limit: Opt.some(parseUnsignedInt(10).get()))
  let (b, handles) = ctx.client.newBuilder().addEmailQueryThenGet(
      ctx.mailAccount, filter = filter, queryParams = qp
    )
  let dr = ?ctx.client.send(b.freeze())
  let both = ?dr.getBoth(handles) # QueryGetResults{query, get}, each a MethodOutcome
  case both.query.kind
  of mokMethodError:
    stderr.writeLine "Email/query: " & both.query.error.message
    ok(1)
  of mokValue:
    case both.get.kind
    of mokMethodError:
      stderr.writeLine "Email/get: " & both.get.error.message
      ok(1)
    of mokValue:
      echo "query matched ",
        $both.query.value.ids.len, ", got ", $both.get.value.list.len, " emails"
      for e in both.get.value.list: # full Email — subject is Opt[string]
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
  let qp = QueryParams(limit: Opt.some(parseUnsignedInt(20).get()))

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
  if "--via-convenience" in args:
    viaConvenience(ctx, unreadOnly)
  else:
    queryInbox(ctx, unreadOnly)

proc run*(args: seq[string]): int =
  queryImpl(args).valueOr:
    stderr.writeLine error.message
    return 1
