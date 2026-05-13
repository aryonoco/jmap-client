# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Re-export hub for all Layer 1 modules. Import this single module to access
## the complete domain type vocabulary.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import results

import ./types/validation
import ./types/primitives
import ./types/identifiers
import ./types/collation
import ./types/capabilities
import ./types/methods_enum
import ./types/session
import ./types/envelope
import ./types/framework
import ./types/errors
import ./types/field_echo

export results
export validation
export primitives
export identifiers except initBuilderId
export collation
export capabilities
export methods_enum
export session
export envelope except arguments
export framework
export errors
export field_echo

type JmapResult*[T] = Result[T, ClientError]
  ## Outer railway: transport/request failure or typed success.
