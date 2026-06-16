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
