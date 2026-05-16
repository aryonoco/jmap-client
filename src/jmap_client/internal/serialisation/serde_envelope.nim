# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## L2-internal aggregator for envelope ser/de. Re-exports both halves
## (``serde_envelope_emit`` and ``serde_envelope_parse``) so existing
## in-tree callers (``client.nim``, ``classify.nim``, ``dispatch.nim``,
## ``methods.nim``) can keep their single ``./serialisation/serde_envelope``
## import path. Only ``serde_envelope_emit`` is re-exported via
## ``internal/protocol.nim`` to user scope — the parse half stays
## hub-private per P19 ("diagnostic emission is fine; the reverse
## direction is not").

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import ./serde_envelope_emit
import ./serde_envelope_parse

export serde_envelope_emit
export serde_envelope_parse
