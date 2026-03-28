# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based tests for error type parsers and constructors.

import std/random

import pkg/results

import jmap_client/primitives
import jmap_client/capabilities
import jmap_client/errors
import ./mproperty

block propParseCapabilityKindTotality:
  checkProperty "parseCapabilityKind never crashes":
    discard parseCapabilityKind(genArbitraryString(rng))

block propParseRequestErrorTypeTotality:
  checkProperty "parseRequestErrorType never crashes":
    discard parseRequestErrorType(genArbitraryString(rng))

block propParseMethodErrorTypeTotality:
  checkProperty "parseMethodErrorType never crashes":
    discard parseMethodErrorType(genArbitraryString(rng))

block propParseSetErrorTypeTotality:
  checkProperty "parseSetErrorType never crashes":
    discard parseSetErrorType(genArbitraryString(rng))

block propCapabilityKindKnownRoundTrip:
  for kind in [
    ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckSmimeVerify,
    ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve,
  ]:
    let uri = capabilityUri(kind).get()
    doAssert parseCapabilityKind(uri) == kind

block propRequestErrorTypeKnownRoundTrip:
  for v in [retUnknownCapability, retNotJson, retNotRequest, retLimit]:
    doAssert parseRequestErrorType($v) == v

block propMethodErrorTypeKnownRoundTrip:
  for v in [
    metServerUnavailable, metServerFail, metServerPartialFail, metUnknownMethod,
    metInvalidArguments, metInvalidResultReference, metForbidden, metAccountNotFound,
    metAccountNotSupportedByMethod, metAccountReadOnly, metAnchorNotFound,
    metUnsupportedSort, metUnsupportedFilter, metCannotCalculateChanges,
    metTooManyChanges, metRequestTooLarge, metStateMismatch, metFromAccountNotFound,
    metFromAccountNotSupportedByMethod,
  ]:
    doAssert parseMethodErrorType($v) == v

block propSetErrorTypeKnownRoundTrip:
  for v in [
    setForbidden, setOverQuota, setTooLarge, setRateLimit, setNotFound, setInvalidPatch,
    setWillDestroy, setInvalidProperties, setAlreadyExists, setSingleton,
  ]:
    doAssert parseSetErrorType($v) == v

block propUnknownStringsMaptoCatchAll:
  checkProperty "arbitrary strings map to catch-all":
    let s = genArbitraryString(rng)
    let ck = parseCapabilityKind(s)
    if ck != ckUnknown:
      doAssert capabilityUri(ck).get() == s

block propRequestErrorRawTypePreserved:
  checkProperty "requestError preserves rawType":
    let s = genArbitraryString(rng)
    doAssert requestError(s).rawType == s

block propMethodErrorRawTypePreserved:
  checkProperty "methodError preserves rawType":
    let s = genArbitraryString(rng)
    doAssert methodError(s).rawType == s

block propSetErrorRawTypePreserved:
  checkProperty "setError preserves rawType":
    let s = genArbitraryString(rng)
    doAssert setError(s).rawType == s

block propClientErrorMessageNonEmpty:
  let te = clientError(transportError(tekNetwork, "msg"))
  doAssert te.message.len > 0
  let re = clientError(requestError("urn:ietf:params:jmap:error:limit"))
  doAssert re.message.len > 0

block propSetErrorDefensiveFallback:
  doAssert setError("invalidProperties").errorType == setUnknown
  doAssert setError("alreadyExists").errorType == setUnknown

block propCapabilityUriUnknownIsErr:
  doAssert capabilityUri(ckUnknown).isErr
