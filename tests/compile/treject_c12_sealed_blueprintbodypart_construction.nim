discard """
  action: "reject"
  errormsg: "the field 'rawIsMultipart' is not accessible."
"""

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## C12/A8b reject — the fully-sealed ``BlueprintBodyPart`` cannot be
## raw-constructed across module boundaries, not even the discriminator
## alone. The ``rawIsMultipart`` discriminator is module-private (surfaced
## read-only via the ``isMultipart`` accessor), so
## ``BlueprintBodyPart(isMultipart: …)`` / ``BlueprintBodyPart(rawIsMultipart:
## …)`` both fail — the only producers reachable from ``import jmap_client``
## are ``inlinePart`` / ``blobRefPart`` / ``multipartPart``. Asserting on the
## discriminator key (evaluated first) proves every raw-construction path is
## closed: a compile success here would mean a caller could mint a part with
## no content and no children, bypassing the leaf/container invariant.

import jmap_client
discard BlueprintBodyPart(rawIsMultipart: true)
