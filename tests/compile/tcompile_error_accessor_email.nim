# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Compile-only audit of the `.error` accessor over Email-carrying Results.
##
## `Result.error` renders the SUCCESS value into its defect message, and the
## renderer is a `noSideEffect` func. Nim's effect inference cannot close on
## the derived `$` for a self-referential value tree — `Email` nests
## `seq[EmailBodyPart]` inside `EmailBodyPart` — so an unguarded renderer makes
## `.error` uncompilable for every Result whose success type embeds an `Email`,
## with no route around it from calling code. The vendored `nim-results` probes
## that provability before choosing the rich message.
##
## This file exists so that a re-vendor which drops the probe fails HERE, by
## name, rather than obscurely inside whichever test happens to inspect a sync
## or one-shot error rail first. Everything is reached through
## `import jmap_client` alone: a consumer never imports `results` separately.

import jmap_client

static:
  # =========================================================================
  # The bare entity, the get response that carries a list of them, and the
  # sync aggregate that carries two such responses — three distinct
  # instantiations of the renderer, since Nim caches one per type argument.
  # =========================================================================

  doAssert compiles(default(Result[Email, JmapError]).error),
    ".error must compile for Result[Email, JmapError]"
  doAssert compiles(default(Result[GetResponse[Email], JmapError]).error),
    ".error must compile for Result[GetResponse[Email], JmapError]"
  doAssert compiles(default(Result[EmailSync, JmapError]).error),
    ".error must compile for Result[EmailSync, JmapError]"
