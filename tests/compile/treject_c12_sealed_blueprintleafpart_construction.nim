discard """
  action: "reject"
  errormsg: "the field 'rawSource' is not accessible."
"""

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## C12/A8b reject — the fully-sealed ``BlueprintLeafPart`` cannot be
## raw-constructed across module boundaries, not even the discriminator
## alone. The ``rawSource`` discriminator is module-private (surfaced
## read-only via the ``source`` accessor), so ``BlueprintLeafPart(source:
## …)`` / ``BlueprintLeafPart(rawSource: …)`` both fail — the only producers
## reachable from ``import jmap_client`` are ``inlinePart`` / ``blobRefPart``,
## via ``BlueprintBodyPart``. Asserting on the discriminator key (evaluated
## first) proves every raw-construction path is closed: a compile success
## here would mean a caller could mint a leaf with neither a partId nor a
## blobId.

import jmap_client
discard BlueprintLeafPart(rawSource: bpsInline)
