# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Re-export hub for all Layer 1 modules. Import this single module to access
## the complete domain type vocabulary.

import pkg/results

import ./validation
import ./primitives
import ./identifiers
import ./capabilities
import ./session
import ./envelope
import ./framework
import ./errors

export validation
export primitives
export identifiers
export capabilities
export session
export envelope
export framework
export errors

type JmapResult*[T] = Result[T, ClientError]
  ## Outer railway alias: success or transport/request-level failure.
