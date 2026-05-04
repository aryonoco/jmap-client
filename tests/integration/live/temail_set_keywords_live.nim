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

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block temailSetKeywordsLive:
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

    # --- Resolve inbox + seed a fresh email (mlive helpers) --------------
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let seededId = seedSimpleEmail(
        client, mailAccountId, inbox, "phase-1 step-7 keyword seed", "seedKeyword"
      )
      .expect("seedSimpleEmail[" & $target.kind & "]")

    # --- Capture pre-update state via Email/get --------------------------
    let (b3, getHandle1) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "keywords"]),
    )
    let resp3 =
      client.send(b3).expect("send Email/get pre-update[" & $target.kind & "]")
    let getResp1 =
      resp3.get(getHandle1).expect("Email/get pre-update extract[" & $target.kind & "]")
    assertOn target, getResp1.list.len == 1, "Email/get must return the seeded message"
    let staleState = getResp1.state

    # --- Happy path: set $seen with matching ifInState -------------------
    let updateSet = initEmailUpdateSet(@[markRead()]).expect(
        "initEmailUpdateSet[" & $target.kind & "]"
      )
    let updates = parseNonEmptyEmailUpdates(@[(seededId, updateSet)]).expect(
        "parseNonEmptyEmailUpdates"
      )
    let (b4, setHandle1) = addEmailSet(
      initRequestBuilder(),
      mailAccountId,
      ifInState = Opt.some(staleState),
      update = Opt.some(updates),
    )
    let resp4 =
      client.send(b4).expect("send Email/set update happy[" & $target.kind & "]")
    let setResp1 = resp4.get(setHandle1).expect(
        "Email/set update happy extract[" & $target.kind & "]"
      )
    let updateOutcome = setResp1.updateResults[seededId]
    assertOn target,
      updateOutcome.isOk, "happy-path Email/set must succeed when ifInState matches"

    # --- Verify $seen keyword is now present -----------------------------
    let (b5, getHandle2) = addEmailGet(
      initRequestBuilder(),
      mailAccountId,
      ids = directIds(@[seededId]),
      properties = Opt.some(@["id", "keywords"]),
    )
    let resp5 =
      client.send(b5).expect("send Email/get post-update[" & $target.kind & "]")
    let getResp2 = resp5.get(getHandle2).expect(
        "Email/get post-update extract[" & $target.kind & "]"
      )
    assertOn target, getResp2.list.len == 1, "Email/get must return the seeded message"
    let email =
      Email.fromJson(getResp2.list[0]).expect("Email.fromJson[" & $target.kind & "]")
    assertOn target,
      email.keywords.isSome,
      "Email/get with properties=[id, keywords] must populate keywords"
    assertOn target,
      kwSeen in email.keywords.unsafeGet,
      "$seen must be present after happy-path Email/set"

    # --- Conflict path: same update with the stale ifInState -------------
    # James 3.9 does not honour ``ifInState`` on Email/set — it ignores
    # the supplied state and processes the update unconditionally,
    # contradicting RFC 8620 §5.3 ("If supplied and the state of the
    # object is not equal to this string, the entire method MUST be
    # aborted with a stateMismatch SetError"). Per-target branching
    # keeps the strict RFC contract enforced on Stalwart while
    # documenting the James behaviour. The captured ``-stalwart``
    # fixture preserves replay coverage for the library's
    # ``metStateMismatch`` projection.
    let updateSetAgain = initEmailUpdateSet(@[markRead()]).expect(
        "initEmailUpdateSet[" & $target.kind & "]"
      )
    let updatesAgain = parseNonEmptyEmailUpdates(@[(seededId, updateSetAgain)]).expect(
        "parseNonEmptyEmailUpdates"
      )
    let (b6, setHandle2) = addEmailSet(
      initRequestBuilder(),
      mailAccountId,
      ifInState = Opt.some(staleState),
      update = Opt.some(updatesAgain),
    )
    let resp6 =
      client.send(b6).expect("send Email/set update conflict[" & $target.kind & "]")
    captureIfRequested(client, "email-set-state-mismatch-" & $target.kind).expect(
      "captureIfRequested"
    )
    let conflictExtract = resp6.get(setHandle2)
    case target.kind
    of ltkStalwart:
      assertOn target,
        conflictExtract.isErr,
        "stale-ifInState Email/set must raise a method-level error"
      let methodErr = conflictExtract.error
      assertOn target,
        methodErr.errorType == metStateMismatch,
        "method error must project as metStateMismatch (got rawType=" & methodErr.rawType &
          ")"
    of ltkJames:
      # James returns success with an ``updated`` map — its
      # implementation does not gate Email/set on ifInState. Assert
      # only that the response is well-formed (``isOk``) and surface
      # the divergence in the rationale for future fix-up tracking.
      assertOn target,
        conflictExtract.isOk,
        "James ignores ifInState on Email/set — assertion documents the divergence"
    client.close()
