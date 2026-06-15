# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Tests for the six ergonomic projection iterators over ``SetResponse[T, U]``
## (``created`` / ``createFailures`` / ``updated`` / ``updateFailures`` /
## ``destroyed`` / ``destroyFailures``). Each success/failure pair must
## partition its underlying typed three-rail table — the iterators surface
## the common read path while the ``Result``-valued tables stay for callers
## consuming the RFC 8620 §5.3 SetError rail. ``updated`` additionally
## carries the ``Opt[U]`` server-changed-property echo, exercised here with
## both a ``some`` and a ``none`` entry.
##
## This file deliberately avoids the ``massertions`` / ``mfixtures`` harness:
## both are currently uncompilable on this branch (``mfixtures.makeEmail``
## assigns ``headers: @[]`` to the now-``Opt[seq[EmailHeader]]`` field), a
## pre-existing breakage outside this change's scope. ``mtestblock`` is clean
## and is used; values come from L1 smart constructors directly.

{.push raises: [].}

import std/sets
import std/tables

import results

import jmap_client/internal/protocol/methods
import jmap_client/internal/types/errors
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/primitives

import ../mtestblock

proc cid(s: string): CreationId =
  ## Build a CreationId from a literal (test helper).
  parseCreationId(s).get()

proc eid(s: string): Id =
  ## Build an Id from a literal (test helper).
  parseId(s).get()

proc setErr(props: seq[string]): SetError =
  ## Build an invalidProperties SetError over the given property names.
  setErrorInvalidProperties("invalidProperties", props)

# T and U are arbitrary here: the iterators only walk the tables and never
# resolve ``fromJson``/``toJson``, so ``int`` is the simplest instantiation
# that compiles. The SetResponse is built directly via the object
# constructor rather than through the wire parser.

proc fixture(): SetResponse[int, int] =
  ## A SetResponse[int, int] with mixed ok/err entries on all three rails
  ## (create/update/destroy), including an Opt.some and an Opt.none update echo.
  var createResults = initTable[CreationId, Result[int, SetError]]()
  createResults[cid("c-ok-1")] = Result[int, SetError].ok(10)
  createResults[cid("c-ok-2")] = Result[int, SetError].ok(20)
  createResults[cid("c-err")] = Result[int, SetError].err(setErr(@["name"]))

  var updateResults = initTable[Id, Result[Opt[int], SetError]]()
  updateResults[eid("u-echo")] = Result[Opt[int], SetError].ok(Opt.some(100))
  updateResults[eid("u-noecho")] = Result[Opt[int], SetError].ok(Opt.none(int))
  updateResults[eid("u-err")] = Result[Opt[int], SetError].err(setErr(@["subject"]))

  var destroyResults = initTable[Id, Result[void, SetError]]()
  destroyResults[eid("d-ok-1")] = Result[void, SetError].ok()
  destroyResults[eid("d-ok-2")] = Result[void, SetError].ok()
  destroyResults[eid("d-err")] = Result[void, SetError].err(setErr(@["foo"]))

  SetResponse[int, int](
    accountId: parseAccountId("acct1").get(),
    oldState: Opt.none(JmapState),
    newState: Opt.none(JmapState),
    createResults: createResults,
    updateResults: updateResults,
    destroyResults: destroyResults,
  )

# --- created vs createFailures partition createResults ---

testCase createdYieldsSuccessfulCreates:
  let resp = fixture()
  var got = initTable[CreationId, int]()
  for k, v in resp.created:
    got[k] = v
  doAssert got.len == 2
  doAssert got[cid("c-ok-1")] == 10
  doAssert got[cid("c-ok-2")] == 20
  doAssert cid("c-err") notin got, "failure key must not appear in created"

testCase createFailuresYieldsNotCreated:
  let resp = fixture()
  var got = initTable[CreationId, SetError]()
  for k, e in resp.createFailures:
    got[k] = e
  doAssert got.len == 1
  doAssert cid("c-err") in got, "expected the err key on createFailures"
  doAssert got[cid("c-err")].kind == setInvalidProperties

testCase createPartitionIsExhaustive:
  let resp = fixture()
  var createdCount = 0
  for _, _ in resp.created:
    inc createdCount
  var failCount = 0
  for _, _ in resp.createFailures:
    inc failCount
  doAssert createdCount + failCount == resp.createResults.len

# --- updated (with serverEcho) vs updateFailures partition updateResults ---

testCase updatedYieldsServerEcho:
  let resp = fixture()
  var got = initTable[Id, Opt[int]]()
  for k, echoVal in resp.updated:
    got[k] = echoVal
  doAssert got.len == 2
  doAssert eid("u-echo") in got
  doAssert eid("u-noecho") in got
  doAssert got[eid("u-echo")].isSome
  doAssert got[eid("u-echo")].get() == 100
  doAssert got[eid("u-noecho")].isNone
  doAssert eid("u-err") notin got, "failure key must not appear in updated"

testCase updateFailuresYieldsNotUpdated:
  let resp = fixture()
  var got = initTable[Id, SetError]()
  for k, e in resp.updateFailures:
    got[k] = e
  doAssert got.len == 1
  doAssert eid("u-err") in got
  doAssert got[eid("u-err")].kind == setInvalidProperties

testCase updatePartitionIsExhaustive:
  let resp = fixture()
  var updatedCount = 0
  for _, _ in resp.updated:
    inc updatedCount
  var failCount = 0
  for _, _ in resp.updateFailures:
    inc failCount
  doAssert updatedCount + failCount == resp.updateResults.len

# --- destroyed vs destroyFailures partition destroyResults ---

testCase destroyedYieldsSuccessfulDestroys:
  let resp = fixture()
  var got = initHashSet[Id]()
  for id in resp.destroyed:
    got.incl(id)
  doAssert got.len == 2
  doAssert eid("d-ok-1") in got
  doAssert eid("d-ok-2") in got
  doAssert eid("d-err") notin got, "failure key must not appear in destroyed"

testCase destroyFailuresYieldsNotDestroyed:
  let resp = fixture()
  var got = initTable[Id, SetError]()
  for k, e in resp.destroyFailures:
    got[k] = e
  doAssert got.len == 1
  doAssert eid("d-err") in got
  doAssert got[eid("d-err")].kind == setInvalidProperties

testCase destroyPartitionIsExhaustive:
  let resp = fixture()
  var destroyedCount = 0
  for _ in resp.destroyed:
    inc destroyedCount
  var failCount = 0
  for _, _ in resp.destroyFailures:
    inc failCount
  doAssert destroyedCount + failCount == resp.destroyResults.len
