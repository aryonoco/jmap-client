# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration smoke test for JMAP session discovery against every
## configured target. Requires running Stalwart and/or James servers with
## JMAP_TEST_<SERVER>_* env vars exported by the matching seed scripts.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it
## entirely; run explicitly via ``just test-integration`` after
## ``just jmap-up``. The runtime guard on ``forEachLiveTarget`` keeps the
## file joinable into ``just test-full``'s megatest even when no server
## is running — the body is a no-op whenever the env vars are absent, so
## the megatest compiles and runs to completion in either mode.
##
## Project test idiom: ``block <name>:`` plus ``doAssert`` (see
## ``docs/design/12-mail-G2-design.md`` §8.1). ``std/unittest``'s
## ``suite`` / ``test`` templates expand to bodies that trip
## ``warningAsError:BareExcept`` (``config.nims``).

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive
import ../../mtestblock

testCase jmapSessionDiscoveryLive:
  forEachLiveTarget(target):
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    captureIfRequested(client, "session-" & $target.kind).expect(
      "captureIfRequested[" & $target.kind & "]"
    )
    assertOn target,
      session.accounts.len > 0, "session must advertise at least one account"
    assertOn target, session.apiUrl.len > 0, "session must advertise an apiUrl"
    client.close()
