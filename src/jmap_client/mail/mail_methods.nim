# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Custom builder functions for VacationResponse (RFC 8621 section 7).
## VacationResponse is a singleton — no entity registration, no create/destroy,
## no /changes. The singleton id is hardcoded internally (Decision A7, A12).

{.push raises: [].}

import std/json

import ../types
import ../serialisation
import ../methods
import ../dispatch
import ../builder
import ./vacation

const VacationResponseCapUri = "urn:ietf:params:jmap:vacationresponse"

# =============================================================================
# VacationResponse/get
# =============================================================================

func addVacationResponseGet*(
    b: RequestBuilder,
    accountId: AccountId,
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ResponseHandle[GetResponse[VacationResponse]]) =
  ## Adds a VacationResponse/get invocation (RFC 8621 section 7). Always
  ## fetches the singleton — no ``ids`` parameter. Optionally restricts
  ## returned properties.
  let req = GetRequest[VacationResponse](
    accountId: accountId, ids: Opt.none(Referencable[seq[Id]]), properties: properties
  )
  let args = req.toJson()
  let (newBuilder, callId) =
    b.addInvocation("VacationResponse/get", args, VacationResponseCapUri)
  return (newBuilder, ResponseHandle[GetResponse[VacationResponse]](callId))

# =============================================================================
# VacationResponse/set
# =============================================================================

func addVacationResponseSet*(
    b: RequestBuilder,
    accountId: AccountId,
    update: PatchObject,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
): (RequestBuilder, ResponseHandle[SetResponse[VacationResponse]]) =
  ## Adds a VacationResponse/set invocation (RFC 8621 section 7). Updates
  ## the singleton only — no create or destroy. The singleton id is
  ## hardcoded from ``VacationResponseSingletonId``.
  var args = newJObject()
  args["accountId"] = accountId.toJson()
  for state in ifInState:
    args["ifInState"] = state.toJson()
  var updateMap = newJObject()
  updateMap[VacationResponseSingletonId] = update.toJson()
  args["update"] = updateMap
  let (newBuilder, callId) =
    b.addInvocation("VacationResponse/set", args, VacationResponseCapUri)
  return (newBuilder, ResponseHandle[SetResponse[VacationResponse]](callId))
