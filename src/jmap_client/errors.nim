# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri
#

## Error constructors for jmap-client

{.experimental: "strictFuncs".}

import types

{.push raises: [].}

func networkError*(message: string): JmapError =
  JmapError(kind: jekNetwork, message: message)

func authError*(message: string): JmapError =
  JmapError(kind: jekAuth, message: message)

func sessionError*(message: string): JmapError =
  JmapError(kind: jekSession, message: message)

func parseError*(message: string): JmapError =
  JmapError(kind: jekParse, message: message)

func protocolError*(message: string): JmapError =
  JmapError(kind: jekProtocol, message: message)
