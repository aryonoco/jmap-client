# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## S2 round-trip guard. The Session read-model flip (private ``rawX``
## accessors → public fields, ``apiUrl`` as the ``ApiUrl`` newtype) must
## not perturb the wire serde. Parses a representative RFC 8620 §2
## ``/session`` document, re-emits it, and verifies the key facts survive
## through the new public-field API, then that re-emission is idempotent.

{.push raises: [].}

import std/json
import std/tables

import results

import jmap_client/internal/serialisation/serde_session
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/primitives
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/session

import ../mtestblock

testCase sessionRoundTripS2:
  let input = %*{
    "capabilities": {
      "urn:ietf:params:jmap:core": {
        "maxSizeUpload": 50000000,
        "maxConcurrentUpload": 4,
        "maxSizeRequest": 10000000,
        "maxConcurrentRequests": 4,
        "maxCallsInRequest": 16,
        "maxObjectsInGet": 500,
        "maxObjectsInSet": 500,
        "collationAlgorithms": ["i;ascii-casemap"],
      },
      "urn:ietf:params:jmap:mail": {},
    },
    "accounts": {
      "a": {
        "name": "alice@example.com",
        "isPersonal": true,
        "isReadOnly": false,
        "accountCapabilities": {
          "urn:ietf:params:jmap:mail": {
            "maxSizeAttachmentsPerEmail": 50000000,
            "emailQuerySortOptions": ["receivedAt", "size"],
            "mayCreateTopLevelMailbox": true,
          }
        },
      }
    },
    "primaryAccounts": {"urn:ietf:params:jmap:mail": "a"},
    "username": "alice@example.com",
    "apiUrl": "https://jmap.example.com/api/",
    "downloadUrl":
      "https://jmap.example.com/download/{accountId}/{blobId}/{type}/{name}",
    "uploadUrl": "https://jmap.example.com/upload/{accountId}/",
    "eventSourceUrl":
      "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}",
    "state": "s-0001",
  }

  let parsed = Session.fromJson(input)
  doAssert parsed.isOk, "Session.fromJson must accept the representative document"
  let s = parsed.value

  # New public-field reads. ``apiUrl`` is the ApiUrl newtype — read via ``$``;
  # ``core`` is the typed required arm; ``additional`` holds the rest.
  doAssert $s.apiUrl == "https://jmap.example.com/api/"
  doAssert s.username == "alice@example.com"
  doAssert $s.state == "s-0001"
  doAssert s.core.maxSizeRequest.toInt64 == 10000000'i64
  doAssert s.accounts.len == 1
  doAssert s.primaryAccounts.len == 1
  doAssert s.additional.len == 1
  doAssert s.capabilities().len == 2

  # Re-emit and re-parse: the flip must preserve the wire shape end-to-end.
  let reemit = s.toJson()
  let reparsed = Session.fromJson(reemit)
  doAssert reparsed.isOk, "re-emitted Session must parse"
  let s2 = reparsed.value

  doAssert $s2.apiUrl == $s.apiUrl
  doAssert s2.username == s.username
  doAssert $s2.state == $s.state
  doAssert s2.core.maxSizeRequest.toInt64 == s.core.maxSizeRequest.toInt64
  doAssert s2.accounts.len == s.accounts.len
  doAssert s2.primaryAccounts.len == s.primaryAccounts.len

  # Re-emission is byte-stable: the same value serialises identically.
  doAssert $s2.toJson() == $reemit
