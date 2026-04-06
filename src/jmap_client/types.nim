# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Re-export hub for all Layer 1 modules. Import this single module to access
## the complete domain type vocabulary.

import results

import ./validation
import ./primitives
import ./identifiers
import ./capabilities
import ./session
import ./envelope
import ./framework
import ./errors

export results
export validation
export primitives
export identifiers
export capabilities
export session
export envelope
export framework
export errors

type JmapResult*[T] = Result[T, ClientError]
  ## Outer railway: transport/request failure or typed success.
