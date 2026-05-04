# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-time fixture loader for the captured-payload replay suite.
##
## ``staticRead`` resolves its path argument relative to the calling
## module file. The path ``../../testdata/captured/<name>.json`` lands
## at ``tests/testdata/captured/<name>.json`` so missing fixtures fail
## the megatest with a clear compile-time error rather than a runtime
## file-not-found, and the test binary's working directory is irrelevant.
## ``testdata`` is testament's hardcoded "non-category" directory, so
## the JSON files sit there without confusing ``just test`` enumeration.

{.push raises: [].}

import std/json

template loadCapturedFixture*(name: static string): JsonNode =
  ## Embeds ``tests/testdata/captured/<name>.json`` at compile time and
  ## returns it as a parsed ``JsonNode``. Missing fixtures fail at
  ## ``staticRead`` (compile error), not at test runtime. The two
  ## ``const`` bindings are required so the path concatenation and
  ## file read both occur in a compile-time context — ``parseJson``
  ## then runs at test runtime over the embedded literal.
  const path = "../../testdata/captured/" & name & ".json"
  const data = staticRead(path)
  parseJson(data)

template forEachCapturedServer*(baseName: static string, fixture, body: untyped) =
  ## Loads ``<baseName>-stalwart.json`` and ``<baseName>-james.json`` in
  ## sequence and runs ``body`` once per server. Two static-read paths
  ## are emitted at compile time — missing fixtures fail at build, not
  ## at runtime. Use ``loadCapturedFixture`` directly for replay tests
  ## whose live counterpart is skipped on James (no James fixture
  ## exists).
  block:
    let fixture {.inject.} = loadCapturedFixture(baseName & "-stalwart")
    body
  block:
    let fixture {.inject.} = loadCapturedFixture(baseName & "-james")
    body
