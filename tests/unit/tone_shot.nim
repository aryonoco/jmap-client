# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Behavioural tests for the Layer-4 one-shots (``src/jmap_client/internal/
## one_shot.nim``). Each one-shot is driven end-to-end through a canned-session
## Transport: the GET exchange returns the session, the POST exchange returns a
## crafted methodResponses envelope keyed by the deterministic ``c0``/``c1``
## call ids the builder mints. Coverage: ``connect`` (default overload, lazy
## session — no network); two bare-get happy paths (Mailbox, Email); a bare-get
## ``mokMethodError`` -> ``jeMethod`` collapse; two query-then-get happy paths
## (Email, Mailbox); and the ``sendPlainText`` two-mailbox flow — the success
## result, the emitted request shape (including the to∪cc∪bcc envelope
## ``rcptTo`` union), a draft-create ``SetError`` collapsing onto the ``jeSet``
## rail, and an absent draft create collapsing onto ``jeProtocol``
## (``pfMissingCall``).

import std/json
import std/strutils
import std/tables

import jmap_client

import ../massertions
import ../mfixtures
import ../mtestblock
import ../mtransport

proc envelope(methodResponses: JsonNode): string =
  ## Wraps a methodResponses array in the RFC 8620 §3.4 Response envelope and
  ## serialises it for a canned POST body.
  $(%*{"methodResponses": methodResponses, "sessionState": "s1"})

proc cannedClient(responseJson: string): JmapClient =
  ## A JmapClient whose POST exchange returns ``responseJson`` and whose
  ## session advertises realistic core limits.
  newClientWithSessionCaps(realisticCoreCaps(), responseJson)

# ---------------------------------------------------------------------------
# connect — default overload builds a client without touching the network
# ---------------------------------------------------------------------------

testCase oneShotConnectDefault:
  ## ``connect`` (default overload) folds the endpoint + credential constructors
  ## and ``initJmapClient`` onto the rail. The RFC 8620 §2 session is lazy, so a
  ## ``JmapClient`` is built with no network exchange.
  let r = connect("https://example.com/jmap", "alice", "secret")
  assertOk r
  let client = r.get()
  doAssert not client.isNil, "connect must yield a live JmapClient handle"

# ---------------------------------------------------------------------------
# Bare-get one-shot — happy path
# ---------------------------------------------------------------------------

testCase oneShotGetMailboxesSuccess:
  ## ``getMailboxes`` returns the full ``GetResponse`` — ``state`` and
  ## ``notFound`` survive the collapse onto the rail.
  let resp = envelope(
    %*[
      [
        "Mailbox/get",
        {"accountId": "a1", "state": "st-1", "list": [], "notFound": ["m9"]},
        "c0",
      ]
    ]
  )
  let client = cannedClient(resp)
  let r = client.getMailboxes(makeAccountId("a1"))
  assertOk r
  let gr = r.get()
  assertEq gr.state, makeState("st-1")
  assertLen gr.notFound, 1
  assertEq gr.notFound[0], makeId("m9")

# ---------------------------------------------------------------------------
# Bare-get one-shot — server method error collapses onto jeMethod
# ---------------------------------------------------------------------------

testCase oneShotGetMailboxesMethodError:
  ## A server ``error`` invocation at the one-shot's call id collapses onto the
  ## ``jeMethod`` rail (RFC 8620 §3.6.2 single-method fail-fast).
  let resp = envelope(%*[["error", {"type": "accountNotFound"}, "c0"]])
  let client = cannedClient(resp)
  let r = client.getMailboxes(makeAccountId("a1"))
  doAssert r.isErr, "expected a rail error for a method-level failure"
  doAssert r.error.kind == jeMethod
  doAssert "Mailbox/get" in $r.error

# ---------------------------------------------------------------------------
# Bare-get one-shot — a second entity (Email) preserves state + notFound
# ---------------------------------------------------------------------------

testCase oneShotGetEmailsSuccess:
  ## ``getEmails`` returns the full ``GetResponse[Email]`` — ``state`` and
  ## ``notFound`` survive the collapse onto the rail (RFC 8621 §4.2).
  let resp = envelope(
    %*[
      [
        "Email/get",
        {"accountId": "a1", "state": "es-9", "list": [], "notFound": ["e7"]},
        "c0",
      ]
    ]
  )
  let client = cannedClient(resp)
  let r = client.getEmails(makeAccountId("a1"))
  assertOk r
  let gr = r.get()
  assertEq gr.state, makeState("es-9")
  assertLen gr.notFound, 1
  assertEq gr.notFound[0], makeId("e7")

# ---------------------------------------------------------------------------
# Query-then-get one-shot — happy path
# ---------------------------------------------------------------------------

testCase oneShotQueryEmailsSuccess:
  ## ``queryEmails`` dispatches Email/query (c0) + Email/get (c1) and returns
  ## both collapsed responses.
  let resp = envelope(
    %*[
      [
        "Email/query",
        {
          "accountId": "a1",
          "queryState": "qs1",
          "canCalculateChanges": true,
          "position": 0,
          "ids": [],
        },
        "c0",
      ],
      [
        "Email/get",
        {"accountId": "a1", "state": "es1", "list": [], "notFound": []},
        "c1",
      ],
    ]
  )
  let client = cannedClient(resp)
  let r = client.queryEmails(makeAccountId("a1"))
  assertOk r
  let qtg = r.get()
  assertEq qtg.get.state, makeState("es1")
  assertLen qtg.query.ids, 0

# ---------------------------------------------------------------------------
# Query-then-get one-shot — a second entity (Mailbox)
# ---------------------------------------------------------------------------

testCase oneShotQueryMailboxesSuccess:
  ## ``queryMailboxes`` dispatches Mailbox/query (c0) + Mailbox/get (c1) and
  ## returns both collapsed responses (RFC 8621 §2.3 + §2.1).
  let resp = envelope(
    %*[
      [
        "Mailbox/query",
        {
          "accountId": "a1",
          "queryState": "mqs1",
          "canCalculateChanges": true,
          "position": 0,
          "ids": ["m1"],
        },
        "c0",
      ],
      [
        "Mailbox/get",
        {"accountId": "a1", "state": "ms1", "list": [], "notFound": []},
        "c1",
      ],
    ]
  )
  let client = cannedClient(resp)
  let r = client.queryMailboxes(makeAccountId("a1"))
  assertOk r
  let qtg = r.get()
  assertEq qtg.get.state, makeState("ms1")
  assertLen qtg.query.ids, 1
  assertEq qtg.query.ids[0], makeId("m1")

# ---------------------------------------------------------------------------
# sendPlainText — happy path + emitted request shape
# ---------------------------------------------------------------------------

proc sendResponseEnvelope(): string =
  ## A success envelope for ``sendPlainText``: Email/set (c0) creating the
  ## draft, EmailSubmission/set (c1) creating the submission, and the implicit
  ## Email/set move (c1, shares the submission's call id per RFC 8620 §5.4).
  envelope(
    %*[
      [
        "Email/set",
        {
          "accountId": "a1",
          "newState": "s2",
          "created":
            {"draft": {"id": "E1", "blobId": "B1", "threadId": "T1", "size": 42}},
        },
        "c0",
      ],
      [
        "EmailSubmission/set",
        {"accountId": "a1", "newState": "s3", "created": {"sub": {"id": "S1"}}},
        "c1",
      ],
      ["Email/set", {"accountId": "a1", "newState": "s4", "updated": {"E1": nil}}, "c1"],
    ]
  )

testCase oneShotSendPlainTextSuccess:
  ## ``sendPlainText`` returns the server-assigned Email and EmailSubmission
  ## ids read from the two ``created`` maps.
  let client = cannedClient(sendResponseEnvelope())
  let r = client.sendPlainText(
    accountId = makeAccountId("a1"),
    identityId = makeId("ident-1"),
    mailboxes = SendMailboxes(drafts: makeId("mb-drafts"), sent: makeId("mb-sent")),
    message = PlainTextMessage(
      fromAddr: "alice@example.com",
      to: @["bob@example.com"],
      subject: "Hi",
      body: "Hello, Bob.",
    ),
  )
  assertOk r
  let sent = r.get()
  assertEq sent.emailId, makeId("E1")
  assertEq sent.submissionId, makeId("S1")

testCase oneShotSendPlainTextRequestShape:
  ## The emitted request is Email/set (draft create) then EmailSubmission/set
  ## carrying ``onSuccessUpdateEmail`` (RFC 8621 §7.5.1).
  let (transport, recorder) = newRecordingTransport(
    newCannedTransport(
      makeSessionJsonWithCoreCaps(realisticCoreCaps()), sendResponseEnvelope()
    )
  )
  let client = initJmapClient(
      directEndpoint("https://example.com/jmap").get(),
      bearerCredential("t").get(),
      transport,
    )
    .get()
  discard client.fetchSession().get()
  discard client.sendPlainText(
    accountId = makeAccountId("a1"),
    identityId = makeId("ident-1"),
    mailboxes = SendMailboxes(drafts: makeId("mb-drafts"), sent: makeId("mb-sent")),
    message = PlainTextMessage(
      fromAddr: "alice@example.com",
      to: @["bob@example.com", "carol@example.com"],
      subject: "Hi",
      body: "Hello.",
      cc: @["dave@example.com"],
    ),
  )
  let reqBody = parseJson(recorder.lastRequest.body)
  let calls = reqBody{"methodCalls"}
  assertLen calls, 2
  # First invocation creates the draft Email.
  doAssert calls[0][0].getStr("") == "Email/set"
  doAssert calls[0][1]{"create"}{"draft"} != nil,
    "Email/set must create the draft keyed by its creation id"
  # Second invocation submits and requests the onSuccess Drafts -> Sent move.
  doAssert calls[1][0].getStr("") == "EmailSubmission/set"
  doAssert calls[1][1]{"create"}{"sub"} != nil,
    "EmailSubmission/set must create the submission keyed by its creation id"
  doAssert calls[1][1]{"onSuccessUpdateEmail"} != nil,
    "EmailSubmission/set must carry onSuccessUpdateEmail for the Sent move"
  # The §7 envelope rcptTo is the to∪cc∪bcc union, so the cc recipient
  # (dave@example.com) must appear alongside the to recipients (RFC 8621 §7).
  let rcptTo = calls[1][1]{"create"}{"sub"}{"envelope"}{"rcptTo"}
  doAssert rcptTo != nil and rcptTo.kind == JArray, "envelope must carry rcptTo"
  var rcptEmails: seq[string] = @[]
  for entry in rcptTo:
    rcptEmails.add entry{"email"}.getStr("")
  doAssert "dave@example.com" in rcptEmails,
    "rcptTo must include the cc recipient (to∪cc∪bcc union)"

# ---------------------------------------------------------------------------
# sendPlainText — error branches
# ---------------------------------------------------------------------------

proc draftSetErrorEnvelope(): string =
  ## Email/set (c0) refuses the draft create with an ``overQuota`` SetError on
  ## the ``notCreated`` rail (RFC 8620 §5.3); EmailSubmission/set (c1) parses as
  ## a valid SetResponse so the flow reaches the draft-create read.
  envelope(
    %*[
      [
        "Email/set",
        {
          "accountId": "a1",
          "newState": "s2",
          "notCreated": {"draft": {"type": "overQuota"}},
        },
        "c0",
      ],
      [
        "EmailSubmission/set",
        {"accountId": "a1", "newState": "s3", "created": {"sub": {"id": "S1"}}},
        "c1",
      ],
    ]
  )

proc absentDraftCreateEnvelope(): string =
  ## Email/set (c0) acknowledges neither a created nor a notCreated draft — a
  ## malformed §5.3 response. EmailSubmission/set (c1) parses validly so the flow
  ## reaches the draft-create read.
  envelope(
    %*[
      ["Email/set", {"accountId": "a1", "newState": "s2"}, "c0"],
      [
        "EmailSubmission/set",
        {"accountId": "a1", "newState": "s3", "created": {"sub": {"id": "S1"}}},
        "c1",
      ],
    ]
  )

testCase oneShotSendPlainTextDraftSetError:
  ## A draft create the server refuses with a typed SetError (RFC 8620 §5.3
  ## notCreated) collapses onto the ``jeSet`` rail, carrying the SetError reason
  ## and the failing method name.
  let client = cannedClient(draftSetErrorEnvelope())
  let r = client.sendPlainText(
    accountId = makeAccountId("a1"),
    identityId = makeId("ident-1"),
    mailboxes = SendMailboxes(drafts: makeId("mb-drafts"), sent: makeId("mb-sent")),
    message = PlainTextMessage(
      fromAddr: "alice@example.com",
      to: @["bob@example.com"],
      subject: "Hi",
      body: "Hello, Bob.",
    ),
  )
  doAssert r.isErr, "a refused draft create must surface on the rail"
  doAssert r.error.kind == jeSet, "a refused create collapses onto jeSet"
  doAssert r.error.setFault.error.kind == setOverQuota,
    "the typed SetError reason must survive on the rail"
  doAssert "Email/set" in $r.error, "the failing method name surfaces in the message"

testCase oneShotSendPlainTextAbsentDraftCreate:
  ## A draft create absent from both the created and notCreated rails is a
  ## malformed response (RFC 8620 §5.3) — ``jeProtocol`` / ``pfMissingCall``.
  let client = cannedClient(absentDraftCreateEnvelope())
  let r = client.sendPlainText(
    accountId = makeAccountId("a1"),
    identityId = makeId("ident-1"),
    mailboxes = SendMailboxes(drafts: makeId("mb-drafts"), sent: makeId("mb-sent")),
    message = PlainTextMessage(
      fromAddr: "alice@example.com",
      to: @["bob@example.com"],
      subject: "Hi",
      body: "Hello, Bob.",
    ),
  )
  doAssert r.isErr, "an absent draft create must surface on the rail"
  doAssert r.error.kind == jeProtocol, "an absent create is a protocol fault"
  doAssert r.error.protocol.kind == pfMissingCall,
    "the absent create maps to pfMissingCall"

# -----------------------------------------------------------------------------
# getEmailState
# -----------------------------------------------------------------------------

testCase oneShotGetEmailStateSuccess:
  ## The state bootstrap issues one empty-ids Email/get and surfaces its
  ## ``state`` field alone — the sinceState cursor for a first sync.
  let responseJson = envelope(
    %*[
      [
        "Email/get",
        {"accountId": "acct-1", "state": "s-42", "list": [], "notFound": []},
        "c0",
      ]
    ]
  )
  let client = cannedClient(responseJson)
  let res = client.getEmailState(makeAccountId("acct-1"))
  assertOk(res)
  assertEq(res.value, makeState("s-42"))

testCase oneShotGetEmailStateRequestShape:
  ## The emitted Email/get call carries an explicit empty ``ids`` array — the
  ## whole point of the one-shot is that bootstrapping ``sinceState`` costs no
  ## email payload. Without this, a permissive ``ids = Opt.none`` implementation
  ## would fetch the entire account's Email list just to read one state string.
  let (transport, recorder) = newRecordingTransport(
    newCannedTransport(
      makeSessionJsonWithCoreCaps(realisticCoreCaps()),
      envelope(
        %*[
          [
            "Email/get",
            {"accountId": "acct-1", "state": "s-42", "list": [], "notFound": []},
            "c0",
          ]
        ]
      ),
    )
  )
  let client = initJmapClient(
      directEndpoint("https://example.com/jmap").get(),
      bearerCredential("t").get(),
      transport,
    )
    .get()
  discard client.fetchSession().get()
  discard client.getEmailState(makeAccountId("acct-1"))
  let reqBody = parseJson(recorder.lastRequest.body)
  let calls = reqBody{"methodCalls"}
  assertLen calls, 1
  doAssert calls[0][0].getStr("") == "Email/get",
    "getEmailState must issue a single Email/get call"
  doAssert calls[0][1]{"ids"} == newJArray(),
    "getEmailState must request ids: [] so no email payload is fetched"

testCase oneShotGetEmailStateMethodError:
  ## A method-level error on the single call collapses onto the rail as
  ## jeMethod — the fail-fast one-shot contract.
  let responseJson = envelope(%*[["error", {"type": "serverFail"}, "c0"]])
  let client = cannedClient(responseJson)
  let res = client.getEmailState(makeAccountId("acct-1"))
  doAssert res.isErr, "expected a rail error for a method-level failure"
  doAssert res.error.kind == jeMethod,
    "a server error invocation collapses onto jeMethod"
  doAssert res.error.methodFault.error.kind == metServerFail,
    "the method-error kind must survive onto the rail"

# -----------------------------------------------------------------------------
# markEmailsRead / markEmailsUnread
# -----------------------------------------------------------------------------

proc setUpdatedNullResponse(id: string): string =
  ## Email/set success where the server confirms the update with a null
  ## echo — the common case for keyword patches.
  envelope(
    %*[
      [
        "Email/set",
        {
          "accountId": "acct-1",
          "oldState": "s1",
          "newState": "s2",
          "updated": {id: nil},
        },
        "c0",
      ]
    ]
  )

testCase oneShotMarkEmailsReadSuccess:
  ## One id marked read: the one-shot folds the triple seal and emits a
  ## single Email/set whose update patch sets keywords/$seen; the
  ## response surfaces through the S2 iterators.
  let inner = newCannedTransport(
    makeSessionJsonWithCoreCaps(realisticCoreCaps()), setUpdatedNullResponse("em-1")
  )
  let (transport, recorder) = newRecordingTransport(inner)
  let client = initJmapClient(
      directEndpoint("https://example.com/jmap").get(),
      bearerCredential("test-token").get(),
      transport,
    )
    .get()
  let res = client.markEmailsRead(makeAccountId("acct-1"), @[makeId("em-1")])
  assertOk(res)
  var updatedCount = 0
  for id, serverEcho in res.value.updated:
    updatedCount.inc
    assertEq($id, "em-1")
    doAssert serverEcho.isNone
  assertEq(updatedCount, 1)
  for _, _ in res.value.updateFailures:
    doAssert false
  # The emitted request carries the $seen patch for exactly this id.
  doAssert """"update":{"em-1":{"keywords/$seen":true}}""" in recorder.lastRequest.body,
    "the update patch must set keywords/$seen for exactly em-1"

testCase oneShotMarkEmailsUnreadEmitsRemoval:
  ## markEmailsUnread patches keywords/$seen to null (removal).
  let inner = newCannedTransport(
    makeSessionJsonWithCoreCaps(realisticCoreCaps()), setUpdatedNullResponse("em-1")
  )
  let (transport, recorder) = newRecordingTransport(inner)
  let client = initJmapClient(
      directEndpoint("https://example.com/jmap").get(),
      bearerCredential("test-token").get(),
      transport,
    )
    .get()
  let res = client.markEmailsUnread(makeAccountId("acct-1"), @[makeId("em-1")])
  assertOk(res)
  doAssert """"update":{"em-1":{"keywords/$seen":null}}""" in recorder.lastRequest.body,
    "the update patch must remove keywords/$seen (null) for exactly em-1"

testCase oneShotMarkEmailsReadSetErrorIsData:
  ## A per-id notUpdated entry stays DATA on the ok branch — the rail is
  ## reserved for whole-method failure.
  let responseJson = envelope(
    %*[
      [
        "Email/set",
        {
          "accountId": "acct-1",
          "oldState": "s1",
          "newState": "s1",
          "notUpdated": {"em-9": {"type": "notFound"}},
        },
        "c0",
      ]
    ]
  )
  let client = cannedClient(responseJson)
  let res = client.markEmailsRead(makeAccountId("acct-1"), @[makeId("em-9")])
  assertOk(res)
  var failureCount = 0
  for id, error in res.value.updateFailures:
    failureCount.inc
    assertEq($id, "em-9")
    doAssert error.kind == setNotFound,
      "the notUpdated SetError's type must survive as data, unmodified"
  assertEq(failureCount, 1)

testCase oneShotMarkEmailsReadEmptyIdsIsValidation:
  ## An empty ids list cannot form a NonEmptyEmailUpdates — the seal's
  ## own validation rides the rail; nothing is sent.
  let client = cannedClient(envelope(%*[]))
  let res = client.markEmailsRead(makeAccountId("acct-1"), newSeq[Id]())
  doAssert res.isErr, "an empty ids list must reject at the seal, not the wire"
  doAssert res.error.kind == jeValidation,
    "an empty ids list is a validation failure, not a transport one"

testCase oneShotMarkEmailsReadDuplicateIdsIsValidation:
  ## Duplicate ids cannot form a NonEmptyEmailUpdates (one entry per
  ## id) — the seal's own validation rides the rail; nothing is sent.
  let client = cannedClient(envelope(%*[]))
  let res =
    client.markEmailsRead(makeAccountId("acct-1"), @[makeId("em-1"), makeId("em-1")])
  doAssert res.isErr, "duplicate ids must reject at the seal, not the wire"
  doAssert res.error.kind == jeValidation,
    "duplicate ids are a validation failure, not a transport one"

testCase oneShotMarkEmailsReadMethodError:
  ## A whole-method error collapses fail-fast onto jeMethod.
  let responseJson = envelope(%*[["error", {"type": "serverFail"}, "c0"]])
  let client = cannedClient(responseJson)
  let res = client.markEmailsRead(makeAccountId("acct-1"), @[makeId("em-1")])
  doAssert res.isErr, "expected a rail error for a method-level failure"
  doAssert res.error.kind == jeMethod,
    "a server error invocation collapses onto jeMethod"
  doAssert res.error.methodFault.error.kind == metServerFail,
    "the method-error kind must survive onto the rail"

# -----------------------------------------------------------------------------
# moveEmails / destroyEmails
# -----------------------------------------------------------------------------

testCase oneShotMoveEmailsReplacesMembership:
  ## moveEmails is a full mailboxIds replace — the emitted patch names
  ## exactly the destination.
  let inner = newCannedTransport(
    makeSessionJsonWithCoreCaps(realisticCoreCaps()), setUpdatedNullResponse("em-1")
  )
  let (transport, recorder) = newRecordingTransport(inner)
  let client = initJmapClient(
      directEndpoint("https://example.com/jmap").get(),
      bearerCredential("test-token").get(),
      transport,
    )
    .get()
  let res =
    client.moveEmails(makeAccountId("acct-1"), @[makeId("em-1")], makeId("mb-2"))
  assertOk(res)
  doAssert """"update":{"em-1":{"mailboxIds":{"mb-2":true}}}""" in
    recorder.lastRequest.body,
    "move must replace mailboxIds wholesale, naming only the destination, for exactly em-1"

testCase oneShotDestroyEmailsSuccess:
  ## destroyEmails surfaces destroyed ids through the destroyed iterator;
  ## per-id refusals stay data in destroyFailures.
  let responseJson = envelope(
    %*[
      [
        "Email/set",
        {
          "accountId": "acct-1",
          "oldState": "s1",
          "newState": "s2",
          "destroyed": ["em-1"],
          "notDestroyed": {"em-2": {"type": "forbidden"}},
        },
        "c0",
      ]
    ]
  )
  let client = cannedClient(responseJson)
  let res =
    client.destroyEmails(makeAccountId("acct-1"), @[makeId("em-1"), makeId("em-2")])
  assertOk(res)
  var destroyedIds: seq[string] = @[]
  for id in res.value.destroyed:
    destroyedIds.add($id)
  assertEq(destroyedIds, @["em-1"])
  var refusals = 0
  for id, error in res.value.destroyFailures:
    refusals.inc
    assertEq($id, "em-2")
    doAssert error.kind == setForbidden,
      "the notDestroyed SetError's type must survive as data, unmodified"
  assertEq(refusals, 1)

testCase oneShotDestroyEmailsEmptyIdsRoundTrips:
  ## An empty ids list is legal wire and destroys nothing — the call
  ## still round-trips, unlike the update rail's seal rejection. This
  ## pins the promise against a future seal being added to the destroy
  ## path.
  let responseJson = envelope(
    %*[["Email/set", {"accountId": "acct-1", "oldState": "s1", "newState": "s1"}, "c0"]]
  )
  let client = cannedClient(responseJson)
  let res = client.destroyEmails(makeAccountId("acct-1"), newSeq[Id]())
  assertOk(res)
  var destroyedCount = 0
  for _ in res.value.destroyed:
    destroyedCount.inc
  assertEq(destroyedCount, 0)
  var failureCount = 0
  for _, _ in res.value.destroyFailures:
    failureCount.inc
  assertEq(failureCount, 0)

testCase oneShotDestroyEmailsMethodError:
  ## A whole-method error collapses fail-fast onto jeMethod.
  let responseJson = envelope(%*[["error", {"type": "forbidden"}, "c0"]])
  let client = cannedClient(responseJson)
  let res = client.destroyEmails(makeAccountId("acct-1"), @[makeId("em-1")])
  doAssert res.isErr, "expected a rail error for a method-level failure"
  doAssert res.error.kind == jeMethod,
    "a server error invocation collapses onto jeMethod"
  doAssert res.error.methodFault.error.kind == metForbidden,
    "the method-error kind must survive onto the rail"

# -----------------------------------------------------------------------------
# setVacationResponse
# -----------------------------------------------------------------------------

testCase oneShotSetVacationResponseSuccess:
  ## Enabling the singleton folds the update-set seal and dispatch into
  ## one call; the server confirms via updated["singleton"].
  let responseJson = envelope(
    %*[
      [
        "VacationResponse/set",
        {
          "accountId": "acct-1",
          "oldState": "s1",
          "newState": "s2",
          "updated": {"singleton": nil},
        },
        "c0",
      ]
    ]
  )
  let client = cannedClient(responseJson)
  let res = client.setVacationResponse(
    makeAccountId("acct-1"),
    @[
      setIsEnabled(true),
      setSubject(Opt.some("Out of office")),
      setTextBody(Opt.some("Back Monday.")),
    ],
  )
  assertOk(res)
  var confirmed = 0
  for id, serverEcho in res.value.updated:
    confirmed.inc
    assertEq($id, "singleton")
    doAssert serverEcho.isNone,
      "the canned response confirms with a null echo, so the partial-echo arm must be none"
  assertEq(confirmed, 1)

testCase oneShotSetVacationResponseEmptyIsValidation:
  ## An empty update batch has exactly one representation — not calling.
  ## The seal rejects it before any network traffic.
  let client = cannedClient(envelope(%*[]))
  let res = client.setVacationResponse(
    makeAccountId("acct-1"), newSeq[VacationResponseUpdate]()
  )
  doAssert res.isErr, "an empty update batch must reject at the seal, not the wire"
  doAssert res.error.kind == jeValidation,
    "an empty update batch is a validation failure, not a transport one"

testCase oneShotSetVacationResponseMethodError:
  ## A whole-method error collapses fail-fast onto jeMethod, matching the
  ## destroy/mark one-shots' method-error coverage.
  let responseJson = envelope(%*[["error", {"type": "serverFail"}, "c0"]])
  let client = cannedClient(responseJson)
  let res = client.setVacationResponse(makeAccountId("acct-1"), @[setIsEnabled(true)])
  doAssert res.isErr, "expected a rail error for a method-level failure"
  doAssert res.error.kind == jeMethod,
    "a server error invocation collapses onto jeMethod"
  doAssert res.error.methodFault.error.kind == metServerFail,
    "the method-error kind must survive onto the rail"

# -----------------------------------------------------------------------------
# syncEmails
# -----------------------------------------------------------------------------

testCase oneShotSyncEmailsSuccess:
  ## One round-trip yields the full fetchable delta: the changes triple
  ## plus both back-referenced gets, every outcome already collapsed
  ## onto the rail. Canned gets return empty lists — the wiring, not
  ## Email decoding, is under test (bare-get coverage owns decoding).
  ## The two Email/get responses are made distinguishable via
  ## ``notFound`` (only the c2/updated leg carries one) so the
  ## assertions below pin ``created``/``updated`` to the right handle
  ## rather than passing on a transposed swap. This is also
  ## RFC-faithful: a record updated then destroyed since ``sinceState``
  ## may legitimately surface as ``notFound`` on the ``/updated`` fetch
  ## (RFC 8620 §5.2).
  let responseJson = envelope(
    %*[
      [
        "Email/changes",
        {
          "accountId": "acct-1",
          "oldState": "s1",
          "newState": "s2",
          "hasMoreChanges": false,
          "created": ["em-new"],
          "updated": ["em-upd"],
          "destroyed": ["em-gone"],
        },
        "c0",
      ],
      [
        "Email/get",
        {"accountId": "acct-1", "state": "s2", "list": [], "notFound": []},
        "c1",
      ],
      [
        "Email/get",
        {"accountId": "acct-1", "state": "s2", "list": [], "notFound": ["em-gone"]},
        "c2",
      ],
    ]
  )
  let client = cannedClient(responseJson)
  let res = client.syncEmails(makeAccountId("acct-1"), makeState("s1"))
  assertOk(res)
  let sync = res.value
  assertEq($sync.changes.newState, "s2")
  doAssert not sync.changes.hasMoreChanges,
    "the canned response reports no further changes"
  assertLen(sync.changes.created, 1)
  assertLen(sync.changes.updated, 1)
  assertLen(sync.changes.destroyed, 1)
  assertLen(sync.created.list, 0)
  assertLen(sync.updated.list, 0)
  assertLen(sync.created.notFound, 0)
  assertLen(sync.updated.notFound, 1)
  assertEq(sync.updated.notFound[0], makeId("em-gone"))

testCase oneShotSyncEmailsChangesErrorFailsFast:
  ## cannotCalculateChanges on the changes call collapses onto jeMethod
  ## even though the dependent gets also errored — fail-fast reports the
  ## root cause, not the cascade.
  let responseJson = envelope(
    %*[
      ["error", {"type": "cannotCalculateChanges"}, "c0"],
      ["error", {"type": "invalidResultReference"}, "c1"],
      ["error", {"type": "invalidResultReference"}, "c2"],
    ]
  )
  let client = cannedClient(responseJson)
  let res = client.syncEmails(makeAccountId("acct-1"), makeState("s1"))
  doAssert res.isErr, "expected a rail error for a method-level failure"
  doAssert res.error.kind == jeMethod,
    "a server error invocation collapses onto jeMethod"
  doAssert res.error.methodFault.error.kind == metCannotCalculateChanges,
    "the root-cause changes error must survive onto the rail, not the cascade"
