# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## VacationResponse entity for RFC 8621 (JMAP Mail) section 7. A
## VacationResponse is a singleton object controlling automatic vacation
## replies. There is no ``id`` field on the Nim type — the singleton identity
## ("singleton") is handled purely in serialisation (Design Decision A6).

{.push raises: [], noSideEffect.}

import ../validation
import ../primitives

const VacationResponseSingletonId* = "singleton"
  ## The fixed identifier for the sole VacationResponse object (RFC 8621 §7).

type VacationResponse* {.ruleOff: "objects".} = object
  ## Server-side vacation auto-reply configuration (RFC 8621 section 7).
  ## All optional fields use ``Opt[T]`` — absent means the server decides.
  isEnabled*: bool ## Whether the vacation response is active.
  fromDate*: Opt[UTCDate] ## Start of the vacation window, or none.
  toDate*: Opt[UTCDate] ## End of the vacation window, or none.
  subject*: Opt[string] ## Subject line for the auto-reply, or none.
  textBody*: Opt[string] ## Plain-text body of the auto-reply, or none.
  htmlBody*: Opt[string] ## HTML body of the auto-reply, or none.
