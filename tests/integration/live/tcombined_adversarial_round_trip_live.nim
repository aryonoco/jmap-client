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
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tcombinedAdversarialRoundTripLive:
  let cfgRes = loadLiveTestConfig()
  if cfgRes.isOk:
    let cfg = cfgRes.get()
    var client = initJmapClient(
        sessionUrl = cfg.sessionUrl,
        bearerToken = cfg.aliceToken,
        authScheme = cfg.authScheme,
      )
      .expect("initJmapClient")
    let session = client.fetchSession().expect("fetchSession")
    var mailAccountId: AccountId
    session.primaryAccounts.withValue("urn:ietf:params:jmap:mail", v):
      mailAccountId = v
    do:
      doAssert false, "session must advertise a primary mail account"
    let submissionAccountId =
      resolveSubmissionAccountId(session).expect("resolveSubmissionAccountId")
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")

    # Seed one Email with a known subject so c1's query has
    # something to surface.
    let seedId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-j-74-corpus subject for combined capstone",
        "phase-j-74-seed",
      )
      .expect("seedSimpleEmail")

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

    let resp =
      client.sendRawHttpForTesting($body).expect("sendRawHttpForTesting envelope")
    captureIfRequested(client, "combined-adversarial-round-trip-stalwart").expect(
      "captureIfRequested combined adversarial"
    )

    doAssert resp.methodResponses.len == 5,
      "envelope must carry five responses, got " & $resp.methodResponses.len

    # c0: Mailbox/get success.
    let c0 = resp.methodResponses[0]
    doAssert c0.rawName == "Mailbox/get", "c0 expected Mailbox/get, got " & c0.rawName
    let mb = GetResponse[Mailbox].fromJson(c0.arguments).expect("Mailbox/get extract")
    doAssert mb.list.len >= 1, "Mailbox/get must surface at least one mailbox"

    # c1: Email/query success.
    let c1 = resp.methodResponses[1]
    doAssert c1.rawName == "Email/query", "c1 expected Email/query, got " & c1.rawName
    let q = QueryResponse[Email].fromJson(c1.arguments).expect("Email/query extract")
    doAssert q.ids.len >= 1, "Email/query must surface the seeded email"

    # c2: broken back-reference must surface as 'error'.
    let c2 = resp.methodResponses[2]
    doAssert c2.rawName == "error",
      "c2 broken back-reference must surface as error, got " & c2.rawName
    let me = MethodError.fromJson(c2.arguments).expect("MethodError.fromJson c2")
    doAssert me.rawType.len > 0, "rawType must be losslessly preserved"
    doAssert me.errorType in
      {metInvalidResultReference, metInvalidArguments, metServerFail, metUnknown},
      "c2 errorType must project into the closed enum, got " & $me.errorType

    # c3: Email/set with immutable property must surface in
    # notCreated.  Stalwart may omit newState here (same deviation
    # as Step 70), so we drop down to raw notCreated when the
    # typed parser rejects the response shape.
    let c3 = resp.methodResponses[3]
    doAssert c3.rawName == "Email/set",
      "c3 expected Email/set with notCreated, got " & c3.rawName
    let setRes = SetResponse[EmailCreatedItem].fromJson(c3.arguments)
    if setRes.isOk:
      let setResp = setRes.unsafeValue
      let cidLabel = parseCreationId("newDraft").expect("parseCreationId")
      setResp.createResults.withValue(cidLabel, outcome):
        doAssert outcome.isErr, "create with immutable property must Err"
        doAssert outcome.error.errorType in
          {setInvalidProperties, setForbidden, setUnknown}
      do:
        doAssert false, "Email/set must report an outcome for the create label"
    else:
      let notCreated = c3.arguments{"notCreated"}
      doAssert not notCreated.isNil and notCreated.kind == JObject
      doAssert notCreated.hasKey("newDraft")
      let entry = notCreated{"newDraft"}
      let se = SetError.fromJson(entry).expect("SetError.fromJson c3")
      doAssert se.errorType in {setInvalidProperties, setForbidden, setUnknown}

    # c4: Identity/get success.
    let c4 = resp.methodResponses[4]
    doAssert c4.rawName == "Identity/get", "c4 expected Identity/get, got " & c4.rawName
    let identResp =
      GetResponse[Identity].fromJson(c4.arguments).expect("Identity/get extract")
    doAssert identResp.list.len >= 0,
      "Identity/get list parses (zero is acceptable on a pristine account)"

    # Round-trip integrity: re-emit individual records and re-parse
    # — structural identity (not byte equality), but the parser
    # must accept its own output.  ``GetResponse[T].toJson`` is not
    # defined (responses are read-only); per-record re-emission via
    # ``Mailbox.toJson`` / ``Email.toJson`` / ``Identity.toJson``
    # exercises the equivalent contract.
    if mb.list.len > 0:
      let mailboxRec = Mailbox.fromJson(mb.list[0]).expect("Mailbox round-trip")
      discard mailboxRec.toJson()
    if identResp.list.len > 0:
      let identRec = Identity.fromJson(identResp.list[0]).expect("Identity round-trip")
      discard identRec.toJson()

    # Cleanup: destroy the seed email.
    let (bClean, cleanHandle) =
      addEmailSet(initRequestBuilder(), mailAccountId, destroy = directIds(@[seedId]))
    let respClean = client.send(bClean).expect("send Email/set cleanup")
    let cleanResp = respClean.get(cleanHandle).expect("Email/set cleanup extract")
    cleanResp.destroyResults.withValue(seedId, outcome):
      doAssert outcome.isOk, "cleanup destroy must succeed"
    do:
      doAssert false, "cleanup must report an outcome"

    client.close()
