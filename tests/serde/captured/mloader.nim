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
  ## ``staticRead`` (compile error), not at test runtime.
  parseJson(staticRead("../../testdata/captured/" & name & ".json"))
