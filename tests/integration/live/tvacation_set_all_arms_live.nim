# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Phase I Step 58 — wire test of ``VacationResponse/set`` covering
## the three update arms not exercised by Phase B9: ``setHtmlBody``,
## ``setFromDate``, ``setToDate``.  Phase B9 covered ``setIsEnabled``,
## ``setSubject``, ``setTextBody``.
##
## **Why three new arms, not four.** The plan-doc anticipated a
## ``setReplyTo`` arm; RFC 8621 §8 defines no ``replyTo`` field on
## ``VacationResponse`` (the four properties are ``isEnabled``,
## ``fromDate``, ``toDate``, ``subject``, ``textBody``, ``htmlBody``),
## so no ``setReplyTo`` constructor exists.  Step 58 asserts the
## three real new arms.
##
## Workflow:
##
##  1. Resolve VacationResponse account.
##  2. Issue VacationResponse/set with all three new arms plus the
##     three from B9 (six total) so the singleton is fully shaped.
##     Capture the wire response.
##  3. Re-read via VacationResponse/get and assert all six fields
##     round-trip.
##  4. Cleanup: disable + clear all date / body fields so the
##     singleton is left in a benign state for subsequent runs.
##
## Capture: ``vacation-set-all-arms-stalwart``.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it;
## run via ``just test-integration`` after ``just stalwart-up``.
## Body is guarded on ``loadLiveTestTargets().isOk`` so the file
## joins testament's megatest cleanly under ``just test-full`` when
## env vars are absent.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tvacationSetAllArmsLive:
  forEachLiveTarget(target):
    # Cat-B (Phase L §0): Stalwart 0.15.5 and James 3.9 implement
    # VacationResponse/set's full update-arm surface. Cyrus 3.12.2
    # disables vacation in the test image (``imapd.conf:
    # jmap_vacation: no``); the unregistered-method dispatch path
    # (``imap/jmap_api.c:713-714``) returns ``metUnknownMethod`` for
    # both methods, so the Cat-B error arm exercises the typed-error
    # projection.
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    var vacAccountId: AccountId
    var vacAccountFound = false
    session.primaryAccounts.withValue("urn:ietf:params:jmap:vacationresponse", v):
      vacAccountId = v
      vacAccountFound = true
    do:
      discard
    if not vacAccountFound:
      client.close()
      continue

    let singletonId =
      parseIdFromServer("singleton").expect("parseId singleton[" & $target.kind & "]")

    let fromDate = parseUtcDate("2026-06-01T00:00:00Z").expect(
        "parseUtcDate fromDate[" & $target.kind & "]"
      )
    let toDate = parseUtcDate("2026-06-30T23:59:59Z").expect(
        "parseUtcDate toDate[" & $target.kind & "]"
      )
    const subjectText = "phase-i 58 OOO"
    const bodyText = "Plain text auto-reply body."
    const htmlBodyText = "<p>HTML auto-reply body.</p>"

    let updateSet = initVacationResponseUpdateSet(
        @[
          setIsEnabled(true),
          setSubject(Opt.some(subjectText)),
          setTextBody(Opt.some(bodyText)),
          setHtmlBody(Opt.some(htmlBodyText)),
          setFromDate(Opt.some(fromDate)),
          setToDate(Opt.some(toDate)),
        ]
      )
      .expect("initVacationResponseUpdateSet all arms[" & $target.kind & "]")
    let (b1, setHandle) = addVacationResponseSet(
      initRequestBuilder(makeBuilderId()), vacAccountId, update = updateSet
    )
    # Cyrus 3.12.2 ships VacationResponse but the test image disables
    # it via ``imapd.conf: jmap_vacation: no``; the URN is absent
    # from the session's ``capabilities`` map and Cyrus rejects the
    # request at the request level with
    # ``urn:ietf:params:jmap:error:unknownCapability``. The library's
    # typed-error rail (``Err(ClientError(cekRequest, ...))``) IS the
    # universal client-library contract here. The capture call below
    # writes the wire response on every target — set-response on
    # Stalwart/James, unknownCapability on Cyrus — and the captured-
    # replay suite round-trips both shapes. mcapture's skip-if-exists
    # preserves existing Stalwart/James fixtures.
    let resp1Result = client.send(b1.freeze())
    captureIfRequested(client, "vacation-set-all-arms-" & $target.kind).expect(
      "captureIfRequested"
    )
    if resp1Result.isErr:
      case target.kind
      of ltkCyrus:
        let err = resp1Result.error
        assertOn target,
          err.kind == cekRequest,
          "Cyrus must surface unknownCapability as a request-level error (got " &
            $err.kind & ")"
      of ltkStalwart, ltkJames:
        assertOn target,
          false, "VacationResponse/set all arms must succeed on " & $target.kind
      client.close()
      continue
    let resp1 = resp1Result.unsafeValue
    let setExtract = resp1.get(setHandle)
    var updateOk = false
    assertSuccessOrTypedError(target, setExtract, {metUnknownMethod}):
      let setResp1 = success
      setResp1.updateResults.withValue(singletonId, outcome):
        if outcome.isOk:
          updateOk = true
      do:
        assertOn target,
          false, "VacationResponse/set must report an outcome for singleton"

    if updateOk:
      # Re-read and verify all six fields.
      let (b2, getHandle) =
        addVacationResponseGet(initRequestBuilder(makeBuilderId()), vacAccountId)
      let resp2 = client.send(b2.freeze()).expect(
          "send VacationResponse/get post-set[" & $target.kind & "]"
        )
      let getExtract = resp2.get(getHandle)
      assertSuccessOrTypedError(target, getExtract, {metUnknownMethod}):
        let getResp = success
        assertOn target,
          getResp.list.len == 1,
          "VacationResponse/get must return the singleton after set"
        let vr = getResp.list[0]
        assertOn target, vr.isEnabled, "isEnabled must round-trip as true"
        assertOn target,
          vr.subject.isSome and vr.subject.unsafeGet == subjectText,
          "subject must round-trip"
        assertOn target,
          vr.textBody.isSome and vr.textBody.unsafeGet == bodyText,
          "textBody must round-trip"
        assertOn target,
          vr.htmlBody.isSome and vr.htmlBody.unsafeGet == htmlBodyText,
          "htmlBody must round-trip"
        assertOn target,
          vr.fromDate.isSome and string(vr.fromDate.unsafeGet) == string(fromDate),
          "fromDate must round-trip as the supplied UTC date"
        assertOn target,
          vr.toDate.isSome and string(vr.toDate.unsafeGet) == string(toDate),
          "toDate must round-trip as the supplied UTC date"

      # Cleanup: disable + clear date / body / subject fields.
      let cleanupSet = initVacationResponseUpdateSet(
          @[
            setIsEnabled(false),
            setSubject(Opt.none(string)),
            setTextBody(Opt.none(string)),
            setHtmlBody(Opt.none(string)),
            setFromDate(Opt.none(UTCDate)),
            setToDate(Opt.none(UTCDate)),
          ]
        )
        .expect("initVacationResponseUpdateSet cleanup[" & $target.kind & "]")
      let (b3, _) = addVacationResponseSet(
        initRequestBuilder(makeBuilderId()), vacAccountId, update = cleanupSet
      )
      discard client.send(b3.freeze()).expect(
          "send VacationResponse/set cleanup[" & $target.kind & "]"
        )
    client.close()
