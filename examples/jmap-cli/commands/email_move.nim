# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli email move <emailId> <mailboxId>` — replace an email's mailbox
## membership (full replace) via Email/set. The "repetition is the finding"
## note this command carried is RESOLVED: `moveEmails` is the sibling of
## `email flag`'s `markEmailsRead`, so both commands are now the same
## one-liner over a folded write and the shared triple-sealing chain has no
## call site left to repeat.

import jmap_client
# No `from std/tables import pairs` here, unlike email_flag — and that asymmetry
# is itself the finding. The projection iterators resolve their Table `pairs` at
# the instantiation site, but Nim caches an instantiation per type argument, so
# email_flag's identical `SetResponse[EmailCreatedItem, PartialEmail]` walk
# already bound it. Compiled alone this module needs the import back; compiled
# after its sibling it must not have it (UnusedImport is an error here).
import ./cli_session

proc moveEmail(emailIdArg, mailboxIdArg: string): JmapResult[int] =
  let emailId = ?parseIdFromServer(emailIdArg).lift
  let mailboxId = ?parseIdFromServer(mailboxIdArg).lift
  let ctx = ?connect()

  # Full mailbox-membership replace: "move" means the email is in the
  # destination and nowhere else (the builder path's addToMailbox is the
  # additive verb).
  let resp = ?ctx.client.moveEmails(ctx.mailAccount, @[emailId], mailboxId)

  for id, serverEcho in resp.updated:
    echo "moved ", $id
  for id, error in resp.updateFailures:
    stderr.writeLine "move failed for " & $id & ": " & error.message
  ok(0)

proc run*(args: seq[string]): int =
  if args.len < 2:
    stderr.writeLine "usage: jmap-cli email move <emailId> <mailboxId>"
    return 2
  moveEmail(args[0], args[1]).valueOr:
    stderr.writeLine error.message
    return 1
