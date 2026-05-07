# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Re-export hub for all Layer 2 serialisation modules. Import this single
## module to access every toJson/fromJson pair and the shared helpers.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import ./internal/serialisation/serde
import ./internal/serialisation/serde_session
import ./internal/serialisation/serde_envelope
import ./internal/serialisation/serde_framework
import ./internal/serialisation/serde_errors

export serde
export serde_session
export serde_envelope
export serde_framework
export serde_errors
