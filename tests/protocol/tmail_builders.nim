# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Custom Mailbox and Email builder and response tests (RFC 8621 §2, §4).
## Covers design doc scenarios 63-83: MailboxChangesResponse serde,
## addMailboxChanges, addMailboxQuery, addMailboxQueryChanges, addMailboxSet,
## addEmailGet, addEmailQuery, addEmailQueryChanges, plus adversarial serde
## tests and builder parameter combination tests.

{.push raises: [].}

import std/json
import std/tables

import jmap_client/types
import jmap_client/serialisation
import jmap_client/methods
import jmap_client/dispatch
import jmap_client/builder
import jmap_client/mail/mailbox
import jmap_client/mail/email
import jmap_client/mail/email_blueprint
import jmap_client/mail/email_update
import jmap_client/mail/mail_entities
import jmap_client/mail/mail_builders
import jmap_client/mail/serde_email

import ../massertions
import ../mfixtures

# ===========================================================================
# A. MailboxChangesResponse fromJson (scenarios 63-67)
# ===========================================================================

block mailboxChangesResponseWithUpdatedProperties:
  ## Scenario 63: updatedProperties present with values.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "newState": "s2",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
    "updatedProperties": ["name", "sortOrder"],
  }
  let res = MailboxChangesResponse.fromJson(node)
  doAssert res.isOk
  let resp = res.get()
  assertSome resp.updatedProperties
  let props = resp.updatedProperties.get()
  assertLen props, 2
  assertEq props[0], "name"
  assertEq props[1], "sortOrder"

block mailboxChangesResponseWithoutUpdatedProperties:
  ## Scenario 64: updatedProperties absent → Opt.none.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "newState": "s2",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
  }
  let res = MailboxChangesResponse.fromJson(node)
  doAssert res.isOk
  assertNone res.get().updatedProperties

block mailboxChangesResponseWithNullUpdatedProperties:
  ## Scenario 65: updatedProperties: null → Opt.none.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "newState": "s2",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
  }
  node["updatedProperties"] = newJNull()
  let res = MailboxChangesResponse.fromJson(node)
  doAssert res.isOk
  assertNone res.get().updatedProperties

block mailboxChangesResponseForwardingAccessors:
  ## Scenario 66: UFCS forwarding accessors return base field values.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "newState": "s2",
    "hasMoreChanges": true,
    "created": ["id1"],
    "updated": ["id2"],
    "destroyed": ["id3"],
    "updatedProperties": ["name"],
  }
  let resp = MailboxChangesResponse.fromJson(node).get()
  assertEq $resp.accountId, "acct1"
  assertEq $resp.oldState, "s1"
  assertEq $resp.newState, "s2"
  doAssert resp.hasMoreChanges
  assertLen resp.created, 1
  assertLen resp.updated, 1
  assertLen resp.destroyed, 1

block mailboxChangesResponseMissingBaseField:
  ## Scenario 67: missing required base field → err.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
  }
  assertErr MailboxChangesResponse.fromJson(node)

# ===========================================================================
# B. Adversarial MailboxChangesResponse serde tests
# ===========================================================================

block mailboxChangesResponseUpdatedPropertiesWrongType:
  ## updatedProperties: "name" (string, not array) → err.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "newState": "s2",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
    "updatedProperties": "name",
  }
  assertErr MailboxChangesResponse.fromJson(node)

block mailboxChangesResponseUpdatedPropertiesNonStringElement:
  ## updatedProperties: ["name", 123] (non-string element) → err.
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "newState": "s2",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
    "updatedProperties": ["name", 123],
  }
  assertErr MailboxChangesResponse.fromJson(node)

block mailboxChangesResponseEmptyUpdatedProperties:
  ## updatedProperties: [] (empty array) → Opt.some(@[]).
  let node = %*{
    "accountId": "acct1",
    "oldState": "s1",
    "newState": "s2",
    "hasMoreChanges": false,
    "created": [],
    "updated": [],
    "destroyed": [],
    "updatedProperties": [],
  }
  let res = MailboxChangesResponse.fromJson(node)
  doAssert res.isOk
  assertSome res.get().updatedProperties
  assertLen res.get().updatedProperties.get(), 0

# ===========================================================================
# C. addMailboxChanges builder tests (scenarios 70-71)
# ===========================================================================

block addMailboxChangesInvocationName:
  ## Scenario 70: produces "Mailbox/changes".
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxChanges(makeAccountId("a1"), makeState("s0"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnMailboxChanges

block addMailboxChangesCapability:
  ## Scenario 71: adds "urn:ietf:params:jmap:mail" to using.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxChanges(makeAccountId("a1"), makeState("s0"))
  let req = b1.build()
  assertLen req.`using`, 1
  assertEq req.`using`[0], "urn:ietf:params:jmap:mail"

# ===========================================================================
# D. addMailboxQuery builder tests (scenarios 72-74)
# ===========================================================================

block addMailboxQueryInvocationName:
  ## Scenario 72: produces "Mailbox/query".
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxQuery(makeAccountId("a1"), filterConditionToJson)
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnMailboxQuery

block addMailboxQuerySortAsTree:
  ## Scenario 73: sortAsTree = true → args{"sortAsTree"} == true.
  let b0 = initRequestBuilder()
  let (b1, _) =
    b0.addMailboxQuery(makeAccountId("a1"), filterConditionToJson, sortAsTree = true)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"sortAsTree"}.getBool(false) == true

block addMailboxQueryFilterAsTree:
  ## Scenario 74: filterAsTree = true → args{"filterAsTree"} == true.
  let b0 = initRequestBuilder()
  let (b1, _) =
    b0.addMailboxQuery(makeAccountId("a1"), filterConditionToJson, filterAsTree = true)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"filterAsTree"}.getBool(false) == true

block addMailboxQueryBothTreeParams:
  ## Both sortAsTree and filterAsTree set independently.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxQuery(
    makeAccountId("a1"), filterConditionToJson, sortAsTree = true, filterAsTree = true
  )
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"sortAsTree"}.getBool(false) == true
  doAssert args{"filterAsTree"}.getBool(false) == true

# ===========================================================================
# E. addMailboxQueryChanges builder tests (scenarios 75-76)
# ===========================================================================

block addMailboxQueryChangesInvocationName:
  ## Scenario 75: produces "Mailbox/queryChanges".
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxQueryChanges(
    makeAccountId("a1"), makeState("qs0"), filterConditionToJson
  )
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnMailboxQueryChanges

block addMailboxQueryChangesNoTreeParams:
  ## Scenario 76: no sortAsTree/filterAsTree in args (Decision B12).
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxQueryChanges(
    makeAccountId("a1"), makeState("qs0"), filterConditionToJson
  )
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"sortAsTree"}.isNil
  doAssert args{"filterAsTree"}.isNil

# ===========================================================================
# F. addMailboxSet builder tests (scenarios 77-79)
# ===========================================================================

block addMailboxSetInvocationName:
  ## Scenario 77: produces "Mailbox/set".
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxSet(makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnMailboxSet

block addMailboxSetOnDestroyRemoveEmails:
  ## Scenario 78: onDestroyRemoveEmails = true in args.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxSet(makeAccountId("a1"), onDestroyRemoveEmails = true)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"onDestroyRemoveEmails"}.getBool(false) == true

block addMailboxSetTypedCreate:
  ## Scenario 79: typed MailboxCreate serialised correctly.
  let mc = parseMailboxCreate("Inbox", role = Opt.some(roleInbox)).get()
  var tbl = initTable[CreationId, MailboxCreate]()
  tbl[makeCreationId("k0")] = mc
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxSet(makeAccountId("a1"), create = Opt.some(tbl))
  let req = b1.build()
  let createObj = req.methodCalls[0].arguments{"create"}
  doAssert createObj.kind == JObject
  let k0 = createObj{"k0"}
  doAssert k0.kind == JObject
  assertEq k0{"name"}.getStr(""), "Inbox"
  assertEq k0{"role"}.getStr(""), "inbox"

block addMailboxSetDefaultOnDestroy:
  ## onDestroyRemoveEmails at default (false) → always emitted.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxSet(makeAccountId("a1"))
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"onDestroyRemoveEmails"}.getBool(true) == false

# ===========================================================================
# G. addEmailGet builder tests (scenarios 75-76)
# ===========================================================================

block addEmailGetInvocationName:
  ## Scenario 75: produces "Email/get" with mail capability.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailGet(makeAccountId("a1"))
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnEmailGet
  doAssert "urn:ietf:params:jmap:mail" in req.`using`

block addEmailGetDefaultBodyFetch:
  ## Scenario 75: default EmailBodyFetchOptions produces no body-fetch keys.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailGet(makeAccountId("a1"))
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"fetchTextBodyValues"}.isNil
  doAssert args{"fetchHTMLBodyValues"}.isNil
  doAssert args{"fetchAllBodyValues"}.isNil
  doAssert args{"bodyProperties"}.isNil
  doAssert args{"maxBodyValueBytes"}.isNil

block addEmailGetWithBodyFetchOptions:
  ## Scenario 76: bvsText emits fetchTextBodyValues: true.
  let opts = EmailBodyFetchOptions(
    bodyProperties: Opt.none(seq[PropertyName]),
    fetchBodyValues: bvsText,
    maxBodyValueBytes: Opt.none(UnsignedInt),
  )
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailGet(makeAccountId("a1"), bodyFetchOptions = opts)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"fetchTextBodyValues"}.getBool(false) == true
  doAssert args{"fetchHTMLBodyValues"}.isNil
  doAssert args{"fetchAllBodyValues"}.isNil

# ===========================================================================
# H. addEmailQuery builder tests (scenarios 78-81)
# ===========================================================================

block addEmailQueryInvocationName:
  ## Scenario 78: produces "Email/query" with mail capability.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQuery(makeAccountId("a1"), filterConditionToJson)
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnEmailQuery
  doAssert "urn:ietf:params:jmap:mail" in req.`using`

block addEmailQueryCollapseThreadsTrue:
  ## Scenario 79: collapseThreads = true in args.
  let b0 = initRequestBuilder()
  let (b1, _) =
    b0.addEmailQuery(makeAccountId("a1"), filterConditionToJson, collapseThreads = true)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"collapseThreads"}.getBool(false) == true

block addEmailQueryCollapseThreadsDefault:
  ## Scenario 80: default collapseThreads = false always emitted.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQuery(makeAccountId("a1"), filterConditionToJson)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"collapseThreads"}.getBool(true) == false

block addEmailQueryWithSort:
  ## Scenario 81: EmailComparator sort serialised correctly.
  let comp = plainComparator(pspReceivedAt, isAscending = Opt.some(false))
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQuery(
    makeAccountId("a1"), filterConditionToJson, sort = Opt.some(@[comp])
  )
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  let sortArr = args{"sort"}
  doAssert not sortArr.isNil
  doAssert sortArr.kind == JArray
  assertLen sortArr.getElems(@[]), 1
  let sortObj = sortArr[0]
  assertEq sortObj{"property"}.getStr(""), "receivedAt"
  doAssert sortObj{"isAscending"}.getBool(true) == false

block addEmailQueryNoSort:
  ## sort: Opt.none → no sort key in args.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQuery(makeAccountId("a1"), filterConditionToJson)
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"sort"}.isNil

# ===========================================================================
# I. addEmailQueryChanges builder tests (scenarios 82-83)
# ===========================================================================

block addEmailQueryChangesInvocationName:
  ## Scenario 82: produces "Email/queryChanges" with mail capability.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQueryChanges(
    makeAccountId("a1"), makeState("qs0"), filterConditionToJson
  )
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnEmailQueryChanges
  doAssert "urn:ietf:params:jmap:mail" in req.`using`

block addEmailQueryChangesCollapseAndSort:
  ## Scenario 83: both collapseThreads and sort in args.
  let comp = plainComparator(pspSize)
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQueryChanges(
    makeAccountId("a1"),
    makeState("qs0"),
    filterConditionToJson,
    sort = Opt.some(@[comp]),
    collapseThreads = true,
  )
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  doAssert args{"collapseThreads"}.getBool(false) == true
  let sortArr = args{"sort"}
  doAssert not sortArr.isNil
  assertLen sortArr.getElems(@[]), 1
  assertEq sortArr[0]{"property"}.getStr(""), "size"

block addEmailQueryChangesSinceState:
  ## sinceQueryState appears in args.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailQueryChanges(
    makeAccountId("a1"), makeState("qs0"), filterConditionToJson
  )
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  assertEq args{"sinceQueryState"}.getStr(""), "qs0"

# ===========================================================================
# J. addEmailSet builder (Design §4.1)
# ===========================================================================

block addEmailSetFullInvocation:
  ## J.1: all four of ``create``, ``update``, ``destroy``, ``ifInState``
  ## populated — every operation key lands under the correct name, and
  ## the returned handle is phantom-typed to ``EmailSetResponse``.
  var createTbl = initTable[CreationId, EmailBlueprint]()
  createTbl[makeCreationId("k1")] = makeEmailBlueprint()
  var updateTbl = initTable[Id, EmailUpdateSet]()
  updateTbl[makeId("e1")] = initEmailUpdateSet(@[markRead()]).get()
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailSet(
    makeAccountId("a1"),
    ifInState = Opt.some(makeState("s0")),
    create = Opt.some(createTbl),
    update = Opt.some(updateTbl),
    destroy = Opt.some(direct(@[makeId("e9")])),
  )
  let req = b1.build()
  assertLen req.methodCalls, 1
  assertEq req.methodCalls[0].name, mnEmailSet
  assertLen req.`using`, 1
  assertEq req.`using`[0], "urn:ietf:params:jmap:mail"
  let args = req.methodCalls[0].arguments
  doAssert args{"create"}.kind == JObject
  doAssert args{"update"}.kind == JObject
  doAssert args{"destroy"}.kind == JArray
  assertEq args{"ifInState"}.getStr(""), "s0"

block addEmailSetMinimalAccountIdOnly:
  ## J.2: none of ``create`` / ``update`` / ``destroy`` / ``ifInState``
  ## populated → none of those keys appear on the wire (``isNil`` on
  ## safe access). ``accountId`` is the only invariant. Pins F1 §4.1.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailSet(makeAccountId("a1"))
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  assertEq args{"accountId"}.getStr(""), "a1"
  doAssert args{"create"}.isNil
  doAssert args{"update"}.isNil
  doAssert args{"destroy"}.isNil
  doAssert args{"ifInState"}.isNil

block addEmailSetIfInStateEmitted:
  ## J.3: ``ifInState: Opt.some`` → key present with exact state string.
  let b0 = initRequestBuilder()
  let (b1, _) =
    b0.addEmailSet(makeAccountId("a1"), ifInState = Opt.some(makeState("s0")))
  let req = b1.build()
  assertEq req.methodCalls[0].arguments{"ifInState"}.getStr(""), "s0"

block addEmailSetIfInStateOmittedWhenNone:
  ## J.4: ``ifInState: Opt.none`` (default) → omit the key entirely,
  ## never emit JSON ``null``. Negative counterpart to J.3.
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailSet(makeAccountId("a1"))
  let req = b1.build()
  doAssert req.methodCalls[0].arguments{"ifInState"}.isNil

block addEmailSetTypedUpdate:
  ## J.5: typed ``EmailUpdateSet`` with ``markRead()`` flattens to the
  ## RFC 8620 §5.3 wire patch ``{"keywords/$seen": true}`` via
  ## ``toJson(EmailUpdateSet)`` at the builder boundary. End-to-end pin
  ## that the typed update algebra reaches the wire through the builder
  ## (Design §4.1, Part F2).
  let updateSet = initEmailUpdateSet(@[markRead()]).get()
  var tbl = initTable[Id, EmailUpdateSet]()
  tbl[makeId("e1")] = updateSet
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailSet(makeAccountId("a1"), update = Opt.some(tbl))
  let req = b1.build()
  let patch = req.methodCalls[0].arguments{"update"}{"e1"}
  doAssert patch.kind == JObject
  doAssert patch{"keywords/$seen"}.getBool(false) == true

# ===========================================================================
# K. addEmailCopy simple overload (Design §5.3)
# ===========================================================================

block addEmailCopyPhantomType:
  ## K.1: ``addEmailCopy`` (simple overload) returns a handle typed to
  ## ``EmailCopyResponse`` and never emits ``onSuccessDestroyOriginal``
  ## (that key belongs to the compound ``addEmailCopyAndDestroy``).
  var createTbl = initTable[CreationId, EmailCopyItem]()
  createTbl[makeCreationId("k1")] = makeEmailCopyItem()
  let b0 = initRequestBuilder()
  let (b1, handle) =
    b0.addEmailCopy(makeAccountId("src"), makeAccountId("dst"), createTbl)
  let req = b1.build()
  assertEq req.methodCalls[0].name, mnEmailCopy
  doAssert req.methodCalls[0].arguments{"onSuccessDestroyOriginal"}.isNil
  # Phantom-type pin: binding to a mismatched ``ResponseHandle`` parameter
  # must not compile. Scoped narrowly to a single assignment so unrelated
  # compile errors can't be laundered through this gate.
  assertNotCompiles:
    let badHandle: ResponseHandle[EmailSetResponse] = handle

block addEmailCopyIfInStateEmittedWithCopySemantics:
  ## K.2: ``ifInState`` (destination state) emitted with exact value;
  ## the simple overload has no ``destroyFromIfInState`` parameter, so
  ## that key is never present on the wire.
  var createTbl = initTable[CreationId, EmailCopyItem]()
  createTbl[makeCreationId("k1")] = makeEmailCopyItem()
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailCopy(
    makeAccountId("src"),
    makeAccountId("dst"),
    createTbl,
    ifInState = Opt.some(makeState("dst0")),
  )
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  assertEq args{"ifInState"}.getStr(""), "dst0"
  doAssert args{"destroyFromIfInState"}.isNil

# ===========================================================================
# L. addEmailCopyAndDestroy compound overload (Design §5.3, §5.4)
# ===========================================================================

block addEmailCopyAndDestroyEmitsTrue:
  ## L.1: compound overload emits ``onSuccessDestroyOriginal: true`` and
  ## returns an ``EmailCopyHandles`` where the destroy handle carries
  ## ``methodName == mnEmailSet`` and copy/destroy share a single
  ## ``MethodCallId`` per RFC 8620 §5.4 (mandatory pins from F2 §8.12).
  var createTbl = initTable[CreationId, EmailCopyItem]()
  createTbl[makeCreationId("k1")] = makeEmailCopyItem()
  let b0 = initRequestBuilder()
  let (b1, handles) =
    b0.addEmailCopyAndDestroy(makeAccountId("src"), makeAccountId("dst"), createTbl)
  let req = b1.build()
  doAssert req.methodCalls[0].arguments{"onSuccessDestroyOriginal"}.getBool(false) ==
    true
  assertEq handles.destroy.methodName, mnEmailSet
  assertEq handles.destroy.callId, handles.copy.callId()

block addEmailCopyAndDestroyDestroyFromIfInStateSome:
  ## L.2: ``destroyFromIfInState: Opt.some`` → key emitted with value.
  var createTbl = initTable[CreationId, EmailCopyItem]()
  createTbl[makeCreationId("k1")] = makeEmailCopyItem()
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailCopyAndDestroy(
    makeAccountId("src"),
    makeAccountId("dst"),
    createTbl,
    destroyFromIfInState = Opt.some(makeState("src0")),
  )
  let req = b1.build()
  assertEq req.methodCalls[0].arguments{"destroyFromIfInState"}.getStr(""), "src0"

block addEmailCopyAndDestroyDestroyFromIfInStateNone:
  ## L.3: ``destroyFromIfInState: Opt.none`` (default) → omit the key,
  ## never emit JSON ``null``.
  var createTbl = initTable[CreationId, EmailCopyItem]()
  createTbl[makeCreationId("k1")] = makeEmailCopyItem()
  let b0 = initRequestBuilder()
  let (b1, _) =
    b0.addEmailCopyAndDestroy(makeAccountId("src"), makeAccountId("dst"), createTbl)
  let req = b1.build()
  doAssert req.methodCalls[0].arguments{"destroyFromIfInState"}.isNil

block addEmailCopyAndDestroyAllStateParamsSome:
  ## L.4: all three state parameters (``ifFromInState``, ``ifInState``,
  ## ``destroyFromIfInState``) populated with distinct values → each
  ## appears under its own key; no aliasing, no silent drop.
  var createTbl = initTable[CreationId, EmailCopyItem]()
  createTbl[makeCreationId("k1")] = makeEmailCopyItem()
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addEmailCopyAndDestroy(
    makeAccountId("src"),
    makeAccountId("dst"),
    createTbl,
    ifFromInState = Opt.some(makeState("ff0")),
    ifInState = Opt.some(makeState("fi0")),
    destroyFromIfInState = Opt.some(makeState("df0")),
  )
  let req = b1.build()
  let args = req.methodCalls[0].arguments
  assertEq args{"ifFromInState"}.getStr(""), "ff0"
  assertEq args{"ifInState"}.getStr(""), "fi0"
  assertEq args{"destroyFromIfInState"}.getStr(""), "df0"

# ===========================================================================
# M. getBoth dispatch (Design §5.4)
# ===========================================================================

block getBothCopyAndDestroyHappyPath:
  ## M.1: well-formed copy + well-formed destroy invocations at the
  ## shared call-id decode via ``resp.getBoth(handles)`` to the paired
  ## ``EmailCopyResults``. Mirrors the ``tconvenience.nim:134`` precedent.
  let cid = makeMcid("c0")
  let handles = makeEmailCopyHandles(cid)
  let copyResp = makeEmailCopyResponse(
    fromAccountId = makeAccountId("src"),
    accountId = makeAccountId("dst"),
    newState = makeState("ns1"),
  )
  let setResp =
    makeEmailSetResponse(accountId = makeAccountId("dst"), newState = makeState("ns2"))
  let resp = Response(
    methodResponses: @[
      initInvocation(mnEmailCopy, copyResp.toJson(), cid),
      initInvocation(mnEmailSet, setResp.toJson(), cid),
    ],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let results = resp.getBoth(handles)
  assertOk results
  let r = results.get()
  assertEq r.copy.accountId, makeAccountId("dst")
  assertEq r.destroy.accountId, makeAccountId("dst")

block getBothShortCircuitOnCopyError:
  ## M.2: copy-side ``MethodError`` short-circuits ``getBoth`` before
  ## destroy is consulted — the typed variant survives round-trip for
  ## every ``MethodErrorType`` variant applicable to Email/copy per
  ## RFC 8621 §4.7. Mirrors the ``tconvenience.nim:154`` precedent.
  const applicable = {
    metStateMismatch, metFromAccountNotFound, metFromAccountNotSupportedByMethod,
    metServerFail, metForbidden, metAccountNotFound, metAccountReadOnly,
  }
  for variant in MethodErrorType:
    if variant notin applicable:
      continue
    let cid = makeMcid("c0")
    let handles = makeEmailCopyHandles(cid)
    let errInv = makeErrorInvocation(cid, $variant)
    let setInv = initInvocation(mnEmailSet, makeEmailSetResponse().toJson(), cid)
    let resp = Response(
      methodResponses: @[errInv, setInv],
      createdIds: Opt.none(Table[CreationId, Id]),
      sessionState: makeState("rs1"),
    )
    let results = resp.getBoth(handles)
    doAssert results.isErr, "variant " & $variant & " should short-circuit"
    assertEq results.error.errorType, variant

block getBothShortCircuitOnDestroyMissing:
  ## M.3: well-formed copy + NO Email/set invocation at the shared cid
  ## → ``getBoth`` returns a ``serverFail`` ``MethodError`` with the
  ## "no Email/set response for call ID ..." description per the shipped
  ## dispatch semantics at ``dispatch.nim:161-167``.
  let cid = makeMcid("c0")
  let handles = makeEmailCopyHandles(cid)
  let copyResp = makeEmailCopyResponse()
  let resp = Response(
    methodResponses: @[initInvocation(mnEmailCopy, copyResp.toJson(), cid)],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let results = resp.getBoth(handles)
  doAssert results.isErr
  assertEq results.error.rawType, "serverFail"
  assertSomeEq results.error.description, "no Email/set response for call ID c0"

block getBothShortCircuitOnDestroyError:
  ## M.4: well-formed copy + an "error" invocation at the shared cid
  ## (wire name ``"error"``, not ``"Email/set"``) → the name-filtered
  ## dispatch of ``NameBoundHandle`` rejects "error" invocations, so
  ## ``getBoth`` surfaces the missing-response ``serverFail`` rather
  ## than the injected error type. Pins ``dispatch.nim:158-184`` name-
  ## filter semantics: a destroy failure is invisible at the destroy
  ## slot because the server's error wire tag is always ``"error"``.
  let cid = makeMcid("c0")
  let handles = makeEmailCopyHandles(cid)
  let copyResp = makeEmailCopyResponse()
  let errInv = makeErrorInvocation(cid, "serverFail")
  let resp = Response(
    methodResponses: @[initInvocation(mnEmailCopy, copyResp.toJson(), cid), errInv],
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("rs1"),
  )
  let results = resp.getBoth(handles)
  doAssert results.isErr
  assertEq results.error.rawType, "serverFail"
  assertSomeEq results.error.description, "no Email/set response for call ID c0"

# ===========================================================================
# N. addMailboxSet typed-update migration (Design §3.3)
# ===========================================================================

block addMailboxSetTypedUpdate:
  ## N.1: typed ``MailboxUpdateSet`` with a single ``setName("Renamed")``
  ## flattens to ``{"name": "Renamed"}`` via ``toJson(MailboxUpdateSet)``
  ## at the builder boundary. Pins the migrated ``addMailboxSet`` signature
  ## routing through the typed algebra (Design §3.3).
  let updateSet = initMailboxUpdateSet(@[setName("Renamed")]).get()
  var tbl = initTable[Id, MailboxUpdateSet]()
  tbl[makeId("mb1")] = updateSet
  let b0 = initRequestBuilder()
  let (b1, _) = b0.addMailboxSet(makeAccountId("a1"), update = Opt.some(tbl))
  let req = b1.build()
  let patch = req.methodCalls[0].arguments{"update"}{"mb1"}
  doAssert patch.kind == JObject
  assertEq patch{"name"}.getStr(""), "Renamed"

block addMailboxSetEmptyUpdateSetRejectedAtConstruction:
  ## N.2: ``initMailboxUpdateSet(@[])`` returns ``Err`` — the builder is
  ## never reached. Pins the construction-level empty rejection at the
  ## protocol layer; the wire boundary cannot be crossed with an empty
  ## update-set (F22 invariant).
  let res = initMailboxUpdateSet(newSeq[MailboxUpdate]())
  assertErr res
