# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Shared connect+session+account boilerplate for commands 5+. Its very
## existence is an AUDIT finding: every command needs this 4-call
## preamble, which is the C5/C8 "capability/connect wrapper trigger"
## made concrete. session.nim deliberately does NOT use it (it documents
## the raw path).
##
## The error rail here is a CLI-local `string`, not `JmapResult`/
## `ClientError`: the hub exposes NO public ClientError constructor (only
## `transportError` -> TransportError, with no lift into ClientError), so
## a consumer cannot return library-typed errors from its own helpers and
## must stringify via `.message`. That constraint is itself a finding.

import std/os
import jmap_client

type CliContext* = object
  client*: JmapClient
  mailAccount*: AccountId

proc connect*(): Result[CliContext, string] =
  let sessionUrl = getEnv("JMAP_TEST_STALWART_SESSION_URL")
  let user = getEnv("JMAP_TEST_STALWART_ALICE_USER")
  let pass = getEnv("JMAP_TEST_STALWART_ALICE_PASSWORD")
  if sessionUrl.len == 0 or user.len == 0 or pass.len == 0:
    return err("missing env; source /tmp/stalwart-env.sh first")
  let endpoint = directEndpoint(sessionUrl).valueOr:
    return err("bad endpoint: " & error.message)
  let credential = basicCredential(user, pass).valueOr:
    return err("bad credential: " & error.message)
  let client = initJmapClient(endpoint, credential).valueOr:
    return err("client init failed: " & error.message)
  let session = client.fetchSession().valueOr:
    return err("fetchSession failed: " & error.message)
  let mailAccount = session.primaryAccount(ckMail).valueOr:
    return err("server does not advertise JMAP Mail")
  ok(CliContext(client: client, mailAccount: mailAccount))
