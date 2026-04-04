# Layer 4: Transport + Session Discovery — Detailed Design (RFC 8620)

## Preface

This document specifies every type definition, procedure signature, error
mapping, algorithm, and module layout for Layer 4 of the jmap-client
library. It builds upon the decisions made in `00-architecture.md`, the
architecture revision in `04-architecture-revision.md`, the types defined
in `01-layer-1-design.md`, the serialisation infrastructure established in
`02-layer-2-design.md`, and the protocol logic from
`03-layer-3-design.md`, so that implementation is mechanical.

**Scope.** Layer 4 covers: the `JmapClient` type and its construction,
Session discovery (direct URL and `.well-known/jmap`), Session fetching
and caching, API request/response round-trips (serialise `Request`, POST
to `apiUrl`, deserialise `Response`), authentication (Bearer token),
exception classification (mapping `std/httpclient` exceptions to
`TransportError` / `RequestError` / `ClientError`), pre-flight validation
(deferred decision R13 from Layer 3), session staleness detection
(`Response.sessionState` vs `Session.state`), Content-Type and HTTP
header management, response body size enforcement (deferred decision R9
from Layer 3), URI template expansion (RFC 6570 Level 1), and the
`-d:ssl` compile flag requirement. The C ABI (Layer 5) is out of scope.
Push/EventSource (RFC 8620 §7) and binary data (§6) are out of scope for
the initial release, as prescribed by architecture decisions §4.5 and
§4.6.

**Relationship to prior documents.** `00-architecture.md` records broad
decisions across all 5 layers. `04-architecture-revision.md` specifies
the idiomatic Nim migration (exceptions replace `Result[T, E]`, `proc`
replaces `func`, `Option[T]` replaces `Opt[T]`). This document is the
detailed specification for Layer 4 only. Decisions here resolve — and are
consistent with — the architecture document's choices 4.1A
(`std/httpclient`, synchronous), 4.2 (direct URL + `.well-known/jmap`,
no DNS SRV), 4.3 (single `send` proc, single-threaded), 4.4 (Bearer
token auth), and the Layer 3 deferred decisions R9 (response body size
cap) and R13 (pre-flight validation).

Layer 4 operates on Layer 1 types: `Session`, `Account`,
`CoreCapabilities`, `UriTemplate`, `JmapState`, `AccountId`, `Id`,
`CreationId`, all identifier types, and all error types
(`TransportError`, `RequestError`, `ClientError`, `ValidationError`).
It imports Layer 2's serialisation: `Session.fromJson`,
`Request.toJson`, `Response.fromJson`, `RequestError.fromJson`, and all
primitive/identifier `toJson`/`fromJson` pairs. Layer 3's method types
are not imported — `send` operates at the envelope level.

**Design principles.** Layer 4 is the **imperative shell** — the sole
boundary where IO occurs. The six governing principles apply as follows:

- **Functional Core, Imperative Shell** — Layer 4 IS the imperative
  shell. Within Layer 4, the design maximises the pure surface: pure
  procs (`validateLimits`, `expandUriTemplate`, `isSessionStale`,
  `classifyException`, `enforceBodySizeLimit`, `parseJsonBody`) are
  separated from the IO procs (`fetchSession`, `send`,
  `refreshSessionIfStale`, `close`). `classifyHttpResponse` composes
  pure classification rules around a single impure step (`httpResp.body`
  lazy stream read) — it is impure but thin. The IO procs are thin
  wrappers that compose pure transforms around a single impure step
  (the HTTP request). Layers 1–3 below are pure by convention — no IO,
  no global state mutation.
- **Immutability by default** — `let` bindings throughout. `var` is used
  only for: (a) the `JmapClient` parameter in IO procs (`fetchSession`,
  `send`, `refreshSessionIfStale`, `close`) and pure mutators
  (`setBearerToken`); (b) local accumulators inside pure procs (e.g.,
  `var count = 0` in `validateLimits`). No module-level mutable state in
  Layer 4 — all mutable state lives inside `JmapClient` objects owned by
  the caller.
- **DRY** — HTTP response classification logic (status codes, Content-Type
  checks, problem details detection, body size enforcement) is written
  once in shared helpers (`classifyHttpResponse`, `classifyException`)
  and called from both `fetchSession` and `send`. URI template expansion
  is a single proc serving download, upload, and event source URLs.
- **Total functions** — every proc handles all inputs. Pure procs either
  return a value or raise a structured exception — no partial functions,
  no uncovered code paths. Exception types (`TransportError`,
  `RequestError`, `ClientError`, `ValidationError`) cover the complete
  failure domain with exhaustive variant enums. The architecture revision
  moved from compile-time totality enforcement (`{.push raises: [].}`) to
  convention-based totality — every `case` statement on an enum is
  exhaustive, every input domain is covered.
- **Parse, don't validate** — Session JSON is deserialised via Layer 2's
  `Session.fromJson`, which calls Layer 1's `parseSession` for
  structural validation. The result is a well-typed `Session` or a
  `ValidationError` is raised. HTTP responses are similarly parsed into
  well-typed `Response` values or structured exceptions. There is no
  "valid but unchecked" intermediate state.
- **Make illegal states unrepresentable** — `JmapClient` fields are
  module-private (no `*` export marker), preventing callers from
  constructing a client with an empty URL or expired token. The smart
  constructor `initJmapClient` enforces all construction invariants.
  Accessor procs provide read-only views. `setBearerToken` re-validates
  on mutation. The `sessionUrl` and `bearerToken` cannot be set to
  invalid values after construction.

**Post-revision context.** The architecture revision
(`04-architecture-revision.md`) eliminated `Result[T, E]`, `Opt[T]`,
`{.push raises: [].}` (on Layers 1–4), `func`, `strictFuncs`,
`strictNotNil`, `strictCaseObjects`, `{.requiresInit.}`, and
`nim-results`. Layer 4 uses idiomatic Nim: `proc`, `Option[T]` from
`std/options`, exceptions. The error types (`TransportError`,
`RequestError`, `ClientError`) are exception objects inheriting from
`CatchableError`. `MethodError` and `SetError` remain plain objects —
data within successful responses, not exceptions.

**Single-threaded constraint.** Handles are not thread-safe; matches
`std/httpclient`'s design (architecture §4.3). All calls must originate
from a single thread. Multi-threaded consumers synchronise externally.

**No automatic retries.** Layer 4 does not retry failed requests. Retry
policy is a consumer concern. The error classification provides enough
information (`TransportErrorKind`, HTTP status codes) for consumers to
implement their own retry logic.

**Compiler flags.** These constrain every type and procedure definition
(from `config.nims`):

```
--mm:arc
--experimental:strictDefs
--threads:on
--panics:on
--floatChecks:on
--overflowChecks:on
--styleCheck:error  (nimble only; omitted from config.nims for test naming)
```

---

## Standard Library Utilisation

Layer 4 introduces IO-related stdlib modules not used in Layers 1–3.
Every adoption and rejection has a concrete reason tied to the project's
compiler constraints and architectural decisions.

### Modules used in Layer 4

| Module | What is used | Rationale |
|--------|-------------|-----------|
| `std/httpclient` | `HttpClient`, `newHttpClient`, `request`, `close`, `HttpMethod`, `newHttpHeaders` | Decision 4.1A. Synchronous HTTP. The sole network IO dependency. |
| `std/json` | `parseJson`, `$` (serialise `JsonNode` to string), `JsonNode`, `JObject`, `JArray`, `hasKey`, `{}` (nil-safe key access), `JsonParsingError` | JSON string parsing (`string → JsonNode`) is the Layer 4 boundary that Layers 1–3 delegate upward. `$` serialises `Request.toJson()` to the HTTP body. `parseJson` is the reverse for responses. `JArray` used in `validateLimits` for ids/destroy array detection. `{}` used in `validateLimits` for nil-safe access to optional method arguments. |
| `std/options` | `Option[T]`, `some`, `none`, `isSome`, `isNone`, `get`. Also available: `map`, `flatMap`, `filter` (not used in v1 but could simplify optional session/capability access patterns). | Cached session field on `JmapClient`. |
| `std/strutils` | `toLowerAscii`, `startsWith`, `endsWith`, `replace`, `contains` | Content-Type case-insensitive matching, method name suffix detection in `validateLimits`, URI template expansion. |

### Modules evaluated and rejected

| Module | Reason not used in Layer 4 |
|--------|---------------------------|
| `std/asynchttpclient` | Architecture decision 4.1A: synchronous only. `AsyncHttpClient` creates closure environments that leak under `--mm:arc` (ARC cannot trace closure-captured ref cycles). |
| `std/asyncdispatch` | No async in this design. The synchronous model is appropriate for a C ABI library (architecture §4.1A). |
| `std/uri` | `parseUri` is permissive (never raises) and does not validate URLs, so it adds no safety guarantees beyond a raw string. Session URLs are stored as plain strings and passed directly to `std/httpclient`. `.well-known` URL construction is simple concatenation. Note: `std/uri.encodeUrl(value, usePlus=false)` is available for RFC 3986 percent-encoding — relevant for URI template variable values (see D4.11). |
| `std/re` / `std/pcre` | Content-Type checking uses `startsWith` after `toLowerAscii`. URI template expansion uses `strutils.replace`. No regex needed. |
| `std/streams` | `Response.body` lazily reads from `Response.bodyStream` (a `Stream`) on first access. Stream handling is internal to `std/httpclient`; direct `std/streams` use is not needed. |
| `std/net` | `std/httpclient` handles TLS configuration internally via `newHttpClient(sslContext = ...)`. `std/net.newContext` could configure TLS (cert, CA, ciphers, TLS version) — see deferred decision R16. Not used in v1. The `-d:ssl` compile-time warning (§9.1) does not require `std/net`. |
| `std/httpcore` | Re-exported by `std/httpclient`. No direct import needed. |

### Critical Nim findings that constrain the design

| Finding | Impact | Evidence |
|---------|--------|----------|
| `std/httpclient` procs have no `{.raises.}` annotations | Must catch `CatchableError` broadly at the IO boundary; the compiler treats them as potentially raising `Exception` | Architecture §4.1A `raises` caveat |
| `std/httpclient` raises: `ProtocolError` (`IOError`), `HttpRequestError` (`IOError`), `ValueError`, `TimeoutError` | Exception classification must map all four to `TransportError` variants | `httpclient.nim` source |
| `HttpClient` is a `ref object` — ARC-managed | `close()` should be called explicitly for deterministic socket release; destructor runs on scope exit under ARC | `httpclient.nim:617` |
| `HttpClient.headers` field persists across requests | Bearer token set once on construction, sent on every subsequent request without per-request header setup | `httpclient.nim:621` |
| Authorisation header stripped on cross-domain redirects | Correct security behaviour for `.well-known` discovery — the token is not leaked if the server redirects to a different domain | `httpclient.nim:1299–1306` |
| `Response.body` is a lazy proc (not a field) | First call reads `bodyStream.readAll()` and caches the result. Body IO occurs inside `classifyHttpResponse`, not at the `request()` call boundary. Body size enforcement happens after this read (before `parseJson`). | `httpclient.nim:332–338` |
| `Response.code` is a proc with `{.raises: [ValueError, OverflowDefect].}` | Parses `response.status[0..2].parseInt.HttpCode`. Malformed status strings raise `ValueError`. `OverflowDefect` is fatal under `--panics:on` (extremely unlikely for valid HTTP). Must be called inside `try/except ValueError`. Safe to convert result to `int` via `int(code)` for `TransportError.httpStatus`. | `httpclient.nim:298–304`, `httpcore.nim:14` |
| `Response.contentType` returns the Content-Type header value | Returns `headers.getOrDefault("content-type")` — header key lookup is case-insensitive. Returns empty string if header absent, which correctly fails the `startsWith("application/json")` check. | `httpclient.nim:306–310` |
| `newHttpClient` takes `timeout` parameter (milliseconds, `int`) | Per-socket-operation timeout, not per-request. `-1` means no timeout (matches `std/httpclient` convention). Passed through from `JmapClient` constructor. | `httpclient.nim:647–649` |
| `newHttpClient` has a built-in `userAgent` parameter | Default is `"Nim-httpclient/" & NimVersion`. Pass `userAgent` directly instead of adding to headers (see §1.2). | `httpclient.nim:647` |
| `newHttpClient.maxRedirects` assigns to a `Natural` field | Negative values trigger `RangeDefect` (fatal under `--panics:on`). Validation rule 5 in §1.2 prevents this. | `httpclient.nim:622` |
| `HttpClient` reuses TCP connections for same hostname/scheme/port | Multiple `send` calls to `apiUrl` reuse the connection. `close()` releases the socket. Partially addresses deferred decision R15. | `httpclient.nim` |
| `Response.contentLength` returns Content-Length header value (or -1) | Calls `parseInt` internally — can raise `ValueError` for malformed headers. Enables early body size rejection before `response.body` is read (see §2.2). | `httpclient.nim:312–320` |
| `parseJson` raises `JsonParsingError` (a `ValueError` descendant) | Must be caught and classified in the IO boundary | `json.nim:890` |
| `$` on `JsonNode` serialises to compact JSON string | Used to convert `Request.toJson()` to HTTP body. Minimises body size. | `json.nim:344` |

---

## 1. JmapClient Type

### 1.1 Type Definition

**RFC reference:** §1.7 (lines 426–447), §2 (lines 477–721), §3.1
(lines 854–863).

```nim
type JmapClient* = object
  ## The JMAP client handle. Encapsulates connection state, authentication,
  ## cached session, and HTTP configuration. Not thread-safe — all calls
  ## must originate from a single thread (architecture §4.3).
  ##
  ## Construction: ``initJmapClient()`` or ``discoverJmapClient()``.
  ## Destruction: ``close()`` releases the underlying HTTP connection.
  ##
  ## All fields are module-private. Access is via public accessor procs.
  ## This makes invalid states unrepresentable: callers cannot construct
  ## a JmapClient with an empty URL or missing token.
  httpClient: HttpClient          ## std/httpclient handle (ref, ARC-managed)
  sessionUrl: string              ## URL for the JMAP Session resource
  bearerToken: string             ## Bearer token for Authorisation header
  session: Option[Session]        ## Cached Session; populated on first fetch
  maxResponseBytes: int           ## Response body size cap (R9). 0 = no limit.
  userAgent: string               ## User-Agent header value
```

**Decision D4.1: `object` vs `ref object`.** `JmapClient` is a value
type (`object`) containing an `HttpClient` (which is itself a
`ref object`). The `JmapClient` is passed by `var` to IO procs
(`fetchSession`, `send`, `setBearerToken`, `close`). This matches the
builder pattern from Layer 3 — owned `var` parameter mutation. A
`ref object` wrapper would add unnecessary indirection. For the C ABI
(Layer 5), `JmapClient` is allocated on the heap via
`create(JmapClient)` and exposed as an opaque `pointer`, as prescribed
by `.claude/rules/nim-ffi-boundary.md`.

### 1.2 Smart Constructor

**Principle: parse, don't validate.** The constructor validates all
parameters and returns a fully-initialised `JmapClient` or raises
`ValidationError`. There is no "partially constructed" state.

```nim
proc initJmapClient*(
    sessionUrl: string,
    bearerToken: string,
    timeout: int = 30_000,
    maxRedirects: int = 5,
    maxResponseBytes: int = 50_000_000,
    userAgent: string = "jmap-client-nim/0.1.0",
): JmapClient =
  ## Creates a new JmapClient from a known session URL and bearer token.
  ##
  ## ``sessionUrl``: the JMAP Session resource URL. Must be non-empty and
  ##   start with "https://" or "http://".
  ## ``bearerToken``: the Bearer token for HTTP Authorisation. Must be
  ##   non-empty. Attached as "Authorization: Bearer {token}" on every
  ##   HTTP request.
  ## ``timeout``: per-socket-operation timeout in milliseconds. Default
  ##   30 000 (30 seconds). -1 disables the timeout. Must be >= -1.
  ## ``maxRedirects``: maximum HTTP redirects to follow automatically.
  ##   Default 5. Must be >= 0.
  ## ``maxResponseBytes``: maximum response body size in bytes. Responses
  ##   exceeding this limit raise TransportError before JSON parsing.
  ##   0 disables the limit. Default 50 000 000 (50 MB). Must be >= 0.
  ## ``userAgent``: the User-Agent header value.
  ##
  ## Does NOT fetch the session — call ``fetchSession()`` explicitly or
  ## let ``send()`` fetch it lazily on first call (Decision D4.2).
  ##
  ## Raises ``ValidationError`` if any parameter is invalid.
```

**Validation rules:**

1. `sessionUrl` must be non-empty.
2. `sessionUrl` must start with `"https://"` or `"http://"`.
3. `bearerToken` must be non-empty.
4. `timeout` must be >= -1.
5. `maxRedirects` must be >= 0. (Safety-critical: `HttpClientBase.maxRedirects`
   is typed `Natural` (`range[0..high(int)]`). Assigning a negative value
   triggers `RangeDefect`, which under `--panics:on` aborts the process
   immediately. This validation converts a fatal Defect into a recoverable
   `ValidationError`.)
6. `maxResponseBytes` must be >= 0.

On violation, raises `ValidationError` with `typeName = "JmapClient"`.

**HttpClient construction:** The constructor creates the internal
`HttpClient` via:

```nim
let headers = newHttpHeaders({
  "Authorization": "Bearer " & bearerToken,
  "Content-Type": "application/json",
  "Accept": "application/json",
})
let httpClient = newHttpClient(
  userAgent = userAgent,
  timeout = timeout,
  maxRedirects = maxRedirects,
  headers = headers,
)
JmapClient(
  httpClient: httpClient,
  sessionUrl: sessionUrl,
  bearerToken: bearerToken,
  session: none(Session),
  maxResponseBytes: maxResponseBytes,
  userAgent: userAgent,
)
```

**Decision D4.2: Eager vs lazy session fetch.** The constructor does NOT
fetch the session. Construction should not perform IO — `initJmapClient`
creates the handle and validates parameters. The session is fetched
lazily on the first `send()` call, or eagerly via explicit
`fetchSession()`.

### 1.3 Discovery Constructor

**RFC reference:** §2.2 (lines 819–835).

```nim
proc discoverJmapClient*(
    domain: string,
    bearerToken: string,
    timeout: int = 30_000,
    maxRedirects: int = 5,
    maxResponseBytes: int = 50_000_000,
    userAgent: string = "jmap-client-nim/0.1.0",
): JmapClient =
  ## Creates a JmapClient by constructing the .well-known/jmap URL from
  ## a domain name (RFC 8620 §2.2).
  ##
  ## ``domain``: the JMAP server's domain (e.g., "jmap.example.com").
  ##   The session URL becomes "https://{domain}/.well-known/jmap".
  ##   Must be non-empty, no whitespace, no "/" characters.
  ##
  ## All other parameters forwarded to ``initJmapClient()``.
  ## Raises ``ValidationError`` if domain or bearerToken are invalid.
```

**Domain validation (parse, don't validate):**

1. `domain` must be non-empty.
2. `domain` must not contain whitespace (prevents header injection).
3. `domain` must not contain `"/"` (prevents path injection).

On passing validation, constructs
`"https://" & domain & "/.well-known/jmap"` and delegates to
`initJmapClient`.

**Decision D4.3: No DNS SRV.** Per architecture §4.2. No reference
JMAP client implements DNS SRV. `.well-known` covers all practical
deployments.

### 1.4 Read-Only Accessors

```nim
proc session*(client: JmapClient): Option[Session]
proc sessionUrl*(client: JmapClient): string
proc bearerToken*(client: JmapClient): string
```

These return immutable copies. The caller cannot mutate the client's
internal state through these accessors.

### 1.5 Mutators

```nim
proc setBearerToken*(client: var JmapClient, token: string) =
  ## Updates the bearer token. Subsequent requests use the new token.
  ## Raises ``ValidationError`` if token is empty.
  ## Also updates the Authorization header on the HttpClient.

proc close*(client: var JmapClient) =
  ## Closes the underlying HTTP connection. Releases the socket
  ## immediately. Idempotent — safe to call multiple times.
  ## Under ARC, the HttpClient ref is also released when the
  ## JmapClient goes out of scope, but ``close()`` is explicit.
  ##
  ## Recommended pattern: ``defer: client.close()`` ensures socket
  ## release even if an exception occurs.
```

---

## 2. HTTP Response Classification (DRY)

**Principle: DRY.** The classification logic for HTTP responses is
shared between `fetchSession` (GET) and `send` (POST). It is factored
into two pure procs that compose with the IO procs.

### 2.1 Exception Classification (Pure)

Maps `std/httpclient` exceptions to `ClientError(cekTransport)`. This
is a pure transform — no IO, no mutation.

```nim
proc classifyException(e: ref CatchableError): ref ClientError =
  ## Maps std/httpclient exceptions to ClientError(cekTransport).
  ## Pure: no IO, no side effects. Exhaustive over known exception types.
  ##
  ## Classification rules (total — every CatchableError is handled):
  ## - TimeoutError           → tekTimeout
  ## - OSError with TLS msg   → tekTls  (heuristic, see D4.5)
  ## - OSError (other)        → tekNetwork
  ## - IOError                → tekNetwork (includes ProtocolError,
  ##                            HttpRequestError, redirect exhaustion)
  ## - ValueError             → tekNetwork (e.g., unparseable URL)
  ## - Other CatchableError   → tekNetwork (defensive catch-all)
  var te: TransportError
  if e of ref TimeoutError:
    te = transportError(tekTimeout, e.msg)
  elif e of ref OSError:
    let msg = e.msg.toLowerAscii
    if "ssl" in msg or "tls" in msg or "certificate" in msg:
      te = transportError(tekTls, e.msg)
    else:
      te = transportError(tekNetwork, e.msg)
  elif e of ref IOError:
    te = transportError(tekNetwork, e.msg)
  elif e of ref ValueError:
    te = transportError(tekNetwork, "protocol error: " & e.msg)
  else:
    te = transportError(tekNetwork, "unexpected error: " & e.msg)
  newClientError(te)
```

**Decision D4.5: TLS detection heuristic.** `std/httpclient` has no
distinct TLS exception type. TLS failures from OpenSSL surface as
`OSError` with messages containing "ssl", "tls", or "certificate"
(case-insensitive). A substring check is the best available heuristic.
False positives are harmless — the error is still classified as a
transport failure, and `te.msg` carries the actual underlying error.

### 2.2 Body Size Enforcement

Two-phase check: Phase 1 rejects before reading the body (using the
Content-Length header); Phase 2 rejects after reading (using the actual
body length). Together they prevent both OOM on oversized responses and
bypass via missing/inaccurate Content-Length.

```nim
proc enforceContentLengthLimit(
    maxResponseBytes: int, httpResp: httpclient.Response, context: string
) =
  ## Phase 1: early rejection via Content-Length header, before the body
  ## is read into memory. No IO — reads only from already-received
  ## response headers. No-op when maxResponseBytes == 0 (no limit)
  ## or Content-Length is absent/unparseable.
  if maxResponseBytes > 0:
    let cl = try:
      httpResp.contentLength
    except ValueError:
      -1  # malformed Content-Length — fall through to Phase 2
    if cl > maxResponseBytes:
      let te = transportError(tekNetwork,
        context & " Content-Length exceeds limit: " &
        $cl & " bytes > " & $maxResponseBytes & " byte limit")
      raise newClientError(te)

proc enforceBodySizeLimit(
    maxResponseBytes: int, body: string, context: string
) =
  ## Phase 2: post-read rejection via actual body length. Catches cases
  ## where Content-Length was absent, inaccurate, or not checked.
  ## No-op when maxResponseBytes == 0 (no limit). Pure — no IO.
  if maxResponseBytes > 0 and body.len > maxResponseBytes:
    let te = transportError(tekNetwork,
      context & " response body exceeds limit: " &
      $body.len & " bytes > " & $maxResponseBytes & " byte limit")
    raise newClientError(te)
```

**Decision D4.4: Body size check timing.** Phase 1 checks
`contentLength` from the response headers before `response.body` is
called, preventing a multi-GB response from being read into memory.
`contentLength` (`httpclient.nim:312–320`) calls `parseInt` internally
and can raise `ValueError` for malformed headers — caught and treated as
"unknown length" (fall through to Phase 2). Phase 2 checks `body.len`
after the full read but before `parseJson`, preventing the expensive
JSON tree allocation. A streaming size limit during the read itself
would require replacing `std/httpclient` — deferred to the libcurl
upgrade path (architecture §4.1A fallback).

### 2.3 HTTP Response Classification

The classification logic for HTTP responses. The IO procs
(`fetchSession`, `send`) call `std/httpclient.request` and pass the
result to this proc. Note: this proc is NOT pure — `httpResp.body`
lazily reads from `bodyStream` on first access.

```nim
proc classifyHttpResponse(
    maxResponseBytes: int,
    httpResp: httpclient.Response,
    context: string,
): string =
  ## Classifies an HTTP response. Returns the body string on 2xx with
  ## correct Content-Type. Raises ClientError otherwise.
  ##
  ## ``context``: "session" or "api" — used in error messages.
  ##
  ## Classification table (total — every status code range handled):
  ##   2xx + application/json       → return body
  ##   2xx + other Content-Type     → raise tekNetwork
  ##   4xx/5xx + problem details    → raise cekRequest (RequestError)
  ##   4xx/5xx + no problem details → raise tekHttpStatus
  ##   Other non-2xx (1xx/3xx)      → raise tekHttpStatus
  ##
  ## Note: despite operating on an already-received ``httpclient.Response``,
  ## this proc is NOT pure. ``httpResp.body`` lazily reads from
  ## ``bodyStream.readAll()`` on first access (IO), and ``httpResp.code``
  ## parses the status string and can raise ``ValueError``.
  let code = try:
    httpResp.code
  except ValueError:
    let te = transportError(tekNetwork,
      "malformed HTTP status from " & context & ": " & httpResp.status)
    raise newClientError(te)

  # Phase 1 body size enforcement (R9) — reject before reading body
  enforceContentLengthLimit(maxResponseBytes, httpResp, context)

  let body = httpResp.body  # lazy: reads bodyStream on first access

  # Phase 2 body size enforcement (R9) — reject after reading body
  enforceBodySizeLimit(maxResponseBytes, body, context)

  if code.is4xx or code.is5xx:
    # Attempt to parse as RFC 7807 problem details
    let ct = httpResp.contentType.toLowerAscii
    if ct.startsWith("application/problem+json") or
       ct.startsWith("application/json"):
      try:
        let jsonNode = parseJson(body)
        if jsonNode.kind == JObject and jsonNode.hasKey("type"):
          let reqErr = RequestError.fromJson(jsonNode)
          raise newClientError(reqErr)
      except ClientError:
        raise  # re-raise the ClientError we just created
      except CatchableError:
        discard  # fall through to generic HTTP status error
    # Generic HTTP status error (no problem details, or parsing failed)
    let te = httpStatusError(int(code),
      "HTTP " & $int(code) & " from " & context)
    raise newClientError(te)

  # Guard: non-2xx that is not 4xx/5xx (e.g. 1xx, 3xx).
  # In practice std/httpclient handles redirects and 1xx internally,
  # so this should never fire — but total functions cover all inputs.
  if not code.is2xx:
    let te = httpStatusError(int(code),
      "unexpected HTTP " & $int(code) & " from " & context)
    raise newClientError(te)

  # Check Content-Type on 2xx success
  let ct = httpResp.contentType.toLowerAscii
  if not ct.startsWith("application/json"):
    let te = transportError(tekNetwork,
      "unexpected Content-Type from " & context & ": " &
      httpResp.contentType)
    raise newClientError(te)

  body
```

**Content-Type checking.** Case-insensitive prefix matching via
`toLowerAscii.startsWith(...)`. This correctly handles
`application/json; charset=utf-8` and similar variants with parameters.
For problem details, also accepts `application/problem+json` (RFC 7807).

### 2.4 JSON Body Parsing (Pure, DRY)

Shared helper for parsing a JSON response body. Eliminates duplicated
`JsonParsingError` handling in `fetchSession` and `send`.

```nim
proc parseJsonBody(body: string, context: string): JsonNode =
  ## Parses a response body as JSON. Raises ClientError(cekTransport) if
  ## the body is not valid JSON. Pure — no IO.
  ##
  ## ``context``: "session" or "api" — used in error messages.
  try:
    parseJson(body)
  except JsonParsingError as e:
    let te = transportError(tekNetwork,
      "invalid JSON in " & context & " response: " & e.msg)
    raise newClientError(te)
```

---

## 3. Session Discovery and Fetching

### 3.1 fetchSession Procedure

**RFC reference:** §2 (lines 477–721), §2.1 (lines 735–817), §2.2
(lines 819–835).

```nim
proc fetchSession*(client: var JmapClient): Session =
  ## Fetches the JMAP Session resource from the server and caches it.
  ##
  ## This is the sole IO proc for session management. It composes:
  ## 1. IO: HTTP GET to sessionUrl (impure — the shell).
  ## 2. Pure: classifyHttpResponse (status, content-type, body size).
  ## 3. Pure: parseJson (string → JsonNode).
  ## 4. Pure: Session.fromJson (JsonNode → Session via Layer 2).
  ## 5. Mutation: cache the Session on the client.
  ##
  ## Re-fetching: calling fetchSession() replaces the cached session.
  ## This is the session refresh mechanism (§6).
  ##
  ## Raises:
  ## - ClientError(cekTransport) for network, TLS, timeout, HTTP errors.
  ## - ClientError(cekRequest) for RFC 7807 problem details responses.
  ## - ValidationError if the session JSON is structurally invalid
  ##   (Decision D4.6).
```

**Decision D4.6: ValidationError propagation.** When `Session.fromJson`
raises `ValidationError` (e.g., missing `ckCore`, invalid `apiUrl`), the
exception propagates as-is, NOT wrapped in `ClientError`. `ClientError`
is for transport and request-level failures — the HTTP round-trip
succeeded but the server's response content violates the Session schema.
`ValidationError` carries richer context (`typeName`, `value`, `msg`).
Layer 5 catches all `CatchableError` subtypes uniformly.

### 3.2 fetchSession Algorithm

```
proc fetchSession*(client: var JmapClient): Session =
  # Step 1: IO boundary — HTTP GET (the only impure line)
  let httpResp = try:
    client.httpClient.request(client.sessionUrl, httpMethod = HttpGet)
  except CatchableError as e:
    raise classifyException(e)

  # Step 2: Classification — status, content-type, body size
  # (reads body stream on first access; see §2.3 note)
  let body = classifyHttpResponse(
    client.maxResponseBytes, httpResp, "session")

  # Step 3: Pure parse — string → JsonNode (DRY: shared helper §2.4)
  let jsonNode = parseJsonBody(body, "session")

  # Step 4: Pure deserialisation — JsonNode → Session (Layer 2)
  let session = Session.fromJson(jsonNode)

  # Step 5: Cache (mutation through var parameter)
  client.session = some(session)
  session
```

---

## 4. API Request/Response Flow

### 4.1 The `send` Procedure

**RFC reference:** §3.1 (lines 854–863), §3.3 (lines 882–943), §3.4
(lines 975–1003).

```nim
proc send*(client: var JmapClient, request: Request): Response =
  ## The primary API call. Serialises a JMAP Request, POSTs to the
  ## server's apiUrl, and deserialises the Response.
  ##
  ## Composes transforms around IO steps:
  ## 1. Ensure session available (may trigger IO via fetchSession).
  ## 2. Pure: validateLimits — pre-flight check against CoreCapabilities.
  ## 3. Pure: toJson + $ — serialise Request to JSON string.
  ## 4. Pure: check serialised size against maxSizeRequest.
  ## 5. IO:   HTTP POST.
  ## 6. IO:   classifyHttpResponse — status, content-type, body size
  ##    (reads body stream on first access; see §2.3 note).
  ## 7. Pure: parseJsonBody — string → JsonNode.
  ## 8. Pure: problem details detection on HTTP 200.
  ## 9. Pure: Response.fromJson — JsonNode → Response (Layer 2).
  ##
  ## Session staleness: after return, the caller should check
  ## ``isSessionStale(client, response)`` and call ``fetchSession()``
  ## if stale. ``send`` does NOT automatically refresh (Decision D4.10).
  ##
  ## Raises:
  ## - ClientError(cekTransport) for network/TLS/timeout/HTTP errors.
  ## - ClientError(cekRequest) for RFC 7807 problem details responses.
  ## - ValidationError for limit violations or structurally invalid
  ##   response JSON (valid JSON that fails Response schema validation).
```

### 4.2 Detailed Algorithm

**Step 1: Ensure session.**

```nim
if client.session.isNone:
  discard client.fetchSession()
let session = client.session.get()
```

If `fetchSession` raises, the exception propagates.

**Step 2: Pre-flight validation (R13).**

```nim
validateLimits(request, session.coreCapabilities())
```

Pure proc (§5). Raises `ValidationError` on violation.

**Step 3: Serialise.**

```nim
let jsonNode = request.toJson()   # Layer 2: Request → JsonNode
let body = $jsonNode               # std/json: JsonNode → string
```

**Step 4: Check serialised size against maxSizeRequest.**

**RFC reference:** §2 (line 528): `maxSizeRequest` — "The maximum
size, in octets, that the server will accept for a single request to
the API endpoint."

**L3 reference:** §16.3 — "requires the serialised JSON byte length,
which is only available after `Request.toJson()` is converted to bytes.
This is a Layer 4 concern."

```nim
let maxSize = int64(session.coreCapabilities().maxSizeRequest)
if body.len > int(maxSize):
  raise newValidationError("Request",
    "serialised request size " & $body.len &
    " octets exceeds server maxSizeRequest " & $maxSize, "")
```

**Step 5: IO boundary — HTTP POST.**

```nim
let httpResp = try:
  client.httpClient.request(
    session.apiUrl,
    httpMethod = HttpPost,
    body = body)
except CatchableError as e:
  raise classifyException(e)
```

Headers are set on `client.httpClient.headers` from construction.

**Step 6: Pure classification.**

```nim
let respBody = classifyHttpResponse(
  client.maxResponseBytes, httpResp, "api")
```

Reuses the shared helper from §2.3 (DRY).

**Step 7: Parse JSON (DRY: shared helper §2.4).**

```nim
let respJson = parseJsonBody(respBody, "api")
```

**Decision D4.7: `JsonParsingError` classification.** Classified as
`tekNetwork`, not `tekHttpStatus`. The HTTP transport succeeded but the
body is not valid JSON — a server encoding error analogous to a protocol
violation. `tekHttpStatus` implies a meaningful status code, which is
inappropriate for a parsing failure.

**Step 8: Problem details detection on HTTP 200.**

**RFC reference:** §3.6.1 (lines 1079–1136). Request-level errors
may be returned with HTTP 200 status.

```nim
if respJson.kind == JObject and respJson.hasKey("type") and
   not respJson.hasKey("methodResponses"):
  let reqErr = RequestError.fromJson(respJson)
  raise newClientError(reqErr)
```

**Decision D4.8: Problem details on HTTP 200.** Heuristic: if the
top-level JSON object has a `"type"` field but lacks
`"methodResponses"`, it is a problem details response. This is safe
because every valid JMAP Response has `methodResponses` (RFC §3.4,
required). Alternative considered: check Content-Type for
`application/problem+json` — rejected because many servers return
problem details with `application/json` Content-Type.

**Step 9: Deserialise as JMAP Response.**

```nim
Response.fromJson(respJson)
```

`ValidationError` from Layer 2 propagates as-is.

---

## 5. Pre-Flight Validation (Deferred Decision R13)

**L3 reference:** §16 — "Session Limit Pre-Flight Validation". Status
changed from "deferred" to "resolved" by this document.

**RFC reference:** §2 (CoreCapabilities), §3.6.1 (limit error), §5.1
(`requestTooLarge` for /get), §5.3 (`requestTooLarge` for /set).

**Principle: total function.** `validateLimits` handles all inputs —
unknown method names are silently skipped (only `/get` and `/set`
suffixes are checked). Reference arguments (`rkReference`) are
documented as uncountable and explicitly skipped.

### 5.1 Procedure Signature

```nim
proc validateLimits*(request: Request, caps: CoreCapabilities) =
  ## Pre-flight validation of a built Request against server-advertised
  ## CoreCapabilities limits. Pure — no IO, no mutation.
  ##
  ## Raises ValidationError describing the first violation.
  ##
  ## Checks:
  ## - len(request.methodCalls) <= maxCallsInRequest
  ## - Per /get call: direct ids count <= maxObjectsInGet
  ##   (skipped for rkReference ids — actual count unknown until
  ##   server resolves the back-reference)
  ## - Per /set call: create + update + direct destroy <= maxObjectsInSet
  ##   (skipped for rkReference destroy)
  ##
  ## NOT checked (handled separately):
  ## - maxSizeRequest (requires serialised bytes — ``send`` step 4)
  ## - maxConcurrentRequests (transport-level concurrency)
  ## - Read-only account prevention (requires Session context)
```

**Decision D4.9: Module placement.** `validateLimits` lives in
`client.nim` alongside `send`. Called exclusively by `send`. No circular
dependency (depends only on `Request` and `CoreCapabilities`, both
Layer 1 types).

### 5.2 Algorithm

```nim
proc validateLimits*(request: Request, caps: CoreCapabilities) =
  let maxCalls = int64(caps.maxCallsInRequest)
  if request.methodCalls.len > int(maxCalls):
    raise newValidationError("Request",
      "method call count " & $request.methodCalls.len &
      " exceeds maxCallsInRequest " & $maxCalls, "")

  let maxGet = int64(caps.maxObjectsInGet)
  let maxSet = int64(caps.maxObjectsInSet)

  for inv in request.methodCalls:
    let args = inv.arguments

    if inv.name.endsWith("/get"):
      # Check maxObjectsInGet for direct (non-reference) ids
      let idsNode = args{"ids"}
      if not idsNode.isNil and idsNode.kind == JArray:
        if idsNode.len > int(maxGet):
          raise newValidationError("Request",
            inv.name & ": ids count " & $idsNode.len &
            " exceeds maxObjectsInGet " & $maxGet, "")
      # Reference ids serialise as #ids key → args{"ids"} is nil → skip

    elif inv.name.endsWith("/set"):
      var count = 0
      let createNode = args{"create"}
      if not createNode.isNil and createNode.kind == JObject:
        count += createNode.len
      let updateNode = args{"update"}
      if not updateNode.isNil and updateNode.kind == JObject:
        count += updateNode.len
      let destroyNode = args{"destroy"}
      if not destroyNode.isNil and destroyNode.kind == JArray:
        count += destroyNode.len
      # Reference destroy serialises as #destroy key → args{"destroy"} is nil → skip
      if count > int(maxSet):
        raise newValidationError("Request",
          inv.name & ": object count " & $count &
          " exceeds maxObjectsInSet " & $maxSet, "")
```

---

## 6. Session Staleness Detection

**RFC reference:** §3.4 (lines 995–999).

### 6.1 Detection (Pure)

```nim
proc isSessionStale*(client: JmapClient, response: Response): bool =
  ## Compares Response.sessionState with cached Session.state.
  ## Returns true if they differ (session should be re-fetched).
  ## Returns false if no session is cached (cannot determine staleness).
  ## Pure — no IO, no mutation.
  if client.session.isNone:
    return false
  client.session.get().state != response.sessionState
```

### 6.2 Refresh (IO)

```nim
proc refreshSessionIfStale*(
    client: var JmapClient, response: Response
): bool =
  ## If the response indicates staleness, re-fetches the session.
  ## Returns true if refreshed, false otherwise.
  ## Raises ClientError on fetch failure (same as fetchSession).
  if client.isSessionStale(response):
    discard client.fetchSession()
    return true
  false
```

**Decision D4.10: Automatic vs manual session refresh.** `send` does
NOT automatically refresh. Rationale: (a) hidden network request makes
latency unpredictable; (b) the caller may want to inspect the response
before deciding; (c) the RFC uses SHOULD (not MUST); (d) in batch
requests, the session may change mid-batch — automatic refresh after
every `send` could cause unnecessary re-fetches. The library provides
composable tools (`isSessionStale`, `refreshSessionIfStale`).

---

## 7. URI Template Expansion (Pure)

**RFC reference:** §2 (lines 679–700), RFC 6570 Level 1.

```nim
proc expandUriTemplate*(
    tmpl: UriTemplate,
    variables: openArray[(string, string)],
): string =
  ## Expands an RFC 6570 Level 1 URI template by replacing {name} with
  ## the corresponding value. Pure — no IO, no mutation.
  ##
  ## Level 1 only: simple string substitution. For values requiring
  ## percent-encoding (e.g., filenames in download URL ``name``),
  ## use ``std/uri.encodeUrl(value, usePlus=false)``.
  ##
  ## Variables not found in ``variables`` are left unexpanded.
  ##
  ## Example:
  ##   expandUriTemplate(session.downloadUrl,
  ##     {"accountId": string(acctId), "blobId": string(blobId),
  ##      "name": "report.pdf", "type": "application/pdf"})
  result = string(tmpl)
  for (name, value) in variables:
    result = result.replace("{" & name & "}", value)
```

**Decision D4.11: Percent-encoding responsibility.** Caller encodes.
`std/uri.encodeUrl(value, usePlus=false)` provides RFC 3986
percent-encoding for values that need it. Common identifiers
(`AccountId`, `Id`) are base64url-safe — no encoding needed. Full
RFC 6570 parser is disproportionate for Level 1.

---

## 8. Content-Type and HTTP Header Management

### 8.1 Default Headers

Set once on `HttpClient.headers` during `initJmapClient`:

| Header | Value | RFC Reference |
|--------|-------|--------------|
| `Authorization` | `Bearer {token}` | §1.7 (lines 429–430) |
| `Content-Type` | `application/json` | §3.1 (lines 860–861) |
| `Accept` | `application/json` | §3.1 (line 862) |
| `User-Agent` | configurable (via `newHttpClient` `userAgent` param) | Not RFC-specified |

**No per-request header manipulation.** JMAP does not use
request-specific headers. Bearer token and Content-Type are constant
across requests (until `setBearerToken` is called). Note:
`std/httpclient.request()` accepts a `headers` parameter that overrides
client headers using right-biased union (per-request headers take
priority). This capability is available for future extension (e.g.,
different Accept header for binary download/upload endpoints) without
modifying the design.

### 8.2 Content-Type Validation on Responses

Header key lookup (`content-type`) is already case-insensitive —
`HttpHeaders` uses `toCaseInsensitive` internally. The `toLowerAscii`
call in §2.3 normalises the header VALUE for MIME type prefix matching,
because MIME types are case-insensitive per RFC 2045 but servers may
return mixed-case values (e.g., `Application/JSON`).

1. **2xx success:** verify `application/json` prefix (case-insensitive).
2. **4xx/5xx:** accept `application/problem+json` or `application/json`
   for problem details parsing.

---

## 9. SSL/TLS Considerations

### 9.1 The `-d:ssl` Compile Flag

`std/httpclient` requires `-d:ssl` for HTTPS. JMAP servers are
exclusively HTTPS (RFC 8620 §1.7: "All HTTP requests MUST use the
'https://' scheme").

**Decision D4.12: Compile-time hint.** `client.nim` emits a hint
when `-d:ssl` is not defined:

```nim
when not defined(ssl):
  {.hint: "jmap-client: -d:ssl is not defined. " &
    "HTTPS connections will fail at runtime. " &
    "Add -d:ssl to your compile flags.".}
```

Hint (not warning or error): `config.nims` sets `warningAsError: User`,
which promotes `{.warning:}` pragmas to compile errors. `{.hint:}` emits
a `[User]` hint that is visible during compilation but does not block it,
since only `hintAsError: DuplicateModuleImport` is configured. This
achieves the design intent — informational, non-blocking — within the
project's strict compiler configuration.

### 9.2 TLS Configuration

OpenSSL defaults via `newHttpClient`. `newHttpClient` accepts an
`sslContext` parameter, and `std/net.newContext` provides TLS
configuration including `protVersion`, `verifyMode`, `certFile`,
`keyFile`, `cipherList`, `caDir`, `caFile`, and `ciphersuites`. This
means `initJmapClient` could accept an optional `SslContext` parameter
and pass it through. Deferred for v1: exposing this parameter adds API
surface, and OpenSSL defaults are sufficient for the initial release.
See Deferred Decision R16.

---

## 10. Module File Layout

### 10.1 Single File: `client.nim`

```
src/jmap_client/
  errors.nim          — provides newClientError ref-returning constructors
                         (already implemented, following newValidationError pattern)
  client.nim          — JmapClient type, constructors, fetchSession, send,
                         validateLimits, classifyException,
                         classifyHttpResponse, enforceContentLengthLimit,
                         enforceBodySizeLimit, parseJsonBody,
                         expandUriTemplate, isSessionStale,
                         refreshSessionIfStale, close
```

**Decision D4.13: Single file.** All procs operate on `JmapClient`.
Estimated 300–500 lines. No natural decomposition boundary. Internal
helpers are module-private.

**Nimalyzer `objects` rule suppression.** The `JmapClient` type has all
private fields by design (§1.1: make illegal states unrepresentable).
The nimalyzer `objects publicfields` rule flags exported types without
public fields. The type definition is wrapped in
`{.push ruleOff: "objects".}` / `{.pop.}` to suppress this diagnostic.

### 10.2 Import DAG

```
client.nim imports:
  std/httpclient       — HttpClient, newHttpClient, request, close,
                         HttpMethod, newHttpHeaders
  std/json             — parseJson, $, JsonNode, JObject, JArray, hasKey,
                         {} (nil-safe access), JsonParsingError
  std/strutils         — toLowerAscii, startsWith, endsWith, replace,
                         contains (via `in` operator), Whitespace
  ./types              — Layer 1 re-export hub (also re-exports std/options)
  ./serialisation      — Layer 2 re-export hub
```

**Import ordering note.** `std/json` and `./serialisation` are not
imported until they are first used (IO helpers and `send`). `config.nims`
sets `warningAsError: UnusedImport`, so importing them before any proc
references them causes a compile error. Similarly, `std/options` is NOT
imported directly — it is re-exported by `./types`, and a direct import
would trigger `hintAsError: DuplicateModuleImport`. The initial file
(constructors + accessors + mutators) imports only `std/httpclient`,
`std/strutils`, and `./types`.

**Name collision: `Response`.** Both `std/httpclient` and the JMAP
envelope types (via `./types`) export a `Response` type. In proc
signatures, the httpclient variant is qualified as
`httpclient.Response`. The unqualified `Response` refers to the JMAP
`Response` (from `envelope.nim`).

Layer 3 (`methods.nim`) is NOT imported. `send` operates at the envelope
level. Method-specific response extraction is a Layer 3 concern.

### 10.3 Re-Export Hub Update

`src/jmap_client.nim` adds:

```nim
import jmap_client/client
export client
```

---

## 11. Design Decisions Summary

| ID | Decision | Alternative considered | Rationale |
|----|----------|----------------------|-----------|
| D4.1 | `JmapClient` as value `object` (not `ref object`) | `ref object` | Value type with `var` parameter passing. Layer 5 allocates on heap via `create()` for C ABI. |
| D4.2 | Constructor does not fetch session (lazy) | Eager fetch | Construction should not perform IO. |
| D4.3 | No DNS SRV — `.well-known/jmap` only | Full RFC 8620 §2.2 | No reference implementation uses DNS SRV. |
| D4.4 | Two-phase body size check: Phase 1 via `contentLength` before body read, Phase 2 via `body.len` after read | Streaming check | Phase 1 prevents OOM on oversized responses. Phase 2 catches absent/inaccurate Content-Length. Streaming check requires replacing `std/httpclient`. |
| D4.5 | TLS detection via substring heuristic | Distinct exception type | `std/httpclient` has no distinct TLS exception. False positives harmless. |
| D4.6 | `ValidationError` from session JSON propagates as-is | Wrap in `ClientError` | Richer context. `ClientError` is for transport/request failures. Layer 5 catches all `CatchableError`. |
| D4.7 | `JsonParsingError` classified as `tekNetwork` | `tekHttpStatus` with 200 | HTTP succeeded, body is invalid JSON. Protocol violation, not an HTTP status error. |
| D4.8 | Problem details on HTTP 200 via `"type"` + missing `"methodResponses"` heuristic | Content-Type check only | Servers often use `application/json` for problem details. `Response` always has `methodResponses`. |
| D4.9 | `validateLimits` in `client.nim` | Separate module or L3 | Called exclusively by `send`. No circular dependency. |
| D4.10 | Manual session staleness (not auto-refresh in `send`) | Auto-refresh | Hidden network request, unpredictable latency. RFC uses SHOULD. Composable tools provided. |
| D4.11 | URI template: caller percent-encodes values (`std/uri.encodeUrl` available) | Library encodes | Common identifiers are base64url-safe. Full RFC 6570 disproportionate. |
| D4.12 | Compile-time hint (`{.hint:}`) for missing `-d:ssl` | `{.warning:}` (blocked by `warningAsError: User`); compile error | `{.hint:}` is informational and non-blocking. `{.warning:}` was the original design but `config.nims` promotes User warnings to errors. |
| D4.13 | Single file `client.nim` | Multiple files | All procs on single type. 300–500 lines. No natural decomposition. |

### Deferred Decisions

| ID | Topic | Disposition | Rationale |
|----|-------|-------------|-----------|
| R14 | Automatic session refresh in `send` | Deferred | Add `sendAndRefresh` when usage patterns emerge. Manual tools suffice. |
| R15 | Connection pooling / keep-alive | Deferred to libcurl | `std/httpclient` already reuses TCP connections for the same hostname/scheme/port within a single client (automatic keep-alive). Multi-client pooling deferred. |
| R16 | Configurable TLS settings | Partially resolvable now; deferred for v1 | `newHttpClient` accepts `sslContext`, and `std/net.newContext` provides full TLS config (cert, CA, ciphers, TLS version). Could expose an optional `SslContext` parameter on `initJmapClient`. Deferred for v1: adds API surface. OpenSSL defaults sufficient for initial release. |
| R17 | Upload/download procs (binary data) | Deferred to §6 | `expandUriTemplate` is ready. Add procs when needed. |
| R18 | Read-only account pre-send validation | Deferred | Requires `Session.accounts` context. Add when entity write methods are used. |

---

## 12. Test Fixtures and Edge Cases

### 12.1 Constructor Validation (Pure, No Network)

| # | Input | Expected | Notes |
|---|-------|----------|-------|
| 1 | Valid HTTPS URL + token | `JmapClient` returned | Happy path |
| 2 | Valid HTTP URL + token | `JmapClient` returned | HTTP allowed (for testing) |
| 3 | Empty `sessionUrl` | `ValidationError` | Non-empty required |
| 4 | URL without scheme prefix | `ValidationError` | Must start with `https://` or `http://` |
| 5 | Empty `bearerToken` | `ValidationError` | Non-empty required |
| 6 | `timeout = -1` (no timeout) | `JmapClient` returned | Valid |
| 7 | `timeout = -2` | `ValidationError` | Must be >= -1 |
| 8 | `maxRedirects = 0` | `JmapClient` returned | No redirects (valid) |
| 9 | `maxResponseBytes = 0` | `JmapClient` returned | No limit (valid) |
| 10 | `discoverJmapClient("example.com", ...)` | URL = `"https://example.com/.well-known/jmap"` | URL construction |
| 11 | `discoverJmapClient("", ...)` | `ValidationError` | Empty domain |
| 12 | `discoverJmapClient("ex/ample", ...)` | `ValidationError` | Path injection |
| 13 | `discoverJmapClient("ex ample", ...)` | `ValidationError` | Whitespace |

### 12.2 Bearer Token Mutation (Pure, No Network)

| # | Input | Expected | Notes |
|---|-------|----------|-------|
| 14 | `setBearerToken("new-token")` | Token updated | Mutator |
| 15 | `setBearerToken("")` | `ValidationError` | Non-empty required |

### 12.3 URI Template Expansion (Pure, No Network)

| # | Input | Expected | Notes |
|---|-------|----------|-------|
| 16 | All variables present | All `{name}` replaced | Happy path |
| 17 | Missing variable | `{name}` left unexpanded | Graceful |
| 18 | Empty value | `{name}` replaced with `""` | Empty substitution |
| 19 | Special chars in value | Characters preserved | No encoding |
| 20 | Multiple occurrences of same variable | All replaced | Global replacement |

### 12.4 Pre-Flight Validation (Pure, No Network)

| # | Input | Expected | Notes |
|---|-------|----------|-------|
| 21 | 0 calls, maxCallsInRequest = 1 | No error | Within limits |
| 22 | 1 call, maxCallsInRequest = 1 | No error | Exactly at limit |
| 23 | 2 calls, maxCallsInRequest = 1 | `ValidationError` | Over limit |
| 24 | `/get` with 5 direct ids, maxObjectsInGet = 10 | No error | Within |
| 25 | `/get` with 11 direct ids, maxObjectsInGet = 10 | `ValidationError` | Over |
| 26 | `/get` with reference ids (JObject) | No error | Skipped |
| 27 | `/get` with null ids | No error | Null = server decides |
| 28 | `/set` with 3+3+3 = 9, maxObjectsInSet = 10 | No error | Within |
| 29 | `/set` with 4+4+3 = 11, maxObjectsInSet = 10 | `ValidationError` | Over |
| 30 | `/set` with reference destroy | Count excludes | Cannot count refs |
| 31 | Empty Request (no calls) | No error | Trivially valid |
| 32 | Mixed `/get` and `/set`, all within limits | No error | Independent checks |
| 33 | Non-standard method name | No per-invocation check | Only suffixes checked |

### 12.5 Session Staleness (Pure, No Network)

| # | Input | Expected | Notes |
|---|-------|----------|-------|
| 34 | Same state | `false` | Not stale |
| 35 | Different state | `true` | Stale |
| 36 | No cached session | `false` | Cannot determine |

### 12.6 Exception Classification (Pure, No Network)

| # | Input | Expected | Notes |
|---|-------|----------|-------|
| 37 | `ref TimeoutError` | `tekTimeout` | Timeout mapping |
| 38 | `ref OSError` with "ssl" in msg | `tekTls` | TLS heuristic |
| 39 | `ref OSError` with "TLS" in msg | `tekTls` | Case-insensitive |
| 40 | `ref OSError` with "certificate" | `tekTls` | Certificate error |
| 41 | `ref OSError` "connection refused" | `tekNetwork` | Non-TLS |
| 42 | `ref IOError` | `tekNetwork` | Protocol error |
| 43 | `ref ValueError` | `tekNetwork` | URL parse error |
| 44 | `ref CatchableError` (other) | `tekNetwork` | Catch-all |

### 12.7 Body Size Enforcement (Pure, No Network)

| # | Input | Expected | Notes |
|---|-------|----------|-------|
| 45 | Body within limit | No error | Within |
| 46 | Body exceeds limit | `ClientError` raised | Over (Phase 2) |
| 47 | Limit = 0 (disabled) | No error | No enforcement |
| 48 | Content-Length exceeds limit | `ClientError` raised | Over (Phase 1, before body read) |
| 49 | Content-Length absent, body exceeds | `ClientError` raised | Phase 1 skipped, Phase 2 catches |
| 50 | Content-Length malformed (non-numeric) | No error from Phase 1 | Falls through to Phase 2 |

### 12.8 Integration Test Scenarios (Require Network or Mock)

| # | Scenario | Expected |
|---|----------|----------|
| 51 | Valid session fetch (GET 200, valid JSON) | `Session` returned and cached |
| 52 | Session URL returns HTTP 404 | `ClientError(cekTransport, tekHttpStatus, 404)` |
| 53 | Session URL returns 301 redirect | Redirect followed, session fetched |
| 54 | Session URL exceeds `maxRedirects` | `ClientError(cekTransport, tekNetwork)` |
| 55 | Session URL returns invalid JSON | `ClientError(cekTransport, tekNetwork)` |
| 56 | Session JSON missing ckCore | `ValidationError` from `parseSession` |
| 57 | Session JSON with empty apiUrl | `ValidationError` from `parseSession` |
| 58 | Session JSON missing downloadUrl variable | `ValidationError` from `parseSession` |
| 59 | API POST returns 200 with valid Response | `Response` returned |
| 60 | API POST returns 200 with problem details | `ClientError(cekRequest)` |
| 61 | API POST returns 400 + `application/problem+json` | `ClientError(cekRequest)` |
| 62 | API POST returns 400 without problem details | `ClientError(cekTransport, tekHttpStatus, 400)` |
| 63 | API POST returns 500 | `ClientError(cekTransport, tekHttpStatus, 500)` |
| 64 | API POST returns 200 with wrong Content-Type | `ClientError(cekTransport)` |
| 65 | Request body exceeds maxSizeRequest | `ValidationError` |
| 66 | Method calls exceed maxCallsInRequest | `ValidationError` |
| 67 | Connection refused | `ClientError(cekTransport, tekNetwork)` |
| 68 | DNS resolution failure | `ClientError(cekTransport, tekNetwork)` |
| 69 | TLS handshake failure | `ClientError(cekTransport, tekTls)` |
| 70 | Socket timeout | `ClientError(cekTransport, tekTimeout)` |
| 71 | Response Content-Length exceeds maxResponseBytes | `ClientError(cekTransport)` (Phase 1, before body read) |
| 72 | Response body exceeds maxResponseBytes (no Content-Length) | `ClientError(cekTransport)` (Phase 2, after body read) |
| 73 | Malformed HTTP status line | `ClientError(cekTransport, tekNetwork)` |
| 74 | Session state changes between requests | `isSessionStale` returns `true` |
| 75 | Bearer token update, then send | New token used |
| 76 | Lazy session fetch on first send | Session fetched, then request sent |
| 77 | Send with cached session | No re-fetch, request sent directly |
| 78 | `refreshSessionIfStale` when stale | Session re-fetched, `true` |
| 79 | `refreshSessionIfStale` when not stale | No fetch, `false` |
| 80 | `urn:ietf:params:jmap:error:unknownCapability` | `ClientError(cekRequest)` with `retUnknownCapability` |
| 81 | `urn:ietf:params:jmap:error:limit` with limit field | `ClientError(cekRequest)` with `retLimit`, `limit` populated |

**Total: 81 enumerated test scenarios.**

---

## 13. Implementation Sequence

0. Verify `newClientError` ref-returning constructors exist in
   `src/jmap_client/errors.nim` (prerequisite — already implemented,
   following `newValidationError` pattern from `validation.nim`).
1. Create `src/jmap_client/client.nim` — copyright header, imports,
   `-d:ssl` warning.
2. Define `JmapClient` type with private fields.
3. Implement `initJmapClient` — parameter validation, `HttpClient`
   construction, header setup.
4. Implement `discoverJmapClient` — domain validation, URL construction,
   delegation to `initJmapClient`.
5. Implement read-only accessors and mutators (`setBearerToken`, `close`).
6. Implement helpers: `expandUriTemplate`, `enforceContentLengthLimit`,
   `enforceBodySizeLimit`, `classifyException`, `classifyHttpResponse`,
   `parseJsonBody`.
7. Implement `fetchSession` — composes IO + pure classification + Layer 2
   deserialisation.
8. Implement `validateLimits` — pure pre-flight checks.
9. Implement `send` — composes all of the above.
10. Implement `isSessionStale` and `refreshSessionIfStale`.
11. Update `src/jmap_client.nim` to import and re-export `client`.
12. Write unit tests — `tests/unit/tclient.nim` covering scenarios 1–50.
13. Run `just ci`.

---

## Appendix: RFC Section Cross-Reference

| Type/Function | RFC 8620 Section | Notes |
|---------------|-----------------|-------|
| `JmapClient` | §1.7 (lines 426–447), §2 (lines 477–721) | Client handle; RFC describes the API model |
| `initJmapClient` | §1.7 (line 429: auth required), §8.2 (auth scheme) | Bearer token |
| `discoverJmapClient` | §2.2 (lines 819–835) | `.well-known/jmap` autodiscovery |
| `fetchSession` | §2 (lines 477–721) | Session resource fetch |
| `send` | §3.1 (lines 854–863), §3.3 (lines 882–943), §3.4 (lines 975–1003) | API request/response |
| `classifyHttpResponse` (problem details) | §3.6.1 (lines 1079–1136) | Request-level errors |
| `validateLimits` | §2 (CoreCapabilities), §3.6.1, §5.1, §5.3 | Pre-flight validation |
| `isSessionStale` | §3.4 (lines 995–999) | Session state comparison |
| `expandUriTemplate` | §2 (lines 679–700), RFC 6570 | URI template expansion |
| `enforceContentLengthLimit` | Client-side (R9); not RFC-specified | Phase 1 response body size cap — pre-read via Content-Length header |
| `enforceBodySizeLimit` | Client-side (R9); not RFC-specified | Phase 2 response body size cap — post-read via actual body length |
| Bearer token auth | §1.7 (line 429), §8.2 | `Authorization: Bearer {token}` |
| Content-Type: `application/json` | §3.1 (lines 860–862) | Required on request; expected on response |
| HTTPS requirement | §1.7 (line 429) | `-d:ssl` compile flag |
| Single-threaded | §3.10 (lines 1535–1539) | Sequential method processing |
