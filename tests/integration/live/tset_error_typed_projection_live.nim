# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: ``SetError.fromJson`` projects every wire
## ``type`` URI Stalwart returns for per-item /set failures into the
## closed ``SetErrorType`` enum AND preserves ``rawType`` losslessly.
## The case-object payload arms — ``setInvalidProperties.properties``
## (RFC 8620 §5.3) and ``setBlobNotFound.notFound`` (RFC 8621 §4.6) —
## deserialise the wire payload correctly. ``parseSetErrorType`` is
## total: unknown URIs project to ``setUnknown``.
##
## Phase J Step 63.  Four sub-tests drive Stalwart through four
## SetError variants the prior phases never exercised at the wire:
## ``setNotFound`` via destroy-of-synthetic-id, ``setInvalidPatch``
## via malformed JSON-Pointer in the update path, ``setInvalidProperties``
## via attempting to set a server-assigned immutable field on create,
## and ``setBlobNotFound`` via Email/import with a synthetic BlobId.
##
## **Library-contract vs server-compliance separation.**  Same
## discipline as Steps 61–62: live assertions verify the library's
## projection contract (closed-enum membership, lossless rawType,
## payload-arm field presence where applicable); the captured
## fixtures pin Stalwart's specific URI choices byte-for-byte via
## the four parser-only replay tests.  Set-membership over the
## variant axis admits Stalwart's discretion to collapse adjacent
## variants per RFC 8620 §5.3 / §5.4.

import std/json
import std/strutils
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tsetErrorTypedProjectionLive:
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
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )

    # Sub-test 1: destroy a synthetic Id that does not exist server-side.
    # Strict library-contract assertions: errorType in closed enum;
    # rawType non-empty; the Result railway carries the typed SetError
    # in the destroyResults table.
    block setNotFoundCase:
      # Stalwart 0.15.5 uses very short base32-like Ids (1–4 chars
      # typical).  A long synthetic Id is silently dropped from
      # destroyResults — Stalwart's Id parser rejects it before it
      # reaches the not-found classifier.  ``zzzz`` is a well-formed
      # short Id Stalwart will look up and reject as not-found.
      let syntheticId = Id("zzzzz")
      let (b, setHandle) = addEmailSet(
        initRequestBuilder(), mailAccountId, destroy = directIds(@[syntheticId])
      )
      let resp =
        client.send(b).expect("send Email/set destroy synthetic[" & $target.kind & "]")
      captureIfRequested(client, "set-error-not-found-" & $target.kind).expect(
        "captureIfRequested setNotFound"
      )
      let setResp =
        resp.get(setHandle).expect("Email/set extract[" & $target.kind & "]")
      var rejected = false
      setResp.destroyResults.withValue(syntheticId, outcome):
        assertOn target, outcome.isErr, "destroy of synthetic id must Err"
        let se = outcome.error
        assertOn target, se.rawType.len > 0, "rawType must be losslessly preserved"
        assertOn target,
          se.errorType in {setNotFound, setForbidden, setUnknown},
          "errorType must project into the closed SetErrorType enum, got " &
            $se.errorType
        rejected = true
      do:
        assertOn target, false, "Email/set must report an outcome for the synthetic id"
      assertOn target, rejected

    # Sub-test 2: PatchObject path naming a property that does not
    # exist in the Email schema.  RFC 8620 §5.3 mandates rejection
    # with ``invalidPatch`` when "the path resolves to an unknown
    # property".  Stalwart 0.15.5 has been empirically observed to
    # silently accept several malformed-patch shapes (string-typed
    # patch values; ``~7`` JSON-Pointer escapes); naming a wholly
    # unknown property is the reliable trigger.
    const seedSubject = "phase-j 63 setError seed"
    let seedId = seedSimpleEmail(
        client, mailAccountId, inbox, seedSubject, "phase-j-63-seed"
      )
      .expect("seedSimpleEmail[" & $target.kind & "]")
    block setInvalidPatchCase:
      let resp = sendRawInvocation(
          client,
          capabilityUris = @["urn:ietf:params:jmap:mail"],
          methodName = "Email/set",
          arguments = %*{
            "accountId": $mailAccountId,
            "update": {string(seedId): {"phaseJSyntheticProperty": "phase-j 63 patch"}},
          },
        )
        .expect("sendRawInvocation setInvalidPatch[" & $target.kind & "]")
      captureIfRequested(client, "set-error-invalid-patch-" & $target.kind).expect(
        "captureIfRequested setInvalidPatch"
      )
      assertOn target, resp.methodResponses.len == 1
      let inv = resp.methodResponses[0]
      assertOn target,
        inv.rawName == "Email/set" or inv.rawName == "error",
        "expected Email/set or error, got " & inv.rawName
      if inv.rawName == "Email/set":
        let setResp = SetResponse[EmailCreatedItem].fromJson(inv.arguments).expect(
            "SetResponse.fromJson"
          )
        var rejected = false
        setResp.updateResults.withValue(seedId, outcome):
          assertOn target, outcome.isErr, "update with unknown property must Err"
          let se = outcome.error
          assertOn target, se.rawType.len > 0, "rawType must be losslessly preserved"
          assertOn target,
            se.errorType in
              {setInvalidPatch, setInvalidProperties, setForbidden, setUnknown},
            "errorType must project into the closed SetErrorType enum, got " &
              $se.errorType
          rejected = true
        do:
          assertOn target, false, "Email/set must report an outcome for the seeded id"
        assertOn target, rejected
      else:
        let me = MethodError.fromJson(inv.arguments).expect(
            "MethodError.fromJson[" & $target.kind & "]"
          )
        assertOn target, me.rawType.len > 0, "rawType must be losslessly preserved"
        assertOn target,
          me.errorType in
            {metInvalidArguments, metUnknownMethod, metServerFail, metUnknown},
          "method-level fallback must project into the closed enum, got " & $me.errorType

    # Sub-test 3: Email/set create attempting to set the server-assigned
    # immutable ``id`` field.  RFC 8620 §5.3 mandates rejection with
    # ``setInvalidProperties``; the SetError arm carries the offending
    # property names in ``properties``.
    block setInvalidPropertiesCase:
      let resp = sendRawInvocation(
          client,
          capabilityUris = @["urn:ietf:params:jmap:mail"],
          methodName = "Email/set",
          arguments = %*{
            "accountId": $mailAccountId,
            "create": {
              "phaseJ63": {
                "id": "client-supplied-id",
                "subject": "phase-j 63 invalidProperties",
                "mailboxIds": {string(inbox): true},
              }
            },
          },
        )
        .expect("sendRawInvocation setInvalidProperties[" & $target.kind & "]")
      captureIfRequested(client, "set-error-invalid-properties-" & $target.kind).expect(
        "captureIfRequested setInvalidProperties"
      )
      assertOn target, resp.methodResponses.len == 1
      let inv = resp.methodResponses[0]
      # RFC 8620 §5.3 lets servers reject an immutable-property create
      # at either the set level (``Email/set`` rawName + ``notCreated``
      # SetError) or the method level (``error`` rawName + MethodError
      # — the entire invocation aborts before per-create dispatch).
      # Stalwart 0.15.5 takes the set-level path; Apache James 3.9
      # validates ``id`` at the request-parsing stage and emits a
      # method-level ``invalidArguments``. Both paths are RFC-conformant
      # — the library projection contract is what's under test.
      if inv.rawName == "Email/set":
        let setResp = SetResponse[EmailCreatedItem].fromJson(inv.arguments).expect(
            "SetResponse.fromJson"
          )
        let cidLabel =
          parseCreationId("phaseJ63").expect("parseCreationId[" & $target.kind & "]")
        var rejected = false
        setResp.createResults.withValue(cidLabel, outcome):
          assertOn target, outcome.isErr, "create with immutable property set must Err"
          let se = outcome.error
          assertOn target, se.rawType.len > 0, "rawType must be losslessly preserved"
          assertOn target,
            se.errorType in {setInvalidProperties, setForbidden, setUnknown},
            "errorType must project into the closed SetErrorType enum, got " &
              $se.errorType
          if se.errorType == setInvalidProperties:
            assertOn target,
              se.properties.len >= 1,
              "setInvalidProperties payload arm must carry at least one " &
                "offending property name"
          rejected = true
        do:
          assertOn target,
            false, "Email/set must report an outcome for the create label"
        assertOn target, rejected
      else:
        assertOn target,
          inv.rawName == "error",
          "method-level rejection must surface as 'error', got " & inv.rawName
        let me = MethodError.fromJson(inv.arguments).expect(
            "MethodError.fromJson[" & $target.kind & "]"
          )
        assertOn target, me.rawType.len > 0, "rawType must be losslessly preserved"
        assertOn target,
          me.errorType in
            {metInvalidArguments, metUnknownMethod, metServerFail, metUnknown},
          "method-level fallback must project into the closed enum, got " & $me.errorType

    # Sub-test 4: Email/import with a synthetic BlobId that does not
    # resolve.  RFC 8621 §4.6 mandates ``setBlobNotFound`` with the
    # unresolved BlobIds carried in ``notFound``.
    #
    # Stalwart 0.15.5 deviates: collapses ``setBlobNotFound`` onto
    # ``setInvalidProperties`` with the offending property name in
    # ``properties: ["blobId"]`` and a description of "Invalid blob
    # id." — same collapse pattern as Stalwart's Step 61 / sub-test
    # 2 behaviour.  Live assertion uses set-membership; the captured
    # fixture pins Stalwart's specific projection byte-for-byte.
    block setBlobNotFoundCase:
      let syntheticBlobId = "phaseJSyntheticBlob" & "z".repeat(8)
      let resp = sendRawInvocation(
          client,
          capabilityUris = @["urn:ietf:params:jmap:mail"],
          methodName = "Email/import",
          arguments = %*{
            "accountId": $mailAccountId,
            "emails": {
              "phaseJ63blob":
                {"blobId": syntheticBlobId, "mailboxIds": {string(inbox): true}}
            },
          },
        )
        .expect("sendRawInvocation setBlobNotFound[" & $target.kind & "]")
      captureIfRequested(client, "set-error-blob-not-found-" & $target.kind).expect(
        "captureIfRequested setBlobNotFound"
      )
      assertOn target, resp.methodResponses.len == 1
      let inv = resp.methodResponses[0]
      assertOn target,
        inv.rawName == "Email/import" or inv.rawName == "error",
        "expected Email/import or error, got " & inv.rawName
      if inv.rawName == "Email/import":
        let setResp = EmailImportResponse.fromJson(inv.arguments).expect(
            "EmailImportResponse.fromJson"
          )
        let cidLabel = parseCreationId("phaseJ63blob").expect(
            "parseCreationId[" & $target.kind & "]"
          )
        var rejected = false
        setResp.createResults.withValue(cidLabel, outcome):
          assertOn target, outcome.isErr, "Email/import with synthetic blob must Err"
          let se = outcome.error
          assertOn target, se.rawType.len > 0, "rawType must be losslessly preserved"
          assertOn target,
            se.errorType in
              {setBlobNotFound, setInvalidProperties, setForbidden, setUnknown},
            "errorType must project into the closed SetErrorType enum, got " &
              $se.errorType
          if se.errorType == setBlobNotFound:
            assertOn target,
              se.notFound.len >= 1,
              "setBlobNotFound payload arm must carry the unresolved BlobIds"
          elif se.errorType == setInvalidProperties:
            assertOn target,
              se.properties.len >= 1,
              "setInvalidProperties payload arm must carry the offending " &
                "property name(s)"
          rejected = true
        do:
          assertOn target,
            false, "Email/import must report an outcome for the create label"
        assertOn target, rejected
      else:
        let me = MethodError.fromJson(inv.arguments).expect(
            "MethodError.fromJson[" & $target.kind & "]"
          )
        assertOn target, me.rawType.len > 0, "rawType must be losslessly preserved"
        assertOn target,
          me.errorType in
            {metInvalidArguments, metUnknownMethod, metServerFail, metUnknown},
          "method-level fallback must project into the closed enum, got " & $me.errorType

    # Cleanup: destroy seedId so re-runs are idempotent.
    let (bClean, cleanHandle) =
      addEmailSet(initRequestBuilder(), mailAccountId, destroy = directIds(@[seedId]))
    let respClean =
      client.send(bClean).expect("send Email/set cleanup[" & $target.kind & "]")
    let cleanResp = respClean.get(cleanHandle).expect(
        "Email/set cleanup extract[" & $target.kind & "]"
      )
    cleanResp.destroyResults.withValue(seedId, outcome):
      assertOn target, outcome.isOk, "cleanup destroy of seed must succeed"
    do:
      assertOn target, false, "cleanup must report an outcome for seedId"

    client.close()
