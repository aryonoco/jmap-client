# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for AccountCapabilityEntry round-trip identity
## across all 13 CapabilityKind arms.

import std/json
import std/random

import jmap_client/internal/serialisation/serde_session
import jmap_client/internal/types/account_capability_schemas
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/validation

import ../mproperty
import ../mtestblock

testCase propAccountCapabilityEntryRoundTrip:
  checkProperty "AccountCapabilityEntry round-trip preserves the entry":
    let entry = rng.genAccountCapabilityEntry()
    lastInput = entry.uri()
    let rt = AccountCapabilityEntry.fromJson(entry.uri(), entry.toJson())
    doAssert rt.isOk, "fromJson failed for " & entry.uri() & ": " & $rt.error
    doAssert rt.get() == entry,
      "round-trip mismatch for " & entry.uri() & " (kind " & $entry.kind & ")"

testCase propAccountCapabilityEntryEveryArmExercised:
  ## Across enough trials, the generator hits every arm. Verify each arm
  ## actually round-trips by enumerating fixed URIs.
  let fixedUris = [
    ("urn:ietf:params:jmap:mail", ckMail),
    ("urn:ietf:params:jmap:submission", ckSubmission),
    ("urn:ietf:params:jmap:vacationresponse", ckVacationResponse),
    ("urn:ietf:params:jmap:core", ckCore),
    ("urn:ietf:params:jmap:websocket", ckWebsocket),
    ("urn:ietf:params:jmap:mdn", ckMdn),
    ("urn:ietf:params:jmap:smimeverify", ckSmimeVerify),
    ("urn:ietf:params:jmap:blob", ckBlob),
    ("urn:ietf:params:jmap:quota", ckQuota),
    ("urn:ietf:params:jmap:contacts", ckContacts),
    ("urn:ietf:params:jmap:calendars", ckCalendars),
    ("urn:ietf:params:jmap:sieve", ckSieve),
    ("https://vendor.example/ext", ckUnknown),
  ]
  for (uri, expectedKind) in fixedUris:
    let payload =
      if expectedKind == ckMail:
        %*{"maxSizeAttachmentsPerEmail": 0, "mayCreateTopLevelMailbox": false}
      elif expectedKind == ckSubmission:
        %*{"maxDelayedSend": 0, "submissionExtensions": {}}
      else:
        newJObject()
    let entry = AccountCapabilityEntry.fromJson(uri, payload).get()
    doAssert entry.kind == expectedKind, "wrong kind for " & uri
    let rt = AccountCapabilityEntry.fromJson(uri, entry.toJson()).get()
    doAssert rt == entry, "round-trip mismatch for " & uri
