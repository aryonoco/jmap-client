# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP capability discovery types. Maps IANA-registered capability URIs to
## typed enums with lossless round-trip for vendor extensions.

{.push raises: [], noSideEffect.}

import std/strutils
import std/sets
from std/json import JsonNode

import results

import ./primitives

type CapabilityKind* = enum
  ## JMAP capability identifiers from the IANA registry.
  ## CRITICAL: must NOT be used as a Table key — multiple vendor extensions
  ## map to ckUnknown, causing collisions. Use raw URI strings for keying.
  ## NOTE: ckMail is first (not ckCore) so that the default CapabilityKind picks
  ## the else branch of ServerCapability, whose rawData: JsonNode can be nil.
  ckMail = "urn:ietf:params:jmap:mail"
  ckCore = "urn:ietf:params:jmap:core"
  ckSubmission = "urn:ietf:params:jmap:submission"
  ckVacationResponse = "urn:ietf:params:jmap:vacationresponse"
  ckWebsocket = "urn:ietf:params:jmap:websocket"
  ckMdn = "urn:ietf:params:jmap:mdn"
  ckSmimeVerify = "urn:ietf:params:jmap:smimeverify"
  ckBlob = "urn:ietf:params:jmap:blob"
  ckQuota = "urn:ietf:params:jmap:quota"
  ckContacts = "urn:ietf:params:jmap:contacts"
  ckCalendars = "urn:ietf:params:jmap:calendars"
  ckSieve = "urn:ietf:params:jmap:sieve"
  ckUnknown

type CoreCapabilities* = object
  ## Server-advertised limits and supported collation algorithms (RFC 8620 §2).
  maxSizeUpload*: UnsignedInt ## Max file size in octets for single upload
  maxConcurrentUpload*: UnsignedInt ## Max concurrent requests to upload endpoint
  maxSizeRequest*: UnsignedInt ## Max request size in octets for API endpoint
  maxConcurrentRequests*: UnsignedInt ## Max concurrent requests to API endpoint
  maxCallsInRequest*: UnsignedInt ## Max method calls per single API request
  maxObjectsInGet*: UnsignedInt ## Max objects per single /get call
  maxObjectsInSet*: UnsignedInt ## Max combined create/update/destroy per /set call
  collationAlgorithms*: HashSet[string] ## Collation algorithm identifiers (RFC 4790)

type ServerCapability* = object
  ## Tagged capability with typed data for ckCore and raw JSON for extensions.
  ## rawUri preserves the original URI for lossless round-trip.
  rawUri*: string ## always populated — lossless round-trip
  case kind*: CapabilityKind
  of ckCore:
    core*: CoreCapabilities
  else:
    rawData*: JsonNode

func parseCapabilityKind*(uri: string): CapabilityKind =
  ## Maps a capability URI string to an enum value.
  ## Total function: always succeeds. Unknown URIs map to ckUnknown.
  ## Uses strutils.parseEnum which matches against the string backing values.
  return strutils.parseEnum[CapabilityKind](uri, ckUnknown)

func capabilityUri*(kind: CapabilityKind): Opt[string] =
  ## Returns the IANA-registered URI for a known capability.
  ## Returns none for ckUnknown — callers must use rawUri from ServerCapability.
  ## Uses ``$`` on the string-backed enum, which returns the backing string.
  if kind == ckUnknown:
    return Opt.none(string)
  return Opt.some($kind)

func hasCollation*(caps: CoreCapabilities, algorithm: string): bool =
  ## Checks whether the server supports a given RFC 4790 collation algorithm.
  return algorithm in caps.collationAlgorithms
