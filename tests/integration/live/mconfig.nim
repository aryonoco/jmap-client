# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test configuration — reads JMAP_TEST_* env vars
## set by .devcontainer/scripts/seed-stalwart.sh.

{.push raises: [].}

import std/os
import results

type LiveTestConfig* = object
  sessionUrl*: string
  authScheme*: string
  aliceToken*: string
  bobToken*: string

proc loadLiveTestConfig*(): Result[LiveTestConfig, string] =
  let sessionUrl = getEnv("JMAP_TEST_SESSION_URL")
  if sessionUrl.len == 0:
    return err("JMAP_TEST_SESSION_URL not set — run 'just stalwart-up' first")
  let authScheme = getEnv("JMAP_TEST_AUTH_SCHEME")
  if authScheme.len == 0:
    return err("JMAP_TEST_AUTH_SCHEME not set")
  let aliceToken = getEnv("JMAP_TEST_ALICE_TOKEN")
  if aliceToken.len == 0:
    return err("JMAP_TEST_ALICE_TOKEN not set")
  let bobToken = getEnv("JMAP_TEST_BOB_TOKEN")
  if bobToken.len == 0:
    return err("JMAP_TEST_BOB_TOKEN not set")
  ok(LiveTestConfig(
    sessionUrl: sessionUrl,
    authScheme: authScheme,
    aliceToken: aliceToken,
    bobToken: bobToken,
  ))
