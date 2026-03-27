# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

import std/strutils
import std/sets
from std/json import JsonNode

import pkg/results

import ./primitives

type CapabilityKind* = enum
  ## JMAP capability identifiers from the IANA registry.
  ## CRITICAL: must NOT be used as a Table key — multiple vendor extensions
  ## map to ckUnknown, causing collisions. Use raw URI strings for keying.
  ckCore = "urn:ietf:params:jmap:core"
  ckMail = "urn:ietf:params:jmap:mail"
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
  maxSizeUpload*: UnsignedInt ## Max file size in octets for single upload
  maxConcurrentUpload*: UnsignedInt ## Max concurrent requests to upload endpoint
  maxSizeRequest*: UnsignedInt ## Max request size in octets for API endpoint
  maxConcurrentRequests*: UnsignedInt ## Max concurrent requests to API endpoint
  maxCallsInRequest*: UnsignedInt ## Max method calls per single API request
  maxObjectsInGet*: UnsignedInt ## Max objects per single /get call
  maxObjectsInSet*: UnsignedInt ## Max combined create/update/destroy per /set call
  collationAlgorithms*: HashSet[string] ## Collation algorithm identifiers (RFC 4790)

type ServerCapability* = object
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
  strutils.parseEnum[CapabilityKind](uri, ckUnknown)

func capabilityUri*(kind: CapabilityKind): Opt[string] =
  ## Returns the IANA-registered URI for a known capability.
  ## Returns err() for ckUnknown — callers must use rawUri from ServerCapability.
  case kind
  of ckCore:
    ok("urn:ietf:params:jmap:core")
  of ckMail:
    ok("urn:ietf:params:jmap:mail")
  of ckSubmission:
    ok("urn:ietf:params:jmap:submission")
  of ckVacationResponse:
    ok("urn:ietf:params:jmap:vacationresponse")
  of ckWebsocket:
    ok("urn:ietf:params:jmap:websocket")
  of ckMdn:
    ok("urn:ietf:params:jmap:mdn")
  of ckSmimeVerify:
    ok("urn:ietf:params:jmap:smimeverify")
  of ckBlob:
    ok("urn:ietf:params:jmap:blob")
  of ckQuota:
    ok("urn:ietf:params:jmap:quota")
  of ckContacts:
    ok("urn:ietf:params:jmap:contacts")
  of ckCalendars:
    ok("urn:ietf:params:jmap:calendars")
  of ckSieve:
    ok("urn:ietf:params:jmap:sieve")
  of ckUnknown:
    err()

func hasCollation*(caps: CoreCapabilities, algorithm: string): bool =
  algorithm in caps.collationAlgorithms
