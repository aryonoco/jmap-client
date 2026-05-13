# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri
#
## Live integration test for Identity/set + Identity/get (RFC 8621 §6)
## against Stalwart. Stalwart does not auto-provision an identity at
## principal-creation time, so the test creates one via Identity/set
## before reading it back via Identity/get in the same request.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.
##
## Re-runs against the same Stalwart instance simply pile up additional
## identities (Stalwart permits multiple identities per address); the
## Identity/get assertion is ``>= 1`` and stays true. Use
## ``just stalwart-reset`` for a clean slate.
##
## If Steps 3 and 4 pass and this one fails, the bug is in the
## submission-URI wiring, the ``IdentityCreate`` toJson serialiser, or
## the ``Identity`` parser — clean isolation by design.

import std/tables

import results
import jmap_client
import jmap_client/client
import ./mconfig
import ./mlive
import ../../mtestblock

testCase tidentityGetLive:
  forEachLiveTarget(target):
    var client = initJmapClient(
        sessionUrl = target.sessionUrl,
        bearerToken = target.aliceToken,
        authScheme = target.authScheme,
      )
      .expect("initJmapClient[" & $target.kind & "]")
    let session = client.fetchSession().expect("fetchSession[" & $target.kind & "]")
    let submissionAccountId = resolveSubmissionAccountId(session).expect(
        "resolveSubmissionAccountId[" & $target.kind & "]"
      )

    let create = parseIdentityCreate(email = "alice@example.com", name = "Alice").expect(
        "parseIdentityCreate"
      )
    let cid =
      parseCreationId("seedAlice").expect("parseCreationId[" & $target.kind & "]")
    var createTbl = initTable[CreationId, IdentityCreate]()
    createTbl[cid] = create
    let (b1, setHandle) = addIdentitySet(
      initRequestBuilder(makeBuilderId()),
      submissionAccountId,
      create = Opt.some(createTbl),
    )
    let (b2, getHandle) = addIdentityGet(b1, submissionAccountId)
    let resp = client.send(b2.freeze()).expect("send[" & $target.kind & "]")

    let setExtract = resp.get(setHandle)
    # Cat-B (Phase L §0): Cyrus 3.12.2 has no ``Identity/set`` and
    # returns ``metUnknownMethod``; Stalwart and James implement it.
    # The Identity/get arm runs on every target (Identity/get is
    # implemented everywhere — Cyrus exposes config-derived
    # identities).
    if setExtract.isOk:
      let setResp = setExtract.unsafeValue
      assertOn target,
        setResp.createResults.len == 1, "set must report one create result"
      let createResult = setResp.createResults[cid]
      assertOn target, createResult.isOk, "Identity/set must succeed for seeded address"
    else:
      let getErr = setExtract.unsafeError
      doAssert getErr.kind == gekMethod, "expected gekMethod, got gekHandleMismatch"
      let methodErr = getErr.methodErr
      assertOn target,
        methodErr.errorType == metUnknownMethod,
        "Identity/set must surface as metUnknownMethod when unimplemented (got " &
          methodErr.rawType & ")"

    let gr = resp.get(getHandle).expect("Identity/get extract[" & $target.kind & "]")
    assertOn target, gr.list.len >= 1, "alice must own at least one identity"
    # ``email`` is RFC 8621 §6.1 ``String`` — Cyrus emits empty for
    # config-derived identities; Stalwart/James populate. Identity/get
    # parses both shapes (see ``serde_identity.nim``); the wire-shape
    # parse is the universal client-library contract.
    var sawAliceEmail = false
    for ident in gr.list:
      assertOn target,
        ident.id.len > 0, "every identity must carry a server-assigned id"
      if ident.email == "alice@example.com":
        sawAliceEmail = true
    if setExtract.isOk:
      assertOn target,
        sawAliceEmail, "alice's seeded address must appear among her identities"
