# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli session` — the first-run path: env -> connect -> fetchSession
## -> capability preflight -> account, and one proving Mailbox/get round-trip.
## Written to document the first-fifteen-minutes experience; this command
## deliberately does NOT use the cli_session helper, so the onboarding steps are
## visible inline. Friction here goes straight to AUDIT.md.
##
## With the one-shots the on-ramp is short: ``connect`` folds the endpoint +
## credential constructors and ``initJmapClient``; ``getMailboxes`` folds the
## whole build -> send -> get lifecycle (and collapses the single method's
## outcome onto the rail). The whole probe threads one ``JmapError`` on a single
## ``?`` — ``connect``, ``fetchSession``, ``requireMail`` and ``getMailboxes``
## all thread bare.

import std/os
import jmap_client

proc connectAndProbe(sessionUrl, user, pass: string): JmapResult[int] =
  # 2. The connect one-shot folds endpoint + credential + initJmapClient onto
  #    the one rail (the 2-arg client form, with the default HTTP transport, is
  #    what the default-transport connect uses internally; the 4-arg connect
  #    takes a custom Transport). The RFC 8620 §2 session stays lazy.
  let client = ?connect(sessionUrl, user, pass)

  # 3. Fetch the session (the first network call; JmapError on the rail).
  let session = ?client.fetchSession()

  echo "connected as: ", session.username
  echo "api url:      ", session.apiUrl

  # 4. Capability pre-flight + mail account in one rail step: requireMail
  #    resolves the JMAP Mail account, primary-preferred with a per-account
  #    fallback (RFC 8620 §2), or fails with a jeSession fault — no ckMail enum
  #    to discover, no hand-rolled Opt unwrap, no fabricated string.
  let mailAccount = ?session.requireMail()
  echo "mail account: ", $mailAccount

  # 5. Surface a few core limits. ``core`` is a direct public field of the
  #    Session, and each limit a direct ``UnsignedInt`` field (toInt64 to read).
  let core = session.core
  echo "maxCallsInRequest: ", $core.maxCallsInRequest.toInt64
  echo "maxObjectsInGet:   ", $core.maxObjectsInGet.toInt64

  # 6. Prove the session with one bare-get one-shot: getMailboxes folds the
  #    build -> send -> get lifecycle and collapses the single Mailbox/get
  #    outcome onto the rail, so a method error arrives through `?` (reported by
  #    run*); the full GetResponse keeps `state`/`notFound` if needed.
  let mailboxes = ?client.getMailboxes(mailAccount)
  echo "mailboxes visible: ", $mailboxes.list.len
  ok(0)

proc run*(args: seq[string]): int =
  # 1. Read connection params (no config-file loader exists in the API).
  let sessionUrl = getEnv("JMAP_TEST_STALWART_SESSION_URL")
  let user = getEnv("JMAP_TEST_STALWART_ALICE_USER")
  let pass = getEnv("JMAP_TEST_STALWART_ALICE_PASSWORD")
  if sessionUrl.len == 0 or user.len == 0 or pass.len == 0:
    # Exit convention: 2 = bad CLI usage (args), 1 = runtime/setup failure.
    # Missing env is a setup precondition handled before the rail, so the
    # onboarding command can offer the source-the-env-file hint.
    stderr.writeLine "missing env; source /tmp/stalwart-env.sh first"
    return 1
  connectAndProbe(sessionUrl, user, pass).valueOr:
    stderr.writeLine error.message
    return 1
