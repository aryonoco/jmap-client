# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test configuration — reads JMAP_TEST_* env vars
## set by .devcontainer/scripts/seed-stalwart.sh.

{.push raises: [].}

import std/os
import results

type LiveTestConfig* = object
  ## Snapshot of the JMAP_TEST_* environment contract published by
  ## ``.devcontainer/scripts/seed-stalwart.sh``: the Stalwart session
  ## URL, the HTTP authentication scheme (Basic, for Stalwart's admin
  ## API), per-user bearer tokens for the seeded alice and bob
  ## accounts, and the base64 admin credential used by the SMTP-queue
  ## drain barrier (Phase K1). Consumed by live integration tests
  ## under ``tests/integration/live``.
  sessionUrl*: string
  authScheme*: string
  aliceToken*: string
  bobToken*: string
  adminBasic*: string

proc loadLiveTestConfig*(): Result[LiveTestConfig, string] =
  ## Reads the four JMAP_TEST_* env vars and returns ``Ok`` when all
  ## four are present and non-empty; ``Err`` otherwise with a message
  ## naming the first missing variable. Live integration tests guard
  ## their bodies on ``.isOk`` so the file joins the megatest cleanly
  ## whether or not Stalwart is running.
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
  let adminBasic = getEnv("JMAP_TEST_ADMIN_BASIC")
  if adminBasic.len == 0:
    return err("JMAP_TEST_ADMIN_BASIC not set — run 'just stalwart-up' first")
  ok(
    LiveTestConfig(
      sessionUrl: sessionUrl,
      authScheme: authScheme,
      aliceToken: aliceToken,
      bobToken: bobToken,
      adminBasic: adminBasic,
    )
  )
