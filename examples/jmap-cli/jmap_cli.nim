# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## jmap-cli — a deliberately thin sample consumer of the jmap_client
## public API. Each subcommand lives in commands/ and exercises one
## RFC 8621 entity area. The CLI is an instrument for the P29 audit,
## not a polished product: argument handling is minimal on purpose.

import std/os

import commands/session as sessionCmd
import commands/mailbox as mailboxCmd
import commands/email_query as emailQueryCmd
import commands/email_read as emailReadCmd
import commands/email_flag as emailFlagCmd
import commands/email_move as emailMoveCmd
import commands/email_send as emailSendCmd
import commands/email_sync as emailSyncCmd
import commands/thread as threadCmd
import commands/identity as identityCmd
import commands/vacation as vacationCmd
import commands/search as searchCmd

proc usage() =
  stderr.writeLine """jmap-cli — sample JMAP consumer (P29 bench)
usage:
  jmap-cli session
  jmap-cli mailbox list
  jmap-cli email query [--unread] [--via-convenience]
  jmap-cli email read <emailId>
  jmap-cli email flag <emailId>
  jmap-cli email move <emailId> <mailboxId>
  jmap-cli email send <toAddress> <subject> <bodyText>
  jmap-cli email sync [<sinceState>]
  jmap-cli thread show <threadId>
  jmap-cli identity list
  jmap-cli vacation get
  jmap-cli vacation set <bodyText>
  jmap-cli search <text>

Connection is read from env (source /tmp/stalwart-env.sh first):
  JMAP_TEST_STALWART_SESSION_URL, _ALICE_USER, _ALICE_PASSWORD"""

when isMainModule:
  let args = commandLineParams()
  if args.len == 0:
    usage()
    quit(2)
  # Dispatch returns an int exit code; commands print their own errors.
  let code =
    case args[0]
    of "session":
      sessionCmd.run(args[1 .. ^1])
    of "mailbox":
      mailboxCmd.run(args[1 .. ^1])
    of "email":
      if args.len >= 2 and args[1] == "query":
        emailQueryCmd.run(args[2 .. ^1])
      elif args.len >= 2 and args[1] == "read":
        emailReadCmd.run(args[2 .. ^1])
      elif args.len >= 2 and args[1] == "flag":
        emailFlagCmd.run(args[2 .. ^1])
      elif args.len >= 2 and args[1] == "move":
        emailMoveCmd.run(args[2 .. ^1])
      elif args.len >= 2 and args[1] == "send":
        emailSendCmd.run(args[2 .. ^1])
      elif args.len >= 2 and args[1] == "sync":
        emailSyncCmd.run(args[2 .. ^1])
      else:
        (usage(); 2)
    of "thread":
      threadCmd.run(args[1 .. ^1])
    of "identity":
      identityCmd.run(args[1 .. ^1])
    of "vacation":
      vacationCmd.run(args[1 .. ^1])
    of "search":
      searchCmd.run(args[1 .. ^1])
    else:
      (usage(); 2)
  quit(code)
