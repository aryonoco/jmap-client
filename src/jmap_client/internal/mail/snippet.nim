# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## SearchSnippet for RFC 8621 (JMAP Mail) §5; SearchSnippet/get is §5.1.
## Pure data carrier highlighting search matches in an Email.
## Serde defined separately in ``serde_snippet.nim``.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import ../types/validation
import ../types/primitives

type SearchSnippet* {.ruleOff: "objects".} = object
  ## Text fragment highlighting search matches in an Email (RFC 8621 §5).
  ## Pure data carrier — no domain invariant, no smart constructor.
  # The field-shape asymmetry is deliberate, not an oversight: RFC 8621 §5
  # makes ``emailId`` mandatory on every snippet, whereas ``subject`` and
  # ``preview`` are ``null`` when that part yielded no match — so the former
  # is a bare ``Id`` and the latter two are ``Opt[string]``.
  emailId*: Id ## The Email this snippet describes.
  subject*: Opt[string] ## Highlighted subject with <mark> tags, or none.
  preview*: Opt[string] ## Highlighted body fragment with <mark> tags, or none.
