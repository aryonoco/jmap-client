# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## JMAP client handle — type definition, smart constructors, read-only
## accessors, and mutators. The imperative shell boundary where IO occurs
## (Layer 4). Not thread-safe — all calls must originate from a single
## thread (architecture §4.3).

{.push raises: [].}

import std/httpclient
import std/json
import std/strutils

when defined(ssl):
  from std/net import TimeoutError, SslError
else:
  from std/net import TimeoutError

import ./types
import ./serialisation

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
  session: Opt[Session]
  maxResponseBytes: int
  userAgent: string

{.pop.}

proc initJmapClient*(
    sessionUrl: string,
    bearerToken: string,
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
  if sessionUrl.len == 0:
    return err(validationError("JmapClient", "sessionUrl must not be empty", ""))
  if not sessionUrl.startsWith("https://") and not sessionUrl.startsWith("http://"):
    return err(
      validationError(
        "JmapClient", "sessionUrl must start with https:// or http://", sessionUrl
      )
    )
  if sessionUrl.contains({'\c', '\L'}):
    return err(
      validationError(
        "JmapClient", "sessionUrl must not contain newline characters", sessionUrl
      )
    )
  if bearerToken.len == 0:
    return err(validationError("JmapClient", "bearerToken must not be empty", ""))
  if timeout < -1:
    return err(validationError("JmapClient", "timeout must be >= -1", $timeout))
  if maxRedirects < 0:
    return
      err(validationError("JmapClient", "maxRedirects must be >= 0", $maxRedirects))
  if maxResponseBytes < 0:
    return err(
      validationError("JmapClient", "maxResponseBytes must be >= 0", $maxResponseBytes)
    )
  let headers =
    try:
      {.cast(raises: [CatchableError]).}:
        newHttpHeaders(
          {
            "Authorization": "Bearer " & bearerToken,
            "Content-Type": "application/json",
            "Accept": "application/json",
          }
        )
    except CatchableError:
      return err(validationError("JmapClient", "failed to create HTTP headers", ""))
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
      return err(validationError("JmapClient", "failed to create HTTP client", ""))
  ok(
    JmapClient(
      httpClient: httpClient,
      sessionUrl: sessionUrl,
      bearerToken: bearerToken,
      session: Opt.none(Session),
      maxResponseBytes: maxResponseBytes,
      userAgent: userAgent,
    )
  )

proc discoverJmapClient*(
    domain: string,
    bearerToken: string,
    timeout: int = 30_000,
    maxRedirects: int = 5,
    maxResponseBytes: int = 50_000_000,
    userAgent: string = "jmap-client-nim/0.1.0",
): Result[JmapClient, ValidationError] =
  ## Creates a JmapClient by constructing the ``.well-known/jmap`` URL from
  ## a domain name (RFC 8620 §2.2).
  ##
  ## Returns err if domain or bearerToken are invalid.
  if domain.len == 0:
    return err(validationError("JmapClient", "domain must not be empty", ""))
  for c in domain:
    if c in Whitespace:
      return
        err(validationError("JmapClient", "domain must not contain whitespace", domain))
  if '/' in domain:
    return err(validationError("JmapClient", "domain must not contain '/'", domain))
  initJmapClient(
    sessionUrl = "https://" & domain & "/.well-known/jmap",
    bearerToken = bearerToken,
    timeout = timeout,
    maxRedirects = maxRedirects,
    maxResponseBytes = maxResponseBytes,
    userAgent = userAgent,
  )

func session*(client: JmapClient): Opt[Session] =
  ## Returns the cached Session, or ``none`` if not yet fetched.
  client.session

func sessionUrl*(client: JmapClient): string =
  ## Returns the session resource URL.
  client.sessionUrl

func bearerToken*(client: JmapClient): string =
  ## Returns the current bearer token.
  client.bearerToken

proc setBearerToken*(
    client: var JmapClient, token: string
): Result[void, ValidationError] =
  ## Updates the bearer token. Subsequent requests use the new token.
  ## Also updates the Authorization header on the underlying HttpClient.
  ##
  ## Returns err if token is empty.
  if token.len == 0:
    return err(validationError("JmapClient", "bearerToken must not be empty", ""))
  client.bearerToken = token
  client.httpClient.headers["Authorization"] = "Bearer " & token
  ok()

proc close*(client: var JmapClient) =
  ## Closes the underlying HTTP connection. Releases the socket
  ## immediately. Idempotent — safe to call multiple times.
  {.cast(raises: []).}:
    client.httpClient.close()

# ---------------------------------------------------------------------------
# Pure helpers (§2, §7)
# ---------------------------------------------------------------------------

func expandUriTemplate*(
    tmpl: UriTemplate, variables: openArray[(string, string)]
): string =
  ## Expands an RFC 6570 Level 1 URI template by replacing ``{name}`` with
  ## the corresponding value. Variables not found in ``variables`` are left
  ## unexpanded. Caller is responsible for percent-encoding values that
  ## require it (``std/uri.encodeUrl(value, usePlus=false)``). Pure.
  result = string(tmpl)
  for (name, value) in variables:
    result = result.replace("{" & name & "}", value)

func isTlsRelatedMsg(msg: string): bool =
  ## Heuristic: checks whether an OSError message indicates a TLS failure.
  ## OpenSSL surfaces TLS errors as OSError with keywords in the message
  ## (D4.5). False positives are harmless — the error is still a transport
  ## failure and ``msg`` carries the actual underlying error.
  let lower = msg.toLowerAscii
  "ssl" in lower or "tls" in lower or "certificate" in lower

func classifyException*(e: ref CatchableError): ClientError =
  ## Maps ``std/httpclient`` exceptions to ``ClientError(cekTransport)``.
  ## Pure: no IO, no side effects. Exhaustive over known exception types.
  var te: TransportError
  if e of ref TimeoutError:
    te = transportError(tekTimeout, e.msg)
  elif (when defined(ssl): e of ref SslError else: false):
    te = transportError(tekTls, e.msg)
  elif e of ref OSError:
    te =
      if isTlsRelatedMsg(e.msg):
        transportError(tekTls, e.msg)
      else:
        transportError(tekNetwork, e.msg)
  elif e of ref IOError:
    te = transportError(tekNetwork, e.msg)
  elif e of ref ValueError:
    te = transportError(tekNetwork, "protocol error: " & e.msg)
  else:
    te = transportError(tekNetwork, "unexpected error: " & e.msg)
  clientError(te)

func enforceBodySizeLimit*(
    maxResponseBytes: int, body: string, context: string
): Result[void, ClientError] =
  ## Phase 2 body size enforcement: post-read rejection via actual body
  ## length. No-op when ``maxResponseBytes == 0`` (no limit). Pure.
  if maxResponseBytes > 0 and body.len > maxResponseBytes:
    let te = transportError(
      tekNetwork,
      context & " response body exceeds limit: " & $body.len & " bytes > " &
        $maxResponseBytes & " byte limit",
    )
    return err(clientError(te))
  ok()

proc enforceContentLengthLimit(
    maxResponseBytes: int, httpResp: httpclient.Response, context: string
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
      let te = transportError(
        tekNetwork,
        context & " Content-Length exceeds limit: " & $cl & " bytes > " &
          $maxResponseBytes & " byte limit",
      )
      return err(clientError(te))
  ok()

proc parseJsonBody(body: string, context: string): Result[JsonNode, ClientError] =
  ## Parses a response body as JSON. Returns err if the body is not valid JSON.
  try:
    {.cast(raises: [CatchableError]).}:
      ok(parseJson(body))
  except CatchableError as e:
    let te =
      transportError(tekNetwork, "invalid JSON in " & context & " response: " & e.msg)
    err(clientError(te))

func checkGetLimit(inv: Invocation, maxGet: int64): Result[void, ValidationError] =
  ## Checks a /get invocation's direct ids count against maxObjectsInGet.
  ## Reference ids (JObject) and absent/null ids are silently skipped.
  if inv.arguments.isNil:
    return ok()
  let idsNode = inv.arguments{"ids"}
  if not idsNode.isNil and idsNode.kind == JArray:
    if int64(idsNode.len) > maxGet:
      return err(
        validationError(
          "Request",
          inv.name & ": ids count " & $idsNode.len & " exceeds maxObjectsInGet " &
            $maxGet,
          "",
        )
      )
  ok()

func checkSetLimit(inv: Invocation, maxSet: int64): Result[void, ValidationError] =
  ## Checks a /set invocation's combined create + update + destroy count
  ## against maxObjectsInSet. Reference destroy (JObject) is silently skipped.
  if inv.arguments.isNil:
    return ok()
  var count: int64 = 0
  let createNode = inv.arguments{"create"}
  if not createNode.isNil and createNode.kind == JObject:
    count += int64(createNode.len)
  let updateNode = inv.arguments{"update"}
  if not updateNode.isNil and updateNode.kind == JObject:
    count += int64(updateNode.len)
  let destroyNode = inv.arguments{"destroy"}
  if not destroyNode.isNil and destroyNode.kind == JArray:
    count += int64(destroyNode.len)
  if count > maxSet:
    return err(
      validationError(
        "Request",
        inv.name & ": object count " & $count & " exceeds maxObjectsInSet " & $maxSet,
        "",
      )
    )
  ok()

func validateLimits*(
    request: Request, caps: CoreCapabilities
): Result[void, ValidationError] =
  ## Pre-flight validation of a built Request against server-advertised
  ## CoreCapabilities limits. Pure — no IO, no mutation.
  ## Returns err describing the first violation.
  let maxCalls = int64(caps.maxCallsInRequest)
  if int64(request.methodCalls.len) > maxCalls:
    return err(
      validationError(
        "Request",
        "method call count " & $request.methodCalls.len & " exceeds maxCallsInRequest " &
          $maxCalls,
        "",
      )
    )

  let maxGet = int64(caps.maxObjectsInGet)
  let maxSet = int64(caps.maxObjectsInSet)

  for inv in request.methodCalls:
    if inv.name.endsWith("/get"):
      ?checkGetLimit(inv, maxGet)
    elif inv.name.endsWith("/set"):
      ?checkSetLimit(inv, maxSet)
  ok()

proc readContentType(httpResp: httpclient.Response): string =
  ## Reads the Content-Type header, returning empty string on failure.
  try:
    {.cast(raises: [CatchableError]).}:
      httpResp.contentType.toLowerAscii
  except CatchableError:
    ""

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
  Opt.none(ClientError)

proc classifyHttpResponse(
    maxResponseBytes: int, httpResp: httpclient.Response, context: string
): JmapResult[string] =
  ## Classifies an HTTP response. Returns the body string on 2xx with
  ## correct Content-Type. Returns err otherwise. Not pure —
  ## ``httpResp.body`` lazily reads from ``bodyStream`` on first access.
  let code =
    try:
      {.cast(raises: [CatchableError]).}:
        httpResp.code
    except CatchableError:
      let te = transportError(
        tekNetwork, "malformed HTTP status from " & context & ": " & httpResp.status
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

  # Phase 2 body size enforcement (R9) — reject after reading body
  ?enforceBodySizeLimit(maxResponseBytes, body, context)

  if code.is4xx or code.is5xx:
    # Attempt to parse as RFC 7807 problem details
    let ct = readContentType(httpResp)
    if ct.startsWith("application/problem+json") or ct.startsWith("application/json"):
      for ce in tryParseProblemDetails(body):
        return err(ce)
    # Generic HTTP status error (no problem details, or parsing failed)
    let te = httpStatusError(int(code), "HTTP " & $int(code) & " from " & context)
    return err(clientError(te))

  # Guard: non-2xx that is not 4xx/5xx (e.g. 1xx, 3xx).
  if not code.is2xx:
    let te =
      httpStatusError(int(code), "unexpected HTTP " & $int(code) & " from " & context)
    return err(clientError(te))

  # Check Content-Type on 2xx success
  let ct = readContentType(httpResp)
  if not ct.startsWith("application/json"):
    let te =
      transportError(tekNetwork, "unexpected Content-Type from " & context & ": " & ct)
    return err(clientError(te))

  ok(body)

proc setSessionForTest*(client: var JmapClient, session: Session) =
  ## Injects a cached session for testing purposes. Enables pure tests
  ## of ``isSessionStale`` without requiring network IO.
  client.session = Opt.some(session)

# ---------------------------------------------------------------------------
# IO procs (§3, §4, §6)
# ---------------------------------------------------------------------------

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
  let body = ?classifyHttpResponse(client.maxResponseBytes, httpResp, "session")
  let jsonNode = ?parseJsonBody(body, "session")
  let session = Session.fromJson(jsonNode).mapErr(
      proc(ve: ValidationError): ClientError =
        clientError(transportError(tekNetwork, "invalid session: " & ve.message))
    )
  let s = ?session
  client.session = Opt.some(s)
  ok(s)

proc send*(client: var JmapClient, request: Request): JmapResult[envelope.Response] =
  ## Serialises a JMAP Request, POSTs to the server's apiUrl, and
  ## deserialises the Response.
  ##
  ## Lazily fetches the session on first call if not yet cached.
  ## Does NOT automatically refresh a stale session (D4.10).
  ##
  ## Returns err for transport/request failures, limit violations,
  ## or invalid response JSON.

  # Step 1: Ensure session available (may trigger IO)
  if client.session.isNone:
    discard ?client.fetchSession()
  let session = client.session.get()
  let coreCaps = session.coreCapabilities()

  # Step 2: Pre-flight validation
  ?validateLimits(request, coreCaps).mapErr(
    proc(ve: ValidationError): ClientError =
      clientError(transportError(tekNetwork, ve.message))
  )

  # Step 3: Serialise
  let jsonNode = request.toJson()
  let body = $jsonNode

  # Step 4: Check serialised size against maxSizeRequest
  let maxSize = int64(coreCaps.maxSizeRequest)
  if body.len > int(maxSize):
    let ve = validationError(
      "Request",
      "serialised request size " & $body.len & " octets exceeds server maxSizeRequest " &
        $maxSize,
      "",
    )
    return err(clientError(transportError(tekNetwork, ve.message)))

  # Step 5: IO boundary — HTTP POST
  let httpResp =
    try:
      {.warning[Uninit]: off.}
      {.cast(raises: [CatchableError]).}:
        client.httpClient.request(session.apiUrl, httpMethod = HttpPost, body = body)
    except CatchableError as e:
      return err(classifyException(e))

  # Step 6: Classify HTTP response
  let respBody = ?classifyHttpResponse(client.maxResponseBytes, httpResp, "api")

  # Step 7: Parse JSON
  let respJson = ?parseJsonBody(respBody, "api")

  # Step 8: Problem details on HTTP 200
  if respJson.kind == JObject and respJson.hasKey("type") and
      not respJson.hasKey("methodResponses"):
    for reqErr in RequestError.fromJson(respJson).optValue:
      return err(clientError(reqErr))

  # Step 9: Deserialise Response
  envelope.Response.fromJson(respJson).mapErr(
    proc(ve: ValidationError): ClientError =
      clientError(transportError(tekNetwork, "invalid response: " & ve.message))
  )

func isSessionStale*(client: JmapClient, response: envelope.Response): bool =
  ## Compares ``response.sessionState`` with the cached ``Session.state``.
  ## Returns ``true`` if they differ (session should be re-fetched).
  ## Returns ``false`` if no session is cached (cannot determine staleness).
  ## Pure — no IO, no mutation.
  let s = client.session.valueOr:
    return false
  s.state != response.sessionState

proc refreshSessionIfStale*(
    client: var JmapClient, response: envelope.Response
): JmapResult[bool] =
  ## If the response indicates a stale session, re-fetches it.
  ## Returns ok(true) if refreshed, ok(false) otherwise.
  ## Returns err on fetch failure (same as ``fetchSession``).
  if client.isSessionStale(response):
    let s = ?client.fetchSession()
    discard s
    return ok(true)
  ok(false)
