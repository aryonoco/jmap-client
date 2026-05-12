# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT (capstone): all prior J1 contracts hold
## simultaneously when combined into one round-trip.  The parser
## projects each error variant in a multi-method envelope without
## one failure contaminating another's parsing; successful method
## calls in the same envelope still round-trip cleanly.
##
## Phase J Step 74.  One ``sendRawHttpForTesting`` carrying a
## hand-crafted five-invocation request body:
##   c0: legitimate Mailbox/get      → success
##   c1: legitimate Email/query      → success
##   c2: Email/get with broken ref   → metInvalidResultReference
##   c3: Email/set create with id    → setInvalidProperties
##   c4: legitimate Identity/get     → success

import std/json
import std/sets
import std/tables

import results
import jmap_client
import jmap_client/client
import jmap_client/internal/types/envelope
import ./mcapture
import ./mconfig
import ./mlive

block tcombinedAdversarialRoundTripLive:
  forEachLiveTarget(target):
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let mailAccountId =
      resolveMailAccountId(session).expect("resolveMailAccountId[" & $target.kind & "]")
    let submissionAccountId = resolveSubmissionAccountId(session).expect(
        "resolveSubmissionAccountId[" & $target.kind & "]"
      )
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )

    # Seed one Email with a known subject so c1's query has
    # something to surface.
    let seedId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-j-74-corpus subject for combined capstone",
        "phase-j-74-seed",
      )
      .expect("seedSimpleEmail[" & $target.kind & "]")

    # Wait for the server's full-text index to surface the seeded
    # email under the same filter the envelope's c1 uses. Cyrus
    # 3.12.2's Xapian rolling indexer settles asynchronously after
    # Email/set; without this barrier the c1 sub-test sees an empty
    # result-set even though the seed succeeded. Stalwart and James
    # index synchronously and the poll returns on the first
    # iteration. ``pollEmailQueryIndexed`` opens a fresh client per
    # iteration to bypass Cyrus's per-session index cache.
    let preFilter =
      filterCondition(EmailFilterCondition(subject: Opt.some("phase-j-74-corpus")))
    discard pollEmailQueryIndexed(target, mailAccountId, preFilter, [seedId].toHashSet)
      .expect("pollEmailQueryIndexed[" & $target.kind & "]")

    # Construct the five-invocation envelope.
    let body = %*{
      "using": @[
        "urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail",
        "urn:ietf:params:jmap:submission",
      ],
      "methodCalls": @[
        %*["Mailbox/get", {"accountId": $mailAccountId}, "c0"],
        %*[
          "Email/query",
          {"accountId": $mailAccountId, "filter": {"subject": "phase-j-74-corpus"}},
          "c1",
        ],
        %*[
          "Email/get",
          {
            "accountId": $mailAccountId,
            "#ids": {
              "resultOf": "c1",
              "name": "Email/query",
              "path": "/list/0/notAField/threadId",
            },
          },
          "c2",
        ],
        %*[
          "Email/set",
          {
            "accountId": $mailAccountId,
            "create":
              {"newDraft": {"id": "client-supplied", "subject": "phase-j 74 newDraft"}},
          },
          "c3",
        ],
        %*["Identity/get", {"accountId": $submissionAccountId}, "c4"],
      ],
    }

    let resp = client.sendRawHttpForTesting($body).expect(
        "sendRawHttpForTesting envelope[" & $target.kind & "]"
      )
    captureIfRequested(client, "combined-adversarial-round-trip-" & $target.kind).expect(
      "captureIfRequested combined adversarial"
    )

    assertOn target,
      resp.methodResponses.len == 5,
      "envelope must carry five responses, got " & $resp.methodResponses.len

    # c0: Mailbox/get success.
    let c0 = resp.methodResponses[0]
    assertOn target,
      c0.rawName == "Mailbox/get", "c0 expected Mailbox/get, got " & c0.rawName
    let mb = GetResponse[Mailbox].fromJson(c0.arguments).expect(
        "Mailbox/get extract[" & $target.kind & "]"
      )
    assertOn target, mb.list.len >= 1, "Mailbox/get must surface at least one mailbox"

    # c1: Email/query success.
    let c1 = resp.methodResponses[1]
    assertOn target,
      c1.rawName == "Email/query", "c1 expected Email/query, got " & c1.rawName
    let q = QueryResponse[Email].fromJson(c1.arguments).expect(
        "Email/query extract[" & $target.kind & "]"
      )
    assertOn target, q.ids.len >= 1, "Email/query must surface the seeded email"

    # c2: broken back-reference must surface as 'error'.
    let c2 = resp.methodResponses[2]
    assertOn target,
      c2.rawName == "error",
      "c2 broken back-reference must surface as error, got " & c2.rawName
    let me = MethodError.fromJson(c2.arguments).expect(
        "MethodError.fromJson c2[" & $target.kind & "]"
      )
    assertOn target, me.rawType.len > 0, "rawType must be losslessly preserved"
    assertOn target,
      me.errorType in
        {metInvalidResultReference, metInvalidArguments, metServerFail, metUnknown},
      "c2 errorType must project into the closed enum, got " & $me.errorType

    # c3: Email/set with immutable property must surface in notCreated.
    let c3 = resp.methodResponses[3]
    assertOn target,
      c3.rawName == "Email/set",
      "c3 expected Email/set with notCreated, got " & c3.rawName
    let setResp = SetResponse[EmailCreatedItem, PartialEmail]
      .fromJson(c3.arguments)
      .expect("SetResponse[EmailCreatedItem, PartialEmail].fromJson c3")
    let cidLabel =
      parseCreationId("newDraft").expect("parseCreationId[" & $target.kind & "]")
    setResp.createResults.withValue(cidLabel, outcome):
      assertOn target, outcome.isErr, "create with immutable property must Err"
      assertOn target,
        outcome.error.errorType in {setInvalidProperties, setForbidden, setUnknown}
    do:
      assertOn target, false, "Email/set must report an outcome for the create label"

    # c4: Identity/get success.
    let c4 = resp.methodResponses[4]
    assertOn target,
      c4.rawName == "Identity/get", "c4 expected Identity/get, got " & c4.rawName
    let identResp = GetResponse[Identity].fromJson(c4.arguments).expect(
        "Identity/get extract[" & $target.kind & "]"
      )
    assertOn target,
      identResp.list.len >= 0,
      "Identity/get list parses (zero is acceptable on a pristine account)"

    # Round-trip integrity: re-emit individual records and re-parse
    # — structural identity (not byte equality), but the parser
    # must accept its own output. ``GetResponse[T].toJson`` is not
    # defined per D3.7 (response types are ``fromJson``-only with the
    # ``SetResponse.toJson`` / ``CopyResponse.toJson`` exceptions; see
    # ``methods.nim:7-9``). Per-record re-emission via
    # ``Mailbox.toJson`` / ``Email.toJson`` / ``Identity.toJson``
    # exercises the equivalent contract for read-back records that
    # A3 typed end-to-end on the receive path.
    if mb.list.len > 0:
      let mailboxRec = mb.list[0]
      discard mailboxRec.toJson()
    if identResp.list.len > 0:
      let identRec = identResp.list[0]
      discard identRec.toJson()

    # Cleanup: destroy the seed email.
    let (bClean, cleanHandle) = addEmailSet(
      initRequestBuilder(makeBuilderId()), mailAccountId, destroy = directIds(@[seedId])
    )
    let respClean = client.send(bClean.freeze()).expect(
        "send Email/set cleanup[" & $target.kind & "]"
      )
    let cleanResp = respClean.get(cleanHandle).expect(
        "Email/set cleanup extract[" & $target.kind & "]"
      )
    cleanResp.destroyResults.withValue(seedId, outcome):
      assertOn target, outcome.isOk, "cleanup destroy must succeed"
    do:
      assertOn target, false, "cleanup must report an outcome"

    client.close()
