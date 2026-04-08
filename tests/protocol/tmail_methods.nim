# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## VacationResponse custom builder tests (RFC 8621 section 7). Covers design
## doc scenarios 72–75, singleton constraints, and multi-operation composition.

{.push raises: [].}

import std/json

import jmap_client/types
import jmap_client/serialisation
import jmap_client/methods
import jmap_client/dispatch
import jmap_client/builder
import jmap_client/mail/thread
import jmap_client/mail/vacation
import jmap_client/mail/mail_entities
import jmap_client/mail/mail_methods

import ../massertions
import ../mfixtures

# ===========================================================================
# A. VacationResponse/get
# ===========================================================================

block vacationGetInvocationName:
  ## Scenario 72: invocation name is "VacationResponse/get".
  var b = initRequestBuilder()
  discard b.addVacationResponseGet(makeAccountId("a1"))
  let req = b.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "VacationResponse/get"

block vacationGetCapability:
  ## Scenario 73: capability is "urn:ietf:params:jmap:vacationresponse".
  var b = initRequestBuilder()
  discard b.addVacationResponseGet(makeAccountId("a1"))
  let req = b.build()
  assertLen req.`using`, 1
  assertEq req.`using`[0], "urn:ietf:params:jmap:vacationresponse"

block vacationGetAccountId:
  ## accountId is present in arguments.
  var b = initRequestBuilder()
  discard b.addVacationResponseGet(makeAccountId("a1"))
  let req = b.build()
  assertEq req.methodCalls[0].arguments{"accountId"}.getStr(""), "a1"

block vacationGetOmitsIds:
  ## Singleton: no ids or #ids key in arguments.
  var b = initRequestBuilder()
  discard b.addVacationResponseGet(makeAccountId("a1"))
  let req = b.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"ids"}.isNil
  doAssert args{"#ids"}.isNil

block vacationGetWithProperties:
  ## properties array emitted when specified.
  var b = initRequestBuilder()
  discard b.addVacationResponseGet(
    makeAccountId("a1"), properties = Opt.some(@["isEnabled", "subject"])
  )
  let req = b.build()
  let props = req.methodCalls[0].arguments{"properties"}
  doAssert props.kind == JArray
  assertLen props.getElems(@[]), 2

block vacationGetMinimal:
  ## Minimal call: just accountId, no ids, no properties.
  var b = initRequestBuilder()
  discard b.addVacationResponseGet(makeAccountId("a1"))
  let req = b.build()
  let args = req.methodCalls[0].arguments
  assertEq args{"accountId"}.getStr(""), "a1"
  doAssert args{"ids"}.isNil
  doAssert args{"properties"}.isNil

# ===========================================================================
# B. VacationResponse/set
# ===========================================================================

block vacationSetInvocationName:
  ## Invocation name is "VacationResponse/set".
  var b = initRequestBuilder()
  discard b.addVacationResponseSet(makeAccountId("a1"), emptyPatch())
  let req = b.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, "VacationResponse/set"

block vacationSetCapability:
  ## Capability is "urn:ietf:params:jmap:vacationresponse".
  var b = initRequestBuilder()
  discard b.addVacationResponseSet(makeAccountId("a1"), emptyPatch())
  let req = b.build()
  assertLen req.`using`, 1
  assertEq req.`using`[0], "urn:ietf:params:jmap:vacationresponse"

block vacationSetSingletonInUpdate:
  ## Scenario 74: update map has key "singleton" with PatchObject JSON.
  var b = initRequestBuilder()
  discard b.addVacationResponseSet(makeAccountId("a1"), emptyPatch())
  let req = b.build()
  let updateMap = req.methodCalls[0].arguments{"update"}
  doAssert updateMap.kind == JObject
  doAssert updateMap{"singleton"}.kind == JObject

block vacationSetOmitsCreateDestroy:
  ## Scenario 75: no create or destroy keys in arguments.
  var b = initRequestBuilder()
  discard b.addVacationResponseSet(makeAccountId("a1"), emptyPatch())
  let req = b.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"create"}.isNil
  doAssert args{"destroy"}.isNil

block vacationSetWithIfInState:
  ## ifInState emitted when specified.
  var b = initRequestBuilder()
  discard b.addVacationResponseSet(
    makeAccountId("a1"), emptyPatch(), ifInState = Opt.some(makeState("s0"))
  )
  let req = b.build()
  assertEq req.methodCalls[0].arguments{"ifInState"}.getStr(""), "s0"

block vacationSetOmitsIfInStateWhenNone:
  ## ifInState key absent when Opt.none (default).
  var b = initRequestBuilder()
  discard b.addVacationResponseSet(makeAccountId("a1"), emptyPatch())
  let req = b.build()
  doAssert req.methodCalls[0].arguments{"ifInState"}.isNil

block vacationSetPatchValues:
  ## PatchObject values correctly serialised inside update.singleton.
  let patch = emptyPatch().setProp("isEnabled", %true).get()
  var b = initRequestBuilder()
  discard b.addVacationResponseSet(makeAccountId("a1"), patch)
  let req = b.build()
  let singleton = req.methodCalls[0].arguments{"update"}{"singleton"}
  doAssert singleton{"isEnabled"}.getBool(false) == true

# ===========================================================================
# C. Multi-operation and capability dedup
# ===========================================================================

block vacationGetAndSetInOneRequest:
  ## Both get and set in one builder: two invocations, capability once.
  var b = initRequestBuilder()
  discard b.addVacationResponseGet(makeAccountId("a1"))
  discard b.addVacationResponseSet(makeAccountId("a1"), emptyPatch())
  let req = b.build()
  assertLen req.methodCalls, 2
  assertEq req.methodCalls[0].name, "VacationResponse/get"
  assertEq req.methodCalls[1].name, "VacationResponse/set"
  assertLen req.`using`, 1

block vacationAndThreadMixedCapabilities:
  ## VacationResponse + Thread produces both capability URIs.
  var b = initRequestBuilder()
  discard b.addVacationResponseGet(makeAccountId("a1"))
  discard addGet[thread.Thread](b, makeAccountId("a1"))
  let caps = b.capabilities
  assertLen caps, 2
  doAssert "urn:ietf:params:jmap:vacationresponse" in caps
  doAssert "urn:ietf:params:jmap:mail" in caps
