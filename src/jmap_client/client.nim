# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri
#

## JMAP HTTP client wrapper

import types, session

{.push raises: [].}

type
  JmapClient* = object
    ## JMAP client holding session and authentication state
    session*: Opt[Session]
    baseUrl*: string
    bearerToken*: string
