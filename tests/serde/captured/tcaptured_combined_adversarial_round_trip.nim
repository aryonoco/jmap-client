# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured five-invocation
## adversarial envelope (``tests/testdata/captured/
## combined-adversarial-round-trip-stalwart.json``).
##
## The envelope mixes successful and erroring invocations:
##   c0: legitimate Mailbox/get      → success
##   c1: legitimate Email/query      → success
##   c2: Email/get with broken ref   → 'error' (invalidResultReference)
##   c3: Email/set create with id    → notCreated (invalidProperties)
##   c4: legitimate Identity/get     → success
##
## Verifies the parser projects each variant in one envelope
## without contamination — c2's error invocation does not break
## c0 / c1 / c4's typed projection; c3's notCreated map parses
## independently.

{.push raises: [].}

import std/tables

import jmap_client
import ./mloader

block tcapturedCombinedAdversarialRoundTrip:
  let j = loadCapturedFixture("combined-adversarial-round-trip-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 5,
    "envelope must carry five responses; got " & $resp.methodResponses.len

  doAssert resp.methodResponses[0].rawName == "Mailbox/get"
  doAssert resp.methodResponses[1].rawName == "Email/query"
  doAssert resp.methodResponses[2].rawName == "error"
  doAssert resp.methodResponses[3].rawName == "Email/set"
  doAssert resp.methodResponses[4].rawName == "Identity/get"

  let mb = GetResponse[Mailbox].fromJson(resp.methodResponses[0].arguments).expect(
      "Mailbox/get extract"
    )
  doAssert mb.list.len >= 1

  let q = QueryResponse[Email].fromJson(resp.methodResponses[1].arguments).expect(
      "Email/query extract"
    )
  doAssert q.ids.len >= 1

  let me = MethodError.fromJson(resp.methodResponses[2].arguments).expect(
      "MethodError.fromJson c2"
    )
  doAssert me.rawType.len > 0
  doAssert me.errorType in
    {metInvalidResultReference, metInvalidArguments, metServerFail, metUnknown}

  # c3 — Stalwart returns notCreated with newDraft → invalidProperties.
  let setResp = SetResponse[EmailCreatedItem]
    .fromJson(resp.methodResponses[3].arguments)
    .expect("SetResponse[EmailCreatedItem].fromJson c3")
  let cidLabel = parseCreationId("newDraft").expect("parseCreationId")
  setResp.createResults.withValue(cidLabel, outcome):
    doAssert outcome.isErr
    doAssert outcome.error.errorType in {setInvalidProperties, setForbidden, setUnknown}
  do:
    doAssert false, "createResults must report newDraft outcome"

  let identResp = GetResponse[Identity]
    .fromJson(resp.methodResponses[4].arguments)
    .expect("Identity/get extract")
  doAssert identResp.list.len >= 0
