# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## `jmap-cli session` — the unhidden first-run path: env -> credential
## -> endpoint -> client -> fetchSession -> capability check -> account,
## and one proving Mailbox/get round-trip. Written verbosely on purpose
## to document the first-fifteen-minutes experience (P29); this command
## deliberately does NOT use the cli_session helper. Friction here goes
## straight to AUDIT.md.

import std/os
import jmap_client

proc run*(args: seq[string]): int =
  # 1. Read connection params (no config-file loader exists in the API).
  let sessionUrl = getEnv("JMAP_TEST_STALWART_SESSION_URL")
  let user = getEnv("JMAP_TEST_STALWART_ALICE_USER")
  let pass = getEnv("JMAP_TEST_STALWART_ALICE_PASSWORD")
  if sessionUrl.len == 0 or user.len == 0 or pass.len == 0:
    # Exit convention: 2 = bad CLI usage (args), 1 = runtime/setup failure.
    # Missing env is a setup failure — matches the connect()-based commands.
    stderr.writeLine "missing env; source /tmp/stalwart-env.sh first"
    return 1

  # 2. Smart constructors (each fallible, each on the ValidationError rail).
  let endpoint = directEndpoint(sessionUrl).valueOr:
    stderr.writeLine "bad endpoint: " & error.message
    return 1
  let credential = basicCredential(user, pass).valueOr:
    stderr.writeLine "bad credential: " & error.message
    return 1

  # 3. Construct the client (2-arg overload supplies the default HTTP
  #    transport via newHttpTransport; the 3-arg form takes a custom one).
  let client = initJmapClient(endpoint, credential).valueOr:
    stderr.writeLine "client init failed: " & error.message
    return 1

  # 4. Fetch the session (the first network call; ClientError on the rail).
  let session = client.fetchSession().valueOr:
    stderr.writeLine "fetchSession failed: " & error.message
    return 1

  echo "connected as: ", session.username
  echo "api url:      ", session.apiUrl

  # 5. Capability pre-flight + primary mail account. primaryAccount returns
  #    Opt[AccountId]; the consumer must know the ckMail capability value.
  let mailAccount = session.primaryAccount(ckMail).valueOr:
    stderr.writeLine "server does not advertise JMAP Mail"
    return 1
  echo "mail account: ", $mailAccount

  # 6. Surface a few core limits (typed UnsignedInt accessors; toInt64 only).
  let core = session.coreCapabilities()
  echo "maxCallsInRequest: ", $core.maxCallsInRequest().toInt64
  echo "maxObjectsInGet:   ", $core.maxObjectsInGet().toInt64

  # 7. Prove the full request lifecycle once: newBuilder -> add*Get (returns a
  #    (RequestBuilder, ResponseHandle) tuple) -> freeze (sink) -> send -> get.
  let b = client.newBuilder()
  let (b2, mailboxesHandle) = b.addMailboxGet(mailAccount)
  let dr = client.send(b2.freeze()).valueOr:
    stderr.writeLine "send failed: " & error.message
    return 1
  let mailboxes = dr.get(mailboxesHandle).valueOr:
    stderr.writeLine "Mailbox/get failed: " & error.message
    return 1
  echo "mailboxes visible: ", $mailboxes.list.len
  return 0
