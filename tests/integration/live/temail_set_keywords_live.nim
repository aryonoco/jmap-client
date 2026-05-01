# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Email/set with the ``ifInState`` guard
## (RFC 8620 §5.3) against Stalwart. Two paths exercised in one test:
##
## 1. Happy path — set the IANA ``$seen`` keyword on a seeded Email
##    using ``ifInState`` matched to the freshly-fetched ``state``.
##    Asserts the update succeeds, then re-fetches and asserts the
##    keyword is now present on the wire.
##
## 2. Conflict path — re-issue the same /set with a now-stale
##    ``ifInState`` (the value captured before the happy path applied).
##    Asserts the response is a method-level error of type
##    ``metStateMismatch`` projected through the L3 error rail.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestConfig().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.
##
## Seeds one Email of its own (does not depend on Step 6's seed) so the
## test runs cleanly against a freshly-reset Stalwart and asserts a
## known-good keyword transition without hunting for an arbitrary id.
## Inbox lookup and email seed are delegated to ``mlive``.

import std/json
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mconfig
import ./mlive

block temailSetKeywordsLive:
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

    # --- Resolve inbox + seed a fresh email (mlive helpers) --------------
    let inbox = resolveInboxId(client, mailAccountId).expect("resolveInboxId")
    let seededId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-1 step-7 keyword seed", "seedKeyword"
      )
      .expect("seedSimpleEmail")

    # --- Capture pre-update state via Email/get --------------------------
    let (b3, getHandle1) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "keywords"]),
    )
    let resp3 = client.send(b3).expect("send Email/get pre-update")
    let getResp1 = resp3.get(getHandle1).expect("Email/get pre-update extract")
    doAssert getResp1.list.len == 1, "Email/get must return the seeded message"
    let staleState = getResp1.state

    # --- Happy path: set $seen with matching ifInState -------------------
    let updateSet = initEmailUpdateSet(@[markRead()]).expect("initEmailUpdateSet")
    let updates = parseNonEmptyEmailUpdates(@[(seededId, updateSet)]).expect(
        "parseNonEmptyEmailUpdates"
      )
    let (b4, setHandle1) = addEmailSet(
      initRequestBuilder(),
      mailAccountId,
      ifInState = Opt.some(staleState),
      update = Opt.some(updates),
    )
    let resp4 = client.send(b4).expect("send Email/set update happy")
    let setResp1 = resp4.get(setHandle1).expect("Email/set update happy extract")
    let updateOutcome = setResp1.updateResults[seededId]
    doAssert updateOutcome.isOk,
      "happy-path Email/set must succeed when ifInState matches"

    # --- Verify $seen keyword is now present -----------------------------
    let (b5, getHandle2) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "keywords"]),
    )
    let resp5 = client.send(b5).expect("send Email/get post-update")
    let getResp2 = resp5.get(getHandle2).expect("Email/get post-update extract")
    doAssert getResp2.list.len == 1, "Email/get must return the seeded message"
    let kwNode = getResp2.list[0]{"keywords"}
    doAssert not kwNode.isNil,
      "Email/get with properties=[id, keywords] must return a keywords field"
    # Parse just the keywords field as a typed KeywordSet — Email/get with
    # restricted properties returns a partial entity, so the strict
    # ``emailFromJson`` parser does not apply (Email requires every field).
    # ``KeywordSet.fromJson`` is the right granularity for this assertion.
    let keywords = KeywordSet.fromJson(kwNode).expect("parse KeywordSet")
    doAssert kwSeen in keywords, "$seen must be present after happy-path Email/set"

    # --- Conflict path: same update with the stale ifInState -------------
    let updateSetAgain = initEmailUpdateSet(@[markRead()]).expect("initEmailUpdateSet")
    let updatesAgain = parseNonEmptyEmailUpdates(@[(seededId, updateSetAgain)]).expect(
        "parseNonEmptyEmailUpdates"
      )
    let (b6, setHandle2) = addEmailSet(
      initRequestBuilder(),
      mailAccountId,
      ifInState = Opt.some(staleState),
      update = Opt.some(updatesAgain),
    )
    let resp6 = client.send(b6).expect("send Email/set update conflict")
    let conflictExtract = resp6.get(setHandle2)
    doAssert conflictExtract.isErr,
      "stale-ifInState Email/set must raise a method-level error"
    let methodErr = conflictExtract.error
    doAssert methodErr.errorType == metStateMismatch,
      "method error must project as metStateMismatch (got rawType=" & methodErr.rawType &
        ")"
    client.close()
