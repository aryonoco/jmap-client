# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email query [--unread]` — query the Inbox (optionally unread
## only), newest-first, then back-reference the matching ids into a partial
## Email/get for id/sender/subject/preview. The Inbox is resolved by
## fetching mailboxes and matching `role.kind == mrInbox`.
##
## (`--via-convenience` is added in the convenience-layer task; this module
## owns the hand-wired Email/query -> #ids -> Email/get back-reference.)

import jmap_client
import jmap_client/convenience # opt-in; NOT re-exported by `import jmap_client`
import ./cli_session

func fieldEchoOr[T](fe: FieldEcho[T], fallback: T): T =
  ## PartialEmail header-derived fields (subject, fromAddr, ...) are
  ## three-state FieldEcho with NO hub read accessor — only the
  ## fieldAbsent/fieldNull/fieldValue constructors and the public `value*`
  ## field on the fekValue arm — so every consumer hand-writes this.
  case fe.kind
  of fekValue: fe.value
  of fekAbsent, fekNull: fallback

proc resolveInbox(ctx: CliContext): Result[Id, string] =
  let (b, h) = ctx.client.newBuilder().addMailboxGet(ctx.mailAccount)
  let dr = ctx.client.send(b.freeze()).valueOr:
    return err("send failed: " & error.message)
  let resp = dr.get(h).valueOr:
    return err("Mailbox/get failed: " & error.message)
  for mb in resp.list:
    for role in mb.role: # Opt[MailboxRole] unwrap
      if role.kind == mrInbox:
        return ok(mb.id)
  err("no Inbox mailbox found")

proc viaConvenience(ctx: CliContext, unreadOnly: bool): int =
  ## Contrast with the hand-wired back-reference below: the opt-in convenience
  ## combinator builds Email/query -> Email/get (FULL Email, not PartialEmail)
  ## in ONE call and ONE getBoth. It requires the explicit
  ## `import jmap_client/convenience` — the headline `import jmap_client`
  ## deliberately does not re-export it. `--unread` is honoured here too
  ## (account-wide, since this path does not resolve the Inbox).
  let filter =
    if unreadOnly:
      Opt.some(filterCondition(EmailFilterCondition(notKeyword: Opt.some(kwSeen))))
    else:
      Opt.none(Filter[EmailFilterCondition])
  let qp = QueryParams(limit: Opt.some(parseUnsignedInt(10).get()))
  let (b, handles) = ctx.client.newBuilder().addEmailQueryThenGet(
    ctx.mailAccount, filter = filter, queryParams = qp
  )
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let both = dr.getBoth(handles).valueOr: # QueryGetResults{query, get}
    stderr.writeLine "getBoth failed: " & error.message
    return 1
  echo "query matched ", $both.query.ids.len, ", got ", $both.get.list.len, " emails"
  for e in both.get.list: # full Email (not PartialEmail) — subject is Opt[string]
    echo e.subject.valueOr("(no subject)")
  return 0

proc run*(args: seq[string]): int =
  let unreadOnly = "--unread" in args
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1
  if "--via-convenience" in args:
    return viaConvenience(ctx, unreadOnly)
  let inboxId = resolveInbox(ctx).valueOr:
    stderr.writeLine error
    return 1

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
  ).get()
  let (b2, getH) =
    b1.addPartialEmailGet(ctx.mailAccount, ids = Opt.some(idsRef), properties = props)

  let dr = ctx.client.send(b2.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let qr = dr.get(queryH).valueOr:
    stderr.writeLine "Email/query failed: " & error.message
    return 1
  stderr.writeLine "matched " & $qr.ids.len & " ids"
  let gr = dr.get(getH).valueOr:
    stderr.writeLine "Email/get failed: " & error.message
    return 1
  for pe in gr.list: # pe is PartialEmail
    let idStr = if pe.id.isSome: $pe.id.get() else: "(no id)" # Opt[Id]
    let tid = if pe.threadId.isSome: $pe.threadId.get() else: "-" # Opt[Id]
    let subject = fieldEchoOr(pe.subject, "(no subject)") # FieldEcho[string]
    let fromAddrs = fieldEchoOr(pe.fromAddr, @[]) # FieldEcho[seq[EmailAddress]]
    let sender =
      if fromAddrs.len > 0: fromAddrs[0].name.valueOr(fromAddrs[0].email)
      else: "(no sender)"
    let preview = pe.preview.valueOr("") # Opt[string]
    echo idStr, "  thread=", tid, "  ", sender, "  ", subject, "  ", preview
  return 0
