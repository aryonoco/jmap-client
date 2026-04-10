# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## SearchSnippet for RFC 8621 (JMAP Mail) §4.8 SearchSnippet/get.
## Pure data carrier highlighting search matches in an Email.
## Serde defined separately in ``serde_snippet.nim``.

{.push raises: [], noSideEffect.}

import ../validation
import ../primitives

type SearchSnippet* {.ruleOff: "objects".} = object
  ## Text fragment highlighting search matches in an Email (RFC 8621 §4.8).
  ## Pure data carrier — no domain invariant, no smart constructor.
  emailId*: Id ## The Email this snippet describes.
  subject*: Opt[string] ## Highlighted subject with <mark> tags, or none.
  preview*: Opt[string] ## Highlighted body fragment with <mark> tags, or none.
