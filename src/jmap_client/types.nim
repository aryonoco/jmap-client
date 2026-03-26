# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri
#

## Core domain types for jmap-client

# Pure module — enable maximum strict modes
{.experimental: "strictFuncs".}
{.experimental: "strictCaseObjects".}

import results
export results # Re-export for Opt[T] usage

{.push raises: [].}

type
  JmapErrorKind* = enum
    ## Categories of JMAP client errors
    jekNetwork ## Network/connection failure
    jekAuth ## Authentication failure
    jekSession ## Session discovery failure
    jekParse ## JSON parse failure
    jekProtocol ## JMAP protocol error

  JmapError* = object
    ## Structured error with kind and message
    kind*: JmapErrorKind
    message*: string

  ## Result alias for JMAP operations
  JmapResult*[T] = Result[T, JmapError]
