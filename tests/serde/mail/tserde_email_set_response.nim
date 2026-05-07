# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Serde tests for the Email/set response (now ``SetResponse[EmailCreatedItem]``
## after the generic-typed createResults promotion) and ``EmailCreatedItem``.
## Pins the merged ``createResults`` / ``updateResults`` / ``destroyResults``
## shape, RFC 8620 §5.3 ``Foo|null`` three-state semantics now encoded as
## ``Opt[JsonNode]`` inside ``Result[_, SetError]``, and the create-merge
## algorithm.

{.push raises: [].}

import std/json
import std/tables

import jmap_client/internal/mail/email
import jmap_client/internal/mail/serde_email
import jmap_client/internal/protocol/methods
import jmap_client/internal/types/errors
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/primitives
import jmap_client/internal/serialisation/serde
import jmap_client/internal/types/validation

import ../../massertions
import ../../mfixtures

# ============= A. SetResponse[EmailCreatedItem].fromJson envelope shape =====

block setResponseEmailEnvelopeShape:
  ## Wire envelope merges to a six-field record: accountId, oldState,
  ## newState, createResults, updateResults, destroyResults.
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
  let res = SetResponse[EmailCreatedItem].fromJson(node)
  assertOk res
  let r = res.get()
  assertEq r.accountId, makeAccountId("acct1")
  assertSomeEq r.oldState, makeState("s0")
  assertSomeEq r.newState, makeState("s1")
  assertLen r.createResults, 2
  # updateResults merges wire updated + notUpdated.
  assertLen r.updateResults, 2
  doAssert r.updateResults[makeId("e2")].isOk
  doAssert r.updateResults[makeId("e4")].isErr
  # destroyResults merges wire destroyed + notDestroyed.
  assertLen r.destroyResults, 2
  doAssert r.destroyResults[makeId("e3")].isOk
  doAssert r.destroyResults[makeId("e5")].isErr

block setResponseEmailMergeCreateResults:
  ## ``mergeCreateResults[EmailCreatedItem]`` (methods.nim) fans the wire's
  ## separate ``created`` and ``notCreated`` maps into a single
  ## ``Table[CreationId, Result[EmailCreatedItem, SetError]]``: one Ok per
  ## ``created`` key (parsed via ``EmailCreatedItem.fromJson``) and one Err
  ## per ``notCreated`` key.
  let node = %*{
    "accountId": "acct1",
    "newState": "s1",
    "created": {"k0": {"id": "e1", "blobId": "b1", "threadId": "t1", "size": 100}},
    "notCreated": {"k1": {"type": "invalidProperties"}},
  }
  let r = SetResponse[EmailCreatedItem].fromJson(node).get()
  assertLen r.createResults, 2
  let kOk = makeCreationId("k0")
  let kErr = makeCreationId("k1")
  doAssert kOk in r.createResults, "expected k0 merged from created"
  doAssert kErr in r.createResults, "expected k1 merged from notCreated"
  doAssert r.createResults[kOk].isOk, "k0 must be Ok"
  doAssert r.createResults[kErr].isErr, "k1 must be Err"
  assertEq r.createResults[kOk].get().id, makeId("e1")

# ============= B. EmailCreatedItem.fromJson =================================

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

# ============= C. ``updated`` three-state inside the merged map =============

block updatedTopLevelAbsentProducesEmpty:
  ## Wire ``updated`` absent → empty ``updateResults`` table.
  let node = %*{"accountId": "acct1", "newState": "s1"}
  let r = SetResponse[EmailCreatedItem].fromJson(node).get()
  assertLen r.updateResults, 0

block updatedTopLevelEmptyObjectProducesEmpty:
  ## Wire ``updated: {}`` → empty ``updateResults`` table; the merged
  ## representation does not distinguish absent from empty-object at the
  ## map level (RFC 8620 §5.3 ``Id[Foo|null]|null`` outer Opt).
  let node = %*{"accountId": "acct1", "newState": "s1", "updated": {}}
  let r = SetResponse[EmailCreatedItem].fromJson(node).get()
  assertLen r.updateResults, 0

block updatedEntryNullVsEmptyObjectDistinct:
  ## RFC 8620 §5.3 ``Foo|null`` inner split survives the merge:
  ## wire ``{id: null}`` → ``ok(Opt.none(JsonNode))`` (server made no
  ## changes the client doesn't already know);
  ## wire ``{id: {}}`` → ``ok(Opt.some(empty JObject))`` (server altered
  ## something, the changed-property map is just empty). The two encodings
  ## stay distinct on the Ok rail.
  let nullNode = %*{"accountId": "acct1", "newState": "s1", "updated": {"e2": nil}}
  let emptyNode = %*{"accountId": "acct1", "newState": "s1", "updated": {"e2": {}}}
  let rNull = SetResponse[EmailCreatedItem].fromJson(nullNode).get()
  let rEmpty = SetResponse[EmailCreatedItem].fromJson(emptyNode).get()
  let id = makeId("e2")
  doAssert rNull.updateResults[id].isOk
  doAssert rNull.updateResults[id].get().isNone
  doAssert rEmpty.updateResults[id].isOk
  doAssert rEmpty.updateResults[id].get().isSome
  doAssert rEmpty.updateResults[id].get().get().kind == JObject
  doAssert rEmpty.updateResults[id].get().get().len == 0

# ============= D. ``destroyed`` three-state inside the merged map ===========

block destroyedAbsentProducesEmpty:
  let node = %*{"accountId": "acct1", "newState": "s1"}
  let r = SetResponse[EmailCreatedItem].fromJson(node).get()
  assertLen r.destroyResults, 0

block destroyedEmptyArrayProducesEmpty:
  let node = %*{"accountId": "acct1", "newState": "s1", "destroyed": []}
  let r = SetResponse[EmailCreatedItem].fromJson(node).get()
  assertLen r.destroyResults, 0

block destroyedTwoElementProducesTwoOks:
  let node = %*{"accountId": "acct1", "newState": "s1", "destroyed": ["id1", "id2"]}
  let r = SetResponse[EmailCreatedItem].fromJson(node).get()
  assertLen r.destroyResults, 2
  doAssert r.destroyResults[makeId("id1")].isOk
  doAssert r.destroyResults[makeId("id2")].isOk

# ============= E. Round-trip =================================================

block setResponseEmailRoundTrip:
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
    newState = Opt.some(makeState("s1")),
    createResults = cr,
  )
  let node = original.toJson()
  let reparsed = SetResponse[EmailCreatedItem].fromJson(node).get()
  assertEq reparsed.accountId, original.accountId
  assertEq reparsed.newState, original.newState
  assertEq reparsed.oldState, original.oldState
  assertLen reparsed.createResults, 2
  doAssert makeCreationId("k0") in reparsed.createResults
  doAssert makeCreationId("k1") in reparsed.createResults
  doAssert reparsed.createResults[makeCreationId("k0")].isOk
  doAssert reparsed.createResults[makeCreationId("k1")].isErr
  assertEq reparsed.createResults[makeCreationId("k0")].get().id, item.id
