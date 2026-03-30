# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Integration test: verifies all toJson/fromJson pairs are accessible
## through the single jmap_client/serialisation import.

import std/json
import std/sets

import results

import jmap_client/serialisation
import jmap_client/types

import ../massertions
import ../mfixtures

# =============================================================================
# A. Shared helpers (from serde)
# =============================================================================

block sharedHelpers:
  let e = parseError("Test", "msg")
  doAssert e.typeName == "Test"

  {.cast(noSideEffect).}:
    let node = %*{"a": 1, "extra": 2}
    let extras = collectExtras(node, ["a"])
    assertSome extras

# =============================================================================
# B. Primitive and identifier round-trips (from serde)
# =============================================================================

block primitiveRoundTrips:
  let id = makeId()
  assertOkEq Id.fromJson(id.toJson()), id

  let aid = makeAccountId()
  assertOkEq AccountId.fromJson(aid.toJson()), aid

  let state = makeState()
  assertOkEq JmapState.fromJson(state.toJson()), state

  let mcid = makeMcid()
  assertOkEq MethodCallId.fromJson(mcid.toJson()), mcid

  let cid = makeCreationId()
  assertOkEq CreationId.fromJson(cid.toJson()), cid

  let tmpl = makeUriTemplate()
  assertOkEq UriTemplate.fromJson(tmpl.toJson()), tmpl

  let pn = makePropertyName()
  assertOkEq PropertyName.fromJson(pn.toJson()), pn

  let d = parseDate("2014-10-30T14:12:00+08:00").get()
  assertOkEq Date.fromJson(d.toJson()), d

  let ud = parseUtcDate("2014-10-30T06:12:00Z").get()
  assertOkEq UTCDate.fromJson(ud.toJson()), ud

  let ui = zeroUint()
  assertOkEq UnsignedInt.fromJson(ui.toJson()), ui

  let ji = parseJmapInt(42).get()
  assertOkEq JmapInt.fromJson(ji.toJson()), ji

# =============================================================================
# C. Session types (from serde_session)
# =============================================================================

block sessionTypes:
  let caps = zeroCoreCaps()
  assertOkEq CoreCapabilities.fromJson(caps.toJson()), caps

  let acct =
    Account(name: "test", isPersonal: true, isReadOnly: false, accountCapabilities: @[])
  assertOkEq Account.fromJson(acct.toJson()), acct

# =============================================================================
# D. Envelope types (from serde_envelope)
# =============================================================================

block envelopeTypes:
  let inv = makeInvocation()
  assertOkEq Invocation.fromJson(inv.toJson()), inv

  let rref = makeResultReference()
  assertOkEq ResultReference.fromJson(rref.toJson()), rref

  let req = makeRequest()
  assertOk Request.fromJson(req.toJson())

  let resp = makeResponse()
  assertOk Response.fromJson(resp.toJson())

  let key = referencableKey("ids", direct(42))
  doAssert key == "ids"

# =============================================================================
# E. Framework types (from serde_framework)
# =============================================================================

block frameworkTypes:
  assertOkEq FilterOperator.fromJson(foAnd.toJson()), foAnd

  let comp = makeComparator()
  assertOk Comparator.fromJson(comp.toJson())

  let patch = emptyPatch()
  assertOk PatchObject.fromJson(patch.toJson())

  let item = makeAddedItem()
  assertOk AddedItem.fromJson(item.toJson())

# =============================================================================
# F. Error types (from serde_errors)
# =============================================================================

block errorTypes:
  let re = makeRequestError()
  assertOkEq RequestError.fromJson(re.toJson()), re

  let me = makeMethodError()
  assertOkEq MethodError.fromJson(me.toJson()), me

  let se = setError("forbidden")
  assertOk SetError.fromJson(se.toJson())

# =============================================================================
# G. Consolidated initResultErr accessible (from serde)
# =============================================================================

block initResultErrAccessible:
  ## Verify initResultErr is importable through serialisation hub.
  let r = initResultErr[int, ValidationError](validationError("Test", "test error", ""))
  assertErr r
  assertEq r.error.typeName, "Test"

# =============================================================================
# H. All type pairs accessible — comprehensive verification
# =============================================================================

block allTypePairsAccessible:
  ## Every toJson/fromJson pair callable through the serialisation re-export.
  # ServerCapability (requires uri parameter)
  {.cast(noSideEffect).}:
    let capData = newJObject()
    let cap = ServerCapability.fromJson("urn:ietf:params:jmap:mail", capData)
    assertOk cap
    discard cap.get().toJson()
  # AccountCapabilityEntry (requires uri parameter)
  {.cast(noSideEffect).}:
    let entry =
      AccountCapabilityEntry.fromJson("urn:ietf:params:jmap:mail", newJObject())
    assertOk entry
    discard entry.get().toJson()
  # Session (full round-trip via golden JSON)
  let sj = goldenSessionJson()
  let session = Session.fromJson(sj)
  assertOk session
  discard session.get().toJson()
