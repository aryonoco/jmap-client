# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Re-export hub for all Layer 1 modules. Import this single module to access
## the complete domain type vocabulary.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import results

import ./internal/types/validation
import ./internal/types/primitives
import ./internal/types/identifiers
import ./internal/types/collation
import ./internal/types/capabilities
import ./internal/types/methods_enum
import ./internal/types/session
import ./internal/types/envelope
import ./internal/types/framework
import ./internal/types/errors

export results
export validation
export primitives
export identifiers
export collation
export capabilities
export methods_enum
export session
export envelope except arguments
export framework
export errors

type JmapResult*[T] = Result[T, ClientError]
  ## Outer railway: transport/request failure or typed success.
