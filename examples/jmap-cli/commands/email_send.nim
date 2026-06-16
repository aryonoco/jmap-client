# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email send <toAddress> <subject> <bodyText>` — create a draft
## Email and submit it in ONE request, moving it to Sent on success. The
## `sendPlainText` one-shot now does the whole compound — it builds the draft
## body, files it in Drafts with `$draft`, submits it from the identity, and
## wires the onSuccess Drafts -> Sent move (RFC 8621 §7.5.1) — so the command
## only resolves the three ids it needs and reads back the `SentEmail`.
##
## The CLI still resolves those ids the way an app developer would: the From
## identity via `getIdentities`, and the Drafts/Sent mailbox ids via
## `getMailboxes` + `hasRole(mrDrafts)` / `hasRole(mrSent)`. The four-layer
## body build, the submission blueprint, the `creationRef` forward-reference,
## the onSuccess update set and the two-table /set wiring all live inside the
## one-shot now — the highest-friction public path collapses to one call.
##
## Error handling stays on the one ``JmapError`` rail: the id-resolving gets and
## `sendPlainText` all thread with a bare ``?``; a server method error on the
## send compound collapses onto the rail inside the one-shot and arrives through
## ``?`` (reported by run*). The former hand-built blueprint chain and its
## ``std/tables`` wiring are gone.

import jmap_client
import ./cli_session

proc resolveIdentity(ctx: CliContext): JmapResult[Opt[(Id, string)]] =
  ## getIdentities; the first identity (its id + address) is the From for
  ## sending. ``none`` means no usable identity — a domain condition, never a
  ## rail error (a method fault would already ride the rail through the one-shot).
  let resp = ?ctx.client.getIdentities(ctx.mailAccount)
  if resp.list.len == 0:
    stderr.writeLine "no identity to send from"
    ok(Opt.none((Id, string)))
  else:
    ok(Opt.some((resp.list[0].id, resp.list[0].email)))

proc resolveRoles(ctx: CliContext): JmapResult[Opt[(Id, Id)]] =
  ## One getMailboxes, scanned for BOTH the Drafts and Sent roles — sending
  ## needs both, and a single fetch returns the whole list. ``none`` means a
  ## required role was missing — a domain condition.
  let resp = ?ctx.client.getMailboxes(ctx.mailAccount)
  var draftsId = Opt.none(Id)
  var sentId = Opt.none(Id)
  for mb in resp.list:
    # The hasRole predicate replaces the role.kind == mr* unwrap per mailbox.
    if mb.hasRole(mrDrafts):
      draftsId = Opt.some(mb.id)
    elif mb.hasRole(mrSent):
      sentId = Opt.some(mb.id)
  let drafts = draftsId.valueOr:
    stderr.writeLine "Drafts mailbox not found"
    return ok(Opt.none((Id, Id)))
  let sent = sentId.valueOr:
    stderr.writeLine "Sent mailbox not found"
    return ok(Opt.none((Id, Id)))
  ok(Opt.some((drafts, sent)))

proc sendEmail(toAddress, subject, bodyText: string): JmapResult[int] =
  let ctx = ?connect()

  let identity = ?resolveIdentity(ctx)
  let (identityId, fromEmail) = identity.valueOr:
    return ok(1) # resolveIdentity already explained the absence
  let roles = ?resolveRoles(ctx)
  let (draftsId, sentId) = roles.valueOr:
    return ok(1) # resolveRoles already explained the absence

  # The whole §7.5.1 send — draft create, submission, onSuccess Drafts -> Sent
  # move — is one call. Addresses are taken as strings and parsed internally
  # onto the rail; `to`/`cc`/`bcc` are seqs (cc/bcc default empty).
  let sent = ?ctx.client.sendPlainText(
    ctx.mailAccount,
    identityId,
    SendMailboxes(drafts: draftsId, sent: sentId),
    PlainTextMessage(
      fromAddr: fromEmail, to: @[toAddress], subject: subject, body: bodyText
    ),
  )
  echo "sent ", $sent.emailId, "  (submission ", $sent.submissionId, ")"
  ok(0)

proc run*(args: seq[string]): int =
  if args.len < 3:
    stderr.writeLine "usage: jmap-cli email send <toAddress> <subject> <bodyText>"
    return 2
  sendEmail(args[0], args[1], args[2]).valueOr:
    stderr.writeLine error.message
    return 1
