discard """
  action: "reject"
  errormsg: "the field 'rawScheme' is not accessible."
"""

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A21/A8b reject — the fully-sealed ``Credential`` cannot be raw-constructed
## across module boundaries, not even the discriminator alone. The ``rawScheme``
## discriminator is now module-private (surfaced read-only via the ``scheme``
## accessor), so ``Credential(scheme: …)`` / ``Credential(rawScheme: …)`` both
## fail — the only producers reachable from ``import jmap_client`` are the smart
## constructors ``bearerCredential`` / ``basicCredential``. Asserting on the
## discriminator key (which is evaluated first) proves every raw-construction
## path is closed: a compile success here would mean a caller could mint an
## empty-payload credential and stuff an unvalidated secret into the wire header.

import jmap_client
discard Credential(rawScheme: asBearer)
