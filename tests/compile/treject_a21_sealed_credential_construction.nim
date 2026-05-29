discard """
  action: "reject"
  errormsg: "the field 'bearerTok' is not accessible."
"""

# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## A21 reject — the sealed ``Credential`` cannot be raw-constructed across
## module boundaries. The scheme discriminator is public, but the secret
## payload (``bearerTok``) is module-private; the only producers reachable from
## ``import jmap_client`` are the smart constructors ``bearerCredential`` /
## ``basicCredential``. A compile success here would mean the seal has drifted
## and a caller could stuff an unvalidated secret into the wire header.

import jmap_client
discard Credential(scheme: asBearer, bearerTok: "x")
