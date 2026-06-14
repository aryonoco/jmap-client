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

proc run*(args: seq[string]): int =
  let ctx = connect().valueOr:
    stderr.writeLine error
    return 1
  let (b, handle) = ctx.client.newBuilder().addMailboxGet(ctx.mailAccount)
  let dr = ctx.client.send(b.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let resp = dr.get(handle).valueOr:
    stderr.writeLine "Mailbox/get failed: " & error.message
    return 1
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
  return 0
