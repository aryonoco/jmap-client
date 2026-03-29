# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Stress tests verifying behaviour at scale. Tests for memory safety under ARC,
## large data structures, and performance boundaries.

import std/json
import std/strutils
import std/tables

import results

import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/session
import jmap_client/envelope
import jmap_client/framework
import jmap_client/errors

import ../massertions
import ../mfixtures

block stressManyParseIdCalls:
  ## 10000 parseId calls: no crash, no leak under ARC.
  for i in 0 ..< 10000:
    let s = "id" & $i
    if s.len <= 255:
      discard parseId(s)

block stressPatchObject10000Entries:
  ## PatchObject with 10000 entries via chained setProp.
  var p = emptyPatch()
  for i in 0 ..< 10000:
    p = p.setProp("key" & $i, %i).get()
  doAssert p.len == 10000

block stressFilterDeep100:
  ## Filter tree 100 levels deep. Tests ARC destructor chain.
  var f = filterCondition(0)
  for i in 1 .. 100:
    f = filterOperator[int](foAnd, @[f])
  doAssert f.kind == fkOperator

block stressFilterWide10000:
  ## Filter tree with 10000 children. Tests memory allocation.
  var children: seq[Filter[int]] = @[]
  for i in 0 ..< 10000:
    children.add filterCondition(i)
  let f = filterOperator(foAnd, children)
  doAssert f.conditions.len == 10000

block stressSession100Accounts:
  ## Session with 100 accounts.
  let args = makeSessionArgs()
  var accounts = initTable[AccountId, Account]()
  for i in 0 ..< 100:
    let id = makeAccountId("acct" & $i)
    accounts[id] = Account(
      name: "Account " & $i,
      isPersonal: i == 0,
      isReadOnly: false,
      accountCapabilities: @[],
    )
  let session = parseSession(
      args.capabilities, accounts, args.primaryAccounts, args.username, args.apiUrl,
      args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
    )
    .get()
  doAssert session.accounts.len == 100
  let acct99 = session.findAccount(makeAccountId("acct99"))
  assertSome acct99

block stressResponse100Invocations:
  ## Response with 100 invocations.
  var invocations: seq[Invocation] = @[]
  for i in 0 ..< 100:
    invocations.add makeInvocation("Method/" & $i, makeMcid("c" & $i))
  let resp = Response(
    methodResponses: invocations,
    createdIds: Opt.none(Table[CreationId, Id]),
    sessionState: makeState("s1"),
  )
  doAssert resp.methodResponses.len == 100
  doAssert resp.methodResponses[99].name == "Method/99"

block stressLongFractionalSeconds:
  ## Date with 100000-digit fractional seconds.
  let frac = "1".repeat(100000)
  let input = "2024-01-01T12:00:00." & frac & "Z"
  assertOk parseDate(input)

block stressVeryLongMethodCallId:
  ## 1MB string for a length-unbounded type.
  assertOk parseMethodCallId("x".repeat(1_000_000))

block stressVeryLongCreationId:
  ## 1MB CreationId.
  assertOk parseCreationId("x".repeat(1_000_000))

block stressVeryLongPropertyName:
  ## 1MB PropertyName.
  assertOk parsePropertyName("x".repeat(1_000_000))

block stressFilterTree1000Deep:
  ## Filter tree 1000 levels deep, built iteratively to avoid stack overflow
  ## during construction. Verifies ARC destructor chain handles deep nesting.
  var f = filterCondition(0)
  for i in 1 .. 1000:
    f = filterOperator[int](foAnd, @[f])
  doAssert f.kind == fkOperator

block stressFilterTree5000Deep:
  ## Filter tree 5000 levels deep. ARC uses deterministic destruction,
  ## which may handle deeper nesting than tracing GC approaches.
  var f = filterCondition(0)
  for i in 1 .. 5000:
    f = filterOperator[int](foAnd, @[f])
  doAssert f.kind == fkOperator

block stressLargeJmapState:
  ## 10MB JmapState: parseJmapState has no upper length bound; succeeds.
  let large = "x".repeat(10_000_000)
  assertOk parseJmapState(large)

block stressLargeCapabilityUri:
  ## 1MB URI through parseCapabilityKind: no match, returns ckUnknown.
  let large = "x".repeat(1_000_000)
  doAssert parseCapabilityKind(large) == ckUnknown

block stressCombinatorialSession:
  ## Combinatorial: session with many accounts, long IDs, and vendor extensions
  ## exercising multiple constraints simultaneously.
  var accounts = initTable[AccountId, Account]()
  var primaryAccounts = initTable[string, AccountId]()
  for i in 0 ..< 50:
    let idStr = 'A'.repeat(200) & $i # Near-boundary AccountId (200+ chars)
    let aid = parseAccountId(idStr).get()
    accounts[aid] = Account(
      name: "account-" & $i,
      isPersonal: i == 0,
      isReadOnly: false,
      accountCapabilities: @[
        AccountCapabilityEntry(
          kind: ckMail, rawUri: "urn:ietf:params:jmap:mail", data: newJObject()
        )
      ],
    )
    if i == 0:
      primaryAccounts["urn:ietf:params:jmap:mail"] = aid
  let caps = @[
    makeCoreServerCap(realisticCoreCaps()),
    ServerCapability(
      rawUri: "urn:ietf:params:jmap:mail", kind: ckMail, rawData: newJObject()
    ),
    ServerCapability(
      rawUri: "https://vendor.example.com/ext1", kind: ckUnknown, rawData: newJObject()
    ),
    ServerCapability(
      rawUri: "https://vendor.example.com/ext2", kind: ckUnknown, rawData: newJObject()
    ),
  ]
  let session = parseSession(
      caps,
      accounts,
      primaryAccounts,
      "user@example.com",
      "https://jmap.example.com/api/",
      makeGoldenDownloadUrl(),
      makeGoldenUploadUrl(),
      makeGoldenEventSourceUrl(),
      makeState("combo-stress"),
    )
    .get()
  doAssert session.accounts.len == 50
  doAssert session.capabilities.len == 4
  doAssert session.coreCapabilities().maxSizeUpload == realisticCoreCaps().maxSizeUpload

block stressFilterWide50000:
  ## Filter tree with 50000 children. Tests wide allocation under ARC.
  var children: seq[Filter[int]] = @[]
  for i in 0 ..< 50000:
    children.add filterCondition(i)
  let f = filterOperator(foAnd, children)
  doAssert f.conditions.len == 50000

block stressFilterExponentialSharing:
  ## Filter tree where the same subtree is referenced from multiple parents.
  ## ARC reference counting must handle shared ownership correctly.
  let shared = filterCondition(42)
  var f = filterOperator[int](foAnd, @[shared, shared])
  for _ in 0 ..< 10:
    f = filterOperator[int](foOr, @[f, f])
  doAssert f.kind == fkOperator

block stressPatchObjectGetKeyMiss:
  ## 10000 getKey misses on a populated PatchObject. Verifies O(1) Table lookup.
  var p = emptyPatch()
  for i in 0 ..< 100:
    p = p.setProp("existing" & $i, %i).get()
  for i in 0 ..< 10000:
    doAssert p.getKey("miss" & $i).isNone
