# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

import std/unittest
import results
import jmap_client
import jmap_client/client
import ./mconfig

suite "JMAP session discovery (live)":
  let cfg = loadLiveTestConfig().expect("live test config")

  test "fetchSession returns valid session with accounts":
    var client = initJmapClient(
      sessionUrl = cfg.sessionUrl,
      bearerToken = cfg.aliceToken,
      authScheme = cfg.authScheme,
    ).expect("initJmapClient")
    let session = client.fetchSession().expect("fetchSession")
    check session.accounts.len > 0
    check session.apiUrl.len > 0
    client.close()
