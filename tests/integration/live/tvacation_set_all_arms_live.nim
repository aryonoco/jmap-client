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
## Body is guarded on ``loadLiveTestConfig().isOk`` so the file
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
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    var vacAccountId: AccountId
    session.primaryAccounts.withValue("urn:ietf:params:jmap:vacationresponse", v):
      vacAccountId = v
    do:
      assertOn target,
        false, "session must advertise a primary vacationresponse account"

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
    let (b1, setHandle) =
      addVacationResponseSet(initRequestBuilder(), vacAccountId, update = updateSet)
    let resp1 =
      client.send(b1).expect("send VacationResponse/set all arms[" & $target.kind & "]")
    captureIfRequested(client, "vacation-set-all-arms-" & $target.kind).expect(
      "captureIfRequested"
    )
    let setResp1 = resp1.get(setHandle).expect(
        "VacationResponse/set all arms extract[" & $target.kind & "]"
      )
    var updateOk = false
    setResp1.updateResults.withValue(singletonId, outcome):
      assertOn target,
        outcome.isOk,
        "VacationResponse/set update with all arms must succeed for singleton"
      updateOk = true
    do:
      assertOn target,
        false, "VacationResponse/set must report an outcome for singleton"
    assertOn target, updateOk

    # Re-read and verify all six fields.
    let (b2, getHandle) = addVacationResponseGet(initRequestBuilder(), vacAccountId)
    let resp2 =
      client.send(b2).expect("send VacationResponse/get post-set[" & $target.kind & "]")
    let getResp = resp2.get(getHandle).expect(
        "VacationResponse/get post-set extract[" & $target.kind & "]"
      )
    assertOn target,
      getResp.list.len == 1, "VacationResponse/get must return the singleton after set"
    let vr = VacationResponse.fromJson(getResp.list[0]).expect(
        "parse VacationResponse[" & $target.kind & "]"
      )
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
    let (b3, _) =
      addVacationResponseSet(initRequestBuilder(), vacAccountId, update = cleanupSet)
    discard
      client.send(b3).expect("send VacationResponse/set cleanup[" & $target.kind & "]")
    client.close()
