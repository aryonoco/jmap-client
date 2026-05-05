# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Live integration test for Email/query (RFC 8621 §4.4) with the
## ``EmailComparator`` sort framework against Stalwart. Builds on
## Steps 13 and 14 — the filter shape is now proven; this step adds
## the orthogonal sort dimension. Validates the ``isAscending`` flag
## in both directions, the ``eckPlain`` arm with ``pspSubject``, and
## an explicit ``collation`` round-trip when Stalwart advertises one.
##
## Sequence:
##  1. Resolve inbox + capture advertised collation algorithms.
##  2. Seed three emails sharing a phase-c-15 prefix and a per-test
##     discriminator token ``"stepfifteen"`` plus a unique ordering
##     word (``"zulu"`` / ``"alpha"`` / ``"mike"``). Insertion order is
##     deliberately non-alphabetical so the subject sort does real
##     reordering rather than echoing insertion order.
##  3. Ascending sort: filter on ``"stepfifteen"`` + sort by
##     ``pspSubject`` ascending. Filter the result to the seeded
##     corpus and assert relative order ``alpha → mike → zulu``.
##  4. Descending sort: same filter + ``isAscending = Opt.some(false)``.
##     Assert relative order ``zulu → mike → alpha``.
##  5. Explicit-collation sub-test (conditional on
##     ``colls.len > 0``): pick the lexicographically-first advertised
##     algorithm, re-issue the ascending sort with that collation
##     bound, assert order unchanged.
##
## Listed in ``tests/testament_skip.txt`` so ``just test`` skips it; run
## via ``just test-integration`` after ``just stalwart-up``. Body is
## guarded on ``loadLiveTestTargets().isOk`` so the file joins testament's
## megatest cleanly under ``just test-full`` when env vars are absent.

import std/algorithm
import std/sets

import results
import jmap_client
import jmap_client/client
import ./mconfig
import ./mlive

block temailQuerySortLive:
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

    let colls = resolveCollationAlgorithms(session)

    # --- Resolve inbox + seed corpus ------------------------------------
    let inbox = resolveInboxId(client, mailAccountId).expect(
        "resolveInboxId[" & $target.kind & "]"
      )
    let ids = seedEmailsWithSubjects(
        client,
        mailAccountId,
        inbox,
        @[
          "phase-c-15 stepfifteen zulu", "phase-c-15 stepfifteen alpha",
          "phase-c-15 stepfifteen mike",
        ],
      )
      .expect("seedEmailsWithSubjects[" & $target.kind & "]")
    assertOn target, ids.len == 3, "seedEmailsWithSubjects must return three ids"
    let zuluId = ids[0]
    let alphaId = ids[1]
    let mikeId = ids[2]
    let corpus = ids.toHashSet

    let filter = filterCondition(EmailFilterCondition(subject: Opt.some("stepfifteen")))

    # --- Ascending sort by pspSubject -----------------------------------
    let ascSort = @[plainComparator(pspSubject, isAscending = Opt.some(true))]
    let (ba, ascHandle) = addEmailQuery(
      initRequestBuilder(),
      mailAccountId,
      filter = Opt.some(filter),
      sort = Opt.some(ascSort),
    )
    # Wait for the full-text index to surface every seeded id so the
    # ordering assertion is comparable across servers (Cyrus 3.12.2's
    # Xapian indexer lags Email/set by ~300 ms; Stalwart/James are
    # synchronous).
    discard pollEmailQueryIndexed(target, mailAccountId, filter, corpus).expect(
        "pollEmailQueryIndexed asc[" & $target.kind & "]"
      )
    let respA = client.send(ba).expect("send Email/query asc[" & $target.kind & "]")
    let ascResp =
      respA.get(ascHandle).expect("Email/query asc extract[" & $target.kind & "]")
    var ascSeeded: seq[Id] = @[]
    for id in ascResp.ids:
      if id in corpus:
        ascSeeded.add(id)
    assertOn target,
      ascSeeded.len == 3,
      "ascending sort must surface all three seeded ids after indexing; got " &
        $ascSeeded.len
    assertOn target,
      ascSeeded == @[alphaId, mikeId, zuluId],
      "ascending pspSubject must order alpha → mike → zulu (got order " & $ascSeeded &
        "; expected " & $(@[alphaId, mikeId, zuluId]) & ")"

    # --- Descending sort by pspSubject ----------------------------------
    let descSort = @[plainComparator(pspSubject, isAscending = Opt.some(false))]
    let (bd, descHandle) = addEmailQuery(
      initRequestBuilder(),
      mailAccountId,
      filter = Opt.some(filter),
      sort = Opt.some(descSort),
    )
    let respD = client.send(bd).expect("send Email/query desc[" & $target.kind & "]")
    let descResp =
      respD.get(descHandle).expect("Email/query desc extract[" & $target.kind & "]")
    var descSeeded: seq[Id] = @[]
    for id in descResp.ids:
      if id in corpus:
        descSeeded.add(id)
    assertOn target,
      descSeeded.len == 3,
      "descending sort must surface all three seeded ids; got " & $descSeeded.len
    assertOn target,
      descSeeded == @[zuluId, mikeId, alphaId],
      "descending pspSubject must order zulu → mike → alpha (got order " &
        $descSeeded & ")"

    # --- Explicit-collation sub-test (conditional) ----------------------
    if colls.len > 0:
      var collationStrings: seq[string] = @[]
      for c in colls:
        collationStrings.add($c)
      collationStrings.sort()
      let chosen = parseCollationAlgorithm(collationStrings[0]).expect(
          "parseCollationAlgorithm[" & $target.kind & "]"
        )
      let collSort = @[
        plainComparator(
          pspSubject, isAscending = Opt.some(true), collation = Opt.some(chosen)
        )
      ]
      let (bc, collHandle) = addEmailQuery(
        initRequestBuilder(),
        mailAccountId,
        filter = Opt.some(filter),
        sort = Opt.some(collSort),
      )
      let respC =
        client.send(bc).expect("send Email/query collation[" & $target.kind & "]")
      let collResp = respC.get(collHandle).expect(
          "Email/query collation extract[" & $target.kind & "]"
        )
      var collSeeded: seq[Id] = @[]
      for id in collResp.ids:
        if id in corpus:
          collSeeded.add(id)
      assertOn target,
        collSeeded == @[alphaId, mikeId, zuluId],
        "explicit collation " & $chosen &
          " must round-trip ascending order alpha → mike → zulu (got " & $collSeeded &
          ")"
    client.close()
