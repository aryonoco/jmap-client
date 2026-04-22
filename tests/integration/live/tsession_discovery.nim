# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration smoke test for JMAP session discovery. Requires a
## running Stalwart JMAP server with JMAP_TEST_* env vars exported by
## ``.devcontainer/scripts/seed-stalwart.sh``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it
## entirely; run explicitly via ``just test-integration`` after
## ``just stalwart-up``. The runtime guard on ``loadLiveTestConfig``
## keeps the file joinable into ``just test-full``'s megatest even
## when Stalwart is not running — the body is a no-op whenever the
## env vars are absent, so the megatest compiles and runs to
## completion in either mode.
##
## Project test idiom: ``block <name>:`` plus ``doAssert`` (see
## ``docs/design/12-mail-G2-design.md`` §8.1). ``std/unittest``'s
## ``suite`` / ``test`` templates expand to bodies that trip
## ``warningAsError:BareExcept`` (``config.nims``).

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mconfig

block jmapSessionDiscoveryLive:
  let cfgRes = loadLiveTestConfig()
  if cfgRes.isOk:
    let cfg = cfgRes.get()
    var client = initJmapClient(
        sessionUrl = cfg.sessionUrl,
        bearerToken = cfg.aliceToken,
        authScheme = cfg.authScheme,
      )
      .expect("initJmapClient")
    let session = client.fetchSession().expect("fetchSession")
    doAssert session.accounts.len > 0, "session must advertise at least one account"
    doAssert session.apiUrl.len > 0, "session must advertise an apiUrl"
    client.close()
