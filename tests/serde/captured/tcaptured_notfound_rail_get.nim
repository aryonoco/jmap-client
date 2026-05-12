# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/get`` response
## carrying both a successful record and an unresolved id in the
## ``notFound`` rail (``tests/testdata/captured/
## notfound-rail-get-stalwart.json``).
##
## RFC 8620 §5.1 mandates that ``/get`` responses carry a
## ``notFound: Id[]`` field listing requested ids that did not match
## any record.  Verifies (a) the typed ``GetResponse[Email]`` parses
## the mixed wire shape; (b) ``getResp.notFound`` deserialises into
## ``seq[Id]``; and (c) the synthetic id round-trips byte-for-byte.

{.push raises: [].}

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader
import ../../mtestblock

testCase tcapturedNotfoundRailGet:
  forEachCapturedServer("notfound-rail-get", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "Email/get",
      "successful Email/get must surface as Email/get; got " & inv.rawName
    let getResp =
      GetResponse[Email].fromJson(inv.arguments).expect("GetResponse[Email].fromJson")
    doAssert getResp.list.len == 1,
      "fixture carries one real Email; got " & $getResp.list.len
    doAssert getResp.notFound.len == 1,
      "fixture carries one synthetic id in notFound; got " & $getResp.notFound.len
    doAssert getResp.notFound[0] == Id("zzzzzz"),
      "notFound id must round-trip byte-for-byte; got " & $getResp.notFound

    let email = getResp.list[0]
    doAssert email.subject.isSome,
      "the real Email's subject must round-trip through Email.fromJson"
    doAssert email.subject.unsafeGet == "phase-j 66 notFound",
      "fixture's seed subject must round-trip; got " & email.subject.unsafeGet
