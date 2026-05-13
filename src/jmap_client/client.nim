# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP client handle (Layer 4). Reference-counted handle binding a
## pluggable ``Transport`` to session URL, bearer credentials, cached
## session state, and the per-handle builder serial counter. ARC
## destroys the underlying ``Transport`` when the last reference drops;
## no public ``close`` proc exists.
##
## **Construction.** ``initJmapClient(sessionUrl, bearerToken)`` uses
## the default ``newHttpTransport()`` backend. ``initJmapClient(
## transport, sessionUrl, bearerToken)`` accepts a caller-supplied
## ``Transport`` for custom HTTP backends (libcurl, puppy, chronos,
## recording proxies, in-process mocks). ``discoverJmapClient`` is the
## ``.well-known/jmap`` URL-construction convenience with the same two
## overloads.
##
## **Threading.** Not thread-safe; hold one per thread. ARC ref-count
## manipulation IS thread-safe under ``--threads:on``, but field access
## and the destructor invocation of the Transport's ``closeImpl`` are
## not. Whichever thread releases the last reference runs the
## destructor on that thread.

{.push raises: [].}
{.experimental: "strictCaseObjects".}

import std/json
import std/strutils
import std/sysrand

import results

import ./types
import ./serialisation
import ./transport
import ./internal/types/identifiers
import ./internal/protocol/builder
import ./internal/protocol/dispatch
import ./internal/protocol/call_meta
import ./internal/transport/url_resolution
import ./internal/transport/classify

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
  sessionUrl: string
  bearerToken: string
  authScheme: string
  session: Opt[Session]
  clientBrand: uint64
  nextBuilderSerial: uint64

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

type JmapClientViolationKind = enum
  jcvEmptySessionUrl
  jcvSessionUrlBadScheme
  jcvSessionUrlControlChar
  jcvEmptyBearerToken
  jcvEntropyUnavailable
  jcvEmptyDomain
  jcvDomainWhitespace
  jcvDomainSlash

type JmapClientViolation {.ruleOff: "objects".} = object
  case kind: JmapClientViolationKind
  of jcvEmptySessionUrl, jcvEmptyBearerToken, jcvEmptyDomain, jcvEntropyUnavailable:
    discard
  of jcvSessionUrlBadScheme, jcvSessionUrlControlChar:
    sessionUrl: string
  of jcvDomainWhitespace, jcvDomainSlash:
    domain: string

func toValidationError(v: JmapClientViolation): ValidationError =
  ## Sole domain-to-wire translator for ``JmapClientViolation``. Every
  ## wire message lives here; adding a ``jcvX`` variant forces a compile
  ## error at this site.
  case v.kind
  of jcvEmptySessionUrl:
    validationError("JmapClient", "sessionUrl must not be empty", "")
  of jcvSessionUrlBadScheme, jcvSessionUrlControlChar:
    if v.kind == jcvSessionUrlBadScheme:
      validationError(
        "JmapClient", "sessionUrl must start with https:// or http://", v.sessionUrl
      )
    else:
      validationError(
        "JmapClient", "sessionUrl must not contain newline characters", v.sessionUrl
      )
  of jcvEmptyBearerToken:
    validationError("JmapClient", "bearerToken must not be empty", "")
  of jcvEntropyUnavailable:
    validationError("JmapClient", "OS entropy source unavailable", "")
  of jcvEmptyDomain:
    validationError("JmapClient", "domain must not be empty", "")
  of jcvDomainWhitespace, jcvDomainSlash:
    if v.kind == jcvDomainWhitespace:
      validationError("JmapClient", "domain must not contain whitespace", v.domain)
    else:
      validationError("JmapClient", "domain must not contain '/'", v.domain)

func detectSessionUrl(sessionUrl: string): Result[void, JmapClientViolation] =
  ## Structural validation of the JMAP session URL: non-empty, https://
  ## or http:// scheme, no embedded newlines that would break HTTP
  ## framing.
  if sessionUrl.len == 0:
    return err(JmapClientViolation(kind: jcvEmptySessionUrl))
  if not sessionUrl.startsWith("https://") and not sessionUrl.startsWith("http://"):
    return
      err(JmapClientViolation(kind: jcvSessionUrlBadScheme, sessionUrl: sessionUrl))
  if sessionUrl.contains({'\c', '\L'}):
    return
      err(JmapClientViolation(kind: jcvSessionUrlControlChar, sessionUrl: sessionUrl))
  ok()

func detectBearerToken(token: string): Result[void, JmapClientViolation] =
  ## Bearer token non-emptiness — the server rejects empty Authorization
  ## headers anyway, but failing here saves a round-trip.
  if token.len == 0:
    return err(JmapClientViolation(kind: jcvEmptyBearerToken))
  ok()

func detectDomain(domain: string): Result[void, JmapClientViolation] =
  ## Bare-domain validation for ``.well-known/jmap`` URL construction
  ## (RFC 8620 §2.2). Rejects empty, whitespace, and slash-containing
  ## inputs; scheme/path appear in the synthesised session URL.
  if domain.len == 0:
    return err(JmapClientViolation(kind: jcvEmptyDomain))
  for c in domain:
    if c in Whitespace:
      return err(JmapClientViolation(kind: jcvDomainWhitespace, domain: domain))
  if '/' in domain:
    return err(JmapClientViolation(kind: jcvDomainSlash, domain: domain))
  ok()

proc drawClientBrand(): Result[uint64, JmapClientViolation] =
  ## Reads 8 bytes of OS entropy via ``std/sysrand.urandom``. Returns
  ## ``err(jcvEntropyUnavailable)`` if the OS entropy source is
  ## unavailable. Brand uniqueness is the only requirement; the sysrand
  ## path is preferred for isolation across cooperating processes.
  var bytes: array[8, byte] = default(array[8, byte])
  if not urandom(bytes):
    return err(JmapClientViolation(kind: jcvEntropyUnavailable))
  ok(cast[uint64](bytes))

# ---------------------------------------------------------------------------
# Constructors
# ---------------------------------------------------------------------------

proc initJmapClient*(
    transport: Transport,
    sessionUrl: string,
    bearerToken: string,
    authScheme: string = "Bearer",
): Result[JmapClient, ValidationError] =
  ## Primary constructor — application developer supplies a Transport
  ## (e.g., a libcurl wrapper, an in-process mock, a recording proxy).
  ##
  ## Does NOT fetch the session — call ``fetchSession()`` explicitly or
  ## let ``send()`` fetch it lazily on first call.
  ##
  ## Returns err on invalid session URL or bearer token.
  detectSessionUrl(sessionUrl).isOkOr:
    return err(toValidationError(error))
  detectBearerToken(bearerToken).isOkOr:
    return err(toValidationError(error))
  let clientBrand = drawClientBrand().valueOr:
    return err(toValidationError(error))
  ok(
    JmapClient(
      transport: transport,
      sessionUrl: sessionUrl,
      bearerToken: bearerToken,
      authScheme: authScheme,
      session: Opt.none(Session),
      clientBrand: clientBrand,
      nextBuilderSerial: 0'u64,
    )
  )

proc initJmapClient*(
    sessionUrl: string, bearerToken: string, authScheme: string = "Bearer"
): Result[JmapClient, ValidationError] =
  ## Convenience constructor — uses the default ``newHttpTransport()``
  ## backend. HTTP-level configuration (timeout, redirects, response-
  ## size cap, user-agent) lives on ``newHttpTransport``; callers who
  ## need non-default values build their own transport and use the
  ## primary overload.
  let t = ?newHttpTransport()
  initJmapClient(t, sessionUrl, bearerToken, authScheme)

proc discoverJmapClient*(
    transport: Transport,
    domain: string,
    bearerToken: string,
    authScheme: string = "Bearer",
): Result[JmapClient, ValidationError] =
  ## Discovers the JMAP session URL via the ``.well-known/jmap`` path
  ## (RFC 8620 §2.2). Application developer supplies a Transport.
  detectDomain(domain).isOkOr:
    return err(toValidationError(error))
  initJmapClient(
    transport,
    sessionUrl = "https://" & domain & "/.well-known/jmap",
    bearerToken = bearerToken,
    authScheme = authScheme,
  )

proc discoverJmapClient*(
    domain: string, bearerToken: string, authScheme: string = "Bearer"
): Result[JmapClient, ValidationError] =
  ## Convenience overload — uses the default ``newHttpTransport()``
  ## backend.
  let t = ?newHttpTransport()
  discoverJmapClient(t, domain, bearerToken, authScheme)

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

proc setBearerToken*(client: JmapClient, token: string): Result[void, ValidationError] =
  ## Updates the bearer token. Subsequent requests use the new token —
  ## the Authorization header is constructed per-call inside
  ## ``fetchSession`` / ``send`` from the current token and authScheme.
  detectBearerToken(token).isOkOr:
    return err(toValidationError(error))
  client.bearerToken = token
  ok()

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
  ## Builds the per-call Authorization header value. Pure.
  client.authScheme & " " & client.bearerToken

proc fetchSession*(client: JmapClient): JmapResult[Session] =
  ## Fetches the JMAP Session resource from the server and caches it.
  ## Re-fetching replaces the cached session.
  let req = HttpRequest(
    url: client.sessionUrl,
    httpMethod: hmGet,
    body: "",
    authorization: authorizationHeader(client),
  )
  let httpResp = client.transport.send(req).valueOr:
    return err(clientError(error))
  let jsonNode = ?parseJmapJson(httpResp, rcSession)
  let session = ?Session.fromJson(jsonNode).mapErr(
    proc(sv: SerdeViolation): ClientError =
      validationToClientErrorCtx(toValidationError(sv, "Session"), "invalid session: ")
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
  let coreCaps = session.coreCapabilities()
  let jsonNode = request.toJson()
  let body = $jsonNode
  let maxSize = coreCaps.maxSizeRequest.toInt64
  if body.len > int(maxSize):
    let ve = toValidationError(
      RequestLimitViolation(
        kind: rlvMaxSizeRequest, actualSize: body.len, maxSize: maxSize
      )
    )
    return err(validationToClientError(ve))
  let req = HttpRequest(
    url: resolveAgainstSession(client.sessionUrl, session.apiUrl),
    httpMethod: hmPost,
    body: body,
    authorization: authorizationHeader(client),
  )
  let httpResp = client.transport.send(req).valueOr:
    return err(clientError(error))
  parseJmapResponse(httpResp, rcApi)

proc ensureSession(client: JmapClient): JmapResult[Session] =
  ## Internal: fetch the session lazily on first call, then return the
  ## cached value.
  if client.session.isNone:
    discard ?client.fetchSession()
  let sessionOpt = client.session
  let session = sessionOpt.valueOr:
    return err(
      clientError(
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
  let coreCaps = session.coreCapabilities()
  ?validateLimits(req, coreCaps).mapErr(validationToClientError)
  let wire = ?performSend(client, req.request, session)
  ok(initDispatchedResponse(wire, req.builderId))
