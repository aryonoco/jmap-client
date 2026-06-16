# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli session` — the unhidden first-run path: env -> credential
## -> endpoint -> client -> fetchSession -> capability preflight -> account,
## and one proving Mailbox/get round-trip. Written verbosely on purpose
## to document the first-fifteen-minutes experience (P29); this command
## deliberately does NOT use the cli_session helper. Friction here goes
## straight to AUDIT.md.
##
## With the unified rail the whole probe threads one ``JmapError`` on a single
## ``?``: the two smart constructors take one ``.lift`` each; ``initJmapClient``,
## ``fetchSession``, ``requireMail`` and ``send`` thread bare.

import std/os
import jmap_client

proc connectAndProbe(sessionUrl, user, pass: string): JmapResult[int] =
  # 2. Smart constructors (each on the ValidationError rail) — one `.lift` each
  #    folds the construction failure onto the one JmapError rail.
  let endpoint = ?directEndpoint(sessionUrl).lift
  let credential = ?basicCredential(user, pass).lift

  # 3. Construct the client (2-arg overload supplies the default HTTP
  #    transport via newHttpTransport; the 3-arg form takes a custom one).
  #    This already returns JmapError, so it threads with a bare `?`.
  let client = ?initJmapClient(endpoint, credential)

  # 4. Fetch the session (the first network call; JmapError on the rail).
  let session = ?client.fetchSession()

  echo "connected as: ", session.username
  echo "api url:      ", session.apiUrl

  # 5. Capability pre-flight + mail account in one rail step: requireMail (the
  #    S3 sugar) resolves the JMAP Mail account, primary-preferred with a
  #    per-account fallback (RFC 8620 §2), or fails with a jeSession fault — no
  #    ckMail enum to discover, no hand-rolled Opt unwrap, no fabricated string.
  let mailAccount = ?session.requireMail()
  echo "mail account: ", $mailAccount

  # 6. Surface a few core limits. ``core`` is a direct public field of the
  #    Session, and each limit a direct ``UnsignedInt`` field (toInt64 to read).
  let core = session.core
  echo "maxCallsInRequest: ", $core.maxCallsInRequest.toInt64
  echo "maxObjectsInGet:   ", $core.maxObjectsInGet.toInt64

  # 7. Prove the full request lifecycle once: newBuilder -> add*Get (returns a
  #    (RequestBuilder, ResponseHandle) tuple) -> freeze (sink) -> send -> get.
  #    A server method error is data on the ok branch; only a dispatch fault
  #    rides the rail through `?`.
  let b = client.newBuilder()
  let (b2, mailboxesHandle) = b.addMailboxGet(mailAccount)
  let dr = ?client.send(b2.freeze())
  let outcome = ?dr.get(mailboxesHandle)
  case outcome.kind
  of mokMethodError:
    stderr.writeLine "Mailbox/get: " & outcome.error.message
    ok(1)
  of mokValue:
    echo "mailboxes visible: ", $outcome.value.list.len
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
