# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for error type parsers and constructors.

import std/json
import std/options
import std/random

import jmap_client/primitives
import jmap_client/capabilities
import jmap_client/errors
import jmap_client/serde_errors
import ../mproperty

block propParseCapabilityKindTotality:
  checkProperty "parseCapabilityKind never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseCapabilityKind(s)

block propParseRequestErrorTypeTotality:
  checkProperty "parseRequestErrorType never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseRequestErrorType(s)

block propParseMethodErrorTypeTotality:
  checkProperty "parseMethodErrorType never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseMethodErrorType(s)

block propParseSetErrorTypeTotality:
  checkProperty "parseSetErrorType never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseSetErrorType(s)

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
    lastInput = s
    let ck = parseCapabilityKind(s)
    if ck != ckUnknown:
      doAssert capabilityUri(ck).get() == s

block propRequestErrorRawTypePreserved:
  checkProperty "requestError preserves rawType":
    let s = genArbitraryString(rng)
    lastInput = s
    doAssert requestError(s).rawType == s

block propMethodErrorRawTypePreserved:
  checkProperty "methodError preserves rawType":
    let s = genArbitraryString(rng)
    lastInput = s
    doAssert methodError(s).rawType == s

block propSetErrorRawTypePreserved:
  checkProperty "setError preserves rawType":
    let s = genArbitraryString(rng)
    lastInput = s
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
  doAssert capabilityUri(ckUnknown).isNone

# --- Error type partition properties ---

block propMethodErrorTypeBackingStringInjective:
  ## Distinct known variants have distinct $ values.
  for v1 in MethodErrorType:
    for v2 in MethodErrorType:
      if v1 != v2 and v1 != metUnknown and v2 != metUnknown:
        doAssert $v1 != $v2

block propSetErrorTypeBackingStringInjective:
  ## Distinct known variants have distinct $ values.
  for v1 in SetErrorType:
    for v2 in SetErrorType:
      if v1 != v2 and v1 != setUnknown and v2 != setUnknown:
        doAssert $v1 != $v2

block propMethodErrorTypeParseDeterministic:
  checkProperty "propMethodErrorTypeParseDeterministic":
    ## Same input always produces same output.
    let s = genArbitraryString(rng, trial)
    lastInput = s
    doAssert parseMethodErrorType(s) == parseMethodErrorType(s)

block propSetErrorTypeParseDeterministic:
  checkProperty "propSetErrorTypeParseDeterministic":
    let s = genArbitraryString(rng, trial)
    lastInput = s
    doAssert parseSetErrorType(s) == parseSetErrorType(s)

block propExhaustiveMethodErrorRoundTrip:
  ## Every non-Unknown variant round-trips through parse.
  for v in MethodErrorType:
    if v != metUnknown:
      doAssert parseMethodErrorType($v) == v

block propExhaustiveSetErrorRoundTrip:
  for v in SetErrorType:
    if v != setUnknown:
      doAssert parseSetErrorType($v) == v

block propExhaustiveRequestErrorRoundTrip:
  for v in RequestErrorType:
    if v != retUnknown:
      doAssert parseRequestErrorType($v) == v

# --- Error constructor auto-parse coherence ---

block propRequestErrorAutoParseCoherence:
  checkProperty "requestError(s).errorType == parseRequestErrorType(s)":
    let s = genArbitraryString(rng, trial)
    lastInput = s
    doAssert requestError(s).errorType == parseRequestErrorType(s)

block propMethodErrorAutoParseCoherence:
  checkProperty "methodError(s).errorType == parseMethodErrorType(s)":
    let s = genArbitraryString(rng, trial)
    lastInput = s
    doAssert methodError(s).errorType == parseMethodErrorType(s)

block propSetErrorRawTypePreservation:
  checkProperty "setError(s).rawType == s for non-variant strings":
    let s = genArbitraryString(rng, trial)
    lastInput = s
    if s != "invalidProperties" and s != "alreadyExists":
      doAssert setError(s).rawType == s

# --- ClientError lift preservation ---

block propClientErrorLiftTransport:
  checkProperty "clientError(te).kind == cekTransport and transport preserved":
    let te = genTransportError(rng)
    let ce = clientError(te)
    doAssert ce.kind == cekTransport
    doAssert ce.transport.kind == te.kind
    doAssert ce.transport.msg == te.msg
    if te.kind == tekHttpStatus:
      doAssert ce.transport.httpStatus == te.httpStatus

block propClientErrorLiftRequest:
  checkProperty "clientError(re).kind == cekRequest and request preserved":
    let re = genRequestError(rng)
    let ce = clientError(re)
    doAssert ce.kind == cekRequest
    doAssert ce.request.errorType == re.errorType
    doAssert ce.request.rawType == re.rawType
    doAssert ce.request.status == re.status
    doAssert ce.request.title == re.title
    doAssert ce.request.detail == re.detail

# --- SetError variant field preservation ---

block propSetErrorInvalidPropertiesFieldPreservation:
  checkProperty "invalidProperties variant preserves properties field":
    let propCount = rng.rand(0 .. 5)
    var props: seq[string] = @[]
    for i in 0 ..< propCount:
      props.add "prop" & $i
    let desc =
      if rng.rand(0 .. 1) == 0:
        some("desc-" & $rng.rand(0 .. 99))
      else:
        none(string)
    let se = setErrorInvalidProperties("invalidProperties", props, desc)
    doAssert se.errorType == setInvalidProperties
    doAssert se.properties == props
    doAssert se.description == desc

block propSetErrorAlreadyExistsFieldPreservation:
  checkProperty "alreadyExists variant preserves existingId field":
    let idStr = genValidIdStrict(rng, minLen = 1, maxLen = 20)
    let id = parseId(idStr)
    let desc =
      if rng.rand(0 .. 1) == 0:
        some("desc-" & $rng.rand(0 .. 99))
      else:
        none(string)
    let se = setErrorAlreadyExists("alreadyExists", id, desc)
    doAssert se.errorType == setAlreadyExists
    doAssert se.existingId == id
    doAssert se.description == desc

# --- Generated error totality and field preservation ---

block propGenMethodErrorFieldPreservation:
  checkProperty "genMethodError preserves rawType and auto-parse coherence":
    let me = genMethodError(rng)
    lastInput = me.rawType
    doAssert me.rawType.len > 0
    doAssert me.errorType == parseMethodErrorType(me.rawType)

block propGenSetErrorFieldPreservation:
  checkProperty "genSetError preserves rawType and variant fields":
    let se = genSetError(rng)
    lastInput = se.rawType
    doAssert se.rawType.len > 0
    case se.errorType
    of setInvalidProperties: discard se.properties
    of setAlreadyExists: discard se.existingId
    else: discard

block propGenClientErrorFieldPreservation:
  checkProperty "genClientError message always non-empty and kind disjoint":
    let ce = genClientError(rng)
    lastInput = ce.message
    doAssert ce.message.len > 0
    doAssert (ce.kind == cekTransport) != (ce.kind == cekRequest)

# =============================================================================
# Phase 4B: Extras preservation through round-trip
# =============================================================================

block propRequestErrorExtrasPreservation:
  ## Extras survive fromJson(toJson(err)) round-trip for RequestError.
  checkPropertyN "RequestError extras preserved through round-trip", ThoroughTrials:
    let re = genRequestError(rng)
    lastInput = re.rawType
    let j = re.toJson()
    let rt = RequestError.fromJson(j)
    # If original had extras, verify they survived.
    if re.extras.isSome:
      doAssert rt.extras.isSome, "extras lost in round-trip"
      for key, val in re.extras.get().pairs:
        doAssert rt.extras.get().hasKey(key),
          "extras key '" & key & "' lost in round-trip"
    # If limit was set, verify it survived.
    doAssert rt.limit == re.limit, "limit field not preserved"

block propMethodErrorExtrasPreservation:
  ## Extras survive fromJson(toJson(err)) round-trip for MethodError.
  checkPropertyN "MethodError extras preserved through round-trip", ThoroughTrials:
    let me = genMethodError(rng)
    lastInput = me.rawType
    let j = me.toJson()
    let rt = MethodError.fromJson(j)
    if me.extras.isSome:
      doAssert rt.extras.isSome, "extras lost in round-trip"
      for key, val in me.extras.get().pairs:
        doAssert rt.extras.get().hasKey(key),
          "extras key '" & key & "' lost in round-trip"

block propSetErrorExtrasPreservation:
  ## Extras survive fromJson(toJson(err)) round-trip for SetError.
  checkPropertyN "SetError extras preserved through round-trip", ThoroughTrials:
    let se = genSetError(rng)
    lastInput = se.rawType
    let j = se.toJson()
    let rt = SetError.fromJson(j)
    if se.extras.isSome:
      doAssert rt.extras.isSome, "extras lost in round-trip"
      for key, val in se.extras.get().pairs:
        doAssert rt.extras.get().hasKey(key),
          "extras key '" & key & "' lost in round-trip"
