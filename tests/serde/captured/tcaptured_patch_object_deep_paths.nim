# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured deep-path PatchObject
## rejection (``tests/testdata/captured/
## patch-object-deep-paths-stalwart.json``).
##
## **Stalwart 0.15.5 deviation pin (combined).**  Two related
## empirical findings recorded in this fixture:
##
## 1. Stalwart classifies a deep-path PatchObject expression
##    (``replyTo/0/name``) as ``invalidProperties`` rather than
##    accepting the deep update.  Stalwart's PatchObject support
##    appears to flatten paths and treat the whole key as a property
##    name; ``replyTo/0/name`` is then unknown and rejected.
##
## 2. When the response carries only ``notUpdated`` (no successful
##    state change), Stalwart omits the ``newState`` field — RFC
##    8620 §5.3 mandates this field as required.  The library's
##    typed ``SetResponse.fromJson`` therefore correctly rejects the
##    response shape; this replay test instead parses the rejection
##    rail at the raw JSON level via ``SetError.fromJson``, which is
##    structurally complete in the captured wire shape.

{.push raises: [].}

import std/json

import jmap_client
import ./mloader

block tcapturedPatchObjectDeepPaths:
  let j = loadCapturedFixture("patch-object-deep-paths-stalwart")
  let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
  doAssert resp.methodResponses.len == 1
  let inv = resp.methodResponses[0]
  doAssert inv.rawName == "Identity/set",
    "deep-path patch must surface as Identity/set with notUpdated; got " & inv.rawName

  # Stalwart-deviation: SetResponse.fromJson would fail because
  # ``newState`` is absent.  Parse the rejection rail directly.
  let notUpdated = inv.arguments{"notUpdated"}
  doAssert not notUpdated.isNil and notUpdated.kind == JObject,
    "deep-path response must carry notUpdated"
  doAssert notUpdated.len == 1, "notUpdated must contain exactly one entry"

  for id, entry in notUpdated.pairs:
    let se = SetError.fromJson(entry).expect("SetError.fromJson")
    doAssert se.rawType == "invalidProperties",
      "Stalwart projects deep-path rejection as invalidProperties; got " & se.rawType
    doAssert se.errorType == setInvalidProperties,
      "errorType must project to setInvalidProperties; got " & $se.errorType
    doAssert se.properties == @["replyTo/0/name"],
      "Stalwart echoes the offending deep path; got " & $se.properties
    doAssert se.description.isSome,
      "Stalwart populates description on deep-path rejection"
    doAssert se.description.unsafeGet == "Field could not be set.",
      "Stalwart's description string on deep-path rejection"
