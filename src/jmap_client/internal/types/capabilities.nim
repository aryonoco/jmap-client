# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP capability discovery types. Maps IANA-registered capability URIs to
## typed enums with lossless round-trip for vendor extensions.

{.push raises: [], noSideEffect.}
{.experimental: "strictCaseObjects".}

import std/hashes
import std/strutils
import std/sets
from std/json import JsonNode

import results

import ./validation
import ./primitives
import ./collation
export collation

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
  collationAlgorithms*: HashSet[CollationAlgorithm]
    ## Collation algorithm identifiers (RFC 4790)

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

func hasCollation*(caps: CoreCapabilities, algorithm: CollationAlgorithm): bool =
  ## Checks whether the server supports a given RFC 4790 collation algorithm.
  return algorithm in caps.collationAlgorithms

type CapabilityUri* {.ruleOff: "objects".} = object
  ## RFC 8620 §2 capability URI carrier. Used internally by every typed
  ## ``add<Entity><Method>`` builder to tag the request's ``using``
  ## field, and publicly as the ``capability`` parameter on
  ## ``addCapabilityInvocation`` for vendor URN escapes. Sealed
  ## Pattern-A object — ``rawValue`` is module-private. External
  ## consumers must go through ``parseCapabilityUri``.
  rawValue: string

defineSealedStringOps(CapabilityUri)

func parseCapabilityUri*(raw: string): Result[CapabilityUri, ValidationError] =
  ## Validates the URN envelope per RFC 8141: lenient-token shape (1..255
  ## octets, no control characters), ``urn:`` prefix, and a non-empty NID
  ## segment after the first colon. Vendor URNs (``urn:com:vendor:*``,
  ## ``urn:io:vendor:*``) and IETF URNs (``urn:ietf:params:jmap:*``) are
  ## both accepted. The convention "IETF capabilities go through the typed
  ## ``add<Entity><Method>`` family" is enforced by docstring + H11 lint,
  ## not by construction-time rejection.
  detectLenientToken(raw).isOkOr:
    return err(toValidationError(error, "CapabilityUri", raw))
  if not raw.startsWith("urn:"):
    return err(validationError("CapabilityUri", "must be a URN", raw))
  let colon2 = raw.find(':', start = 4)
  if colon2 < 5:
    return err(validationError("CapabilityUri", "malformed urn: missing NID", raw))
  ok(CapabilityUri(rawValue: raw))
