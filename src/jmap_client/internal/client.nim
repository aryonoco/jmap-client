# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP client handle (Layer 4). Reference-counted handle binding a
## pluggable ``Transport`` to a typed ``SessionEndpoint``, a typed
## ``Credential``, cached session state, and the per-handle builder
## serial counter. ARC destroys the underlying ``Transport`` when the
## last reference drops; no public ``close`` proc exists.
##
## **Construction.** ``initJmapClient(endpoint, credential)`` uses the
## default ``newHttpTransport()`` backend. ``initJmapClient(endpoint,
## credential, transport)`` accepts a caller-supplied ``Transport`` for
## custom HTTP backends (libcurl, puppy, chronos, recording proxies,
## in-process mocks). A discovery domain is expressed as a
## ``SessionEndpoint`` variant (``discoveryEndpoint``), not a separate
## constructor.
##
## **Threading.** Not thread-safe; hold one per thread. ARC ref-count
## manipulation IS thread-safe under ``--threads:on``, but field access
## and the destructor invocation of the Transport's ``closeImpl`` are
## not. Whichever thread releases the last reference runs the
## destructor on that thread.

{.push raises: [].}
{.experimental: "strictCaseObjects".}

import std/json
import std/sysrand

import results

import ./types
import ./types/envelope
import ./types/validation
import ./types/errors
import ./serialisation/serde
import ./serialisation/serde_envelope
import ./serialisation/serde_session
import ./transport
import ./types/identifiers
import ./protocol/builder
import ./protocol/dispatch
import ./protocol/jmap_error
import ./protocol/call_meta
import ./transport/url_resolution
import ./transport/classify
import ./types/credential
import ./types/session_endpoint

type WireDirection* = enum
  ## Direction of a wire byte sequence as observed by a
  ## ``DebugCallback``. ``wdSend`` is the request body the client is
  ## about to hand to ``Transport.send``; ``wdReceive`` is the
  ## response body the transport returned. The library invokes the
  ## callback once per direction per HTTP exchange — every
  ## ``fetchSession`` and every ``send``, including the GET exchange
  ## where ``wdSend`` carries an empty ``openArray[byte]``.
  wdSend
  wdReceive

type DebugCallback* =
  proc(direction: WireDirection, bytes: openArray[byte]) {.closure, gcsafe, raises: [].}
  ## Per-handle wire-inspection callback (P11). Modelled after
  ## libcurl's ``CURLOPT_DEBUGFUNCTION``. ``bytes`` is borrowed for
  ## the duration of the call — the application must copy if it
  ## needs to retain the data across the return.

# Design §9.1 (D4.12): compile-time hint when -d:ssl is missing.
# Uses {.hint:} rather than {.warning:} because config.nims promotes
# User warnings to errors (warningAsError: User). A hint achieves the
# same informational goal without blocking compilation.
when not defined(ssl):
  {.
    hint:
      "jmap-client: -d:ssl is not defined. " & "HTTPS connections will fail at runtime. " &
      "Add -d:ssl to your compile flags."
  .}

{.push ruleOff: "objects".}

type JmapClientObj = object
  transport: Transport
  endpoint: SessionEndpoint
  credential: Credential
  resolvedSessionUrl: Opt[string]
  session: Opt[Session]
  clientBrand: uint64
  nextBuilderSerial: uint64
  debugCallback: Opt[DebugCallback]

# ``{.ruleOff: "hasDoc".}`` on the ref alias works around a
# nimalyzer 0.12.2 bug: hasdoc.nim:217-228 indexes
# ``node[2][0][2]`` on the nkRefTy arm of nkTypeDef, assuming the
# inner node is always nkObjectTy. For ``ref NamedType`` the inner
# is nkIdent (a leaf) and the access raises FieldDefect — see the
# matching comment in ``src/jmap_client/transport.nim``. The
# named-inner-type shape is the canonical Nim 2.x pattern
# (mirrors stdlib's ``Regex``, ``FlowVar``) and is preserved here
# instead of working around the bug at the type level.
type JmapClient* {.ruleOff: "hasDoc".} = ref JmapClientObj
  ## JMAP client handle. Reference-counted; ARC tears down the
  ## underlying ``Transport`` when the last reference drops. Not thread-
  ## safe — hold one per thread.

{.pop.}

proc drawClientBrand(): Result[uint64, ValidationError] =
  ## Reads 8 bytes of OS entropy via ``std/sysrand.urandom``. Errs when the
  ## OS entropy source is unavailable — the sole construction failure now that
  ## endpoint and credential arrive pre-validated as sealed Layer-1 values.
  ## Brand uniqueness is the only requirement; the sysrand path is preferred
  ## for isolation across cooperating processes.
  var bytes: array[8, byte] = default(array[8, byte])
  if not urandom(bytes):
    return err(validationError("JmapClient", "OS entropy source unavailable", ""))
  ok(cast[uint64](bytes))

# ---------------------------------------------------------------------------
# Constructors
# ---------------------------------------------------------------------------

proc initJmapClient*(
    endpoint: SessionEndpoint, credential: Credential, transport: Transport
): Result[JmapClient, JmapError] =
  ## Primary constructor — the application developer supplies a ``Transport``
  ## (libcurl wrapper, in-process mock, recording proxy). The session is NOT
  ## fetched here; call ``fetchSession()`` or let ``send()`` fetch it lazily.
  ## ``endpoint`` and ``credential`` are pre-validated sealed values, so the
  ## only failure is OS entropy for the client brand — lifted onto the one rail.
  let clientBrand = ?drawClientBrand().lift
  ok(
    JmapClient(
      transport: transport,
      endpoint: endpoint,
      credential: credential,
      resolvedSessionUrl: Opt.none(string),
      session: Opt.none(Session),
      clientBrand: clientBrand,
      nextBuilderSerial: 0'u64,
      debugCallback: Opt.none(DebugCallback),
    )
  )

proc initJmapClient*(
    endpoint: SessionEndpoint, credential: Credential
): Result[JmapClient, JmapError] =
  ## Convenience constructor — uses the default ``newHttpTransport()`` backend.
  ## HTTP-level configuration (timeout, redirects, response-size cap,
  ## user-agent) lives on ``newHttpTransport``; callers who need non-default
  ## values build their own transport and use the primary overload.
  let t = ?newHttpTransport()
  initJmapClient(endpoint, credential, t)

# ---------------------------------------------------------------------------
# Mutators and pure observers
# ---------------------------------------------------------------------------

proc newBuilder*(client: JmapClient): RequestBuilder =
  ## Single blessed entry point for building a request. Mints a
  ## ``BuilderId`` from the client's ``clientBrand`` and the next
  ## builder serial, increments the serial, and returns a fresh
  ## ``RequestBuilder`` branded with that id.
  let id = initBuilderId(client.clientBrand, client.nextBuilderSerial)
  client.nextBuilderSerial += 1
  initRequestBuilder(id)

proc setCredential*(client: JmapClient, credential: Credential) =
  ## Rotates the client's credential. Subsequent requests build the
  ## ``Authorization`` header from the new credential. No validation — a
  ## ``Credential`` is valid by construction.
  client.credential = credential

proc setDebugCallback*(client: JmapClient, cb: DebugCallback) =
  ## Installs, replaces, or detaches the per-handle wire debug
  ## callback. Pass ``nil`` to detach — libcurl shape:
  ## ``curl_easy_setopt(h, CURLOPT_DEBUGFUNCTION, NULL)``. Once set,
  ## fires on every transport exchange until detached or until the
  ## ``JmapClient`` is dropped.
  if cb.isNil:
    client.debugCallback = Opt.none(DebugCallback)
  else:
    client.debugCallback = Opt.some(cb)

# ---------------------------------------------------------------------------
# Pre-flight validation (§7)
# ---------------------------------------------------------------------------

type RequestLimitViolationKind = enum
  rlvMaxCallsInRequest
  rlvMaxObjectsInGet
  rlvMaxObjectsInSet
  rlvMaxSizeRequest

type RequestLimitViolation {.ruleOff: "objects".} = object
  case kind: RequestLimitViolationKind
  of rlvMaxCallsInRequest:
    actualCalls: int64
    maxCalls: int64
  of rlvMaxObjectsInGet:
    getMethodName: string
    actualGetIds: int
    maxGet: int64
  of rlvMaxObjectsInSet:
    setMethodName: string
    actualSetObjects: int64
    maxSet: int64
  of rlvMaxSizeRequest:
    actualSize: int
    maxSize: int64

func toValidationError(v: RequestLimitViolation): ValidationError =
  ## Sole domain-to-wire translator for ``RequestLimitViolation``.
  case v.kind
  of rlvMaxCallsInRequest:
    validationError(
      "Request",
      "method call count " & $v.actualCalls & " exceeds maxCallsInRequest " & $v.maxCalls,
      "",
    )
  of rlvMaxObjectsInGet:
    validationError(
      "Request",
      v.getMethodName & ": ids count " & $v.actualGetIds & " exceeds maxObjectsInGet " &
        $v.maxGet,
      "",
    )
  of rlvMaxObjectsInSet:
    validationError(
      "Request",
      v.setMethodName & ": object count " & $v.actualSetObjects &
        " exceeds maxObjectsInSet " & $v.maxSet,
      "",
    )
  of rlvMaxSizeRequest:
    validationError(
      "Request",
      "serialised request size " & $v.actualSize &
        " octets exceeds server maxSizeRequest " & $v.maxSize,
      "",
    )

func detectGetLimit(
    meta: CallLimitMeta, methodName: string, maxGet: int64
): Result[void, RequestLimitViolation] =
  ## Enforces ``maxObjectsInGet`` from the typed ``idCount`` carried by
  ## the builder. Reference-resolved ids (``Opt.none``) are silently
  ## skipped — actual count is unknown until the server resolves the
  ## back-reference.
  case meta.kind
  of clmGet:
    let n = meta.idCount.valueOr:
      return ok()
    if int64(n) > maxGet:
      return err(
        RequestLimitViolation(
          kind: rlvMaxObjectsInGet,
          getMethodName: methodName,
          actualGetIds: n,
          maxGet: maxGet,
        )
      )
    ok()
  of clmSet, clmOther:
    ok()

func detectSetLimit(
    meta: CallLimitMeta, methodName: string, maxSet: int64
): Result[void, RequestLimitViolation] =
  ## Enforces ``maxObjectsInSet`` from the typed ``objectCount`` carried
  ## by the builder. Reference-resolved destroy (``Opt.none``) is
  ## silently skipped.
  case meta.kind
  of clmSet:
    let n = meta.objectCount.valueOr:
      return ok()
    if int64(n) > maxSet:
      return err(
        RequestLimitViolation(
          kind: rlvMaxObjectsInSet,
          setMethodName: methodName,
          actualSetObjects: int64(n),
          maxSet: maxSet,
        )
      )
    ok()
  of clmGet, clmOther:
    ok()

func detectMaxCalls(
    request: Request, maxCalls: int64
): Result[void, RequestLimitViolation] =
  ## Top-level method-call count against ``maxCallsInRequest``.
  if int64(request.methodCalls.len) > maxCalls:
    return err(
      RequestLimitViolation(
        kind: rlvMaxCallsInRequest,
        actualCalls: int64(request.methodCalls.len),
        maxCalls: maxCalls,
      )
    )
  ok()

func detectRequestLimitsTyped(
    request: Request, callLimits: seq[CallLimitMeta], caps: CoreCapabilities
): Result[void, RequestLimitViolation] =
  ## Pre-flight composition: max-calls then per-invocation /get and
  ## /set limits. The parallel invariant
  ## ``request.methodCalls.len == callLimits.len`` is maintained by
  ## ``addInvocation*``.
  ?detectMaxCalls(request, caps.maxCallsInRequest.toInt64)
  let maxGet = caps.maxObjectsInGet.toInt64
  let maxSet = caps.maxObjectsInSet.toInt64
  for i in 0 ..< callLimits.len:
    let meta = callLimits[i]
    let methodName = request.methodCalls[i].rawName
    case meta.kind
    of clmGet:
      ?detectGetLimit(meta, methodName, maxGet)
    of clmSet:
      ?detectSetLimit(meta, methodName, maxSet)
    of clmOther:
      discard
  ok()

func validateLimits(
    req: BuiltRequest, caps: CoreCapabilities
): Result[void, ValidationError] =
  ## Full pre-flight validation for a frozen request. Module-private —
  ## the single internal caller is ``send``; tests drive limit
  ## enforcement through ``client.send`` via a canned-session transport.
  detectRequestLimitsTyped(req.request, req.callLimits, caps).isOkOr:
    return err(toValidationError(error))
  ok()

# ---------------------------------------------------------------------------
# Session and dispatch (§3, §4, §6)
# ---------------------------------------------------------------------------

func authorizationHeader(client: JmapClient): string =
  ## Per-call Authorization header value, materialised from the typed
  ## credential. Pure.
  client.credential.authorizationHeaderValue

proc fireDebug(client: JmapClient, direction: WireDirection, bytes: openArray[byte]) =
  ## Fires the per-handle debug callback if installed. ``DebugCallback``
  ## is typed ``{.closure, gcsafe, raises: [].}``, so the call site
  ## requires no ``cast(gcsafe)`` block — the typed pragma is the
  ## contract. ``for cb in opt:`` is the canonical ``Opt[T]``
  ## consumption form (``nim-conventions.md`` "Optional Values").
  for cb in client.debugCallback:
    cb(direction, bytes)

func resolveEndpoint(client: JmapClient): string =
  ## Resolves the endpoint intent to a concrete session URL. Both current arms
  ## are pure and infallible; the reserved ``sekSrvDomain`` arm will make this
  ## effectful (DNS) and is the single seam where that lands (decision #12).
  case client.endpoint.kind
  of sekDirectUrl:
    # asDirectUrl is Some whenever kind is sekDirectUrl (just matched).
    client.endpoint.asDirectUrl.get()
  of sekDiscoveryDomain:
    # asDiscoveryDomain is Some whenever kind is sekDiscoveryDomain.
    "https://" & client.endpoint.asDiscoveryDomain.get() & "/.well-known/jmap"

proc fetchSession*(client: JmapClient): JmapResult[Session] =
  ## Resolves the endpoint to a concrete session URL (caching it in
  ## ``resolvedSessionUrl``), fetches the JMAP Session resource from the
  ## server, and caches it. Re-fetching replaces both cached values.
  let sessionUrl = resolveEndpoint(client)
  client.resolvedSessionUrl = Opt.some(sessionUrl)
  let req = HttpRequest(
    url: sessionUrl,
    httpMethod: hmGet,
    body: "",
    authorization: authorizationHeader(client),
  )
  client.fireDebug(wdSend, req.body.toOpenArrayByte(0, req.body.high))
  let httpResp = client.transport.send(req).valueOr:
    return err(jmapTransport(error))
  client.fireDebug(wdReceive, httpResp.body.toOpenArrayByte(0, httpResp.body.high))
  let jsonNode = ?parseJmapJson(httpResp, rcSession)
  let session = ?Session.fromJson(jsonNode).mapErr(
    proc(sv: SerdeViolation): JmapError =
      jmapProtocol(protocolDecode(sv))
  )
  client.session = Opt.some(session)
  ok(session)

proc performSend(
    client: JmapClient, request: Request, session: Session
): JmapResult[envelope.Response] =
  ## Internal: serialise + post-serialisation maxSizeRequest check +
  ## HTTP POST via Transport + response classification + decode.
  ## Pre-flight validation (``validateLimits``) MUST happen in
  ## ``send`` before invoking this.
  let coreCaps = session.core
  let jsonNode = request.toJson()
  let body = $jsonNode
  client.fireDebug(wdSend, body.toOpenArrayByte(0, body.high))
  let maxSize = coreCaps.maxSizeRequest.toInt64
  if body.len > int(maxSize):
    let ve = toValidationError(
      RequestLimitViolation(
        kind: rlvMaxSizeRequest, actualSize: body.len, maxSize: maxSize
      )
    )
    return err(jmapValidation(ve))
  let resolved = client.resolvedSessionUrl
  let baseUrl = resolved.valueOr:
    # ensureSession → fetchSession populated this before any performSend.
    return err(
      jmapTransport(transportError(tekNetwork, "session URL unresolved before send"))
    )
  let req = HttpRequest(
    url: resolveAgainstSession(baseUrl, $session.apiUrl),
    httpMethod: hmPost,
    body: body,
    authorization: authorizationHeader(client),
  )
  let httpResp = client.transport.send(req).valueOr:
    return err(jmapTransport(error))
  client.fireDebug(wdReceive, httpResp.body.toOpenArrayByte(0, httpResp.body.high))
  parseJmapResponse(httpResp, rcApi)

proc ensureSession(client: JmapClient): JmapResult[Session] =
  ## Internal: fetch the session lazily on first call, then return the
  ## cached value.
  if client.session.isNone:
    discard ?client.fetchSession()
  let sessionOpt = client.session
  let session = sessionOpt.valueOr:
    return err(
      jmapTransport(
        transportError(tekNetwork, "session unavailable after fetchSession succeeded")
      )
    )
  ok(session)

func isSessionStale*(client: JmapClient, dr: DispatchedResponse): bool =
  ## Compares ``dr.sessionState`` with the cached ``Session.state``.
  ## Returns ``true`` if they differ; ``false`` if no session is cached.
  let s = client.session.valueOr:
    return false
  s.state != dr.sessionState

proc refreshSessionIfStale*(
    client: JmapClient, dr: DispatchedResponse
): JmapResult[bool] =
  ## If the dispatched response indicates a stale session, re-fetches
  ## it. Returns ``ok(true)`` if refreshed, ``ok(false)`` otherwise.
  if client.isSessionStale(dr):
    discard ?client.fetchSession()
    return ok(true)
  ok(false)

proc send*(client: JmapClient, req: sink BuiltRequest): JmapResult[DispatchedResponse] =
  ## Validates limits, fetches the session lazily, POSTs the serialised
  ## request through the Transport, parses the wire ``Response``, and
  ## returns a ``DispatchedResponse`` branded with the builder's ``id``.
  ##
  ## **Consumes ``req``**. ``BuiltRequest`` is uncopyable (``=copy`` and
  ## ``=dup`` are ``{.error.}``); double-``send`` of the same ``req`` is
  ## a compile error.
  let session = ?ensureSession(client)
  let coreCaps = session.core
  ?validateLimits(req, coreCaps).lift
  let wire = ?performSend(client, req.request, session)
  ok(initDispatchedResponse(wire, req.builderId))
