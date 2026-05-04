# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## LIBRARY CONTRACT: ``MethodError.fromJson`` projects every wire
## ``type`` URI Stalwart returns for per-method failures into the
## closed ``MethodErrorType`` enum AND preserves ``rawType``
## losslessly. ``parseMethodErrorType`` is total: unknown URIs
## project to ``metUnknown``. ``resp.get(handle)`` for a method-
## level error invocation routes through ``MethodError.fromJson``
## and returns the typed error on the inner railway.
##
## Phase J Step 62.  Four sequential ``sendRawInvocation`` calls
## drive Stalwart through four RFC 8620 §3.6.2 method-level
## rejection scenarios that the typed builder cannot easily
## reproduce: an unknown method name, a broken result-reference, an
## unsupported sort property, and an unsupported filter property.
##
## **Library-contract vs server-compliance separation.**  Same
## discipline as Step 61: assert the library's projection contract
## (closed-enum, lossless rawType, "error" rawName routing); pin
## Stalwart's specific URI choices in the four captured fixtures
## byte-for-byte via the replay tests.  RFC 8620 §3.6.2 lets
## servers collapse most variants onto ``invalidArguments`` at
## their discretion; assertions therefore admit set-membership on
## the variant axis but never on rawType structure.
##
## Listed in ``tests/testament_skip.txt``; run via
## ``just test-integration``.

import std/json
import std/tables

import results
import jmap_client
import jmap_client/client
import ./mcapture
import ./mconfig
import ./mlive

block tmethodErrorTypedProjectionLive:
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
    let mailAccountId = resolveMailAccountId(session).expect("resolveMailAccountId")

    # Sub-test 1: unknown method name.
    block unknownMethodCase:
      let resp = sendRawInvocation(
          client,
          capabilityUris = @["urn:ietf:params:jmap:mail"],
          methodName = "Mailbox/snorgleflarp",
          arguments = %*{"accountId": $mailAccountId},
        )
        .expect("sendRawInvocation unknownMethod")
      captureIfRequested(client, "method-error-unknown-method-stalwart").expect(
        "captureIfRequested unknownMethod"
      )
      doAssert resp.methodResponses.len == 1
      let inv = resp.methodResponses[0]
      doAssert inv.rawName == "error",
        "method-level errors arrive on the literal 'error' rawName"
      let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
      doAssert me.rawType.len > 0, "rawType must be losslessly preserved"
      doAssert me.errorType in {
        metUnknownMethod, metInvalidArguments, metServerFail, metServerUnavailable,
        metUnknown,
      },
        "errorType must project into the closed MethodErrorType enum, got " &
          $me.errorType

    # Sub-test 2: broken result-reference path.
    block invalidResultReferenceCase:
      let getArgs = %*{"accountId": $mailAccountId}
      let getArgsRef = injectBrokenBackReference(
        getArgs,
        refField = "ids",
        refPath = "/methodResponses/0/notAField/that/exists",
        refName = "Email/query",
      )
      let resp = sendRawInvocation(
          client,
          capabilityUris = @["urn:ietf:params:jmap:mail"],
          methodName = "Email/get",
          arguments = getArgsRef,
        )
        .expect("sendRawInvocation invalidResultReference")
      captureIfRequested(client, "method-error-invalid-result-reference-stalwart")
        .expect("captureIfRequested invalidResultReference")
      doAssert resp.methodResponses.len >= 1
      let inv = resp.methodResponses[resp.methodResponses.len - 1]
      doAssert inv.rawName == "error",
        "Email/get with broken back-reference must surface as 'error', got " &
          inv.rawName
      let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
      doAssert me.rawType.len > 0, "rawType must be losslessly preserved"
      doAssert me.errorType in
        {metInvalidResultReference, metInvalidArguments, metServerFail, metUnknown},
        "errorType must project into the closed MethodErrorType enum, got " &
          $me.errorType

    # Sub-test 3: unsupported sort property.
    block unsupportedSortCase:
      let resp = sendRawInvocation(
          client,
          capabilityUris = @["urn:ietf:params:jmap:mail"],
          methodName = "Email/query",
          arguments = %*{
            "accountId": $mailAccountId,
            "sort": [{"property": "phaseJSyntheticProperty"}],
          },
        )
        .expect("sendRawInvocation unsupportedSort")
      captureIfRequested(client, "method-error-unsupported-sort-stalwart").expect(
        "captureIfRequested unsupportedSort"
      )
      doAssert resp.methodResponses.len == 1
      let inv = resp.methodResponses[0]
      doAssert inv.rawName == "error",
        "unsupported-sort must surface as 'error', got " & inv.rawName
      let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
      doAssert me.rawType.len > 0, "rawType must be losslessly preserved"
      doAssert me.errorType in
        {metUnsupportedSort, metInvalidArguments, metServerFail, metUnknown},
        "errorType must project into the closed MethodErrorType enum, got " &
          $me.errorType

    # Sub-test 4: unsupported filter property.
    block unsupportedFilterCase:
      let resp = sendRawInvocation(
          client,
          capabilityUris = @["urn:ietf:params:jmap:mail"],
          methodName = "Email/query",
          arguments =
            %*{"accountId": $mailAccountId, "filter": {"phaseJSyntheticProperty": true}},
        )
        .expect("sendRawInvocation unsupportedFilter")
      captureIfRequested(client, "method-error-unsupported-filter-stalwart").expect(
        "captureIfRequested unsupportedFilter"
      )
      doAssert resp.methodResponses.len == 1
      let inv = resp.methodResponses[0]
      doAssert inv.rawName == "error",
        "unsupported-filter must surface as 'error', got " & inv.rawName
      let me = MethodError.fromJson(inv.arguments).expect("MethodError.fromJson")
      doAssert me.rawType.len > 0, "rawType must be losslessly preserved"
      doAssert me.errorType in
        {metUnsupportedFilter, metInvalidArguments, metServerFail, metUnknown},
        "errorType must project into the closed MethodErrorType enum, got " &
          $me.errorType

    client.close()
