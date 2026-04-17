# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Custom method builder tests (RFC 8621). Covers VacationResponse scenarios
## 72–75, Email/parse scenarios 84–85, and SearchSnippet/get scenarios 86–90.

{.push raises: [].}

import std/json

import jmap_client/types
import jmap_client/serialisation
import jmap_client/methods
import jmap_client/dispatch
import jmap_client/builder
import jmap_client/mail/thread
import jmap_client/mail/email
import jmap_client/mail/mail_entities
import jmap_client/mail/mail_methods
import jmap_client/mail/vacation

import ../massertions
import ../mfixtures

# Minimal non-empty VacationResponseUpdateSet used wherever the test is
# exercising builder mechanics (invocation name, capability, envelope
# fields) rather than the update content. Produces {"isEnabled": true}
# on the wire — the one scenario that inspects the patch body asserts
# exactly that.
let minimalVacUpdate = initVacationResponseUpdateSet(@[setIsEnabled(true)]).get()

# ===========================================================================
# A. VacationResponse/get
# ===========================================================================

block vacationGetInvocationName:
  ## Scenario 72: invocation name is "VacationResponse/get".
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseGet(makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnVacationResponseGet

block vacationGetCapability:
  ## Scenario 73: capability is "urn:ietf:params:jmap:vacationresponse".
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseGet(makeAccountId("a1"))
  let req = b1.build()
  assertLen req.`using`, 1
  assertEq req.`using`[0], "urn:ietf:params:jmap:vacationresponse"

block vacationGetAccountId:
  ## accountId is present in arguments.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseGet(makeAccountId("a1"))
  let req = b1.build()
  assertEq req.methodCalls[0].arguments{"accountId"}.getStr(""), "a1"

block vacationGetOmitsIds:
  ## Singleton: no ids or #ids key in arguments.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseGet(makeAccountId("a1"))
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"ids"}.isNil
  doAssert args{"#ids"}.isNil

block vacationGetWithProperties:
  ## properties array emitted when specified.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseGet(
    makeAccountId("a1"), properties = Opt.some(@["isEnabled", "subject"])
  )
  let req = b1.build()
  let props = req.methodCalls[0].arguments{"properties"}
  doAssert props.kind == JArray
  assertLen props.getElems(@[]), 2

block vacationGetMinimal:
  ## Minimal call: just accountId, no ids, no properties.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseGet(makeAccountId("a1"))
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  assertEq args{"accountId"}.getStr(""), "a1"
  doAssert args{"ids"}.isNil
  doAssert args{"properties"}.isNil

# ===========================================================================
# B. VacationResponse/set
# ===========================================================================

block vacationSetInvocationName:
  ## Invocation name is "VacationResponse/set".
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseSet(makeAccountId("a1"), minimalVacUpdate)
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnVacationResponseSet

block vacationSetCapability:
  ## Capability is "urn:ietf:params:jmap:vacationresponse".
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseSet(makeAccountId("a1"), minimalVacUpdate)
  let req = b1.build()
  assertLen req.`using`, 1
  assertEq req.`using`[0], "urn:ietf:params:jmap:vacationresponse"

block vacationSetSingletonInUpdate:
  ## Scenario 74: update map has key "singleton" with typed-algebra JSON.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseSet(makeAccountId("a1"), minimalVacUpdate)
  let req = b1.build()
  let updateMap = req.methodCalls[0].arguments{"update"}
  doAssert updateMap.kind == JObject
  doAssert updateMap{"singleton"}.kind == JObject

block vacationSetOmitsCreateDestroy:
  ## Scenario 75: no create or destroy keys in arguments.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseSet(makeAccountId("a1"), minimalVacUpdate)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"create"}.isNil
  doAssert args{"destroy"}.isNil

block vacationSetWithIfInState:
  ## ifInState emitted when specified.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseSet(
    makeAccountId("a1"), minimalVacUpdate, ifInState = Opt.some(makeState("s0"))
  )
  let req = b1.build()
  assertEq req.methodCalls[0].arguments{"ifInState"}.getStr(""), "s0"

block vacationSetOmitsIfInStateWhenNone:
  ## ifInState key absent when Opt.none (default).
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseSet(makeAccountId("a1"), minimalVacUpdate)
  let req = b1.build()
  doAssert req.methodCalls[0].arguments{"ifInState"}.isNil

block vacationSetPatchValues:
  ## Typed VacationResponseUpdateSet values correctly serialised inside
  ## update.singleton — matches the RFC 8620 §5.3 wire patch shape.
  let updateSet = initVacationResponseUpdateSet(@[setIsEnabled(true)]).get()
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseSet(makeAccountId("a1"), updateSet)
  let req = b1.build()
  let singleton = req.methodCalls[0].arguments{"update"}{"singleton"}
  doAssert singleton{"isEnabled"}.getBool(false) == true

# ===========================================================================
# C. Multi-operation and capability dedup
# ===========================================================================

block vacationGetAndSetInOneRequest:
  ## Both get and set in one builder: two invocations, capability once.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseGet(makeAccountId("a1"))
  let (b2, _) = b1.addVacationResponseSet(makeAccountId("a1"), minimalVacUpdate)
  let req = b2.build()
  assertLen req.methodCalls, 2
  assertEq req.methodCalls[0].name, mnVacationResponseGet
  assertEq req.methodCalls[1].name, mnVacationResponseSet
  assertLen req.`using`, 1

block vacationAndThreadMixedCapabilities:
  ## VacationResponse + Thread produces both capability URIs.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addVacationResponseGet(makeAccountId("a1"))
  let (b2, _) = addGet[thread.Thread](b1, makeAccountId("a1"))
  let caps = b2.capabilities
  assertLen caps, 2
  doAssert "urn:ietf:params:jmap:vacationresponse" in caps
  doAssert "urn:ietf:params:jmap:mail" in caps

# ===========================================================================
# D. Email/parse and SearchSnippet/get
# ===========================================================================

block addEmailParseInvocationName:
  ## Scenario 84: invocation name is "Email/parse", capability is mail.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailParse(makeAccountId("a1"), @[makeBlobId("blob1")])
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnEmailParse
  assertLen req.`using`, 1
  assertEq req.`using`[0], "urn:ietf:params:jmap:mail"

block addEmailParseWithBodyFetchOptions:
  ## Scenario 85: bvsText emits fetchTextBodyValues = true.
  let opts = EmailBodyFetchOptions(fetchBodyValues: bvsText)
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailParse(
    makeAccountId("a1"), @[makeBlobId("blob1")], bodyFetchOptions = opts
  )
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"fetchTextBodyValues"}.getBool(false) == true

block addSearchSnippetGetInvocationName:
  ## Scenario 86: invocation name is "SearchSnippet/get", capability is mail.
  let cond = filterCondition(makeEmailFilterCondition())
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addSearchSnippetGet(
    makeAccountId("a1"), filterConditionToJson, cond, makeId("e1")
  )
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnSearchSnippetGet
  assertLen req.`using`, 1
  assertEq req.`using`[0], "urn:ietf:params:jmap:mail"

block addSearchSnippetGetSingleId:
  ## Scenario 87: emailIds contains exactly the head ID when no tail.
  let cond = filterCondition(makeEmailFilterCondition())
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addSearchSnippetGet(
    makeAccountId("a1"), filterConditionToJson, cond, makeId("e1")
  )
  let req = b1.build()
  let ids = req.methodCalls[0].arguments{"emailIds"}
  doAssert ids.kind == JArray
  assertLen ids.getElems(@[]), 1
  assertEq ids.getElems(@[])[0].getStr(""), "e1"

block addSearchSnippetGetConsIds:
  ## Scenario 88: emailIds from head + tail produces ["e1","e2","e3"].
  let cond = filterCondition(makeEmailFilterCondition())
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addSearchSnippetGet(
    makeAccountId("a1"),
    filterConditionToJson,
    cond,
    makeId("e1"),
    @[makeId("e2"), makeId("e3")],
  )
  let req = b1.build()
  let ids = req.methodCalls[0].arguments{"emailIds"}
  doAssert ids.kind == JArray
  assertLen ids.getElems(@[]), 3
  assertEq ids.getElems(@[])[0].getStr(""), "e1"
  assertEq ids.getElems(@[])[1].getStr(""), "e2"
  assertEq ids.getElems(@[])[2].getStr(""), "e3"

block addSearchSnippetGetFilterRequired:
  ## Scenario 89: omitting the filter parameter is a compile error.
  assertNotCompiles:
    let b0 = initRequestBuilder()
    discard
      b0.addSearchSnippetGet(makeAccountId("a1"), filterConditionToJson, makeId("e1"))

block addSearchSnippetGetFilterInArgs:
  ## Scenario 90: filter JSON object is present in arguments.
  let cond = filterCondition(makeEmailFilterCondition())
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addSearchSnippetGet(
    makeAccountId("a1"), filterConditionToJson, cond, makeId("e1")
  )
  let req = b1.build()
  let filterNode = req.methodCalls[0].arguments{"filter"}
  doAssert filterNode.kind == JObject

# ===========================================================================
# E. addEmailImport — Email/import (RFC 8621 §4.8)
# ===========================================================================

block addEmailImportInvocationName:
  ## E.1: invocation name is "Email/import" and the mail capability URI
  ## is added. The returned handle is phantom-typed to
  ## ``EmailImportResponse`` — binding it to a mismatched
  ## ``ResponseHandle`` parameter must not compile.
  let emails = makeNonEmptyEmailImportMap(
    @[(makeCreationId("k1"), makeEmailImportItem(blobId = makeBlobId("b1")))]
  )
  let b0 = initRequestBuilder()
  let (b1, handle) = b0.addEmailImport(makeAccountId("a1"), emails)
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnEmailImport
  assertLen req.`using`, 1
  assertEq req.`using`[0], "urn:ietf:params:jmap:mail"
  assertNotCompiles:
    let badHandle: ResponseHandle[EmailSetResponse] = handle

block addEmailImportEmailsPassthrough:
  ## E.2: the typed ``NonEmptyEmailImportMap`` flattens to the wire via
  ## ``toJson(NonEmptyEmailImportMap)`` at the builder boundary — the
  ## per-creation-id blobId survives unchanged into ``args.emails``.
  let emails = makeNonEmptyEmailImportMap(
    @[(makeCreationId("k1"), makeEmailImportItem(blobId = makeBlobId("b1")))]
  )
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailImport(makeAccountId("a1"), emails)
  let req = b1.build()
  let emailsNode = req.methodCalls[0].arguments{"emails"}
  doAssert emailsNode.kind == JObject
  assertEq emailsNode{"k1"}{"blobId"}.getStr(""), "b1"

block addEmailImportIfInStateSomePassthrough:
  ## E.3: ``ifInState: Opt.some`` → key emitted with exact state string.
  let emails =
    makeNonEmptyEmailImportMap(@[(makeCreationId("k1"), makeEmailImportItem())])
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailImport(
    makeAccountId("a1"), emails, ifInState = Opt.some(makeState("s0"))
  )
  let req = b1.build()
  assertEq req.methodCalls[0].arguments{"ifInState"}.getStr(""), "s0"

block addEmailImportIfInStateNoneOmitted:
  ## E.4: default (``Opt.none``) ``ifInState`` → omit the key, never
  ## emit JSON ``null``.
  let emails =
    makeNonEmptyEmailImportMap(@[(makeCreationId("k1"), makeEmailImportItem())])
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailImport(makeAccountId("a1"), emails)
  let req = b1.build()
  doAssert req.methodCalls[0].arguments{"ifInState"}.isNil
