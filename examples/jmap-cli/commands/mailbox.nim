# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli mailbox list` — fetch all mailboxes (Mailbox/get with no id
## filter) and print id, role, unread/total counts, a hand-rolled rights
## summary (MailboxRights has no roll-up helper yet — tracker C4), and name.

import jmap_client
import ./cli_session

func rightsSummary(r: MailboxRights): string =
  ## The library exposes no roll-up over the nine RFC 8621 ACL flags (C4),
  ## so the CLI derives a compact "rwas" descriptor from the bool fields.
  let read = if r.mayReadItems: "r" else: "-"
  let write =
    if r.mayAddItems and r.mayRemoveItems and r.maySetSeen and r.maySetKeywords:
      "w"
    else:
      "-"
  let admin = if r.mayCreateChild and r.mayRename and r.mayDelete: "a" else: "-"
  let submit = if r.maySubmit: "s" else: "-"
  read & write & admin & submit

func roleLabel(role: Opt[MailboxRole]): string =
  ## Opt[MailboxRole] read: present roles render via their wire identifier;
  ## absent -> "-".
  for r in role: # `for v in opt` is the idiomatic Opt unwrap
    return r.identifier
  "-"

proc listMailboxes(): JmapResult[int] =
  let ctx = ?connect()
  # The getMailboxes one-shot folds newBuilder -> addMailboxGet -> freeze ->
  # send -> get and collapses the single Mailbox/get outcome onto the rail, so a
  # method error arrives through `?` (reported by run*) and the body just reads
  # the full GetResponse's `.list`.
  let resp = ?ctx.client.getMailboxes(ctx.mailAccount)
  for mb in resp.list:
    echo $mb.id,
      "  ",
      roleLabel(mb.role),
      "  unread=",
      $mb.unreadEmails,
      " total=",
      $mb.totalEmails,
      "  rights=",
      rightsSummary(mb.myRights),
      "  ",
      mb.name
  ok(0)

proc run*(args: seq[string]): int =
  listMailboxes().valueOr:
    stderr.writeLine error.message
    return 1
