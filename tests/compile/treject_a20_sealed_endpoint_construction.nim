discard """
  action: "reject"
  errormsg: "the field 'rawKind' is not accessible."
"""

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A20/A8b reject — the fully-sealed ``SessionEndpoint`` cannot be
## raw-constructed across module boundaries, not even the discriminator alone.
## The ``rawKind`` discriminator is now module-private (surfaced read-only via
## the ``kind`` accessor), so ``SessionEndpoint(kind: …)`` /
## ``SessionEndpoint(rawKind: …)`` both fail — the only producers reachable from
## ``import jmap_client`` are the smart constructors ``directEndpoint`` /
## ``discoveryEndpoint``. Asserting on the discriminator key (evaluated first)
## proves every raw-construction path is closed: a compile success here would
## mean a caller could mint an empty-URL endpoint and bypass URL validation.

import jmap_client
discard SessionEndpoint(rawKind: sekDirectUrl)
