# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for EmailSetResponse, EmailCreatedItem, and UpdatedEntry
## (F2 §8.3 response-decode row, §8.12 coverage matrix). Pins the eight-field
## envelope shape, the ``created`` / ``notCreated`` → ``createResults`` merge,
## RFC 8620 §5.3 ``updated`` / ``destroyed`` three-state semantics, and the
## ``UpdatedEntry`` null-vs-empty distinctness that a single ``Opt[JsonNode]``
## would collapse.

{.push raises: [].}

import std/json
import std/tables

import jmap_client/mail/email
import jmap_client/mail/serde_email
import jmap_client/errors
import jmap_client/identifiers
import jmap_client/primitives
import jmap_client/serde
import jmap_client/validation

import ../../massertions
import ../../mfixtures

# ============= A. EmailSetResponse.fromJson eight-field shape =============

block emailSetResponseEightFieldShape:
  let node = %*{
    "accountId": "acct1",
    "oldState": "s0",
    "newState": "s1",
    "created": {"k0": {"id": "e1", "blobId": "b1", "threadId": "t1", "size": 100}},
    "notCreated": {"k1": {"type": "invalidProperties"}},
    "updated": {"e2": nil},
    "destroyed": ["e3"],
    "notUpdated": {"e4": {"type": "serverFail"}},
    "notDestroyed": {"e5": {"type": "serverFail"}},
  }
  let res = EmailSetResponse.fromJson(node)
  assertOk res
  let r = res.get()
  assertEq r.accountId, makeAccountId("acct1")
  assertSomeEq r.oldState, makeState("s0")
  assertEq r.newState, makeState("s1")
  assertLen r.createResults, 2
  assertSome r.updated
  assertSome r.destroyed
  assertSome r.notUpdated
  assertSome r.notDestroyed

block emailSetResponseMergeCreatedResults:
  ## ``mergeCreatedResults`` (serde_email.nim) fans the wire's separate
  ## ``created`` and ``notCreated`` maps into a single
  ## ``Table[CreationId, Result[EmailCreatedItem, SetError]]`` — one Ok
  ## entry per ``created`` key, one Err per ``notCreated`` key.
  let node = %*{
    "accountId": "acct1",
    "newState": "s1",
    "created": {"k0": {"id": "e1", "blobId": "b1", "threadId": "t1", "size": 100}},
    "notCreated": {"k1": {"type": "invalidProperties"}},
  }
  let r = EmailSetResponse.fromJson(node).get()
  assertLen r.createResults, 2
  let kOk = makeCreationId("k0")
  let kErr = makeCreationId("k1")
  doAssert kOk in r.createResults, "expected k0 merged from created"
  doAssert kErr in r.createResults, "expected k1 merged from notCreated"
  doAssert r.createResults[kOk].isOk, "k0 must be Ok"
  doAssert r.createResults[kErr].isErr, "k1 must be Err"
  assertEq r.createResults[kOk].get().id, makeId("e1")

# ============= B. EmailCreatedItem.fromJson =============

block emailCreatedItemMinimalConstruction:
  let node = %*{"id": "e1", "blobId": "b1", "threadId": "t1", "size": 42}
  let res = EmailCreatedItem.fromJson(node)
  assertOk res
  let item = res.get()
  assertEq item.id, makeId("e1")
  assertEq item.blobId, makeBlobId("b1")
  assertEq item.threadId, makeId("t1")
  assertEq item.size, parseUnsignedInt(42).get()

block emailCreatedItemMissingSizeRejected:
  ## Per RFC 8621 §§4.6/4.7/4.8 the server MUST emit all four fields on a
  ## successful create; a server omitting ``size`` has produced a malformed
  ## response and we reject at the parser rather than defaulting silently.
  let node = %*{"id": "e1", "blobId": "b1", "threadId": "t1"}
  assertSvKind EmailCreatedItem.fromJson(node), svkMissingField

# ============= C. ``updated`` three-state =============

block updatedTopLevelAbsent:
  let node = %*{"accountId": "acct1", "newState": "s1"}
  let r = EmailSetResponse.fromJson(node).get()
  assertNone r.updated

block updatedTopLevelNull:
  let node = %*{"accountId": "acct1", "newState": "s1", "updated": nil}
  let r = EmailSetResponse.fromJson(node).get()
  assertNone r.updated

block updatedTopLevelEmptyObject:
  ## ``{}`` is distinct from ``null`` / absent — it is the server signalling
  ## "I considered the update map and it is empty", not "I have no updated
  ## map". Pin this separately from the three-state above.
  let node = %*{"accountId": "acct1", "newState": "s1", "updated": {}}
  let r = EmailSetResponse.fromJson(node).get()
  assertSome r.updated
  assertEq r.updated.get().len, 0

# ============= D. ``destroyed`` three-state =============

block destroyedAbsent:
  let node = %*{"accountId": "acct1", "newState": "s1"}
  let r = EmailSetResponse.fromJson(node).get()
  assertNone r.destroyed

block destroyedEmptyArray:
  let node = %*{"accountId": "acct1", "newState": "s1", "destroyed": []}
  let r = EmailSetResponse.fromJson(node).get()
  assertSome r.destroyed
  assertEq r.destroyed.get().len, 0

block destroyedTwoElement:
  let node = %*{"accountId": "acct1", "newState": "s1", "destroyed": ["id1", "id2"]}
  let r = EmailSetResponse.fromJson(node).get()
  assertSome r.destroyed
  let ids = r.destroyed.get()
  assertLen ids, 2
  assertEq ids[0], makeId("id1")
  assertEq ids[1], makeId("id2")

# ============= E. UpdatedEntry distinctness =============

block updatedEntryNullVsEmptyDistinct:
  ## RFC 8620 §5.3 ``Foo|null``: wire ``null`` is "no changes you don't
  ## already know about" (``uekUnchanged``), while wire ``{}`` is "the
  ## server altered something but the changed-property map happens to be
  ## empty" (``uekChanged``). These are DIFFERENT domain facts; a single
  ## ``Opt[JsonNode]`` would collapse them.
  let unchanged = UpdatedEntry.fromJson(newJNull()).get()
  let changed = UpdatedEntry.fromJson(newJObject()).get()
  doAssert unchanged.kind == uekUnchanged
  doAssert changed.kind == uekChanged
  doAssert unchanged.kind != changed.kind

# ============= F. Round-trip =============

block emailSetResponseRoundTrip:
  var cr = initTable[CreationId, Result[EmailCreatedItem, SetError]]()
  let item = EmailCreatedItem(
    id: makeId("e1"), blobId: makeBlobId("b1"), threadId: makeId("t1"), size: zeroUint()
  )
  cr[makeCreationId("k0")] = Result[EmailCreatedItem, SetError].ok(item)
  cr[makeCreationId("k1")] =
    Result[EmailCreatedItem, SetError].err(makeSetErrorInvalidProperties(@["subject"]))
  let original = makeEmailSetResponse(
    accountId = makeAccountId("acct1"),
    oldState = Opt.some(makeState("s0")),
    newState = makeState("s1"),
    createResults = cr,
  )
  let node = original.toJson()
  let reparsed = EmailSetResponse.fromJson(node).get()
  assertEq reparsed.accountId, original.accountId
  assertEq reparsed.newState, original.newState
  assertEq reparsed.oldState, original.oldState
  assertLen reparsed.createResults, 2
  doAssert makeCreationId("k0") in reparsed.createResults
  doAssert makeCreationId("k1") in reparsed.createResults
  doAssert reparsed.createResults[makeCreationId("k0")].isOk
  doAssert reparsed.createResults[makeCreationId("k1")].isErr
  assertEq reparsed.createResults[makeCreationId("k0")].get().id, item.id
