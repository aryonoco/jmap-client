# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP client handle — type definition, smart constructors, read-only
## accessors, and mutators. The imperative shell boundary where IO occurs
## (Layer 4). Not thread-safe — all calls must originate from a single
## thread (architecture §4.3).

{.push raises: [].}
{.experimental: "strictCaseObjects".}

import std/httpclient
import std/json
import std/strutils
import std/sysrand
import std/uri

import ./types
import ./serialisation
import ./internal/types/identifiers
import ./internal/protocol/builder
import ./internal/protocol/dispatch
import ./internal/protocol/call_meta

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

type JmapClient* = object
  ## JMAP client handle. Encapsulates connection state, authentication,
  ## cached session, and HTTP configuration. Not thread-safe — all calls
  ## must originate from a single thread.
  ##
  ## A ``JmapClient`` is not thread-safe; hold one per thread. The
  ## client's ``clientBrand`` and builder serial counter are accessed
  ## only inside ``newBuilder``, preserving the single-thread
  ## invariant.
  ##
  ## Construction: ``initJmapClient()`` or ``discoverJmapClient()``.
  ## Destruction: ``close()`` releases the underlying HTTP connection.
  ##
  ## All fields are module-private — access via public accessor procs.
  ## This makes invalid states unrepresentable: callers cannot construct
  ## a JmapClient with an empty URL or missing token.
  ##
  ## Copying a ``JmapClient`` shares the underlying HTTP connection —
  ## ``close()`` on any copy closes it for all copies.
  httpClient: HttpClient
  sessionUrl: string
  bearerToken: string
  authScheme: string
  session: Opt[Session]
  maxResponseBytes: int
  userAgent: string
  clientBrand: uint64
    ## Random 64-bit token drawn once at construction via ``std/sysrand``.
    ## Together with ``nextBuilderSerial`` it forms a ``BuilderId``
    ## composite that brands every ``RequestBuilder`` produced by
    ## ``newBuilder``.
  nextBuilderSerial: uint64
    ## Monotonic counter — incremented inside ``newBuilder``. Accessed
    ## only on the owning thread (see threading invariant above).
  lastRawResponseBody: string
    ## Raw bytes of the most recent HTTP response body (Session or
    ## ``/jmap/api``). Populated unconditionally by ``send`` and
    ## ``fetchSession``. Production code never reads it; the test-only
    ## ``tests/integration/live/mcapture.captureIfRequested`` consults a
    ## runtime env var to decide whether to persist the bytes to a
    ## fixture file.

{.pop.}

type JmapClientViolationKind = enum
  jcvEmptySessionUrl
  jcvSessionUrlBadScheme
  jcvSessionUrlControlChar
  jcvEmptyBearerToken
  jcvTimeoutTooLow
  jcvMaxRedirectsNegative
  jcvMaxResponseBytesNegative
  jcvHttpHeadersInitFailed
  jcvHttpClientInitFailed
  jcvEntropyUnavailable
  jcvEmptyDomain
  jcvDomainWhitespace
  jcvDomainSlash

type JmapClientViolation {.ruleOff: "objects".} = object
  case kind: JmapClientViolationKind
  of jcvEmptySessionUrl, jcvEmptyBearerToken, jcvEmptyDomain, jcvHttpHeadersInitFailed,
      jcvHttpClientInitFailed, jcvEntropyUnavailable:
    discard
  of jcvSessionUrlBadScheme, jcvSessionUrlControlChar:
    sessionUrl: string
  of jcvTimeoutTooLow:
    timeout: int
  of jcvMaxRedirectsNegative:
    maxRedirects: int
  of jcvMaxResponseBytesNegative:
    maxResponseBytes: int
  of jcvDomainWhitespace, jcvDomainSlash:
    domain: string

func toValidationError(v: JmapClientViolation): ValidationError =
  ## Sole domain-to-wire translator for ``JmapClientViolation``. Every wire
  ## message lives here; adding a ``jcvX`` variant forces a compile error
  ## at this site.
  case v.kind
  of jcvEmptySessionUrl:
    validationError("JmapClient", "sessionUrl must not be empty", "")
  of jcvSessionUrlBadScheme, jcvSessionUrlControlChar:
    # Combined of-arm mirrors the declaration; inner if discriminates.
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
  of jcvTimeoutTooLow:
    validationError("JmapClient", "timeout must be >= -1", $v.timeout)
  of jcvMaxRedirectsNegative:
    validationError("JmapClient", "maxRedirects must be >= 0", $v.maxRedirects)
  of jcvMaxResponseBytesNegative:
    validationError("JmapClient", "maxResponseBytes must be >= 0", $v.maxResponseBytes)
  of jcvHttpHeadersInitFailed:
    validationError("JmapClient", "failed to create HTTP headers", "")
  of jcvHttpClientInitFailed:
    validationError("JmapClient", "failed to create HTTP client", "")
  of jcvEntropyUnavailable:
    validationError("JmapClient", "OS entropy source unavailable", "")
  of jcvEmptyDomain:
    validationError("JmapClient", "domain must not be empty", "")
  of jcvDomainWhitespace, jcvDomainSlash:
    # Combined of-arm mirrors the declaration; inner if discriminates.
    if v.kind == jcvDomainWhitespace:
      validationError("JmapClient", "domain must not contain whitespace", v.domain)
    else:
      validationError("JmapClient", "domain must not contain '/'", v.domain)

func detectSessionUrl(sessionUrl: string): Result[void, JmapClientViolation] =
  ## Structural validation of the JMAP session URL: non-empty, https:// or
  ## http:// scheme, no embedded newlines that would break HTTP framing.
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

func detectTimeout(timeout: int): Result[void, JmapClientViolation] =
  ## HttpClient accepts -1 (no timeout) and non-negative values; anything
  ## below -1 is nonsense.
  if timeout < -1:
    return err(JmapClientViolation(kind: jcvTimeoutTooLow, timeout: timeout))
  ok()

func detectMaxRedirects(maxRedirects: int): Result[void, JmapClientViolation] =
  ## Redirect-follow count cannot be negative.
  if maxRedirects < 0:
    return err(
      JmapClientViolation(kind: jcvMaxRedirectsNegative, maxRedirects: maxRedirects)
    )
  ok()

func detectMaxResponseBytes(maxResponseBytes: int): Result[void, JmapClientViolation] =
  ## Response-size cap cannot be negative (zero disables the check).
  if maxResponseBytes < 0:
    return err(
      JmapClientViolation(
        kind: jcvMaxResponseBytesNegative, maxResponseBytes: maxResponseBytes
      )
    )
  ok()

func detectClientConfig(
    sessionUrl: string,
    bearerToken: string,
    timeout: int,
    maxRedirects: int,
    maxResponseBytes: int,
): Result[void, JmapClientViolation] =
  ## Sequential short-circuit composition of the five pure config
  ## detectors. Ordering matches pre-refactor first-error reporting.
  ?detectSessionUrl(sessionUrl)
  ?detectBearerToken(bearerToken)
  ?detectTimeout(timeout)
  ?detectMaxRedirects(maxRedirects)
  ?detectMaxResponseBytes(maxResponseBytes)
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
  ## unavailable — a real failure on a misconfigured host (no
  ## ``/dev/urandom`` under Linux, ``BCryptGenRandom`` denied under
  ## Windows). Brand uniqueness is the only requirement; unguessability
  ## is not — but the sysrand path is preferred for isolation across
  ## cooperating processes.
  var bytes: array[8, byte] = default(array[8, byte])
  if not urandom(bytes):
    return err(JmapClientViolation(kind: jcvEntropyUnavailable))
  ok(cast[uint64](bytes))

proc initJmapClient*(
    sessionUrl: string,
    bearerToken: string,
    authScheme: string = "Bearer",
    timeout: int = 30_000,
    maxRedirects: int = 5,
    maxResponseBytes: int = 50_000_000,
    userAgent: string = "jmap-client-nim/0.1.0",
): Result[JmapClient, ValidationError] =
  ## Creates a new JmapClient from a known session URL and bearer token.
  ##
  ## Does NOT fetch the session — call ``fetchSession()`` explicitly or
  ## let ``send()`` fetch it lazily on first call.
  ##
  ## Returns err on invalid parameters.
  detectClientConfig(sessionUrl, bearerToken, timeout, maxRedirects, maxResponseBytes).isOkOr:
    return err(toValidationError(error))
  let clientBrand = drawClientBrand().valueOr:
    return err(toValidationError(error))
  let headers =
    try:
      {.cast(raises: [CatchableError]).}:
        newHttpHeaders(
          {
            "Authorization": authScheme & " " & bearerToken,
            "Content-Type": "application/json",
            "Accept": "application/json",
          }
        )
    except CatchableError:
      return err(toValidationError(JmapClientViolation(kind: jcvHttpHeadersInitFailed)))
  let httpClient =
    try:
      {.cast(raises: [CatchableError]).}:
        newHttpClient(
          userAgent = userAgent,
          timeout = timeout,
          maxRedirects = maxRedirects,
          headers = headers,
        )
    except CatchableError:
      return err(toValidationError(JmapClientViolation(kind: jcvHttpClientInitFailed)))
  ok(
    JmapClient(
      httpClient: httpClient,
      sessionUrl: sessionUrl,
      bearerToken: bearerToken,
      authScheme: authScheme,
      session: Opt.none(Session),
      maxResponseBytes: maxResponseBytes,
      userAgent: userAgent,
      clientBrand: clientBrand,
      nextBuilderSerial: 0'u64,
      lastRawResponseBody: "",
    )
  )

proc discoverJmapClient*(
    domain: string,
    bearerToken: string,
    authScheme: string = "Bearer",
    timeout: int = 30_000,
    maxRedirects: int = 5,
    maxResponseBytes: int = 50_000_000,
    userAgent: string = "jmap-client-nim/0.1.0",
): Result[JmapClient, ValidationError] =
  ## Creates a JmapClient by constructing the ``.well-known/jmap`` URL from
  ## a domain name (RFC 8620 §2.2).
  ##
  ## Returns err if domain or bearerToken are invalid.
  detectDomain(domain).isOkOr:
    return err(toValidationError(error))
  initJmapClient(
    sessionUrl = "https://" & domain & "/.well-known/jmap",
    bearerToken = bearerToken,
    authScheme = authScheme,
    timeout = timeout,
    maxRedirects = maxRedirects,
    maxResponseBytes = maxResponseBytes,
    userAgent = userAgent,
  )

proc newBuilder*(client: var JmapClient): RequestBuilder =
  ## Single blessed entry point for building a request. Mints a
  ## ``BuilderId`` from the client's ``clientBrand`` and the next builder
  ## serial, increments the serial, and constructs an empty
  ## ``RequestBuilder`` branded with that id. Application developers use
  ## this to start every request; ``initRequestBuilder`` is hub-private
  ## and not reachable from ``import jmap_client``.
  let id = initBuilderId(client.clientBrand, client.nextBuilderSerial)
  client.nextBuilderSerial += 1
  initRequestBuilder(id)

func session*(client: JmapClient): Opt[Session] =
  ## Returns the cached Session, or ``none`` if not yet fetched.
  return client.session

func sessionUrl*(client: JmapClient): string =
  ## Returns the session resource URL.
  return client.sessionUrl

func bearerToken*(client: JmapClient): string =
  ## Returns the current bearer token.
  return client.bearerToken

func authScheme*(client: JmapClient): string =
  ## Returns the authentication scheme (e.g. "Bearer", "Basic").
  return client.authScheme

proc setBearerToken*(
    client: var JmapClient, token: string
): Result[void, ValidationError] =
  ## Updates the bearer token. Subsequent requests use the new token.
  ## Also updates the Authorization header on the underlying HttpClient.
  ##
  ## Returns err if token is empty.
  detectBearerToken(token).isOkOr:
    return err(toValidationError(error))
  client.bearerToken = token
  client.httpClient.headers["Authorization"] = client.authScheme & " " & token
  ok()

proc close*(client: var JmapClient) =
  ## Closes the underlying HTTP connection. Releases the socket
  ## immediately. Idempotent — safe to call multiple times.
  {.cast(raises: []).}:
    client.httpClient.close()

# ---------------------------------------------------------------------------
# Pure helpers (§2, §7)
# ---------------------------------------------------------------------------

proc enforceContentLengthLimit(
    maxResponseBytes: int, httpResp: httpclient.Response, context: RequestContext
): Result[void, ClientError] =
  ## Phase 1 body size enforcement: early rejection via Content-Length
  ## header before the body is read into memory. No-op when
  ## ``maxResponseBytes == 0`` or Content-Length is absent/unparseable.
  if maxResponseBytes > 0:
    let cl =
      try:
        {.cast(raises: [CatchableError]).}:
          httpResp.contentLength
      except CatchableError:
        -1
    if cl > maxResponseBytes:
      return err(sizeLimitExceeded(context, "Content-Length", cl, maxResponseBytes))
  return ok()

proc parseJsonBody(
    body: string, context: RequestContext
): Result[JsonNode, ClientError] =
  ## Parses a response body as JSON. Returns err if the body is not valid JSON.
  try:
    {.cast(raises: [CatchableError]).}:
      return ok(parseJson(body))
  except CatchableError as e:
    let te =
      transportError(tekNetwork, "invalid JSON in " & $context & " response: " & e.msg)
    return err(clientError(te))

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
  ## Sole domain-to-wire translator for ``RequestLimitViolation``. Every
  ## compound limit message lives here; adding a ``rlvX`` variant forces a
  ## compile error at this site.
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
  ## back-reference, matching pre-A2c behaviour.
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
  ## silently skipped, matching pre-A2c behaviour.
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
  ## Total method-call count (top-level only — batching across HTTP
  ## requests is a separate concern) against maxCallsInRequest.
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
  ## Pre-flight composition for typed-builder callers: max-calls then
  ## per-invocation /get and /set limits from typed ``CallLimitMeta``.
  ## The parallel invariant ``request.methodCalls.len == callLimits.len``
  ## is maintained by ``addInvocation*`` — the only function that
  ## extends either field — so the loop indexes both safely.
  ?detectMaxCalls(request, int64(caps.maxCallsInRequest))
  let maxGet = int64(caps.maxObjectsInGet)
  let maxSet = int64(caps.maxObjectsInSet)
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

func validateLimits*(
    req: BuiltRequest, caps: CoreCapabilities
): Result[void, ValidationError] =
  ## Full pre-flight validation for a frozen request: enforces
  ## ``maxCallsInRequest`` and per-call ``maxObjectsInGet`` /
  ## ``maxObjectsInSet`` from typed ``CallLimitMeta``. Pure — no IO,
  ## no mutation.
  detectRequestLimitsTyped(req.request, req.callLimits, caps).isOkOr:
    return err(toValidationError(error))
  ok()

proc readContentType(httpResp: httpclient.Response): string =
  ## Reads the Content-Type header, returning empty string on failure.
  try:
    {.cast(raises: [CatchableError]).}:
      return httpResp.contentType.toLowerAscii
  except CatchableError:
    return ""

proc tryParseProblemDetails(body: string): Opt[ClientError] =
  ## Attempts to parse RFC 7807 problem details from a response body.
  ## Returns Opt.some(ClientError) on success, none on failure.
  try:
    {.cast(raises: [CatchableError]).}:
      let jsonNode = parseJson(body)
      if jsonNode.kind == JObject and jsonNode.hasKey("type"):
        let reqErrResult = RequestError.fromJson(jsonNode)
        if reqErrResult.isOk:
          return Opt.some(clientError(reqErrResult.get()))
  except CatchableError:
    discard
  return Opt.none(ClientError)

proc classifyHttpResponse(
    maxResponseBytes: int,
    httpResp: httpclient.Response,
    context: RequestContext,
    capturedBody: var string,
): JmapResult[JsonNode] =
  ## Classifies an HTTP response and parses the JSON body. Returns the
  ## parsed ``JsonNode`` on 2xx with correct Content-Type. Returns err
  ## otherwise. Not pure — ``httpResp.body`` lazily reads from
  ## ``bodyStream`` on first access.
  ##
  ## The raw body bytes are written to ``capturedBody`` immediately after
  ## reading (before any 4xx/5xx classification) so a calling test can
  ## persist them as a fixture without losing byte fidelity.
  let code =
    try:
      {.cast(raises: [CatchableError]).}:
        httpResp.code
    except CatchableError:
      let te = transportError(
        tekNetwork, "malformed HTTP status from " & $context & ": " & httpResp.status
      )
      return err(clientError(te))

  # Phase 1 body size enforcement (R9) — reject before reading body
  ?enforceContentLengthLimit(maxResponseBytes, httpResp, context)

  let body =
    try:
      {.cast(raises: [CatchableError]).}:
        httpResp.body # lazy: reads bodyStream on first access
    except CatchableError:
      return err(clientError(transportError(tekNetwork, "failed to read body")))
  capturedBody = body

  # Phase 2 body size enforcement (R9) — reject after reading body
  ?enforceBodySizeLimit(maxResponseBytes, body, context)

  if code.is4xx or code.is5xx:
    # Attempt to parse as RFC 7807 problem details
    let ct = readContentType(httpResp)
    if ct.startsWith("application/problem+json") or ct.startsWith("application/json"):
      for ce in tryParseProblemDetails(body):
        return err(ce)
    # Generic HTTP status error (no problem details, or parsing failed)
    let te = httpStatusError(int(code), "HTTP " & $int(code) & " from " & $context)
    return err(clientError(te))

  # Guard: non-2xx that is not 4xx/5xx (e.g. 1xx, 3xx).
  if not code.is2xx:
    let te =
      httpStatusError(int(code), "unexpected HTTP " & $int(code) & " from " & $context)
    return err(clientError(te))

  # Check Content-Type on 2xx success
  let ct = readContentType(httpResp)
  if not ct.startsWith("application/json"):
    let te =
      transportError(tekNetwork, "unexpected Content-Type from " & $context & ": " & ct)
    return err(clientError(te))

  return parseJsonBody(body, context)

proc setSessionForTest*(client: var JmapClient, session: Session) =
  ## Injects a cached session for testing purposes. Enables pure tests
  ## of ``isSessionStale`` without requiring network IO.
  client.session = Opt.some(session)

func lastRawResponseBody*(client: JmapClient): string =
  ## Returns the raw bytes of the most recent HTTP response body. Empty
  ## before the first ``send`` or ``fetchSession`` call. Test-only reach-
  ## in for ``mcapture.captureIfRequested``; production callers should
  ## consume the typed ``Response`` returned by ``send``.
  client.lastRawResponseBody

# ---------------------------------------------------------------------------
# IO procs (§3, §4, §6)
# ---------------------------------------------------------------------------

func resolveAgainstSession(sessionUrl, urlOrPath: string): string =
  ## Resolves ``urlOrPath`` against the session URL per RFC 3986 §5.
  ##
  ## RFC 8620 §2 defines the session document URLs (apiUrl,
  ## downloadUrl, uploadUrl, eventSourceUrl) as URLs without
  ## explicitly mandating absolute form. Some conformant servers
  ## (Cyrus 3.12.2, ``imap/jmap_api.c``) emit relative references
  ## (``"/jmap/"``) so the client resolves any reference against the
  ## known-absolute session URL — Postel-tolerant on receive.
  ##
  ## When ``urlOrPath`` already carries a scheme, it is returned
  ## unchanged. When it is relative, ``std/uri.combine`` performs the
  ## RFC 3986 §5 resolution against ``sessionUrl``.
  if urlOrPath.startsWith("http://") or urlOrPath.startsWith("https://"):
    return urlOrPath
  $combine(parseUri(sessionUrl), parseUri(urlOrPath))

proc fetchSession*(client: var JmapClient): JmapResult[Session] =
  ## Fetches the JMAP Session resource from the server and caches it.
  ## Re-fetching replaces the cached session.
  ##
  ## Returns err for network, TLS, timeout, HTTP errors, RFC 7807
  ## problem details, or structurally invalid session JSON.
  let httpResp =
    try:
      {.warning[Uninit]: off.}
      {.cast(raises: [CatchableError]).}:
        client.httpClient.request(client.sessionUrl, httpMethod = HttpGet)
    except CatchableError as e:
      return err(classifyException(e))
  let jsonNode = ?classifyHttpResponse(
    client.maxResponseBytes, httpResp, rcSession, client.lastRawResponseBody
  )
  let session = Session.fromJson(jsonNode).mapErr(
      proc(sv: SerdeViolation): ClientError =
        validationToClientErrorCtx(
          toValidationError(sv, "Session"), "invalid session: "
        )
    )
  let s = ?session
  client.session = Opt.some(s)
  return ok(s)

proc performSend(
    client: var JmapClient, request: Request, session: Session
): JmapResult[envelope.Response] =
  ## Internal: serialise + post-serialisation maxSizeRequest check +
  ## HTTP POST + response classification + JSON parse + Response
  ## decoding. Pre-flight validation (``validateLimits``) MUST happen
  ## in the calling overload before invoking this; this proc does NOT
  ## re-validate.
  let coreCaps = session.coreCapabilities()

  # Step 3: Serialise
  let jsonNode = request.toJson()
  let body = $jsonNode

  # Step 4: Check serialised size against maxSizeRequest
  let maxSize = int64(coreCaps.maxSizeRequest)
  if body.len > int(maxSize):
    let ve = toValidationError(
      RequestLimitViolation(
        kind: rlvMaxSizeRequest, actualSize: body.len, maxSize: maxSize
      )
    )
    return err(validationToClientError(ve))

  # Step 5: IO boundary — HTTP POST
  let httpResp =
    try:
      {.warning[Uninit]: off.}
      {.cast(raises: [CatchableError]).}:
        client.httpClient.request(
          resolveAgainstSession(client.sessionUrl, session.apiUrl),
          httpMethod = HttpPost,
          body = body,
        )
    except CatchableError as e:
      return err(classifyException(e))

  # Step 6: Classify HTTP response and parse JSON
  let respJson = ?classifyHttpResponse(
    client.maxResponseBytes, httpResp, rcApi, client.lastRawResponseBody
  )

  # Step 8: Problem details on HTTP 200
  if respJson.kind == JObject and respJson.hasKey("type") and
      not respJson.hasKey("methodResponses"):
    for reqErr in RequestError.fromJson(respJson).optValue:
      return err(clientError(reqErr))

  # Step 9: Deserialise Response
  return envelope.Response.fromJson(respJson).mapErr(
      proc(sv: SerdeViolation): ClientError =
        validationToClientErrorCtx(
          toValidationError(sv, "Response"), "invalid response: "
        )
    )

proc ensureSession(client: var JmapClient): JmapResult[Session] =
  ## Internal: fetch the session lazily on first call, then return the
  ## cached value. The let-bound ``Opt`` ensures the non-var ``get``
  ## template is selected at the use site (strict-safe per
  ## ``nim-type-safety.md`` Rule R-var). The ``valueOr:`` return path
  ## produces a defined error path instead of the Defect that ``.get()``
  ## would raise — critical for the FFI boundary (``--panics:on`` would
  ## ``rawQuit(1)`` the host process on a Defect).
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
  ## Returns ``true`` if they differ (session should be re-fetched).
  ## Returns ``false`` if no session is cached (cannot determine staleness).
  ## Pure — no IO, no mutation.
  let s = client.session.valueOr:
    return false
  return s.state != dr.sessionState

proc refreshSessionIfStale*(
    client: var JmapClient, dr: DispatchedResponse
): JmapResult[bool] =
  ## If the dispatched response indicates a stale session, re-fetches it.
  ## Returns ok(true) if refreshed, ok(false) otherwise.
  ## Returns err on fetch failure (same as ``fetchSession``).
  if client.isSessionStale(dr):
    let s = ?client.fetchSession()
    discard s
    return ok(true)
  return ok(false)

proc send*(client: var JmapClient, req: BuiltRequest): JmapResult[DispatchedResponse] =
  ## Validates limits, fetches the session lazily, POSTs the serialised
  ## request, parses the wire ``Response``, and returns a
  ## ``DispatchedResponse`` branded with the builder's ``id``. Single
  ## blessed send path — raw-Request and unfrozen-builder sends are
  ## gone; ``RequestBuilder.freeze()`` is the obligatory transition.
  ##
  ## Lazily fetches the session on first call if not yet cached.
  ## Does NOT automatically refresh a stale session (D4.10).
  ##
  ## Returns err for transport/request failures, limit violations,
  ## or invalid response JSON.
  let session = ?ensureSession(client)
  let coreCaps = session.coreCapabilities()
  ?validateLimits(req, coreCaps).mapErr(validationToClientError)
  let wire = ?performSend(client, req.request, session)
  ok(initDispatchedResponse(wire, req.builderId))

proc sendRawHttpForTesting*(
    client: var JmapClient, body: string
): JmapResult[envelope.Response] {.used.} =
  ## Test-only escape hatch — POSTs ``body`` verbatim to the cached
  ## session's ``apiUrl``. Bypasses ``Request.toJson`` and the pre-flight
  ## ``validateLimits`` check so adversarial wire shapes (oversized
  ## bodies, hand-crafted invocations, malformed JSON) reach the server
  ## without being rejected client-side. The response still flows through
  ## ``classifyHttpResponse`` so HTTP-error classification, RFC 7807
  ## problem-details detection, and ``lastRawResponseBody`` capture are
  ## identical to ``send``. The ``ForTesting`` suffix and ``{.used.}``
  ## pragma make the test-only intent visible at every call site and
  ## silence nimalyzer's unused-export rule on the symbol when no test
  ## file references it yet.
  if client.session.isNone:
    discard ?client.fetchSession()
  let sessionOpt = client.session
  let session = sessionOpt.valueOr:
    return err(
      clientError(
        transportError(tekNetwork, "session unavailable after fetchSession succeeded")
      )
    )
  let httpResp =
    try:
      {.warning[Uninit]: off.}
      {.cast(raises: [CatchableError]).}:
        client.httpClient.request(
          resolveAgainstSession(client.sessionUrl, session.apiUrl),
          httpMethod = HttpPost,
          body = body,
        )
    except CatchableError as e:
      return err(classifyException(e))
  let respJson = ?classifyHttpResponse(
    client.maxResponseBytes, httpResp, rcApi, client.lastRawResponseBody
  )
  if respJson.kind == JObject and respJson.hasKey("type") and
      not respJson.hasKey("methodResponses"):
    for reqErr in RequestError.fromJson(respJson).optValue:
      return err(clientError(reqErr))
  return envelope.Response.fromJson(respJson).mapErr(
      proc(sv: SerdeViolation): ClientError =
        validationToClientErrorCtx(
          toValidationError(sv, "Response"), "invalid response: "
        )
    )
