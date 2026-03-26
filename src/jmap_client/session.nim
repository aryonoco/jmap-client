# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri
#

## JMAP session discovery (RFC 8620 Section 2)

import types

{.push raises: [].}

type
  Session* = object
    ## A JMAP session resource
    apiUrl*: string
    uploadUrl*: string
    downloadUrl*: string
