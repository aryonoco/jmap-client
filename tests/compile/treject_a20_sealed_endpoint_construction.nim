discard """
  action: "reject"
  errormsg: "the field 'directUrl' is not accessible."
"""

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A20 reject — the sealed ``SessionEndpoint`` cannot be raw-constructed across
## module boundaries. The ``kind`` discriminator is public, but the payload
## (``directUrl``) is module-private; the only producers reachable from
## ``import jmap_client`` are the smart constructors ``directEndpoint`` /
## ``discoveryEndpoint``. A compile success here would mean the seal has
## drifted and a caller could bypass URL validation.

import jmap_client
discard SessionEndpoint(kind: sekDirectUrl, directUrl: "x")
