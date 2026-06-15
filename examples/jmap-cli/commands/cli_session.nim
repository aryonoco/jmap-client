# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared connect+session+account boilerplate for commands 5+. Its very
## existence is an AUDIT finding: every command needs this preamble, which is
## the C5/C8 "capability/connect wrapper trigger" made concrete. session.nim
## deliberately does NOT use it (it documents the raw path).
##
## The whole preamble now threads the library's one error rail on a single
## ``?``. The two construction calls (``directEndpoint`` / ``basicCredential``,
## each on the ``ValidationError`` rail) compose with one explicit ``.lift``;
## the pipeline calls (``initJmapClient`` / ``fetchSession`` /
## ``requirePrimaryAccount``) already return ``JmapError`` and thread bare. The
## former string rail — and the finding that a consumer could not return
## library-typed errors from its own helpers — is gone: ``connect`` returns
## ``JmapResult[CliContext]`` directly.
##
## Connection vars are read straight from the environment. An empty/unset var
## is rejected by ``directEndpoint`` / ``basicCredential`` as a ``jeValidation``
## failure on the rail — the consumer needs no presence check of its own
## (parse, don't validate). The friendly "source the env file first" hint lives
## in the ``session`` onboarding command.

import std/os
import jmap_client

type CliContext* = object
  client*: JmapClient
  mailAccount*: AccountId

proc connect*(): JmapResult[CliContext] =
  ## env -> endpoint -> credential -> client -> session -> primary mail account,
  ## end to end on the one rail. The capability/account preflight is
  ## ``requirePrimaryAccount`` (a ``jeSession`` fault when JMAP Mail or its
  ## primary account is absent) — no hand-rolled ``Opt`` unwrap, no fabricated
  ## string.
  let sessionUrl = getEnv("JMAP_TEST_STALWART_SESSION_URL")
  let user = getEnv("JMAP_TEST_STALWART_ALICE_USER")
  let pass = getEnv("JMAP_TEST_STALWART_ALICE_PASSWORD")
  let endpoint = ?directEndpoint(sessionUrl).lift
  let credential = ?basicCredential(user, pass).lift
  let client = ?initJmapClient(endpoint, credential)
  let session = ?client.fetchSession()
  let mailAccount = ?session.requirePrimaryAccount(ckMail)
  ok(CliContext(client: client, mailAccount: mailAccount))
