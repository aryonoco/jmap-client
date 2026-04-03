# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Cross-module integration and scenario tests. Exercises realistic JMAP
## interaction workflows that span multiple Layer 1 modules.

import std/json
import std/options
import std/tables

import jmap_client/primitives
import jmap_client/identifiers
import jmap_client/capabilities
import jmap_client/session
import jmap_client/envelope
import jmap_client/framework
import jmap_client/errors
import jmap_client/types

import ../massertions
import ../mfixtures

# =============================================================================
# Happy path workflows
# =============================================================================

block scenarioSessionToRequest:
  ## Parse a Session, extract the primary account for mail, verify capabilities,
  ## then construct a Mailbox/get Request with the correct AccountId.
  let args = makeFastmailSession()
  let session = parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
  )

  # Extract primary account for mail
  let mailAcctId = session.primaryAccount(ckMail)
  assertSome mailAcctId
  let acctId = mailAcctId.get()

  # Verify the account exists and has mail capability
  let account = session.findAccount(acctId)
  assertSome account
  doAssert account.get().hasCapability(ckMail)

  # Verify core limits
  let core = session.coreCapabilities()
  doAssert core.maxCallsInRequest == parseUnsignedInt(32)

  # Construct a Request
  let mcid = makeMcid("c0")
  let inv = initInvocation("Mailbox/get", %*{"accountId": $acctId}, mcid)
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
    methodCalls: @[inv],
    createdIds: none(Table[CreationId, Id]),
  )
  doAssert req.methodCalls.len == 1
  doAssert req.methodCalls[0].methodCallId == mcid

block scenarioMultiMethodWithReferences:
  ## Three-invocation request: query, get with ResultReference, set.
  let mcid0 = makeMcid("c0")
  let mcid1 = makeMcid("c1")
  let mcid2 = makeMcid("c2")

  let queryInv = initInvocation(
    "Email/query", %*{"accountId": "acct1", "filter": {"inMailbox": "inbox"}}, mcid0
  )

  # get with ResultReference pointing to query's /ids
  let rr = ResultReference(resultOf: mcid0, name: "Email/query", path: RefPathIds)
  let getRef = referenceTo[seq[Id]](rr)
  doAssert getRef.kind == rkReference
  doAssert getRef.reference.resultOf == mcid0

  let getInv = initInvocation("Email/get", %*{"accountId": "acct1"}, mcid1)

  let setInv = initInvocation("Email/set", %*{"accountId": "acct1"}, mcid2)

  let req = Request(
    `using`: @["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
    methodCalls: @[queryInv, getInv, setInv],
    createdIds: none(Table[CreationId, Id]),
  )
  doAssert req.methodCalls.len == 3
  doAssert req.methodCalls[0].methodCallId == mcid0
  doAssert req.methodCalls[1].methodCallId == mcid1
  doAssert req.methodCalls[2].methodCallId == mcid2

block scenarioCreatedIdsRoundTrip:
  ## Request with createdIds table echoed back in Response.
  var cids = initTable[CreationId, Id]()
  cids[makeCreationId("k0")] = makeId("serverId1")
  cids[makeCreationId("k1")] = makeId("serverId2")

  let req = Request(
    `using`: @["urn:ietf:params:jmap:core"],
    methodCalls: @[makeInvocation()],
    createdIds: some(cids),
  )
  doAssert req.createdIds.isSome
  doAssert req.createdIds.get().len == 2

  # Response echoes the same createdIds
  let resp = Response(
    methodResponses: @[makeInvocation()],
    createdIds: some(cids),
    sessionState: makeState("s2"),
  )
  doAssert resp.createdIds.isSome
  doAssert resp.createdIds.get()[makeCreationId("k0")] == makeId("serverId1")

block scenarioResponseCorrelation:
  ## Response invocations correlate to request invocations via methodCallId.
  let mcid0 = makeMcid("c0")
  let mcid1 = makeMcid("c1")

  let req = Request(
    `using`: @["urn:ietf:params:jmap:core"],
    methodCalls:
      @[makeInvocation("Mailbox/get", mcid0), makeInvocation("Email/get", mcid1)],
    createdIds: none(Table[CreationId, Id]),
  )

  let resp = Response(
    methodResponses:
      @[makeInvocation("Mailbox/get", mcid0), makeInvocation("Email/get", mcid1)],
    createdIds: none(Table[CreationId, Id]),
    sessionState: makeState("s1"),
  )

  # Correlate by methodCallId
  for i in 0 ..< req.methodCalls.len:
    doAssert req.methodCalls[i].methodCallId == resp.methodResponses[i].methodCallId

# =============================================================================
# Error railway cascades
# =============================================================================

block scenarioTransportFailureCascade:
  ## Track 1: Transport failure -> ClientError -> message().
  let te = transportError(tekNetwork, "connection refused")
  let ce = clientError(te)
  doAssert ce.kind == cekTransport
  doAssert ce.message == "connection refused"

  # ClientError message accessible directly
  doAssert message(ce) == "connection refused"

block scenarioRequestRejectionCascade:
  ## Track 1: Request rejection with limit error -> message prefers detail.
  let re = requestError(
    "urn:ietf:params:jmap:error:limit",
    detail = some("Too many method calls"),
    limit = some("maxCallsInRequest"),
  )
  let ce = clientError(re)
  doAssert ce.kind == cekRequest
  doAssert ce.message == "Too many method calls"

block scenarioMessageCascadePriority:
  ## ClientError.message cascade: detail > title > rawType.
  # detail present
  let re1 = requestError(
    "urn:ietf:params:jmap:error:notJSON",
    title = some("Not JSON"),
    detail = some("Body is not valid JSON"),
  )
  doAssert clientError(re1).message == "Body is not valid JSON"

  # detail absent, title present
  let re2 = requestError("urn:ietf:params:jmap:error:notJSON", title = some("Not JSON"))
  doAssert clientError(re2).message == "Not JSON"

  # both absent, falls back to rawType
  let re3 = requestError("urn:ietf:params:jmap:error:notJSON")
  doAssert clientError(re3).message == "urn:ietf:params:jmap:error:notJSON"

block scenarioMethodErrorInResponse:
  ## Track 2: Method error within a successful response.
  let errInv = initInvocation(
    "error",
    %*{"type": "invalidArguments", "description": "missing accountId"},
    makeMcid("c0"),
  )
  doAssert errInv.name == "error"
  let me = methodError("invalidArguments", description = some("missing accountId"))
  doAssert me.errorType == metInvalidArguments
  doAssert me.description.get() == "missing accountId"

block scenarioSetErrorVariants:
  ## Data-level: Per-item SetError with variant-specific fields.
  # invalidProperties variant
  let se1 = setErrorInvalidProperties("invalidProperties", @["subject", "from"])
  doAssert se1.errorType == setInvalidProperties
  doAssert se1.properties.len == 2

  # alreadyExists variant
  let existId = makeId("existing42")
  let se2 = setErrorAlreadyExists("alreadyExists", existId)
  doAssert se2.errorType == setAlreadyExists
  doAssert se2.existingId == existId

  # generic variant
  let se3 = setError("forbidden")
  doAssert se3.errorType == setForbidden

block scenarioTlsError:
  ## Transport TLS failure path.
  let te = transportError(tekTls, "certificate verification failed")
  let ce = clientError(te)
  doAssert ce.kind == cekTransport
  doAssert ce.transport.kind == tekTls

block scenarioTimeoutError:
  ## Transport timeout failure path.
  let te = transportError(tekTimeout, "request timed out after 30s")
  let ce = clientError(te)
  doAssert ce.message == "request timed out after 30s"

block scenarioHttpStatusError:
  ## Transport HTTP status error with status code.
  let te = httpStatusError(503, "Service Unavailable")
  let ce = clientError(te)
  doAssert ce.kind == cekTransport
  doAssert ce.transport.kind == tekHttpStatus
  doAssert ce.transport.httpStatus == 503

# =============================================================================
# Real-world server fixtures
# =============================================================================

block scenarioFastmailSession:
  ## Fastmail-style session: multiple capabilities including vendor extensions.
  let args = makeFastmailSession()
  let session = parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
  )

  # Verify vendor extension accessible by URI
  let vendorCap = session.findCapabilityByUri("https://www.fastmail.com/dev/contacts")
  assertSome vendorCap
  doAssert vendorCap.get().kind == ckUnknown

  # Verify standard capability
  let mailCap = session.findCapability(ckMail)
  assertSome mailCap

  # Verify username
  doAssert session.username == "user@fastmail.com"

block scenarioCyrusStyleIdentifiers:
  ## Cyrus-style IDs contain characters outside base64url.
  assertOk parseIdFromServer("user.folder.12345")
  assertOk parseIdFromServer("msg+draft/1")
  assertErr parseId("user.folder.12345")
  assertErr parseId("msg+draft/1")
  assertOk parseAccountId("user@example.com")

block scenarioMinimalSession:
  ## Bare minimum session: ckCore only, no accounts, no primary accounts.
  let args = makeMinimalSession()
  let session = parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
  )
  doAssert session.accounts.len == 0
  doAssert session.primaryAccounts.len == 0
  doAssert session.username == ""
  let core = session.coreCapabilities()
  doAssert core.maxSizeUpload == parseUnsignedInt(0)

block scenarioMultiTenantAccounts:
  ## Session with multiple accounts, different capability subsets.
  let args = makeSessionArgs()
  var accounts = initTable[AccountId, Account]()
  for i in 1 .. 5:
    let id = makeAccountId("acct" & $i)
    accounts[id] = Account(
      name: "Account " & $i,
      isPersonal: i == 1,
      isReadOnly: i > 3,
      accountCapabilities: @[],
    )
  var primaryAccounts = initTable[string, AccountId]()
  primaryAccounts["urn:ietf:params:jmap:mail"] = makeAccountId("acct1")

  let session = parseSession(
    args.capabilities, accounts, primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
  )

  doAssert session.accounts.len == 5
  let acct3 = session.findAccount(makeAccountId("acct3"))
  assertSome acct3
  doAssert acct3.get().name == "Account 3"
  doAssert not acct3.get().isReadOnly

  let acct5 = session.findAccount(makeAccountId("acct5"))
  assertSome acct5
  doAssert acct5.get().isReadOnly

# =============================================================================
# Cross-module composition
# =============================================================================

block scenarioSessionAccountCapabilityChain:
  ## Accessor chain: Session -> Account -> findCapability -> AccountCapabilityEntry.
  let args = makeFastmailSession()
  let session = parseSession(
    args.capabilities, args.accounts, args.primaryAccounts, args.username, args.apiUrl,
    args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
  )
  let acctId = session.primaryAccount(ckMail).get()
  let account = session.findAccount(acctId).get()
  let mailCap = account.findCapability(ckMail)
  assertSome mailCap
  doAssert mailCap.get().rawUri == "urn:ietf:params:jmap:mail"

block scenarioResultReferenceCorrelation:
  ## ResultReference.resultOf matches a previous Invocation's MethodCallId.
  let mcid = makeMcid("query-0")
  let queryInv = makeInvocation("Email/query", mcid)
  let rr = ResultReference(resultOf: mcid, name: "Email/query", path: RefPathIds)
  doAssert rr.resultOf == queryInv.methodCallId

block scenarioSetErrorWithIdFromPrimitives:
  ## SetError alreadyExists variant uses Id from primitives module.
  let existingId = makeId("existing42")
  let se = setErrorAlreadyExists("alreadyExists", existingId)
  doAssert se.existingId == existingId
  doAssert $se.existingId == "existing42"

block scenarioReferencableBothForms:
  ## Referencable[seq[Id]] in both direct and reference forms.
  let ids = @[makeId("id1"), makeId("id2")]
  let directForm = direct(ids)
  doAssert directForm.kind == rkDirect
  doAssert directForm.value.len == 2

  let rr =
    ResultReference(resultOf: makeMcid("c0"), name: "Email/query", path: RefPathIds)
  let refForm = referenceTo[seq[Id]](rr)
  doAssert refForm.kind == rkReference
  doAssert refForm.reference.path == "/ids"

# =============================================================================
# Data preservation
# =============================================================================

block scenarioRawTypePreservation:
  ## All error constructors preserve rawType for lossless round-trip.
  let me = methodError("vendorCustomError")
  doAssert me.rawType == "vendorCustomError"
  doAssert me.errorType == metUnknown

  let re = requestError("urn:vendor:custom:error")
  doAssert re.rawType == "urn:vendor:custom:error"
  doAssert re.errorType == retUnknown

  let se = setError("vendorSetError")
  doAssert se.rawType == "vendorSetError"
  doAssert se.errorType == setUnknown

block scenarioServerCapabilityRawDataPreservation:
  ## Non-core ServerCapability preserves raw JSON data.
  let data = %*{"maxContacts": 10000, "vendor-flag": true}
  let sc = ServerCapability(
    rawUri: "https://vendor.example/contacts", kind: ckUnknown, rawData: data
  )
  doAssert sc.rawData["maxContacts"].getInt() == 10000
  doAssert sc.rawData["vendor-flag"].getBool() == true

block scenarioRequestErrorExtrasPreservation:
  ## Non-standard fields in RequestError are preserved in extras.
  let extras = %*{"requestId": "req-123", "retryAfter": 30}
  let re = requestError("urn:ietf:params:jmap:error:limit", extras = some(extras))
  doAssert re.extras.isSome
  doAssert re.extras.get()["requestId"].getStr() == "req-123"
  doAssert re.extras.get()["retryAfter"].getInt() == 30

block scenarioMethodErrorExtrasPreservation:
  ## Non-standard fields in MethodError are preserved in extras.
  let extras = %*{"serverMessage": "database overloaded"}
  let me = methodError("serverFail", extras = some(extras))
  doAssert me.extras.isSome
  doAssert me.extras.get()["serverMessage"].getStr() == "database overloaded"

# =============================================================================
# Cross-module interaction tests
# =============================================================================

block scenarioPrimaryAccountCkUnknownReturnsNone:
  ## primaryAccount(session, ckUnknown) returns none because capabilityUri
  ## returns err for ckUnknown — the early return via ? propagates.
  let args = makeSessionArgs()
  let session = parseSessionFromArgs(args)
  doAssert primaryAccount(session, ckUnknown).isNone,
    "primaryAccount for ckUnknown should return None"

block scenarioEmptyUsingAndMethodCalls:
  ## Request with empty using and empty methodCalls is valid at Layer 1.
  ## Layer 3 protocol logic may reject this, but Layer 1 holds the data.
  let req =
    Request(`using`: @[], methodCalls: @[], createdIds: none(Table[CreationId, Id]))
  doAssert req.`using`.len == 0
  doAssert req.methodCalls.len == 0

block scenarioDuplicateMethodCallIdsInRequest:
  ## Request with duplicate MethodCallIds is valid at Layer 1. The protocol
  ## uses MethodCallId for correlation; uniqueness is a Layer 3 concern.
  let mcid = makeMcid("shared")
  let inv1 = initInvocation("Email/get", newJObject(), mcid)
  let inv2 = initInvocation("Email/query", newJObject(), mcid)
  let req = Request(
    `using`: @["urn:ietf:params:jmap:core"],
    methodCalls: @[inv1, inv2],
    createdIds: none(Table[CreationId, Id]),
  )
  doAssert req.methodCalls.len == 2
  doAssert req.methodCalls[0].methodCallId == req.methodCalls[1].methodCallId

block scenarioResponseWithErrorInvocation:
  ## Response containing an Invocation with name="error" is valid.
  let errInv = initInvocation("error", %*{"type": "serverFail"}, makeMcid("c0"))
  let resp = Response(
    methodResponses: @[errInv],
    createdIds: none(Table[CreationId, Id]),
    sessionState: makeState("s1"),
  )
  doAssert resp.methodResponses[0].name == "error"

block scenarioHasVariableEmptyString:
  ## hasVariable with empty name searches for "{}" — not present in typical
  ## templates, so returns false. Documents the wrapping semantics.
  let tmpl = parseUriTemplate("https://example.com/{accountId}")
  doAssert not tmpl.hasVariable(""), "empty variable name searches for '{}'"

block scenarioFindAccountEmptyTable:
  ## findAccount returns None when accounts table is empty.
  let args = makeMinimalSession()
  let session = parseSessionFromArgs(args)
  doAssert session.findAccount(makeAccountId("nonexistent")).isNone

# =============================================================================
# Phase 8: Cross-module integration tests
# =============================================================================

block filterWithPropertyNameType:
  ## Filter parameterised with a validated domain type (PropertyName) as string.
  ## Note: PropertyName has {.requiresInit.}, so Filter[PropertyName] cannot be
  ## used directly (seq requires a default value). We verify the name round-trips.
  let pn = parsePropertyName("subject")
  let pnStr = $pn
  let f = filterCondition(pnStr)
  doAssert f.kind == fkCondition
  doAssert f.condition == pnStr

block filterWithAccountIdType:
  ## Filter parameterised with string — using AccountId string representations
  ## to verify Filter composition across module boundaries. Direct use of
  ## requiresInit distinct types as Filter[C] triggers seq default-value issues.
  let acctStr1 = $parseAccountId("acct1")
  let acctStr2 = $parseAccountId("acct2")
  let f = filterCondition(acctStr1)
  let f2 = filterCondition(acctStr2)
  let combined = filterOperator[string](foAnd, @[f, f2])
  doAssert combined.kind == fkOperator
  doAssert combined.conditions.len == 2

block errorCascadeAllNoneFields:
  ## Transport error -> ClientError -> message extraction with no optional fields.
  let te = transportError(tekNetwork, "connection refused")
  let ce = clientError(te)
  doAssert message(ce) == "connection refused"

block errorCascadeDetailPriority:
  ## Request error with detail, title, and rawType — detail takes priority.
  let re = requestError(
    "urn:ietf:params:jmap:error:limit",
    title = some("Rate Limited"),
    detail = some("Too many requests per second"),
  )
  let ce = clientError(re)
  doAssert message(ce) == "Too many requests per second"

block sessionToRequestIntegration:
  ## Construct Session -> extract capabilities -> build Request with those URIs.
  let args = makeFastmailSession()
  let session = parseSessionFromArgs(args)
  var capUris: seq[string] = @[]
  for cap in session.capabilities:
    capUris.add cap.rawUri
  let req = Request(
    `using`: capUris,
    methodCalls: @[initInvocation("Mailbox/get", newJObject(), parseMethodCallId("c0"))],
    createdIds: none(Table[CreationId, Id]),
  )
  doAssert req.`using`.len == capUris.len

block resultReferenceWithPriorInvocation:
  ## Build a ResultReference that references a prior Invocation's MethodCallId.
  let mcid1 = parseMethodCallId("c1")
  let inv1 = initInvocation("Email/query", newJObject(), mcid1)
  let ref1 = ResultReference(resultOf: mcid1, name: "Email/query", path: RefPathIds)
  doAssert ref1.resultOf == inv1.methodCallId
  doAssert ref1.path == "/ids"
