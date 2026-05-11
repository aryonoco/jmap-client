# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured per-item /set rejection
## Stalwart returns when an Email/import targets an unresolvable
## BlobId (``tests/testdata/captured/set-error-blob-not-found-stalwart.json``).
##
## **Stalwart 0.15.5 deviation pin.**  RFC 8621 §4.6 mandates
## ``blobNotFound`` rawType with ``notFound: [BlobId, …]`` payload
## when ``Email/import`` cannot resolve the supplied BlobId.
## Stalwart collapses the case onto ``invalidProperties`` with
## ``properties: ["blobId"]`` and a description of "Invalid blob
## id." — same collapse pattern as Stalwart's other RFC variants
## (Step 61 / sub-test 2 of Step 63).
##
## Verifies the typed ``SetError.properties`` arm deserialises
## correctly under the deviated wire shape.

{.push raises: [].}

import std/tables

import jmap_client
import jmap_client/internal/types/envelope
import ./mloader

block tcapturedSetErrorBlobNotFound:
  let j = loadCapturedFixture("set-error-blob-not-found-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Email/import",
    "Email/import with notCreated must surface as Email/import, got " & inv.rawName
  let setResp =
    EmailImportResponse.fromJson(inv.arguments).expect("EmailImportResponse.fromJson")
  let cidLabel = parseCreationId("phaseJ63blob").expect("parseCreationId")
  var found = false
  setResp.createResults.withValue(cidLabel, outcome):
    doAssert outcome.isErr, "Email/import outcome must be Err(SetError)"
    let se = outcome.error
    doAssert se.rawType == "invalidProperties",
      "Stalwart 0.15.5 collapses blobNotFound onto 'invalidProperties' " &
        "(RFC mandates 'blobNotFound'); got " & se.rawType
    doAssert se.errorType == setInvalidProperties,
      "errorType must project to setInvalidProperties, got " & $se.errorType
    doAssert se.errorType == parseSetErrorType(se.rawType),
      "errorType / rawType must be derived consistently"
    doAssert se.properties == @["blobId"],
      "Stalwart names the offending property; got " & $se.properties
    doAssert se.description.isSome and se.description.unsafeGet == "Invalid blob id.",
      "Stalwart's description echoes the blob-resolution failure"
    found = true
  do:
    doAssert false, "createResults must contain the create label"
  doAssert found
