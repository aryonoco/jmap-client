# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for error type parsers and constructors.

import std/json
import std/random
import std/sequtils
import std/strutils

import jmap_client/internal/types/primitives
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/errors
import jmap_client/internal/serialisation/serde_errors
import jmap_client/internal/types/validation
import ../mproperty
import ../mtestblock

testCase propParseCapabilityKindTotality:
  checkProperty "parseCapabilityKind never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseCapabilityKind(s)

testCase propParseRequestErrorKindTotality:
  checkProperty "parseRequestErrorKind never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseRequestErrorKind(s)

testCase propParseMethodErrorKindTotality:
  checkProperty "parseMethodErrorKind never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseMethodErrorKind(s)

testCase propParseSetErrorKindTotality:
  checkProperty "parseSetErrorKind never crashes":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseSetErrorKind(s)

testCase propCapabilityKindKnownRoundTrip:
  for kind in [
    ckCore, ckMail, ckSubmission, ckVacationResponse, ckWebsocket, ckMdn, ckSmimeVerify,
    ckBlob, ckQuota, ckContacts, ckCalendars, ckSieve,
  ]:
    let uri = capabilityUri(kind).get()
    doAssert parseCapabilityKind(uri) == kind

testCase propRequestErrorKindKnownRoundTrip:
  for v in [retUnknownCapability, retNotJson, retNotRequest, retLimit]:
    doAssert parseRequestErrorKind($v) == v

testCase propMethodErrorKindKnownRoundTrip:
  for v in [
    metServerUnavailable, metServerFail, metServerPartialFail, metUnknownMethod,
    metInvalidArguments, metInvalidResultReference, metForbidden, metAccountNotFound,
    metAccountNotSupportedByMethod, metAccountReadOnly, metAnchorNotFound,
    metUnsupportedSort, metUnsupportedFilter, metCannotCalculateChanges,
    metTooManyChanges, metRequestTooLarge, metStateMismatch, metFromAccountNotFound,
    metFromAccountNotSupportedByMethod,
  ]:
    doAssert parseMethodErrorKind($v) == v

testCase propSetErrorKindKnownRoundTrip:
  for v in [
    setForbidden, setOverQuota, setTooLarge, setRateLimit, setNotFound, setInvalidPatch,
    setWillDestroy, setInvalidProperties, setAlreadyExists, setSingleton,
  ]:
    doAssert parseSetErrorKind($v) == v

testCase propUnknownStringsMaptoCatchAll:
  checkProperty "arbitrary strings map to catch-all":
    let s = genArbitraryString(rng)
    lastInput = s
    let ck = parseCapabilityKind(s)
    if ck != ckUnknown:
      doAssert capabilityUri(ck).get() == s

testCase propRequestErrorRawTypePreserved:
  checkProperty "requestError preserves rawType":
    let s = genArbitraryString(rng)
    lastInput = s
    doAssert requestError(s).rawType == s

testCase propMethodErrorRawTypePreserved:
  checkProperty "methodError preserves rawType":
    let s = genArbitraryString(rng)
    lastInput = s
    doAssert methodError(s).rawType == s

testCase propSetErrorRawTypePreserved:
  checkProperty "setError preserves rawType":
    let s = genArbitraryString(rng)
    lastInput = s
    doAssert setError(s).rawType == s

testCase propClientErrorMessageNonEmpty:
  let te = clientError(transportError(tekNetwork, "msg"))
  doAssert te.message.len > 0
  let re = clientError(requestError("urn:ietf:params:jmap:error:limit"))
  doAssert re.message.len > 0

testCase propSetErrorDefensiveFallback:
  doAssert setError("invalidProperties").kind == setUnknown
  doAssert setError("alreadyExists").kind == setUnknown

testCase propCapabilityUriUnknownIsErr:
  doAssert capabilityUri(ckUnknown).isNone

# --- Error type partition properties ---

testCase propMethodErrorKindBackingStringInjective:
  ## Distinct known variants have distinct $ values.
  for v1 in MethodErrorKind:
    for v2 in MethodErrorKind:
      if v1 != v2 and v1 != metUnknown and v2 != metUnknown:
        doAssert $v1 != $v2

testCase propSetErrorKindBackingStringInjective:
  ## Distinct known variants have distinct $ values.
  for v1 in SetErrorKind:
    for v2 in SetErrorKind:
      if v1 != v2 and v1 != setUnknown and v2 != setUnknown:
        doAssert $v1 != $v2

testCase propMethodErrorKindParseDeterministic:
  checkProperty "propMethodErrorKindParseDeterministic":
    ## Same input always produces same output.
    let s = genArbitraryString(rng, trial)
    lastInput = s
    doAssert parseMethodErrorKind(s) == parseMethodErrorKind(s)

testCase propSetErrorKindParseDeterministic:
  checkProperty "propSetErrorKindParseDeterministic":
    let s = genArbitraryString(rng, trial)
    lastInput = s
    doAssert parseSetErrorKind(s) == parseSetErrorKind(s)

testCase propExhaustiveMethodErrorRoundTrip:
  ## Every non-Unknown variant round-trips through parse.
  for v in MethodErrorKind:
    if v != metUnknown:
      doAssert parseMethodErrorKind($v) == v

testCase propExhaustiveSetErrorRoundTrip:
  for v in SetErrorKind:
    if v != setUnknown:
      doAssert parseSetErrorKind($v) == v

testCase propExhaustiveRequestErrorRoundTrip:
  for v in RequestErrorKind:
    if v != retUnknown:
      doAssert parseRequestErrorKind($v) == v

# --- Error constructor auto-parse coherence ---

testCase propRequestErrorAutoParseCoherence:
  checkProperty "requestError(s).kind == parseRequestErrorKind(s)":
    let s = genArbitraryString(rng, trial)
    lastInput = s
    doAssert requestError(s).kind == parseRequestErrorKind(s)

testCase propMethodErrorAutoParseCoherence:
  checkProperty "methodError(s).kind == parseMethodErrorKind(s)":
    let s = genArbitraryString(rng, trial)
    lastInput = s
    doAssert methodError(s).kind == parseMethodErrorKind(s)

testCase propSetErrorRawTypePreservation:
  checkProperty "setError(s).rawType == s for non-variant strings":
    let s = genArbitraryString(rng, trial)
    lastInput = s
    if s != "invalidProperties" and s != "alreadyExists":
      doAssert setError(s).rawType == s

# --- ClientError lift preservation ---

testCase propClientErrorLiftTransport:
  checkProperty "clientError(te).kind == cekTransport and transport preserved":
    let te = genTransportError(rng)
    let ce = clientError(te)
    doAssert ce.kind == cekTransport
    doAssert ce.transport.kind == te.kind
    doAssert ce.transport.message == te.message
    if te.kind == tekHttpStatus:
      doAssert ce.transport.httpStatus == te.httpStatus

testCase propClientErrorLiftRequest:
  checkProperty "clientError(re).kind == cekRequest and request preserved":
    let re = genRequestError(rng)
    let ce = clientError(re)
    doAssert ce.kind == cekRequest
    doAssert ce.request.kind == re.kind
    doAssert ce.request.rawType == re.rawType
    doAssert ce.request.status == re.status
    doAssert ce.request.title == re.title
    doAssert ce.request.detail == re.detail

# --- SetError variant field preservation ---

testCase propSetErrorInvalidPropertiesFieldPreservation:
  checkProperty "invalidProperties variant preserves properties field":
    let propCount = rng.rand(0 .. 5)
    var props: seq[string] = @[]
    for i in 0 ..< propCount:
      props.add "prop" & $i
    let desc =
      if rng.rand(0 .. 1) == 0:
        Opt.some("desc-" & $rng.rand(0 .. 99))
      else:
        Opt.none(string)
    let se = setErrorInvalidProperties("invalidProperties", props, desc)
    doAssert se.kind == setInvalidProperties
    doAssert se.properties == props
    doAssert se.description == desc

testCase propSetErrorAlreadyExistsFieldPreservation:
  checkProperty "alreadyExists variant preserves existingId field":
    let idStr = genValidIdStrict(rng, minLen = 1, maxLen = 20)
    let id = parseId(idStr).get()
    let desc =
      if rng.rand(0 .. 1) == 0:
        Opt.some("desc-" & $rng.rand(0 .. 99))
      else:
        Opt.none(string)
    let se = setErrorAlreadyExists("alreadyExists", id, desc)
    doAssert se.kind == setAlreadyExists
    doAssert se.existingId == id
    doAssert se.description == desc

# --- Generated error totality and field preservation ---

testCase propGenMethodErrorFieldPreservation:
  checkProperty "genMethodError preserves rawType and auto-parse coherence":
    let me = genMethodError(rng)
    lastInput = me.rawType
    doAssert me.rawType.len > 0
    doAssert me.kind == parseMethodErrorKind(me.rawType)

testCase propGenSetErrorFieldPreservation:
  checkProperty "genSetError preserves rawType and variant fields":
    let se = genSetError(rng)
    lastInput = se.rawType
    doAssert se.rawType.len > 0
    case se.kind
    of setInvalidProperties: discard se.properties
    of setAlreadyExists: discard se.existingId
    else: discard

testCase propGenClientErrorFieldPreservation:
  checkProperty "genClientError message always non-empty and kind disjoint":
    let ce = genClientError(rng)
    lastInput = ce.message
    doAssert ce.message.len > 0
    doAssert (ce.kind == cekTransport) != (ce.kind == cekRequest)

# =============================================================================
# Phase 4B: Extras preservation through round-trip
# =============================================================================

testCase propRequestErrorExtrasPreservation:
  ## Extras survive fromJson(toJson(err)) round-trip for RequestError.
  checkPropertyN "RequestError extras preserved through round-trip", ThoroughTrials:
    let re = genRequestError(rng)
    lastInput = re.rawType
    let j = re.toJson()
    let rt = RequestError.fromJson(j).get()
    # If original had extras, verify they survived.
    if re.extras.isSome:
      doAssert rt.extras.isSome, "extras lost in round-trip"
      for key, val in re.extras.get().pairs:
        doAssert rt.extras.get().hasKey(key),
          "extras key '" & key & "' lost in round-trip"
    # If limit was set, verify it survived.
    doAssert rt.limit == re.limit, "limit field not preserved"

testCase propMethodErrorExtrasPreservation:
  ## Extras survive fromJson(toJson(err)) round-trip for MethodError.
  checkPropertyN "MethodError extras preserved through round-trip", ThoroughTrials:
    let me = genMethodError(rng)
    lastInput = me.rawType
    let j = me.toJson()
    let rt = MethodError.fromJson(j).get()
    if me.extras.isSome:
      doAssert rt.extras.isSome, "extras lost in round-trip"
      for key, val in me.extras.get().pairs:
        doAssert rt.extras.get().hasKey(key),
          "extras key '" & key & "' lost in round-trip"

testCase propSetErrorExtrasPreservation:
  ## Extras survive fromJson(toJson(err)) round-trip for SetError.
  checkPropertyN "SetError extras preserved through round-trip", ThoroughTrials:
    let se = genSetError(rng)
    lastInput = se.rawType
    let j = se.toJson()
    let rt = SetError.fromJson(j).get()
    if se.extras.isSome:
      doAssert rt.extras.isSome, "extras lost in round-trip"
      for key, val in se.extras.get().pairs:
        doAssert rt.extras.get().hasKey(key),
          "extras key '" & key & "' lost in round-trip"

# =============================================================================
# A12: diagnostic projection invariants
# =============================================================================
#
# Five properties locking the ``message()`` contract for every error type:
# determinism, no control bytes, bounded length, lossless classification,
# and (for ``ValidationError``) no ``value`` leak.

testCase propMessageDeterminism:
  ## Two consecutive ``message()`` calls on the same value yield the same
  ## string. The diagnostic is a pure projection — no hidden state.
  checkProperty "message() is deterministic across all error types":
    let ve = genValidationError(rng)
    doAssert ve.message == ve.message
    let te = genTransportError(rng)
    doAssert te.message == te.message
    let re = genRequestError(rng)
    doAssert re.message == re.message
    let me = genMethodError(rng)
    doAssert me.message == me.message
    let se = genSetError(rng)
    doAssert se.message == se.message
    let ce = genClientError(rng)
    doAssert ce.message == ce.message

testCase propMessageNoControlBytes:
  ## ``message()`` never embeds control bytes (below SP, except TAB) —
  ## diagnostics must be safe to splice into a logger line without escaping.
  checkProperty "message() contains no control bytes":
    template noCtl(s: string): bool =
      ## Predicate: ``s`` contains no control bytes apart from TAB.
      s.allIt(it >= ' ' or it == '\t')

    let ve = genValidationError(rng)
    doAssert noCtl(ve.message)
    let te = genTransportError(rng)
    doAssert noCtl(te.message)
    let re = genRequestError(rng)
    doAssert noCtl(re.message)
    let me = genMethodError(rng)
    doAssert noCtl(me.message)
    let se = genSetError(rng)
    doAssert noCtl(se.message)
    let ce = genClientError(rng)
    doAssert noCtl(ce.message)

testCase propMessageBoundedLength:
  ## ``message()`` fits inside a 4096-byte ceiling — prerequisite for the
  ## eventual libcurl ``CURLOPT_ERRORBUFFER``-style FFI surface (D10).
  checkProperty "message().len <= 4096 across all error types":
    let ve = genValidationError(rng)
    doAssert ve.message.len <= 4096
    let te = genTransportError(rng)
    doAssert te.message.len <= 4096
    let re = genRequestError(rng)
    doAssert re.message.len <= 4096
    let me = genMethodError(rng)
    doAssert me.message.len <= 4096
    let se = genSetError(rng)
    doAssert se.message.len <= 4096
    let ce = genClientError(rng)
    doAssert ce.message.len <= 4096

testCase propMessageLosslessClassification:
  ## The classification token is always recoverable from the diagnostic:
  ## ``typeName`` for ValidationError, ``rawType`` for MethodError /
  ## SetError, ``"HTTP " & $status`` for tekHttpStatus TransportError.
  checkProperty "message() carries the classification token verbatim":
    let ve = genValidationError(rng)
    doAssert ve.typeName in ve.message
    let me = genMethodError(rng)
    doAssert me.rawType in me.message
    let se = genSetError(rng)
    doAssert se.rawType in se.message
    let te = genTransportError(rng)
    if te.kind == tekHttpStatus:
      doAssert ("HTTP " & $te.httpStatus) in te.message

testCase propValidationErrorMessageNoValueLeak:
  ## The redaction rule (D4): ``ValidationError.message`` MUST NOT embed
  ## ``value``. ``value`` is untrusted input — callers compose it
  ## explicitly when redaction is safe. The generator constrains the
  ## value's character class to ``'g'..'z'`` and the typeName / reason
  ## strings to disjoint character classes, so any non-empty substring of
  ## ``value`` appearing in ``message`` would be a true regression rather
  ## than a generator-induced false positive.
  checkProperty "ValidationError.message does not embed value":
    let ve = genValidationError(rng)
    doAssert ve.value notin ve.message
