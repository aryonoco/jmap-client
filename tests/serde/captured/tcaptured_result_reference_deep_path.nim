# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured three-leg back-reference
## chain (``Email/query`` → ``Email/get`` → ``Thread/get``) that
## exercises a depth-3 JSON Pointer (``/list/*/threadId``) routed
## through the typed ``rpListThreadId`` enum (``methods_enum.nim:79``).
##
## ``tests/testdata/captured/result-reference-deep-path-stalwart.json``.
##
## Verifies: (a) all three method responses parse through their
## typed shapes; (b) ``Email/query`` ids match the ``Email/get``
## list; (c) ``Email/get`` threadIds match the ``Thread/get`` list
## ids — proving Stalwart resolved the deep pointer correctly.

{.push raises: [].}

import jmap_client
import jmap_client/mail/thread as jthread
import ./mloader

block tcapturedResultReferenceDeepPath:
  let j = loadCapturedFixture("result-reference-deep-path-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 3,
    "envelope must carry the three-leg chain; got " & $resp.methodResponses.len

  doAssert resp.methodResponses[0].rawName == "Email/query"
  doAssert resp.methodResponses[1].rawName == "Email/get"
  doAssert resp.methodResponses[2].rawName == "Thread/get"

  let queryResp = QueryResponse[Email]
    .fromJson(resp.methodResponses[0].arguments)
    .expect("QueryResponse[Email].fromJson")
  let getResp = GetResponse[Email].fromJson(resp.methodResponses[1].arguments).expect(
      "GetResponse[Email].fromJson"
    )
  let threadResp = GetResponse[jthread.Thread]
    .fromJson(resp.methodResponses[2].arguments)
    .expect("GetResponse[Thread].fromJson")

  doAssert queryResp.ids.len >= 1, "Email/query must surface ids"
  doAssert getResp.list.len == queryResp.ids.len,
    "Email/get must return one record per id from query"
  doAssert threadResp.list.len >= 1, "Thread/get must surface threads"

  # Cross-leg coherence: each Email's threadId must appear in the
  # Thread/get list.  Proves Stalwart resolved the deep
  # ``/list/*/threadId`` pointer on the Email/get response.  Linear
  # scans avoid HashSet overload ambiguity between std/sets and the
  # mail-layer ``MailboxIdSet`` / ``KeywordSet`` ``contains`` defs.
  for emailNode in getResp.list:
    let email = Email.fromJson(emailNode).expect("Email.fromJson")
    doAssert email.id.isSome, "Email.id must be present after fromJson"
    let emailId = email.id.unsafeGet
    var foundInQuery = false
    for id in queryResp.ids:
      if id == emailId:
        foundInQuery = true
        break
    doAssert foundInQuery,
      "every Email/get id must trace back to the Email/query result"

  for emailNode in getResp.list:
    let email = Email.fromJson(emailNode).expect("Email.fromJson")
    doAssert email.threadId.isSome, "Email.threadId must be present"
    let emailThreadId = email.threadId.unsafeGet
    var foundInThreads = false
    for threadNode in threadResp.list:
      let t = jthread.Thread.fromJson(threadNode).expect("Thread.fromJson")
      if t.id == emailThreadId:
        foundInThreads = true
        break
    doAssert foundInThreads,
      "every Email's threadId must surface in the Thread/get response — " &
        "proves the deep pointer ``/list/*/threadId`` resolved correctly"
