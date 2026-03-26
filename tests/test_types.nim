# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri
#

## Tests for JMAP domain types

import unittest
import ../src/jmap_client/types
import ../src/jmap_client/errors

suite "JmapError":
  test "error constructors set correct kind":
    check networkError("timeout").kind == jekNetwork
    check authError("invalid token").kind == jekAuth
    check sessionError("not found").kind == jekSession
    check parseError("invalid json").kind == jekParse
    check protocolError("method not found").kind == jekProtocol

  test "error constructors preserve message":
    let err = networkError("connection refused")
    check err.message == "connection refused"

suite "JmapResult":
  test "ok result":
    let r: JmapResult[int] = ok(42)
    check r.isOk
    check r.get == 42

  test "err result":
    let r: JmapResult[int] = err(networkError("fail"))
    check r.isErr
    check r.error.kind == jekNetwork
