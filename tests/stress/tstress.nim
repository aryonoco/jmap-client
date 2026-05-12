# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Stress tests verifying behaviour at scale. Tests for memory safety under ARC,
## large data structures, and performance boundaries.

import std/json
import std/strutils
import std/tables

import jmap_client/internal/types/validation
import jmap_client/internal/types/primitives
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/session
import jmap_client/internal/types/envelope
import jmap_client/internal/types/framework

import ../massertions
import ../mfixtures

testCase stressManyParseIdCalls:
  ## 10000 parseId calls: no crash, no leak under ARC.
  for i in 0 ..< 10000:
    let s = "id" & $i
    if s.len <= 255:
      discard parseId(s).get()

testCase stressFilterDeep100:
  ## Filter tree 100 levels deep. Tests ARC destructor chain.
  var f = filterCondition(0)
  for i in 1 .. 100:
    f = filterOperator[int](foAnd, @[f])
  doAssert f.kind == fkOperator

testCase stressFilterWide10000:
  ## Filter tree with 10000 children. Tests memory allocation.
  var children: seq[Filter[int]] = @[]
  for i in 0 ..< 10000:
    children.add filterCondition(i)
  let f = filterOperator(foAnd, children)
  doAssert f.conditions.len == 10000

testCase stressSession100Accounts:
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

testCase stressResponse100Invocations:
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
  doAssert resp.methodResponses[99].rawName == "Method/99"

testCase stressLongFractionalSeconds:
  ## Date with 100000-digit fractional seconds.
  let frac = "1".repeat(100000)
  let input = "2024-01-01T12:00:00." & frac & "Z"
  assertOk parseDate(input)

testCase stressVeryLongMethodCallId:
  ## 1MB string for a length-unbounded type.
  assertOk parseMethodCallId("x".repeat(1_000_000))

testCase stressVeryLongCreationId:
  ## 1MB CreationId.
  assertOk parseCreationId("x".repeat(1_000_000))

testCase stressVeryLongPropertyName:
  ## 1MB PropertyName.
  assertOk parsePropertyName("x".repeat(1_000_000))

testCase stressFilterTree1000Deep:
  ## Filter tree 1000 levels deep, built iteratively to avoid stack overflow
  ## during construction. Verifies ARC destructor chain handles deep nesting.
  var f = filterCondition(0)
  for i in 1 .. 1000:
    f = filterOperator[int](foAnd, @[f])
  doAssert f.kind == fkOperator

testCase stressFilterTree5000Deep:
  ## Filter tree 5000 levels deep. ARC uses deterministic destruction,
  ## which may handle deeper nesting than tracing GC approaches.
  var f = filterCondition(0)
  for i in 1 .. 5000:
    f = filterOperator[int](foAnd, @[f])
  doAssert f.kind == fkOperator

testCase stressLargeJmapState:
  ## 10MB JmapState: parseJmapState has no upper length bound; succeeds.
  let large = "x".repeat(10_000_000)
  assertOk parseJmapState(large)

testCase stressLargeCapabilityUri:
  ## 1MB URI through parseCapabilityKind: no match, returns ckUnknown.
  let large = "x".repeat(1_000_000)
  doAssert parseCapabilityKind(large) == ckUnknown

testCase stressCombinatorialSession:
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

testCase stressFilterWide50000:
  ## Filter tree with 50000 children. Tests wide allocation under ARC.
  var children: seq[Filter[int]] = @[]
  for i in 0 ..< 50000:
    children.add filterCondition(i)
  let f = filterOperator(foAnd, children)
  doAssert f.conditions.len == 50000

testCase stressFilterExponentialSharing:
  ## Filter tree where the same subtree is referenced from multiple parents.
  ## ARC reference counting must handle shared ownership correctly.
  let shared = filterCondition(42)
  var f = filterOperator[int](foAnd, @[shared, shared])
  for _ in 0 ..< 10:
    f = filterOperator[int](foOr, @[f, f])
  doAssert f.kind == fkOperator

# =============================================================================
# Layer 2 serde stress tests
# =============================================================================

import jmap_client/internal/serialisation/serde
import jmap_client/internal/serialisation/serde_session
import jmap_client/internal/serialisation/serde_envelope
import jmap_client/internal/serialisation/serde_framework
import ../mtestblock

testCase stressArcSharedRefSessionParse:
  ## Parse 100 sessions where capabilities share a JsonNode ref.
  ## Validates Phase 1A ARC safety fix under repeated destruction.
  let sharedData = %*{"limit": 42}
  for i in 0 ..< 100:
    let cap1 = ServerCapability.fromJson("urn:ietf:params:jmap:mail", sharedData).get()
    let cap2 =
      ServerCapability.fromJson("urn:ietf:params:jmap:contacts", sharedData).get()
    discard cap1
    discard cap2
    # Both destroyed at end of iteration — ARC must not double-free

testCase stressRequestWith1000MethodCalls:
  ## Request with 1000 method calls. Tests allocation and iteration.
  var calls = newJArray()
  for i in 0 ..< 1000:
    let inv = newJArray()
    inv.add(%("Method/" & $i))
    inv.add(newJObject())
    inv.add(%("c" & $i))
    calls.add(inv)
  let j = %*{"using": ["urn:ietf:params:jmap:core"], "methodCalls": calls}
  let r = Request.fromJson(j).get()
  assertEq r.methodCalls.len, 1000

testCase stressFilterDeep100Serde:
  ## Filter tree 100 levels deep through serde round-trip.
  proc fromIntCond(
      n: JsonNode, path: JsonPath = emptyJsonPath()
  ): Result[int, SerdeViolation] {.raises: [].} =
    ## Deserialise int condition from {"value": N}.
    ?expectKind(n, JObject, path)
    let vNode = ?fieldJInt(n, "value", path)
    ok(vNode.getInt(0))

  var f = filterCondition(0)
  for i in 1 .. 100:
    f = filterOperator(foAnd, @[f])
  # ``int.toJson`` lives in mserde_fixtures (UFCS) — the mixin cascade in
  # Filter[int].toJson picks it up at instantiation.
  let j = f.toJson()
  discard Filter[int].fromJson(j, fromIntCond).get()
