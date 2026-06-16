# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared connect+session+account helper for the entity commands. The
## ``connect`` one-shot now does the heavy lifting: this helper survives only
## to bind the resolved mail account alongside the client, so every command
## opens with a single ``?connect()`` instead of repeating the session +
## ``requireMail`` step. session.nim deliberately does NOT use it (it documents
## the onboarding path inline).
##
## The whole helper threads the library's one error rail on a single ``?``. The
## ``connect(url, user, pass)`` one-shot folds the endpoint + credential
## constructors and ``initJmapClient`` onto the rail internally (the RFC 8620 §2
## session stays lazy); ``fetchSession`` / ``requireMail`` already return
## ``JmapError`` and thread bare. The former string rail — and the finding that
## a consumer could not return library-typed errors from its own helpers — is
## gone: this helper returns ``JmapResult[CliContext]`` directly.
##
## Connection vars are read straight from the environment. An empty/unset var
## is rejected inside ``connect`` as a ``jeValidation`` failure on the rail —
## the consumer needs no presence check of its own (parse, don't validate). The
## friendly "source the env file first" hint lives in the ``session`` command.

import std/os
import jmap_client

type CliContext* = object
  client*: JmapClient
  mailAccount*: AccountId

proc connect*(): JmapResult[CliContext] =
  ## env -> client -> session -> mail account, end to end on the one rail. The
  ## library's ``connect`` one-shot (resolved here by its three-string arity)
  ## folds endpoint + credential + ``initJmapClient``; the capability/account
  ## preflight is the ``requireMail`` sugar — a bare-``AccountId`` resolve (a
  ## ``jeSession`` fault when no account advertises JMAP Mail), primary-preferred
  ## with a per-account fallback (RFC 8620 §2), so neither the ``ckMail`` enum
  ## nor a hand-rolled ``Opt`` unwrap surfaces here.
  let sessionUrl = getEnv("JMAP_TEST_STALWART_SESSION_URL")
  let user = getEnv("JMAP_TEST_STALWART_ALICE_USER")
  let pass = getEnv("JMAP_TEST_STALWART_ALICE_PASSWORD")
  let client = ?connect(sessionUrl, user, pass)
  let session = ?client.fetchSession()
  let mailAccount = ?session.requireMail()
  ok(CliContext(client: client, mailAccount: mailAccount))
