# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

discard """
  action: "run"
  exitcode: 1
  outputsub: "Session missing ckCore"
"""

## Verifies that coreCapabilities() panics on a Session without ckCore.
## Separated from tsession.nim because --panics:on makes Defects uncatchable.

import std/tables

import jmap_client/identifiers
import jmap_client/session
import jmap_client/validation

let badSession = Session(
  capabilities: @[],
  accounts: initTable[AccountId, Account](),
  primaryAccounts: initTable[string, AccountId](),
  username: "",
  apiUrl: "https://example.com/api/",
  downloadUrl: parseUriTemplate("https://example.com/d").get(),
  uploadUrl: parseUriTemplate("https://example.com/u").get(),
  eventSourceUrl: parseUriTemplate("https://example.com/e").get(),
  state: parseJmapState("s1").get(),
)
discard coreCapabilities(badSession)
