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

block tvacationSetAllArmsLive:
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
    var vacAccountId: AccountId
    session.primaryAccounts.withValue("urn:ietf:params:jmap:vacationresponse", v):
      vacAccountId = v
    do:
      doAssert false, "session must advertise a primary vacationresponse account"

    let singletonId = parseIdFromServer("singleton").expect("parseId singleton")

    let fromDate = parseUtcDate("2026-06-01T00:00:00Z").expect("parseUtcDate fromDate")
    let toDate = parseUtcDate("2026-06-30T23:59:59Z").expect("parseUtcDate toDate")
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
      .expect("initVacationResponseUpdateSet all arms")
    let (b1, setHandle) =
      addVacationResponseSet(initRequestBuilder(), vacAccountId, update = updateSet)
    let resp1 = client.send(b1).expect("send VacationResponse/set all arms")
    captureIfRequested(client, "vacation-set-all-arms-stalwart").expect(
      "captureIfRequested"
    )
    let setResp1 = resp1.get(setHandle).expect("VacationResponse/set all arms extract")
    var updateOk = false
    setResp1.updateResults.withValue(singletonId, outcome):
      doAssert outcome.isOk,
        "VacationResponse/set update with all arms must succeed for singleton"
      updateOk = true
    do:
      doAssert false, "VacationResponse/set must report an outcome for singleton"
    doAssert updateOk

    # Re-read and verify all six fields.
    let (b2, getHandle) = addVacationResponseGet(initRequestBuilder(), vacAccountId)
    let resp2 = client.send(b2).expect("send VacationResponse/get post-set")
    let getResp = resp2.get(getHandle).expect("VacationResponse/get post-set extract")
    doAssert getResp.list.len == 1,
      "VacationResponse/get must return the singleton after set"
    let vr = VacationResponse.fromJson(getResp.list[0]).expect("parse VacationResponse")
    doAssert vr.isEnabled, "isEnabled must round-trip as true"
    doAssert vr.subject.isSome and vr.subject.unsafeGet == subjectText,
      "subject must round-trip"
    doAssert vr.textBody.isSome and vr.textBody.unsafeGet == bodyText,
      "textBody must round-trip"
    doAssert vr.htmlBody.isSome and vr.htmlBody.unsafeGet == htmlBodyText,
      "htmlBody must round-trip"
    doAssert vr.fromDate.isSome and string(vr.fromDate.unsafeGet) == string(fromDate),
      "fromDate must round-trip as the supplied UTC date"
    doAssert vr.toDate.isSome and string(vr.toDate.unsafeGet) == string(toDate),
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
      .expect("initVacationResponseUpdateSet cleanup")
    let (b3, _) =
      addVacationResponseSet(initRequestBuilder(), vacAccountId, update = cleanupSet)
    discard client.send(b3).expect("send VacationResponse/set cleanup")
    client.close()
