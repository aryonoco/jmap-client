# Layer 4: Transport + Session Discovery — Detailed Design (RFC 8620)

## Preface

This document specifies every type definition, procedure signature, error
mapping, algorithm, and module layout for Layer 4 of the jmap-client
library. It builds upon the decisions made in `00-architecture.md`, the
types defined in `01-layer-1-design.md`, the serialisation infrastructure
established in `02-layer-2-design.md`, and the protocol logic from
`03-layer-3-design.md`, so that implementation is mechanical.

**Scope.** Layer 4 covers: the `JmapClient` type and its construction,
Session discovery (direct URL and `.well-known/jmap`), Session fetching
and caching, API request/response round-trips (serialise `Request`, POST
to `apiUrl`, deserialise `Response`), authentication (Bearer token),
exception-to-Result classification (mapping `std/httpclient` exceptions
to `ClientError` values on the Result error rail), pre-flight validation
(deferred decision R13 from Layer 3), session staleness detection
(`Response.sessionState` vs `Session.state`), Content-Type and HTTP
header management, response body size enforcement (deferred decision R9
from Layer 3), URI template expansion (RFC 6570 Level 1), and the
`-d:ssl` compile flag requirement. Additionally, response dispatch
(`dispatch.nim` — phantom-typed handles and typed extraction from
`Response` envelopes) and pipeline combinators (`convenience.nim` —
opt-in multi-method patterns like query-then-get) are documented here as
closely related modules that bridge Layer 3 protocol logic with Layer 4
IO. The C ABI (Layer 5) is out of scope. Push/EventSource (RFC 8620 §7)
and binary data (§6) are out of scope for the initial release, as
prescribed by architecture decisions §4.5 and §4.6.

**Relationship to prior documents.** `00-architecture.md` records broad
decisions across all 5 layers. This document is the detailed
specification for Layer 4 only. Decisions here resolve — and are
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
primitive/identifier `toJson`/`fromJson` pairs. It imports the Layer 3
`RequestBuilder` for the convenience `send(RequestBuilder)` overload.
The `send` proc operates at the envelope level. Per-invocation response
extraction is handled by `dispatch.nim` (`ResponseHandle[T]`, `get[T]`)
which operates on the `Response` value returned by `send`. Pipeline
combinators in `convenience.nim` compose Layer 3 builder methods with
dispatch extraction for common multi-method patterns.

**Design principles.** Layer 4 is the **imperative shell** — the sole
boundary where IO occurs. The six governing principles apply as follows:

- **Functional Core, Imperative Shell** — Layer 4 IS the imperative
  shell. Within Layer 4, the design maximises the pure surface: pure
  funcs (`validateLimits`, `detectGetLimit`, `detectSetLimit`,
  `detectMaxCalls`, `detectRequestLimits`, `detectClientConfig`,
  `detectDomain`, `isSessionStale`, `resolveAgainstSession`,
  `classifyException`, `enforceBodySizeLimit`, `sizeLimitExceeded`,
  `validationToClientError`, `validationToClientErrorCtx`,
  `serdeToMethodError`) are separated from the IO procs
  (`fetchSession`, `send`, `refreshSessionIfStale`,
  `sendRawHttpForTesting`, `close`). `classifyHttpResponse` composes
  pure classification rules around a single impure step
  (`httpResp.body` lazy stream read) plus a `var string` write-out
  for raw-bytes capture — it is impure but thin. The IO procs are
  thin wrappers that compose pure transforms around a single impure
  step (the HTTP request). Layers 1-3 below are pure by
  convention — no IO, no global state mutation.
- **Immutability by default** — `let` bindings throughout. `var` is used
  only for: (a) the `JmapClient` parameter in IO procs (`fetchSession`,
  `send`, `sendRawHttpForTesting`, `refreshSessionIfStale`, `close`)
  and mutators (`setBearerToken`, `setSessionForTest`); (b) local
  accumulators inside pure funcs (e.g., `var count: int64 = 0` in
  `detectSetLimit`); (c) the `capturedBody: var string` parameter on
  `classifyHttpResponse` that routes raw response bytes into
  `client.lastRawResponseBody`. No module-level mutable state in
  Layer 4 — all mutable state lives inside `JmapClient` objects owned
  by the caller.
- **DRY** — HTTP response classification logic (status codes, Content-Type
  checks, problem details detection, body size enforcement) is written
  once in shared helpers (`classifyHttpResponse`, `classifyException`,
  `tryParseProblemDetails`, `readContentType`) and called from both
  `fetchSession` and `send`. URI template expansion is a single func
  serving download, upload, and event source URLs. Size limit error
  construction is shared via `sizeLimitExceeded`.
- **Total functions** — every proc/func handles all inputs. Pure funcs
  return `Result[T, E]` values — no partial functions, no uncovered code
  paths. Error types (`TransportError`, `RequestError`, `ClientError`,
  `ValidationError`) cover the complete failure domain with exhaustive
  variant enums. `{.push raises: [].}` on every source module provides
  compile-time totality enforcement — every `case` statement on an enum
  is exhaustive, every input domain is covered.
- **Parse, don't validate** — Session JSON is deserialised via Layer 2's
  `Session.fromJson`, which calls Layer 1's `parseSession` for
  structural validation. The result is a well-typed `Session` on the
  ok rail or a `ValidationError` on the error rail. HTTP responses are
  similarly parsed into well-typed `Response` values or structured error
  values. There is no "valid but unchecked" intermediate state.
- **Make illegal states unrepresentable** — `JmapClient` fields are
  module-private (no `*` export marker), preventing callers from
  constructing a client with an empty URL or expired token. The smart
  constructor `initJmapClient` enforces all construction invariants
  and returns `Result[JmapClient, ValidationError]`. Accessor funcs
  provide read-only views. `setBearerToken` re-validates on mutation.
  The `sessionUrl` and `bearerToken` cannot be set to invalid values
  after construction.

**Error handling: Railway-Oriented Programming.** All error types are
plain objects (not `CatchableError` exceptions), carried on the
`Result[T, E]` error rail via nim-results. The `?` operator provides
early-return error propagation. `{.push raises: [].}` is on every source
module — the compiler enforces that no `CatchableError` can escape any
function. Stdlib IO calls that can raise are wrapped in `try/except` +
`{.cast(raises: [CatchableError]).}` to convert exceptions to `Result`
at the IO boundary.

**Railway aliases.** `JmapResult[T]` is defined in `types.nim` as
`Result[T, ClientError]` — the outer railway for transport/request
failures.

**`func` vs `proc`.** `func` for pure functions (accessors, validators,
classifiers, size checks). `proc` for IO (`fetchSession`, `send`,
`close`), impure helpers that read HTTP response bodies
(`classifyHttpResponse`, `readContentType`, `tryParseProblemDetails`,
`parseJsonBody`), and functions that take `proc` callback parameters.

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

Layer 4 introduces IO-related stdlib modules not used in Layers 1-3.
Every adoption and rejection has a concrete reason tied to the project's
compiler constraints and architectural decisions.

### Modules used in Layer 4

| Module | What is used | Where | Rationale |
|--------|-------------|-------|-----------|
| `std/httpclient` | `HttpClient`, `newHttpClient`, `request`, `close`, `HttpMethod`, `newHttpHeaders` | `client.nim` | Decision 4.1A. Synchronous HTTP. The sole network IO dependency. |
| `std/json` | `parseJson`, `$` (serialise `JsonNode` to string), `JsonNode`, `JObject`, `JArray`, `hasKey`, `{}` (nil-safe key access) | `client.nim` | JSON string parsing (`string -> JsonNode`) is the Layer 4 boundary that Layers 1-3 delegate upward. `$` serialises `Request.toJson()` to the HTTP body. `parseJson` is the reverse for responses. `JArray` used in `detectGetLimit` for ids array detection. `{}` used in `detectGetLimit`/`detectSetLimit` for nil-safe access to optional method arguments. |
| `std/uri` | `parseUri`, `combine` | `client.nim` | RFC 3986 §5 reference resolution in `resolveAgainstSession` — relative `apiUrl` values (e.g., Cyrus's `"/jmap/"`) are resolved against the absolute session URL. Absolute `apiUrl` values bypass `combine` entirely. |
| `std/strutils` | `toLowerAscii`, `startsWith`, `endsWith`, `contains`, `Whitespace` | `client.nim`, `errors.nim` | Content-Type case-insensitive matching, method name suffix detection on `inv.rawName` in `detectRequestLimits`, domain validation in `detectDomain`, embedded-newline check in `detectSessionUrl`, TLS message heuristic. URI template expansion folds parsed parts (§7). |
| `std/net` | `TimeoutError`, `SslError` (selective imports) | `errors.nim` | `TimeoutError` for timeout classification in `classifyException`. `SslError` (guarded by `when defined(ssl)`) for direct TLS error classification — `SslError` inherits `CatchableError` directly, not `OSError`, so it requires its own branch. |

### Modules evaluated and rejected

| Module | Reason not used in Layer 4 |
|--------|---------------------------|
| `std/asynchttpclient` | Architecture decision 4.1A: synchronous only. `AsyncHttpClient` creates closure environments that leak under `--mm:arc` (ARC cannot trace closure-captured ref cycles). |
| `std/asyncdispatch` | No async in this design. The synchronous model is appropriate for a C ABI library (architecture §4.1A). |
| `std/options` | Not used. `Opt[T]` from nim-results is the project-wide standard for optional values. `Opt[T]` is `Result[T, void]` sharing the full Result API (`?`, `valueOr:`, `map`, `flatMap`, iterators). |
| `std/uri` | `parseUri` is permissive (never raises) and does not validate URLs, so it adds no safety guarantees beyond a raw string. Session URLs are stored as plain strings and passed directly to `std/httpclient`. `.well-known` URL construction is simple concatenation. Note: `std/uri.encodeUrl(value, usePlus=false)` is available for RFC 3986 percent-encoding — relevant for URI template variable values (see D4.11). |
| `std/re` / `std/pcre` | Content-Type checking uses `startsWith` after `toLowerAscii`. URI template expansion uses `strutils.replace`. No regex needed. |
| `std/streams` | `Response.body` lazily reads from `Response.bodyStream` (a `Stream`) on first access. Stream handling is internal to `std/httpclient`; direct `std/streams` use is not needed. |
| `std/net` (full) | `std/httpclient` handles TLS configuration internally via `newHttpClient(sslContext = ...)`. `std/net.newContext` could configure TLS (cert, CA, ciphers, TLS version) — see deferred decision R16. Not used for TLS configuration in v1. Exception types `TimeoutError` and `SslError` are imported selectively in `errors.nim` — see "Modules used in Layer 4". |
| `std/httpcore` | Re-exported by `std/httpclient`. No direct import needed. |

### Critical Nim findings that constrain the design

| Finding | Impact | Evidence |
|---------|--------|----------|
| `std/httpclient` procs have no `{.raises.}` annotations | Must catch `CatchableError` broadly at the IO boundary via `{.cast(raises: [CatchableError]).}` + `try/except`; convert to `Result` err values | Architecture §4.1A `raises` caveat |
| `std/httpclient` raises: `ProtocolError` (`IOError`), `HttpRequestError` (`IOError`), `ValueError`, `TimeoutError` (from `std/net`), `SslError` (from `std/net`, when `-d:ssl`) | Exception classification must map all five to `TransportError` variants. `SslError` inherits `CatchableError` directly (not `OSError`), requiring its own classification branch. | `httpclient.nim` source, `net.nim:121` |
| `HttpClient` is a `ref object` — ARC-managed | `close()` should be called explicitly for deterministic socket release; destructor runs on scope exit under ARC | `httpclient.nim:617` |
| `HttpClient.headers` field persists across requests | Bearer token set once on construction, sent on every subsequent request without per-request header setup | `httpclient.nim:621` |
| Authorisation header stripped on cross-domain redirects | Correct security behaviour for `.well-known` discovery — the token is not leaked if the server redirects to a different domain | `httpclient.nim:1299-1306` |
| `Response.body` is a lazy proc (not a field) | First call reads `bodyStream.readAll()` and caches the result. Body IO occurs inside `classifyHttpResponse`, not at the `request()` call boundary. Body size enforcement happens after this read (before `parseJson`). | `httpclient.nim:332-338` |
| `Response.code` is a proc with `{.raises: [ValueError, OverflowDefect].}` | Parses `response.status[0..2].parseInt.HttpCode`. Malformed status strings raise `ValueError`. `OverflowDefect` is fatal under `--panics:on` (extremely unlikely for valid HTTP). Must be called inside `try/except ValueError`. Safe to convert result to `int` via `int(code)` for `TransportError.httpStatus`. | `httpclient.nim:298-304`, `httpcore.nim:14` |
| `Response.contentType` returns the Content-Type header value | Returns `headers.getOrDefault("content-type")` — header key lookup is case-insensitive. Returns empty string if header absent, which correctly fails the `startsWith("application/json")` check. | `httpclient.nim:306-310` |
| `newHttpClient` takes `timeout` parameter (milliseconds, `int`) | Per-socket-operation timeout, not per-request. `-1` means no timeout (matches `std/httpclient` convention). Passed through from `JmapClient` constructor. | `httpclient.nim:647-649` |
| `newHttpClient` has a built-in `userAgent` parameter | Default is `"Nim-httpclient/" & NimVersion`. Pass `userAgent` directly instead of adding to headers (see §1.2). | `httpclient.nim:647` |
| `newHttpClient.maxRedirects` assigns to a `Natural` field | Negative values trigger `RangeDefect` (fatal under `--panics:on`). Validation rule 5 in §1.2 prevents this. | `httpclient.nim:622` |
| `HttpClient` reuses TCP connections for same hostname/scheme/port | Multiple `send` calls to `apiUrl` reuse the connection. `close()` releases the socket. Partially addresses deferred decision R15. | `httpclient.nim` |
| `Response.contentLength` returns Content-Length header value (or -1) | Calls `parseInt` internally — can raise `ValueError` for malformed headers. Enables early body size rejection before `response.body` is read (see §2.2). | `httpclient.nim:312-320` |
| `parseJson` raises `JsonParsingError` (a `ValueError` descendant) | Must be caught and converted to `Result` err at the IO boundary | `json.nim:890` |
| `$` on `JsonNode` serialises to compact JSON string | Used to convert `Request.toJson()` to HTTP body. Minimises body size. | `json.nim:344` |

---

## 1. JmapClient Type

### 1.1 Type Definition

**RFC reference:** §1.7 (lines 426-447), §2 (lines 477-721), §3.1
(lines 854-863).

```nim
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
  httpClient: HttpClient          ## std/httpclient handle (ref, ARC-managed)
  sessionUrl: string              ## URL for the JMAP Session resource
  bearerToken: string             ## token attached to the Authorisation header
  authScheme: string              ## auth scheme prefix (e.g. ``"Bearer"``, ``"Basic"``)
  session: Opt[Session]           ## Cached Session; populated on first fetch
  maxResponseBytes: int           ## Response body size cap (R9). 0 = no limit.
  userAgent: string               ## User-Agent header value
  lastRawResponseBody: string     ## Raw bytes of the most recent HTTP
                                  ## response body. Populated unconditionally
                                  ## by ``send`` and ``fetchSession``;
                                  ## consumed only by the test-only
                                  ## ``mcapture.captureIfRequested`` helper.

{.pop.}
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

**Nimalyzer `objects` rule suppression.** The `JmapClient` type has all
private fields by design (§1.1: make illegal states unrepresentable).
The nimalyzer `objects publicfields` rule flags exported types without
public fields. The type definition is wrapped in
`{.push ruleOff: "objects".}` / `{.pop.}` to suppress this diagnostic.

### 1.2 Smart Constructor

**Principle: parse, don't validate.** The constructor validates all
parameters and returns `Result[JmapClient, ValidationError]`. There is
no "partially constructed" state.

```nim
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
  ## ``sessionUrl``: the JMAP Session resource URL. Must be non-empty,
  ##   start with "https://" or "http://", and contain no newline
  ##   characters (header injection prevention).
  ## ``bearerToken``: the credential attached to the Authorization header.
  ##   Must be non-empty. Attached as ``"<authScheme> <bearerToken>"`` on
  ##   every HTTP request.
  ## ``authScheme``: the auth scheme prefix. Default ``"Bearer"`` per
  ##   RFC 8620 §1.7. Set to ``"Basic"`` for legacy Cyrus deployments
  ##   (or any other RFC 7235 scheme name) without rebuilding the
  ##   credential header by hand.
  ## ``timeout``: per-socket-operation timeout in milliseconds. Default
  ##   30 000 (30 seconds). -1 disables the timeout. Must be >= -1.
  ## ``maxRedirects``: maximum HTTP redirects to follow automatically.
  ##   Default 5. Must be >= 0.
  ## ``maxResponseBytes``: maximum response body size in bytes. Responses
  ##   exceeding this limit return err before JSON parsing.
  ##   0 disables the limit. Default 50 000 000 (50 MB). Must be >= 0.
  ## ``userAgent``: the User-Agent header value.
  ##
  ## Does NOT fetch the session — call ``fetchSession()`` explicitly or
  ## let ``send()`` fetch it lazily on first call (Decision D4.2).
  ##
  ## Returns err(ValidationError) if any parameter is invalid.
```

**Validation as a sum-type ADT.** Parameter checks are expressed as a
private sum type `JmapClientViolation` (functional-core pattern 1 — sum
type for internal classification). Detection lives in single-purpose
`detect*` funcs returning `Result[void, JmapClientViolation]`; a single
boundary function `toValidationError(JmapClientViolation)` translates
to the wire `ValidationError` shape (functional-core pattern 5 —
translation at the boundary). Adding a new failure mode is a compile
error in exactly one place.

```nim
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
  jcvEmptyDomain
  jcvDomainWhitespace
  jcvDomainSlash

type JmapClientViolation {.ruleOff: "objects".} = object
  case kind: JmapClientViolationKind
  of jcvEmptySessionUrl, jcvEmptyBearerToken, jcvEmptyDomain,
      jcvHttpHeadersInitFailed, jcvHttpClientInitFailed:
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

func toValidationError(v: JmapClientViolation): ValidationError
```

The detector composition `detectClientConfig` chains the five config
detectors with `?` for first-error short-circuit reporting:

```nim
func detectClientConfig(
    sessionUrl, bearerToken: string,
    timeout, maxRedirects, maxResponseBytes: int,
): Result[void, JmapClientViolation] =
  ?detectSessionUrl(sessionUrl)
  ?detectBearerToken(bearerToken)
  ?detectTimeout(timeout)
  ?detectMaxRedirects(maxRedirects)
  ?detectMaxResponseBytes(maxResponseBytes)
  ok()
```

**Validation rules** (one detector per rule):

1. `detectSessionUrl` — non-empty; starts with `"https://"` or
   `"http://"`; no embedded `\c`/`\L` (preventing header injection that
   would trip a fatal `doAssert` inside `std/httpclient`).
2. `detectBearerToken` — non-empty.
3. `detectTimeout` — must be ≥ -1.
4. `detectMaxRedirects` — must be ≥ 0. Safety-critical:
   `HttpClientBase.maxRedirects` is typed `Natural`
   (`range[0..high(int)]`); assigning a negative value triggers
   `RangeDefect`, which under `--panics:on` aborts the process
   immediately. This detector converts a fatal Defect into a
   recoverable `ValidationError`.
5. `detectMaxResponseBytes` — must be ≥ 0.

`detectDomain` (used by `discoverJmapClient`, see §1.3) covers the
remaining three `jcvDomain*` variants. Stdlib-construction failures
(`jcvHttpHeadersInitFailed`, `jcvHttpClientInitFailed`) are emitted by
the constructor itself when `newHttpHeaders` / `newHttpClient` raise.

**Constructor body.** Detection runs first; on any violation the
single boundary translator produces the `ValidationError`.
`HttpClient` construction is wrapped in `{.cast(raises:
[CatchableError]).}` + `try/except` for `{.push raises: [].}`
compatibility.

```nim
detectClientConfig(sessionUrl, bearerToken, timeout, maxRedirects, maxResponseBytes).isOkOr:
  return err(toValidationError(error))
let headers =
  try:
    {.cast(raises: [CatchableError]).}:
      newHttpHeaders({
        "Authorization": authScheme & " " & bearerToken,
        "Content-Type": "application/json",
        "Accept": "application/json",
      })
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
ok(JmapClient(
  httpClient: httpClient,
  sessionUrl: sessionUrl,
  bearerToken: bearerToken,
  authScheme: authScheme,
  session: Opt.none(Session),
  maxResponseBytes: maxResponseBytes,
  userAgent: userAgent,
  lastRawResponseBody: "",
))
```

**Decision D4.2: Eager vs lazy session fetch.** The constructor does NOT
fetch the session. Construction should not perform IO — `initJmapClient`
creates the handle and validates parameters. The session is fetched
lazily on the first `send()` call, or eagerly via explicit
`fetchSession()`.

### 1.3 Discovery Constructor

**RFC reference:** §2.2 (lines 819-835).

```nim
proc discoverJmapClient*(
    domain: string,
    bearerToken: string,
    authScheme: string = "Bearer",
    timeout: int = 30_000,
    maxRedirects: int = 5,
    maxResponseBytes: int = 50_000_000,
    userAgent: string = "jmap-client-nim/0.1.0",
): Result[JmapClient, ValidationError] =
  ## Creates a JmapClient by constructing the .well-known/jmap URL from
  ## a domain name (RFC 8620 §2.2).
  ##
  ## ``domain``: the JMAP server's domain (e.g., "jmap.example.com").
  ##   The session URL becomes "https://{domain}/.well-known/jmap".
  ##   Must be non-empty, no whitespace, no "/" characters.
  ##
  ## All other parameters forwarded to ``initJmapClient()``.
  ## Returns err(ValidationError) if domain or bearerToken are invalid.
```

**Domain validation.** A single detector `detectDomain` covers the
three domain-shape failure modes via the same `JmapClientViolation`
ADT (§1.2). Each rule maps to a distinct `jcvDomain*` variant:

1. Empty domain → `jcvEmptyDomain`.
2. Domain contains a `strutils.Whitespace` character (prevents header
   injection) → `jcvDomainWhitespace`.
3. Domain contains `'/'` (prevents path injection) → `jcvDomainSlash`.

```nim
func detectDomain(domain: string): Result[void, JmapClientViolation] =
  if domain.len == 0:
    return err(JmapClientViolation(kind: jcvEmptyDomain))
  for c in domain:
    if c in Whitespace:
      return err(JmapClientViolation(kind: jcvDomainWhitespace, domain: domain))
  if '/' in domain:
    return err(JmapClientViolation(kind: jcvDomainSlash, domain: domain))
  ok()
```

On passing validation, the constructor synthesises
`"https://" & domain & "/.well-known/jmap"` and delegates to
`initJmapClient` — the rest of the parameter validation runs there.

**Decision D4.3: No DNS SRV.** Per architecture §4.2. No reference
JMAP client implements DNS SRV. `.well-known` covers all practical
deployments.

### 1.4 Read-Only Accessors

```nim
func session*(client: JmapClient): Opt[Session]
func sessionUrl*(client: JmapClient): string
func bearerToken*(client: JmapClient): string
func authScheme*(client: JmapClient): string
func lastRawResponseBody*(client: JmapClient): string
```

These return immutable copies. The caller cannot mutate the client's
internal state through these accessors. `lastRawResponseBody` is the
test-only reach-in for `mcapture.captureIfRequested` — production
callers should consume the typed `Response` returned by `send`. It is
empty before the first `send` or `fetchSession` call.

### 1.5 Mutators

```nim
proc setBearerToken*(
    client: var JmapClient, token: string
): Result[void, ValidationError] =
  ## Updates the bearer token. Subsequent requests use the new token.
  ## Also updates the Authorization header on the underlying HttpClient
  ## using the client's stored ``authScheme`` (so the scheme prefix
  ## chosen at construction is preserved verbatim across rotations).
  ##
  ## Returns err(ValidationError) if token is empty.

proc close*(client: var JmapClient) =
  ## Closes the underlying HTTP connection. Releases the socket
  ## immediately. Idempotent — safe to call multiple times.
  ## Under ARC, the HttpClient ref is also released when the
  ## JmapClient goes out of scope, but ``close()`` is explicit.
  ##
  ## Recommended pattern: ``defer: client.close()`` ensures socket
  ## release even if an error occurs.
  ##
  ## Uses ``{.cast(raises: []).}`` to suppress the compiler warning
  ## from ``HttpClient.close()``'s missing raises annotation.
```

### 1.6 Test-Only Surface

Two procs exist solely to support live integration tests:

```nim
proc setSessionForTest*(client: var JmapClient, session: Session) =
  ## Injects a cached session for testing purposes. Enables pure tests
  ## of ``isSessionStale`` without requiring network IO.

proc sendRawHttpForTesting*(
    client: var JmapClient, body: string
): JmapResult[envelope.Response] {.used.}
  ## Test-only escape hatch — POSTs ``body`` verbatim to the cached
  ## session's ``apiUrl``. Bypasses ``Request.toJson`` and the
  ## pre-flight ``validateLimits`` check so adversarial wire shapes
  ## (oversized bodies, hand-crafted invocations, malformed JSON)
  ## reach the server without being rejected client-side. The
  ## response still flows through ``classifyHttpResponse`` so HTTP-
  ## error classification, RFC 7807 problem-details detection, and
  ## ``lastRawResponseBody`` capture are identical to ``send``. The
  ## ``ForTesting`` suffix and ``{.used.}`` pragma make the test-only
  ## intent visible at every call site and silence nimalyzer's
  ## unused-export rule when no test file references it yet.
```

---

## 2. HTTP Response Classification (DRY)

**Principle: DRY.** The classification logic for HTTP responses is
shared between `fetchSession` (GET) and `send` (POST). It is factored
into helpers that compose with the IO procs. Several of these helpers
live in `errors.nim` (where they operate on error types) rather than
`client.nim`.

### 2.1 RequestContext Enum (errors.nim)

```nim
type RequestContext* = enum
  ## Identifies the JMAP endpoint being processed. Used in error messages
  ## by size-limit and HTTP-response classification functions.
  rcSession = "session"
  rcApi = "api"
```

The string backing values allow `$context` to produce human-readable
error messages (e.g., `"session Content-Length exceeds limit"`).

### 2.2 Exception Classification (errors.nim, Pure)

Maps `std/httpclient` exceptions to `ClientError(cekTransport)`. This
is a pure transform — no IO, no mutation. Lives in `errors.nim` because
it constructs error types and imports `std/net` for `TimeoutError` and
`SslError`.

```nim
func isTlsRelatedMsg(msg: string): bool =
  ## Heuristic: checks whether an OSError message indicates a TLS failure.
  ## OpenSSL surfaces TLS errors as OSError with keywords in the message
  ## (D4.5). False positives are harmless — the error is still a transport
  ## failure and ``msg`` carries the actual underlying error.
  let lower = msg.toLowerAscii
  "ssl" in lower or "tls" in lower or "certificate" in lower

func classifyException*(e: ref CatchableError): ClientError =
  ## Maps std/httpclient exceptions to ClientError(cekTransport).
  ## Pure: no IO, no side effects. Exhaustive over known exception types.
  ##
  ## Classification rules (total — every CatchableError is handled):
  ## - TimeoutError           -> tekTimeout
  ## - SslError               -> tekTls  (when defined(ssl); direct type match)
  ## - OSError with TLS msg   -> tekTls  (heuristic, see D4.5)
  ## - OSError (other)        -> tekNetwork
  ## - IOError                -> tekNetwork (includes ProtocolError,
  ##                            HttpRequestError, redirect exhaustion)
  ## - ValueError             -> tekNetwork (e.g., unparseable URL)
  ## - Other CatchableError   -> tekNetwork (defensive catch-all)
  let te =
    if e of ref TimeoutError:
      transportError(tekTimeout, e.msg)
    elif (when defined(ssl): e of ref SslError else: false):
      transportError(tekTls, e.msg)
    elif e of ref OSError:
      if isTlsRelatedMsg(e.msg):
        transportError(tekTls, e.msg)
      else:
        transportError(tekNetwork, e.msg)
    elif e of ref IOError:
      transportError(tekNetwork, e.msg)
    elif e of ref ValueError:
      transportError(tekNetwork, "protocol error: " & e.msg)
    else:
      transportError(tekNetwork, "unexpected error: " & e.msg)
  clientError(te)
```

`classifyException` is exported (`*`) for testability and consumer use
(e.g., consumers wrapping additional IO around the client).

`isTlsRelatedMsg` is a module-private helper extracted to keep
`classifyException` within the nimalyzer complexity limit.

**Decision D4.5: TLS detection — two-tier approach.** `std/net` defines
`SslError` (inheriting `CatchableError` directly, NOT `OSError`) which
is raised during TLS handshake failures, certificate errors, and context
creation failures. `std/httpclient` does not catch or wrap `SslError` —
it propagates directly to callers. The first tier matches `SslError` by
type (guarded by `when defined(ssl)` since `SslError` is only defined
when `-d:ssl` is active). The second tier is a heuristic for `OSError`
with messages containing "ssl", "tls", or "certificate"
(case-insensitive) — covering cases where OpenSSL errors surface as
`OSError` rather than `SslError`. False positives are harmless — the
error is still classified as a transport failure, and `te.msg` carries
the actual underlying error.

### 2.3 Size Limit Error Constructor (errors.nim, Pure)

```nim
func sizeLimitExceeded*(
    context: RequestContext, what: string, actual, limit: int
): ClientError =
  ## Constructs a ClientError for a size-limit violation. Shared by
  ## body-length and Content-Length enforcement.
  clientError(transportError(tekNetwork,
    $context & " " & what & " exceeds limit: " &
    $actual & " bytes > " & $limit & " byte limit"))
```

### 2.4 Body Size Enforcement

Two-phase check: Phase 1 rejects before reading the body (using the
Content-Length header); Phase 2 rejects after reading (using the actual
body length). Together they prevent both OOM on oversized responses and
bypass via missing/inaccurate Content-Length.

**Phase 2 (errors.nim, pure):**

```nim
func enforceBodySizeLimit*(
    maxResponseBytes: int, body: string, context: RequestContext
): Result[void, ClientError] =
  ## Phase 2: post-read rejection via actual body length. Catches cases
  ## where Content-Length was absent, inaccurate, or not checked.
  ## No-op when maxResponseBytes == 0 (no limit). Pure — no IO.
  ## Exported for testability.
  if maxResponseBytes > 0 and body.len > maxResponseBytes:
    return err(sizeLimitExceeded(context, "response body", body.len, maxResponseBytes))
  ok()
```

**Phase 1 (client.nim, impure — reads headers via stdlib):**

```nim
proc enforceContentLengthLimit(
    maxResponseBytes: int, httpResp: httpclient.Response, context: RequestContext
): Result[void, ClientError] =
  ## Phase 1: early rejection via Content-Length header, before the body
  ## is read into memory. No-op when maxResponseBytes == 0 (no limit)
  ## or Content-Length is absent/unparseable.
  if maxResponseBytes > 0:
    let cl =
      try:
        {.cast(raises: [CatchableError]).}:
          httpResp.contentLength
      except CatchableError:
        -1  # malformed Content-Length — fall through to Phase 2
    if cl > maxResponseBytes:
      return err(sizeLimitExceeded(context, "Content-Length", cl, maxResponseBytes))
  ok()
```

**Decision D4.4: Body size check timing.** Phase 1 checks
`contentLength` from the response headers before `response.body` is
called, preventing a multi-GB response from being read into memory.
`contentLength` (`httpclient.nim:312-320`) calls `parseInt` internally
and can raise — caught via `{.cast(raises: [CatchableError]).}` and
treated as "unknown length" (fall through to Phase 2). Phase 2 checks
`body.len` after the full read but before `parseJson`, preventing the
expensive JSON tree allocation. A streaming size limit during the read
itself would require replacing `std/httpclient` — deferred to the
libcurl upgrade path (architecture §4.1A fallback).

### 2.5 Content-Type Reader (client.nim)

```nim
proc readContentType(httpResp: httpclient.Response): string =
  ## Reads the Content-Type header, returning empty string on failure.
  ## Uses ``{.cast(raises: [CatchableError]).}`` for ``{.push raises: [].}``
  ## compatibility.
  try:
    {.cast(raises: [CatchableError]).}:
      httpResp.contentType.toLowerAscii
  except CatchableError:
    ""
```

### 2.6 Problem Details Parser (client.nim)

```nim
proc tryParseProblemDetails(body: string): Opt[ClientError] =
  ## Attempts to parse RFC 7807 problem details from a response body.
  ## Returns Opt.some(ClientError) on success, none on any failure.
  ## Non-panicking: catches all exceptions via cast.
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
```

### 2.7 HTTP Response Classification (client.nim)

The classification logic for HTTP responses. The IO procs
(`fetchSession`, `send`, `sendRawHttpForTesting`) call
`std/httpclient.request` and pass the result to this proc, along with
a `var string` slot into which the raw body bytes are written so that
fixture-capture tests can persist them without losing byte fidelity.
This proc is NOT pure — `httpResp.body` lazily reads from
`bodyStream` on first access.

```nim
proc classifyHttpResponse(
    maxResponseBytes: int,
    httpResp: httpclient.Response,
    context: RequestContext,
    capturedBody: var string,
): JmapResult[JsonNode] =
  ## Classifies an HTTP response and parses the JSON body. Returns the
  ## parsed ``JsonNode`` on the ok rail on 2xx with correct Content-Type.
  ## Returns err otherwise.
  ##
  ## ``context``: ``rcSession`` or ``rcApi`` — used in error messages.
  ## ``capturedBody``: write-only sink for the raw body bytes. Populated
  ##   immediately after ``httpResp.body`` is read (before any 4xx/5xx
  ##   classification), so any subsequent return path leaves the bytes
  ##   intact for ``mcapture.captureIfRequested`` to persist.
  ##
  ## Classification table (total — every status code range handled):
  ##   2xx + application/json       -> ok(JsonNode)
  ##   2xx + other Content-Type     -> err(tekNetwork)
  ##   4xx/5xx + problem details    -> err(cekRequest via RequestError)
  ##   4xx/5xx + no problem details -> err(tekHttpStatus)
  ##   Other non-2xx (1xx/3xx)      -> err(tekHttpStatus)
  ##
  ## Note: ``httpResp.body`` lazily reads from ``bodyStream.readAll()``
  ## on first access (IO), and ``httpResp.code`` parses the status
  ## string and can raise.
  let code =
    try:
      {.cast(raises: [CatchableError]).}:
        httpResp.code
    except CatchableError:
      let te = transportError(tekNetwork,
        "malformed HTTP status from " & $context & ": " & httpResp.status)
      return err(clientError(te))

  # Phase 1 body size enforcement (R9) — reject before reading body
  ?enforceContentLengthLimit(maxResponseBytes, httpResp, context)

  let body =
    try:
      {.cast(raises: [CatchableError]).}:
        httpResp.body  # lazy: reads bodyStream on first access
    except CatchableError:
      return err(clientError(transportError(tekNetwork, "failed to read body")))
  capturedBody = body

  # Phase 2 body size enforcement (R9) — reject after reading body
  ?enforceBodySizeLimit(maxResponseBytes, body, context)

  if code.is4xx or code.is5xx:
    # Attempt to parse as RFC 7807 problem details
    let ct = readContentType(httpResp)
    if ct.startsWith("application/problem+json") or
       ct.startsWith("application/json"):
      for ce in tryParseProblemDetails(body):
        return err(ce)
    # Generic HTTP status error (no problem details, or parsing failed)
    let te = httpStatusError(int(code),
      "HTTP " & $int(code) & " from " & $context)
    return err(clientError(te))

  # Guard: non-2xx that is not 4xx/5xx (e.g. 1xx, 3xx).
  # In practice std/httpclient handles redirects and 1xx internally,
  # so this should never fire — but total functions cover all inputs.
  if not code.is2xx:
    let te = httpStatusError(int(code),
      "unexpected HTTP " & $int(code) & " from " & $context)
    return err(clientError(te))

  # Check Content-Type on 2xx success
  let ct = readContentType(httpResp)
  if not ct.startsWith("application/json"):
    let te = transportError(tekNetwork,
      "unexpected Content-Type from " & $context & ": " & ct)
    return err(clientError(te))

  parseJsonBody(body, context)
```

**Content-Type checking.** Case-insensitive prefix matching via
`readContentType` (which calls `toLowerAscii`). This correctly handles
`application/json; charset=utf-8` and similar variants with parameters.
For problem details, also accepts `application/problem+json` (RFC 7807).

### 2.8 JSON Body Parsing (client.nim, DRY)

Shared helper for parsing a JSON response body. Eliminates duplicated
error handling in `fetchSession` and `send`.

```nim
proc parseJsonBody(
    body: string, context: RequestContext
): Result[JsonNode, ClientError] =
  ## Parses a response body as JSON. Returns err if the body is not valid
  ## JSON.
  ##
  ## ``context``: ``rcSession`` or ``rcApi`` — used in error messages.
  try:
    {.cast(raises: [CatchableError]).}:
      ok(parseJson(body))
  except CatchableError as e:
    let te = transportError(tekNetwork,
      "invalid JSON in " & $context & " response: " & e.msg)
    err(clientError(te))
```

### 2.9 Validation-to-Client Error Bridge (errors.nim, Pure)

DRY helpers that map `ValidationError` (the construction railway) to
`ClientError` (the outer railway). Used by `validateLimits` (which
returns `Result[void, ValidationError]`), and by `fetchSession`/`send`
after `toValidationError(sv, ...)` has collapsed a Layer 2
`SerdeViolation` to the wire `ValidationError` shape.

```nim
func validationToClientError*(ve: ValidationError): ClientError =
  ## Bridges the construction railway (ValidationError) to the outer railway
  ## (ClientError). For use with ``mapErr`` when a Layer 1 validation failure
  ## must be surfaced as a transport error.
  clientError(transportError(tekNetwork, ve.message))

func validationToClientErrorCtx*(ve: ValidationError, context: string): ClientError =
  ## Bridges with a context prefix prepended to the error message.
  clientError(transportError(tekNetwork, context & ve.message))
```

`validationToClientErrorCtx` adds a prefix (e.g., `"invalid session: "`,
`"invalid response: "`) for contextual error messages.

---

## 3. Session Discovery and Fetching

### 3.1 fetchSession Procedure

**RFC reference:** §2 (lines 477-721), §2.1 (lines 735-817), §2.2
(lines 819-835).

```nim
proc fetchSession*(client: var JmapClient): JmapResult[Session] =
  ## Fetches the JMAP Session resource from the server and caches it.
  ##
  ## This is the sole IO proc for session management. It composes:
  ## 1. IO: HTTP GET to sessionUrl (impure — the shell).
  ## 2. Classify: classifyHttpResponse (status, content-type, body size;
  ##    raw bytes captured into client.lastRawResponseBody).
  ## 3. Parse: parseJsonBody embedded in classifyHttpResponse.
  ## 4. Deserialise: Session.fromJson -> Result[Session, SerdeViolation].
  ## 5. Map err: SerdeViolation -> ValidationError -> ClientError via
  ##    a two-stage mapErr (toValidationError(sv, "Session") then
  ##    validationToClientErrorCtx(_, "invalid session: ")).
  ## 6. Cache: store the Session on the client.
  ##
  ## Re-fetching: calling fetchSession() replaces the cached session.
  ## This is the session refresh mechanism (§6).
  ##
  ## Returns err for network, TLS, timeout, HTTP errors, RFC 7807
  ## problem details, or structurally invalid session JSON.
```

**Decision D4.6: Serde violation mapping.** Layer 2 deserialisation
returns `Result[T, SerdeViolation]` — the structured serde error type
(`serde.SerdeViolation`) carries an RFC 6901 path plus a kind-tagged
payload. `fetchSession` chains two translators via `mapErr`:
`toValidationError(sv, "Session")` collapses the `SerdeViolation` to a
wire `ValidationError` (sole serde→validation boundary), then
`validationToClientErrorCtx(ve, "invalid session: ")` lifts it onto
the outer railway with the context prefix. The HTTP round-trip
succeeded but the server's response content violates the Session
schema — classified as `tekNetwork` (transport-level protocol error).
This keeps `JmapResult[Session]` uniform: `ClientError` is always the
error rail at Layer 4.

### 3.2 fetchSession Algorithm

```nim
proc fetchSession*(client: var JmapClient): JmapResult[Session] =
  # Step 1: IO boundary — HTTP GET (the only impure line)
  let httpResp =
    try:
      {.warning[Uninit]: off.}
      {.cast(raises: [CatchableError]).}:
        client.httpClient.request(client.sessionUrl, httpMethod = HttpGet)
    except CatchableError as e:
      return err(classifyException(e))

  # Step 2-3: Classification + JSON parse (§2.7, §2.8). The raw bytes
  # land in client.lastRawResponseBody for fixture capture.
  let jsonNode = ?classifyHttpResponse(
    client.maxResponseBytes, httpResp, rcSession, client.lastRawResponseBody)

  # Step 4-5: Deserialisation + two-stage error mapping
  let session = Session.fromJson(jsonNode).mapErr(
      proc(sv: SerdeViolation): ClientError =
        validationToClientErrorCtx(
          toValidationError(sv, "Session"), "invalid session: "
        )
    )
  let s = ?session

  # Step 6: Cache (mutation through var parameter)
  client.session = Opt.some(s)
  ok(s)
```

**`{.warning[Uninit]: off.}` pragma.** Suppresses a spurious compiler
warning from `std/httpclient.request` where the compiler cannot prove
the return value is initialised on all paths through the stdlib code.

---

## 4. API Request/Response Flow

### 4.1 The `send` Procedure

**RFC reference:** §3.1 (lines 854-863), §3.3 (lines 882-943), §3.4
(lines 975-1003).

```nim
proc send*(client: var JmapClient, request: Request): JmapResult[envelope.Response] =
  ## Serialises a JMAP Request, POSTs to the server's apiUrl, and
  ## deserialises the Response.
  ##
  ## Lazily fetches the session on first call if not yet cached.
  ## Does NOT automatically refresh a stale session (D4.10).
  ##
  ## Returns err for transport/request failures, limit violations,
  ## or invalid response JSON.
```

### 4.2 Detailed Algorithm

**Step 1: Ensure session.**

```nim
if client.session.isNone:
  discard ?client.fetchSession()
let sessionOpt = client.session
let session = sessionOpt.valueOr:
  return err(clientError(transportError(
    tekNetwork, "session unavailable after fetchSession succeeded")))
let coreCaps = session.coreCapabilities()
```

If `fetchSession` returns err, the `?` operator propagates it. The
let-bind into an immutable `sessionOpt` picks the non-`var` `valueOr`
overload; under `--mm:arc`/`--panics:on`, `.get()` on an `Opt` would
route through `withAssertOk`, raising `ResultDefect` and triggering
`rawQuit(1)` with no unwinding — catastrophic at the FFI boundary. The
`valueOr:` block produces a defined error path instead.

**Step 2: Pre-flight validation (R13).**

```nim
?validateLimits(request, coreCaps).mapErr(validationToClientError)
```

Pure func (§5). Returns `Result[void, ValidationError]` which is
mapped to `ClientError` via `mapErr` using the DRY bridge function
(§2.9) to match the `JmapResult` outer railway, then propagated
with `?`.

**Step 3: Serialise.**

```nim
let jsonNode = request.toJson()   # Layer 2: Request -> JsonNode
let body = $jsonNode               # std/json: JsonNode -> string
```

**Step 4: Check serialised size against maxSizeRequest.**

**RFC reference:** §2 (line 528): `maxSizeRequest` — "The maximum
size, in octets, that the server will accept for a single request to
the API endpoint."

**L3 reference:** §16.3 — "requires the serialised JSON byte length,
which is only available after `Request.toJson()` is converted to bytes.
This is a Layer 4 concern."

The check uses the `RequestLimitViolation` ADT (§5) so the wire message
shape matches the in-process `validateLimits` violations:

```nim
let maxSize = int64(coreCaps.maxSizeRequest)
if body.len > int(maxSize):
  let ve = toValidationError(RequestLimitViolation(
    kind: rlvMaxSizeRequest, actualSize: body.len, maxSize: maxSize))
  return err(validationToClientError(ve))
```

**Step 5: IO boundary — HTTP POST.**

```nim
let httpResp =
  try:
    {.warning[Uninit]: off.}
    {.cast(raises: [CatchableError]).}:
      client.httpClient.request(
        resolveAgainstSession(client.sessionUrl, session.apiUrl),
        httpMethod = HttpPost,
        body = body)
  except CatchableError as e:
    return err(classifyException(e))
```

Headers are set on `client.httpClient.headers` from construction.
`resolveAgainstSession` (a private helper) performs RFC 3986 §5
resolution of `session.apiUrl` against `client.sessionUrl`: when
`apiUrl` carries a scheme it is returned unchanged, otherwise
`std/uri.combine(parseUri(sessionUrl), parseUri(apiUrl))` resolves the
relative reference. Cyrus 3.12.2 (`imap/jmap_api.c`) emits relative
references like `"/jmap/"`; RFC 8620 §2 does not explicitly mandate
absolute form, so the client is Postel-tolerant on receive.

**Step 6: Classify HTTP response and parse JSON.**

```nim
let respJson = ?classifyHttpResponse(
  client.maxResponseBytes, httpResp, rcApi, client.lastRawResponseBody)
```

Reuses the shared helper from §2.7 (DRY). Raw body bytes are written
to `client.lastRawResponseBody` for fixture-capture tests.

**Decision D4.7: `JsonParsingError` classification.** Classified as
`tekNetwork`, not `tekHttpStatus`. The HTTP transport succeeded but the
body is not valid JSON — a server encoding error analogous to a protocol
violation. `tekHttpStatus` implies a meaningful status code, which is
inappropriate for a parsing failure.

**Step 8: Problem details detection on HTTP 200.**

**RFC reference:** §3.6.1 (lines 1079-1136). Request-level errors
may be returned with HTTP 200 status.

```nim
if respJson.kind == JObject and respJson.hasKey("type") and
    not respJson.hasKey("methodResponses"):
  for reqErr in RequestError.fromJson(respJson).optValue:
    return err(clientError(reqErr))
```

Uses `optValue` to bridge `Result[RequestError, _]` to
`Opt[RequestError]` (discards error details), then the `for val in opt:`
idiom for conditional consumption.

**Decision D4.8: Problem details on HTTP 200.** Heuristic: if the
top-level JSON object has a `"type"` field but lacks
`"methodResponses"`, it is a problem details response. This is safe
because every valid JMAP Response has `methodResponses` (RFC §3.4,
required). Alternative considered: check Content-Type for
`application/problem+json` — rejected because many servers return
problem details with `application/json` Content-Type.

**Note:** The step numbering deliberately skips step 7 — Steps 1-6
cover everything from session resolution through HTTP classification;
Step 8 picks up at the first transformation of the parsed JSON.

**Step 9: Deserialise as JMAP Response.**

```nim
envelope.Response.fromJson(respJson).mapErr(
  proc(sv: SerdeViolation): ClientError =
    validationToClientErrorCtx(
      toValidationError(sv, "Response"), "invalid response: "
    )
)
```

`SerdeViolation` from Layer 2 is collapsed to a wire `ValidationError`
via `toValidationError(sv, "Response")`, then lifted onto the outer
railway via the DRY bridge function (§2.9) — mirroring the
`fetchSession` two-stage mapping.

### 4.3 Convenience Overloads

**`send(RequestBuilder)` — builder bridge.**

```nim
proc send*(
    client: var JmapClient, builder: RequestBuilder
): JmapResult[envelope.Response] =
  ## Convenience: builds the request and sends it in one step.
  ## Equivalent to ``client.send(builder.build())``.
  ## This is the imperative shell boundary where the functional core
  ## (builder) meets IO.
  client.send(builder.build())
```

This overload bridges the Layer 3 `RequestBuilder` directly to the
Layer 4 IO boundary, eliminating the need for callers to call
`build()` separately.

**Pipeline combinators (`convenience.nim`) — opt-in multi-method
patterns.**

`convenience.nim` provides higher-level pipeline combinators that
compose Layer 3 builder methods with response dispatch extraction.
This module is explicitly NOT re-exported by `protocol.nim` or
`src/jmap_client.nim` — consumers opt in via
`import jmap_client/convenience`. This physical separation keeps the
core API surface in `builder.nim` and `dispatch.nim` frozen while
providing ergonomic patterns for common JMAP workflows (Decision D4.14).

**Naming convention.** Pipeline combinators use the `add*` prefix
(following the builder threading convention) and return
`(RequestBuilder, <Handles>)` tuples — mirroring the per-method
`addQuery`/`addGet`/`addChanges` shape from `builder.nim`. The builder
flows through the combinator immutably; no `var` mutation. Paired
extraction uses `getBoth` (always exactly two handles).

Types and combinators:

```nim
type QueryGetHandles*[T] = object
  ## Paired phantom-typed handles from a query-then-get pipeline.
  query*: ResponseHandle[QueryResponse[T]]
  get*: ResponseHandle[GetResponse[T]]

template addQueryThenGet*[T](
    b: RequestBuilder, accountId: AccountId
): (RequestBuilder, QueryGetHandles[T])
  ## Adds Foo/query + Foo/get with automatic result reference wiring.
  ## The get's ``ids`` parameter references the query's ``/ids`` path.
  ##
  ## Implemented as a template so filter and sort type defaults
  ## resolve at the caller's instantiation site (the underlying
  ## ``addQuery[T]`` template performs that resolution via
  ## ``filterType(T)`` and ``Comparator``).
  ##
  ## Implicit decisions:
  ## - Reference path is always ``/ids`` (``rpIds``)
  ## - Both calls use the same ``accountId`` (no cross-account)
  ## - No filter, sort, or properties constraints applied
  ## - Response method name derived from ``queryMethodName(T)``

type ChangesGetHandles*[T] = object
  ## Paired phantom-typed handles from a changes-then-get pipeline.
  changes*: ResponseHandle[ChangesResponse[T]]
  get*: ResponseHandle[GetResponse[T]]

func addChangesToGet*[T](
    b: RequestBuilder,
    accountId: AccountId,
    sinceState: JmapState,
    maxChanges: Opt[MaxChanges] = Opt.none(MaxChanges),
    properties: Opt[seq[string]] = Opt.none(seq[string]),
): (RequestBuilder, ChangesGetHandles[T])
  ## Adds Foo/changes + Foo/get with automatic result reference from
  ## ``/created``. Only newly created IDs are fetched — for updated IDs,
  ## use the core API with ``updatedRef``. Internally calls
  ## ``addChanges[T, ChangesResponse[T]]`` rather than
  ## ``changesResponseType(T)``: ``createdRef`` is defined only over
  ## ``ResponseHandle[ChangesResponse[T]]`` because its contract is the
  ## RFC 8620 §5.2 ``/created`` field, not any entity-specific extension.

type QueryGetResults*[T] = object
  ## Paired extraction results from a query-then-get pipeline.
  query*: QueryResponse[T]
  get*: GetResponse[T]

func getBoth*[T](
    resp: Response, handles: QueryGetHandles[T]
): Result[QueryGetResults[T], MethodError]
  ## Extracts both query and get responses, failing on the first error.
  ## Composes naturally with the ``?`` operator.

type ChangesGetResults*[T] = object
  ## Paired extraction results from a changes-then-get pipeline.
  changes*: ChangesResponse[T]
  get*: GetResponse[T]

func getBoth*[T](
    resp: Response, handles: ChangesGetHandles[T]
): Result[ChangesGetResults[T], MethodError]
  ## Extracts both changes and get responses, failing on the first error.
```

For queries with filters, sorting, or properties constraints, use the
core builder API directly (`addQuery[T, C, S]` + `idsRef` + `addGet[T]`).

---

## 5. Pre-Flight Validation

**L3 reference:** §16 — "Session Limit Pre-Flight Validation".

**RFC reference:** §2 (CoreCapabilities), §3.6.1 (limit error), §5.1
(`requestTooLarge` for /get), §5.3 (`requestTooLarge` for /set).

**Principle: total function.** `validateLimits` handles all inputs —
unknown method names are silently skipped (only `/get` and `/set`
suffixes are checked, dispatched on the wire-form `inv.rawName`).
Reference arguments (`{"resultOf": ...}`-shaped values) are
uncountable and explicitly skipped.

### 5.1 Limit Violation ADT

Limit checks share a private sum type — functional-core pattern 1
(named ADT for internal classification) plus pattern 5 (single
boundary translator to the wire shape). Adding a new limit kind is a
compile error in exactly one place.

```nim
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

func toValidationError(v: RequestLimitViolation): ValidationError
  ## Sole domain-to-wire translator for ``RequestLimitViolation``.
```

`rlvMaxSizeRequest` is the same ADT variant used by `send` step 4
(§4.2) for the post-serialisation size check — keeping the wire
message shape uniform across the in-process and serialised checks.

### 5.2 Per-Invocation Detectors (Pure)

Three single-purpose detectors, each returning `Result[void,
RequestLimitViolation]`:

```nim
func detectGetLimit(
    inv: Invocation, maxGet: int64
): Result[void, RequestLimitViolation] =
  ## Checks a /get invocation's direct ids count against maxObjectsInGet.
  ## Reference ids (JObject) and absent/null ids are silently skipped.
  if inv.arguments.isNil:
    return ok()
  let idsNode = inv.arguments{"ids"}
  if not idsNode.isNil and idsNode.kind == JArray:
    if int64(idsNode.len) > maxGet:
      return err(RequestLimitViolation(
        kind: rlvMaxObjectsInGet,
        getMethodName: inv.rawName,
        actualGetIds: idsNode.len,
        maxGet: maxGet))
  ok()

func detectSetLimit(
    inv: Invocation, maxSet: int64
): Result[void, RequestLimitViolation] =
  ## Checks a /set invocation's combined create + update + destroy count
  ## against maxObjectsInSet. Reference destroy (JObject) is silently
  ## skipped.
  ## (counts create JObject, update JObject, destroy JArray entries)

func detectMaxCalls(
    request: Request, maxCalls: int64
): Result[void, RequestLimitViolation] =
  ## Total method-call count (top-level only — batching across HTTP
  ## requests is a separate concern) against maxCallsInRequest.
```

The composition `detectRequestLimits` chains the three detectors with
`?` for first-error short-circuit reporting. Per-invocation dispatch
matches the wire-form name (`inv.rawName`) — `inv.name` returns the
parsed `MethodName` enum, which has no `endsWith` and would lose
unrecognised method names to `mnUnknown`.

```nim
func detectRequestLimits(
    request: Request, caps: CoreCapabilities
): Result[void, RequestLimitViolation] =
  ?detectMaxCalls(request, int64(caps.maxCallsInRequest))
  let maxGet = int64(caps.maxObjectsInGet)
  let maxSet = int64(caps.maxObjectsInSet)
  for inv in request.methodCalls:
    if inv.rawName.endsWith("/get"):
      ?detectGetLimit(inv, maxGet)
    elif inv.rawName.endsWith("/set"):
      ?detectSetLimit(inv, maxSet)
  ok()
```

### 5.3 validateLimits Public Surface

```nim
func validateLimits*(
    request: Request, caps: CoreCapabilities
): Result[void, ValidationError] =
  ## Pre-flight validation of a built Request against server-advertised
  ## CoreCapabilities limits. Pure — no IO, no mutation. Returns err
  ## describing the first violation, projected to the wire
  ## ``ValidationError`` shape.
  ##
  ## Checks:
  ## - len(request.methodCalls) <= maxCallsInRequest
  ## - Per /get call: direct ids count <= maxObjectsInGet
  ##   (skipped for reference ids, null ids, absent arguments)
  ## - Per /set call: create + update + direct destroy <= maxObjectsInSet
  ##   (skipped for reference destroy, absent arguments)
  ##
  ## NOT checked here (handled separately):
  ## - maxSizeRequest (requires serialised bytes — ``send`` step 4
  ##   uses ``rlvMaxSizeRequest`` from the same ADT)
  ## - maxConcurrentRequests (transport-level concurrency)
  ## - Read-only account prevention (requires Session context)
  detectRequestLimits(request, caps).isOkOr:
    return err(toValidationError(error))
  ok()
```

**Decision D4.9: Module placement.** The `RequestLimitViolation` ADT,
its detectors, and `validateLimits` live in `client.nim` alongside
`send`. Called exclusively by `send` (and the post-serialisation
size check, which constructs an `rlvMaxSizeRequest` directly). No
circular dependency (depends only on `Request` and
`CoreCapabilities`, both Layer 1 types).

---

## 6. Session Staleness Detection

**RFC reference:** §3.4 (lines 995-999).

### 6.1 Detection (Pure)

```nim
func isSessionStale*(client: JmapClient, response: envelope.Response): bool =
  ## Compares Response.sessionState with cached Session.state.
  ## Returns true if they differ (session should be re-fetched).
  ## Returns false if no session is cached (cannot determine staleness).
  ## Pure — no IO, no mutation.
  let s = client.session.valueOr:
    return false
  s.state != response.sessionState
```

Uses `valueOr:` for the early-return pattern with `Opt[Session]`.

### 6.2 Refresh (IO)

```nim
proc refreshSessionIfStale*(
    client: var JmapClient, response: envelope.Response
): JmapResult[bool] =
  ## If the response indicates staleness, re-fetches the session.
  ## Returns ok(true) if refreshed, ok(false) otherwise.
  ## Returns err on fetch failure (same as fetchSession).
  if client.isSessionStale(response):
    let s = ?client.fetchSession()
    discard s
    return ok(true)
  ok(false)
```

**Decision D4.10: Automatic vs manual session refresh.** `send` does
NOT automatically refresh. Rationale: (a) hidden network request makes
latency unpredictable; (b) the caller may want to inspect the response
before deciding; (c) the RFC uses SHOULD (not MUST); (d) in batch
requests, the session may change mid-batch — automatic refresh after
every `send` could cause unnecessary re-fetches. The library provides
composable tools (`isSessionStale`, `refreshSessionIfStale`).

---

## 7. URI Template Expansion (session.nim, Pure)

**RFC reference:** §2 (lines 679-700), RFC 6570 Level 1.

`UriTemplate` is parsed once at construction (`parseUriTemplate`) into
an alternating sequence of `UriPart` literals and variable references:

```nim
type UriPartKind* = enum
  upLiteral
  upVariable

type UriPart* {.ruleOff: "objects".} = object
  case kind*: UriPartKind
  of upLiteral:
    text*: string
  of upVariable:
    name*: string
```

Expansion folds the parsed parts into a string — no scanning of the
raw template, no per-variable string replacement pass:

```nim
func expandUriTemplate*(
    tmpl: UriTemplate,
    variables: openArray[(string, string)],
): string =
  ## Folds the parsed parts into a string. Variables not found in
  ## ``variables`` are emitted unexpanded as ``{name}``. Caller is
  ## responsible for percent-encoding values that require it
  ## (``std/uri.encodeUrl(value, usePlus=false)``). Pure.
  ##
  ## Level 1 only: simple string substitution. Common identifiers
  ## (``AccountId``, ``Id``) are base64url-safe — no encoding needed.
  ##
  ## Example:
  ##   expandUriTemplate(session.downloadUrl,
  ##     {"accountId": string(acctId), "blobId": string(blobId),
  ##      "name": "report.pdf", "type": "application/pdf"})
  result = ""
  for part in tmpl.parts:
    case part.kind
    of upLiteral:
      result.add(part.text)
    of upVariable:
      var found = false
      for i in 0 ..< variables.len:
        if variables[i][0] == part.name:
          result.add(variables[i][1])
          found = true
          break
      if not found:
        result.add("{")
        result.add(part.name)
        result.add("}")
```

Lives in `session.nim` alongside the `UriTemplate`, `UriPart`, and
`Session` types (which owns the `downloadUrl`, `uploadUrl`, and
`eventSourceUrl` template fields). This collocates the expansion logic
with the types it operates on. The parsed-parts shape lets
`Session.fromJson` reject malformed templates (unmatched `{`, empty
`{}`, missing required variables) at deserialisation time as a
`SerdeViolation`, so by the time `expandUriTemplate` runs the template
is structurally sound.

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
| `Authorization` | `Bearer {token}` | §1.7 (lines 429-430) |
| `Content-Type` | `application/json` | §3.1 (lines 860-861) |
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
`HttpHeaders` uses `toCaseInsensitive` internally. The
`readContentType` helper (§2.5) calls `toLowerAscii` on the header
VALUE for MIME type prefix matching, because MIME types are
case-insensitive per RFC 2045 but servers may return mixed-case values
(e.g., `Application/JSON`).

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

### 10.1 Module Layout

```
src/jmap_client/
  errors.nim          — TransportError, RequestError, ClientError,
                         MethodError, SetError types + constructors;
                         variant-specific SetError smart constructors
                         (setErrorInvalidProperties, setErrorAlreadyExists,
                         setErrorBlobNotFound, setErrorInvalidEmail,
                         setErrorTooManyRecipients,
                         setErrorInvalidRecipients, setErrorTooLarge);
                         RequestContext enum; classifyException;
                         sizeLimitExceeded; enforceBodySizeLimit;
                         validationToClientError;
                         validationToClientErrorCtx;
                         isTlsRelatedMsg (private)
  session.nim         — UriPart, UriTemplate, parseUriTemplate,
                         expandUriTemplate, hasVariable (collocated
                         with the UriTemplate and Session types)
  client.nim          — JmapClient type, initJmapClient,
                         discoverJmapClient, accessors (session,
                         sessionUrl, bearerToken, authScheme,
                         lastRawResponseBody), setBearerToken,
                         close, setSessionForTest,
                         sendRawHttpForTesting, fetchSession, send
                         (Request + RequestBuilder overloads),
                         validateLimits, isSessionStale,
                         refreshSessionIfStale;
                         JmapClientViolation ADT + detect* helpers
                         (private), RequestLimitViolation ADT +
                         detect* helpers (private),
                         resolveAgainstSession (private),
                         enforceContentLengthLimit (private),
                         readContentType (private),
                         tryParseProblemDetails (private),
                         classifyHttpResponse (private),
                         parseJsonBody (private)
  dispatch.nim        — ResponseHandle[T] (phantom-typed handle),
                         NameBoundHandle[T] (RFC 8620 §5.4 compound
                         dispatch), CompoundHandles[A, B] +
                         CompoundResults[A, B] +
                         registerCompoundMethod, ChainedHandles[A, B] +
                         ChainedResults[A, B] + registerChainableMethod
                         (RFC 8620 §3.7 back-reference chains);
                         callId, get[T] (mixin, callback, and
                         NameBoundHandle overloads), getBoth (two
                         overloads), serdeToMethodError, reference,
                         idsRef, listIdsRef, addedIdsRef, createdRef,
                         updatedRef; findInvocation (private),
                         extractInvocation (private),
                         findInvocationByName (private),
                         extractInvocationByName (private).
                         Layer 3 module, re-exported via protocol.nim.
  convenience.nim     — Pipeline combinators: QueryGetHandles[T],
                         addQueryThenGet, ChangesGetHandles[T],
                         addChangesToGet, QueryGetResults[T],
                         ChangesGetResults[T], getBoth (two overloads).
                         NOT re-exported — explicit import required
                         (Decision D4.14).
```

**Decision D4.13: Module split.** Error types and pure error-related
functions (`classifyException`, `enforceBodySizeLimit`,
`sizeLimitExceeded`, `validationToClientError`,
`validationToClientErrorCtx`) live in `errors.nim` because they
construct and operate on error types and require `std/net` imports for
exception type matching. The validation bridge functions
(`validationToClientError`, `validationToClientErrorCtx`) also live
in `errors.nim` because they construct `ClientError` values — they
import `ValidationError` from `./validation` via `from` import.
`expandUriTemplate` lives in `session.nim` alongside the `UriTemplate`
and `UriPart` types. `client.nim` contains the `JmapClient` type and
all procs that operate on it. Internal helpers
(`enforceContentLengthLimit`, `readContentType`,
`tryParseProblemDetails`, `classifyHttpResponse`, `parseJsonBody`,
`resolveAgainstSession`, the `JmapClientViolation` and
`RequestLimitViolation` ADTs and their `detect*` helpers) are
module-private. `dispatch.nim` contains the phantom-typed response
handles, dispatch extraction logic, and the compile-time registration
templates for §5.4 compound and §3.7 back-reference patterns — it is
a Layer 3 module re-exported via `protocol.nim`, but documented here
because it operates on the `Response` value returned by `client.send`.
`convenience.nim` composes builder and dispatch functions into
multi-method pipeline combinators and is deliberately excluded from
all re-export hubs (Decision D4.14).

**Nimalyzer `objects` rule suppression.** The `JmapClient` type has all
private fields by design (§1.1: make illegal states unrepresentable).
The nimalyzer `objects publicfields` rule flags exported types without
public fields. The type definition is wrapped in
`{.push ruleOff: "objects".}` / `{.pop.}` to suppress this diagnostic.
The same `{.ruleOff: "objects".}` annotation applies to the private
`JmapClientViolation` and `RequestLimitViolation` ADTs (case objects
without public fields).

### 10.2 Import DAG

```
errors.nim imports:
  std/strutils         — toLowerAscii, contains (via `in` operator)
  std/json             — JsonNode (via `from` import)
  results              — Result, Opt, ok, err
  std/net              — TimeoutError (selective import via `from`);
                         SslError (selective import, guarded by
                         `when defined(ssl)`)
  ./validation         — ValidationError (via `from` import; used
                         by validationToClientError/Ctx bridge funcs)
  ./primitives         — Id, UnsignedInt (for SetError variant fields)
  ./identifiers        — BlobId (for setErrorBlobNotFound)

client.nim imports:
  std/httpclient       — HttpClient, newHttpClient, request, close,
                         HttpMethod, newHttpHeaders
  std/json             — parseJson, $, JsonNode, JObject, JArray, hasKey,
                         {} (nil-safe access)
  std/strutils         — startsWith, endsWith, contains, Whitespace
  std/uri              — parseUri, combine ($-stringification of the
                         combined URI; used by resolveAgainstSession)
  ./types              — Layer 1 re-export hub (also re-exports results,
                         Opt, all error types, RequestContext)
  ./serialisation      — Layer 2 re-export hub (SerdeViolation,
                         toValidationError translator)
  ./builder            — RequestBuilder, build

dispatch.nim imports:
  std/hashes           — Hash (for ResponseHandle and NameBoundHandle)
  std/json             — JsonNode
  ./types              — Layer 1 re-export hub
  ./serialisation      — Layer 2 re-export hub (SerdeViolation,
                         toValidationError translator)
  ./methods            — QueryResponse, GetResponse, ChangesResponse,
                         QueryChangesResponse, queryMethodName,
                         getMethodName, changesMethodName,
                         queryChangesMethodName (mixins)

convenience.nim imports:
  ./types              — Layer 1 re-export hub
  ./methods            — Method response types, addQuery, addGet,
                         addChanges
  ./dispatch           — ResponseHandle, get, idsRef, createdRef
  ./builder            — RequestBuilder
```

**Import notes.**

- `std/options` is NOT imported anywhere — `Opt[T]` from nim-results is
  used throughout. A direct import would trigger
  `hintAsError: DuplicateModuleImport` since `results` (re-exported by
  `./types`) already provides optional value support.
- `std/net` is imported only in `errors.nim` (selective import via
  `from std/net import TimeoutError` and `SslError` under
  `when defined(ssl)`), not in `client.nim`.
- `std/uri` is imported in `client.nim` for `resolveAgainstSession`
  (RFC 3986 §5 reference resolution of relative ``apiUrl`` values).
- `./validation` is imported only in `errors.nim` (selective import via
  `from ./validation import ValidationError`) for the validation bridge
  functions (`validationToClientError`, `validationToClientErrorCtx`).
- `./builder` is imported in `client.nim` for the `send(RequestBuilder)`
  convenience overload.
- `dispatch.nim` and `convenience.nim` do not import `client.nim` — the
  dependency flows one way: `client.nim` produces `Response` values,
  `dispatch.nim` consumes them, `convenience.nim` composes both sides.

**Name collision: `Response`.** Both `std/httpclient` and the JMAP
envelope types (via `./types`) export a `Response` type. In proc
signatures, the httpclient variant is qualified as
`httpclient.Response`. The unqualified `Response` in `send`'s return
type is qualified as `envelope.Response` for clarity.

### 10.3 Re-Export Hub

`src/jmap_client.nim` re-exports the complete type vocabulary, Layer 2
serialisation, Layer 3 protocol logic, Layer 4 client, and the mail
sub-library (Layer 1.5 — RFC 8621 entities, separately documented in
`05-mail-architecture.md` onward):

```nim
import jmap_client/types
import jmap_client/serialisation
import jmap_client/protocol
import jmap_client/client
import jmap_client/mail

export types
export serialisation
export protocol
export client
export mail
```

`protocol.nim` (Layer 3 hub) re-exports `entity`, `methods`,
`dispatch`, and `builder`:

```nim
import ./entity
import ./methods
import ./dispatch
import ./builder

export entity
export methods
export dispatch
export builder
```

**`convenience.nim` is NOT re-exported** by any hub. Consumers who
want pipeline combinators must explicitly
`import jmap_client/convenience`. This keeps the core API surface
frozen and avoids pulling in opinionated composition patterns by
default (Decision D4.14).

---

## 11. Design Decisions Summary

| ID | Decision | Alternative considered | Rationale |
|----|----------|----------------------|-----------|
| D4.1 | `JmapClient` as value `object` (not `ref object`) | `ref object` | Value type with `var` parameter passing. Layer 5 allocates on heap via `create()` for C ABI. |
| D4.2 | Constructor does not fetch session (lazy) | Eager fetch | Construction should not perform IO. |
| D4.3 | No DNS SRV — `.well-known/jmap` only | Full RFC 8620 §2.2 | No reference implementation uses DNS SRV. |
| D4.4 | Two-phase body size check: Phase 1 via `contentLength` before body read, Phase 2 via `body.len` after read | Streaming check | Phase 1 prevents OOM on oversized responses. Phase 2 catches absent/inaccurate Content-Length. Streaming check requires replacing `std/httpclient`. |
| D4.5 | TLS detection — two-tier: `SslError` type match + `OSError` substring heuristic | Single heuristic only | `SslError` (from `std/net`) inherits `CatchableError` directly, not `OSError`, requiring its own branch. `OSError` heuristic retained as fallback for OpenSSL errors that surface as `OSError`. |
| D4.6 | Two-stage mapping for Layer 2 deserialisation failures: `SerdeViolation` -> `ValidationError` (via `toValidationError(sv, rootType)`) -> `ClientError` (via `validationToClientErrorCtx`) | Propagate `SerdeViolation` directly | Keeps the outer railway uniform: `JmapResult[T]` always carries `ClientError`. The `toValidationError` translator is the sole serde→validation boundary; the bridge then lifts onto the outer railway. Session/response validation failures are classified as `tekNetwork` (protocol error). |
| D4.7 | `JsonParsingError` classified as `tekNetwork` | `tekHttpStatus` with 200 | HTTP succeeded, body is invalid JSON. Protocol violation, not an HTTP status error. |
| D4.8 | Problem details on HTTP 200 via `"type"` + missing `"methodResponses"` heuristic; uses `optValue` + `for val in opt:` idiom | Content-Type check only | Servers often use `application/json` for problem details. `Response` always has `methodResponses`. |
| D4.9 | `validateLimits` in `client.nim`; `RequestLimitViolation` ADT + `detectGetLimit`/`detectSetLimit`/`detectMaxCalls`/`detectRequestLimits` as private helpers; `rlvMaxSizeRequest` shared with `send`'s post-serialisation size check | Single monolithic proc with inline `validationError` calls | ADT decouples in-process classification from wire serialisation (functional-core patterns 1 + 5); single-purpose detectors keep each func within nimalyzer complexity limits; shared variant for `maxSizeRequest` keeps the wire message shape uniform. |
| D4.10 | Manual session staleness (not auto-refresh in `send`) | Auto-refresh | Hidden network request, unpredictable latency. RFC uses SHOULD. Composable tools provided. |
| D4.11 | URI template: caller percent-encodes values (`std/uri.encodeUrl` available) | Library encodes | Common identifiers are base64url-safe. Full RFC 6570 disproportionate. |
| D4.12 | Compile-time hint (`{.hint:}`) for missing `-d:ssl` | `{.warning:}` (blocked by `warningAsError: User`); compile error | `{.hint:}` is informational and non-blocking. `{.warning:}` is rejected because `config.nims` promotes User warnings to errors. |
| D4.13 | Error types, classifiers, and validation bridge functions in `errors.nim`; `expandUriTemplate` in `session.nim`; `JmapClient` and IO in `client.nim` | Single file | Error types require `std/net` imports; validation bridge functions construct `ClientError` values; collocating `expandUriTemplate` with `UriTemplate` type is natural; `client.nim` contains all JmapClient-related code. |
| D4.14 | `convenience.nim` is opt-in (not re-exported by any hub) | Auto-export via `protocol.nim` | Pipeline combinators encode opinionated choices (reference paths, same-account assumption). The core API in `builder.nim` + `dispatch.nim` provides full control. Lessons from OpenSSL/libgit2: freezing the core API surface while providing opt-in ergonomics reduces breaking changes. |
| D4.15 | Configurable `authScheme` parameter on `initJmapClient`/`discoverJmapClient` (default `"Bearer"`) | Hard-coded `"Bearer"` prefix | RFC 8620 §1.7 specifies Bearer, but legacy Cyrus deployments accept Basic auth at the JMAP endpoint. Storing the scheme on the client lets `setBearerToken` re-emit the same scheme on rotation without rebuilding the header by hand. |
| D4.16 | Raw response body captured into `client.lastRawResponseBody` via a `var string` parameter on `classifyHttpResponse` | Re-read the body in tests; or expose a separate capture proc | Capture happens immediately after `httpResp.body` is read, before any 4xx/5xx classification, so byte fidelity is preserved on every code path. The `mcapture.captureIfRequested` test helper consults a runtime env var to decide whether to persist; production callers ignore the field. |
| D4.17 | `resolveAgainstSession` resolves `apiUrl` against the session URL via RFC 3986 §5 (`std/uri.combine`) when `apiUrl` is a relative reference | Reject relative `apiUrl` as invalid wire data | RFC 8620 §2 does not explicitly mandate absolute form. Cyrus 3.12.2 (`imap/jmap_api.c`) emits `"/jmap/"`. Postel-tolerant on receive — the resolution is deterministic against the known-absolute session URL. Absolute `apiUrl` values pass through unchanged. |
| D4.18 | `send` uses `valueOr:` (with `return err(...)`) when unwrapping `client.session` after a successful `fetchSession`; never `.get()` | `.get()` on the cached `Opt[Session]` | Under `--mm:arc`/`--panics:on`, `.get()` on a `none` `Opt` routes through `withAssertOk` and triggers `rawQuit(1)` with no unwinding — catastrophic at the FFI boundary. The `valueOr:` block flows through the Result railway as a defined `tekNetwork` error. |
| D4.19 | Limit dispatch keys on `inv.rawName.endsWith("/get")`/`"/set"`, not `inv.name.endsWith` | Use the parsed `MethodName` enum | `inv.name` returns the parsed `MethodName` enum (no `endsWith`); unrecognised names parse to a catch-all variant, losing suffix dispatch. The wire-form `rawName` is the lossless string. |

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
| 1 | Valid HTTPS URL + token | `ok(JmapClient)` | Happy path |
| 2 | Valid HTTP URL + token | `ok(JmapClient)` | HTTP allowed (for testing) |
| 3 | Empty `sessionUrl` | `err(ValidationError)` | Non-empty required |
| 4 | URL without scheme prefix | `err(ValidationError)` | Must start with `https://` or `http://` |
| 5 | Empty `bearerToken` | `err(ValidationError)` | Non-empty required |
| 6 | `timeout = -1` (no timeout) | `ok(JmapClient)` | Valid |
| 7 | `timeout = -2` | `err(ValidationError)` | Must be >= -1 |
| 8 | `maxRedirects = 0` | `ok(JmapClient)` | No redirects (valid) |
| 9 | `maxResponseBytes = 0` | `ok(JmapClient)` | No limit (valid) |
| 10 | `discoverJmapClient("example.com", ...)` | URL = `"https://example.com/.well-known/jmap"` | URL construction |
| 11 | `discoverJmapClient("", ...)` | `err(ValidationError)` | Empty domain |
| 12 | `discoverJmapClient("ex/ample", ...)` | `err(ValidationError)` | Path injection |
| 13 | `discoverJmapClient("ex ample", ...)` | `err(ValidationError)` | Whitespace |
| 13a | URL with `\r\n` characters | `err(ValidationError)` | Header injection prevention |
| 13b | `maxRedirects = -1` | `err(ValidationError)` | Prevents `RangeDefect` on `Natural` field |
| 13c | `maxResponseBytes = -1` | `err(ValidationError)` | Must be >= 0 |

### 12.2 Bearer Token Mutation (Pure, No Network)

| # | Input | Expected | Notes |
|---|-------|----------|-------|
| 14 | `setBearerToken("new-token")` | `ok()`, token updated | Mutator |
| 15 | `setBearerToken("")` | `err(ValidationError)` | Non-empty required |

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
| 21 | 0 calls, maxCallsInRequest = 1 | `ok()` | Within limits |
| 22 | 1 call, maxCallsInRequest = 1 | `ok()` | Exactly at limit |
| 23 | 2 calls, maxCallsInRequest = 1 | `err(ValidationError)` | Over limit |
| 24 | `/get` with 5 direct ids, maxObjectsInGet = 10 | `ok()` | Within |
| 25 | `/get` with 11 direct ids, maxObjectsInGet = 10 | `err(ValidationError)` | Over |
| 26 | `/get` with reference ids (JObject) | `ok()` | Skipped |
| 27 | `/get` with null ids | `ok()` | Null = server decides |
| 28 | `/set` with 3+3+3 = 9, maxObjectsInSet = 10 | `ok()` | Within |
| 29 | `/set` with 4+4+3 = 11, maxObjectsInSet = 10 | `err(ValidationError)` | Over |
| 30 | `/set` with reference destroy | Count excludes | Cannot count refs |
| 31 | Empty Request (no calls) | `ok()` | Trivially valid |
| 32 | Mixed `/get` and `/set`, all within limits | `ok()` | Independent checks |
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
| 44a | `ref SslError` | `tekTls` | Direct type match (`when defined(ssl)`) |

### 12.7 Body Size Enforcement (Pure, No Network)

| # | Input | Expected | Notes |
|---|-------|----------|-------|
| 45 | Body within limit | `ok()` | Within |
| 46 | Body exceeds limit | `err(ClientError)` | Over (Phase 2) |
| 46a | Body length exactly at limit | `ok()` | Strict `>` comparison |
| 47 | Limit = 0 (disabled) | `ok()` | No enforcement |
| 48 | Content-Length exceeds limit | `err(ClientError)` | Over (Phase 1, before body read) |
| 49 | Content-Length absent, body exceeds | `err(ClientError)` | Phase 1 skipped, Phase 2 catches |
| 50 | Content-Length malformed (non-numeric) | No error from Phase 1 | Falls through to Phase 2 |

### 12.8 Integration Test Scenarios (Require Network or Mock)

| # | Scenario | Expected |
|---|----------|----------|
| 51 | Valid session fetch (GET 200, valid JSON) | `ok(Session)`, cached |
| 52 | Session URL returns HTTP 404 | `err(ClientError(cekTransport, tekHttpStatus, 404))` |
| 53 | Session URL returns 301 redirect | Redirect followed, session fetched |
| 54 | Session URL exceeds `maxRedirects` | `err(ClientError(cekTransport, tekNetwork))` |
| 55 | Session URL returns invalid JSON | `err(ClientError(cekTransport, tekNetwork))` |
| 56 | Session JSON missing ckCore | `err(ClientError(cekTransport, tekNetwork))` (mapped from ValidationError) |
| 57 | Session JSON with empty apiUrl | `err(ClientError(cekTransport, tekNetwork))` (mapped from ValidationError) |
| 58 | Session JSON missing downloadUrl variable | `err(ClientError(cekTransport, tekNetwork))` (mapped from ValidationError) |
| 59 | API POST returns 200 with valid Response | `ok(Response)` |
| 60 | API POST returns 200 with problem details | `err(ClientError(cekRequest))` |
| 61 | API POST returns 400 + `application/problem+json` | `err(ClientError(cekRequest))` |
| 62 | API POST returns 400 without problem details | `err(ClientError(cekTransport, tekHttpStatus, 400))` |
| 63 | API POST returns 500 | `err(ClientError(cekTransport, tekHttpStatus, 500))` |
| 64 | API POST returns 200 with wrong Content-Type | `err(ClientError(cekTransport))` |
| 65 | Request body exceeds maxSizeRequest | `err(ClientError(cekTransport, tekNetwork))` |
| 66 | Method calls exceed maxCallsInRequest | `err(ClientError(cekTransport, tekNetwork))` (mapped from ValidationError) |
| 67 | Connection refused | `err(ClientError(cekTransport, tekNetwork))` |
| 68 | DNS resolution failure | `err(ClientError(cekTransport, tekNetwork))` |
| 69 | TLS handshake failure | `err(ClientError(cekTransport, tekTls))` |
| 70 | Socket timeout | `err(ClientError(cekTransport, tekTimeout))` |
| 71 | Response Content-Length exceeds maxResponseBytes | `err(ClientError(cekTransport))` (Phase 1, before body read) |
| 72 | Response body exceeds maxResponseBytes (no Content-Length) | `err(ClientError(cekTransport))` (Phase 2, after body read) |
| 73 | Malformed HTTP status line | `err(ClientError(cekTransport, tekNetwork))` |
| 74 | Session state changes between requests | `isSessionStale` returns `true` |
| 75 | Bearer token update, then send | New token used |
| 76 | Lazy session fetch on first send | Session fetched, then request sent |
| 77 | Send with cached session | No re-fetch, request sent directly |
| 78 | `refreshSessionIfStale` when stale | Session re-fetched, `ok(true)` |
| 79 | `refreshSessionIfStale` when not stale | No fetch, `ok(false)` |
| 80 | `urn:ietf:params:jmap:error:unknownCapability` | `err(ClientError(cekRequest))` with `retUnknownCapability` |
| 81 | `urn:ietf:params:jmap:error:limit` with limit field | `err(ClientError(cekRequest))` with `retLimit`, `limit` populated |

**Total: 86 enumerated test scenarios (including 13a, 13b, 13c, 44a,
46a).**

---

## 13. Implementation Sequence (As-Built)

0. Verified error types and constructors in
   `src/jmap_client/errors.nim` — `TransportError`, `RequestError`,
   `ClientError` (plain objects), `MethodError`, `SetError` plus
   variant-specific smart constructors (RFC 8620 §5.3/§5.4 and
   RFC 8621 §4.6/§7.5 payloads), `classifyException`,
   `enforceBodySizeLimit`, `sizeLimitExceeded`,
   `validationToClientError`, `validationToClientErrorCtx`,
   `RequestContext`.
1. Created `src/jmap_client/client.nim` — copyright header, imports
   (including `std/uri` for `resolveAgainstSession`),
   `{.push raises: [].}`, `{.experimental: "strictCaseObjects".}`,
   `-d:ssl` hint.
2. Defined `JmapClient` type with private fields including
   `authScheme` and `lastRawResponseBody` (wrapped in
   `{.push ruleOff: "objects".}` / `{.pop.}`).
3. Defined the private `JmapClientViolation` ADT and per-rule
   `detect*` helpers (`detectSessionUrl`, `detectBearerToken`,
   `detectTimeout`, `detectMaxRedirects`, `detectMaxResponseBytes`,
   `detectClientConfig`, `detectDomain`) plus the sole boundary
   translator `toValidationError(JmapClientViolation)`.
4. Implemented `initJmapClient` — composed config detection,
   `HttpClient` construction with `{.cast(raises: []).}`, returning
   `Result[JmapClient, ValidationError]`.
5. Implemented `discoverJmapClient` — `detectDomain`, URL synthesis,
   delegation to `initJmapClient`.
6. Implemented read-only accessors (`session`, `sessionUrl`,
   `bearerToken`, `authScheme`, `lastRawResponseBody`) and mutators
   (`setBearerToken` returning `Result[void, ValidationError]` and
   re-emitting the stored auth scheme; `close` with
   `{.cast(raises: []).}`).
7. Implemented `setSessionForTest` and `sendRawHttpForTesting` for
   test injection and adversarial wire-shape exercises.
8. Implemented helpers: `enforceContentLengthLimit`,
   `readContentType`, `tryParseProblemDetails`, `classifyHttpResponse`
   (with `capturedBody: var string`), `parseJsonBody`,
   `resolveAgainstSession`.
9. Implemented `fetchSession` — composes IO + classification +
   Layer 2 deserialisation + the two-stage
   `SerdeViolation`→`ValidationError`→`ClientError` mapping; raw
   bytes routed into `client.lastRawResponseBody`.
10. Defined the private `RequestLimitViolation` ADT and per-rule
    `detect*` helpers (`detectGetLimit`, `detectSetLimit`,
    `detectMaxCalls`, `detectRequestLimits`) plus the sole boundary
    translator `toValidationError(RequestLimitViolation)`. Public
    `validateLimits` projects via `isOkOr:`.
11. Implemented `send(Request)` — defensive `valueOr:` session
    unwrap, pre-flight validation, serialisation, post-serialisation
    `rlvMaxSizeRequest` check, IO POST through
    `resolveAgainstSession`, classification, problem-details
    detection, response deserialisation with the same two-stage
    error mapping.
12. Implemented `send(RequestBuilder)` — convenience overload over
    `send(builder.build())`.
13. Implemented `isSessionStale` and `refreshSessionIfStale`.
14. Implemented `dispatch.nim` — `ResponseHandle[T]`,
    `NameBoundHandle[T]`, the three `get[T]` overloads
    (mixin/callback/`NameBoundHandle`), `serdeToMethodError`,
    `CompoundHandles`/`CompoundResults` with
    `registerCompoundMethod` (RFC 8620 §5.4),
    `ChainedHandles`/`ChainedResults` with
    `registerChainableMethod` (RFC 8620 §3.7), `getBoth` overloads,
    `reference`, and the type-safe convenience refs (`idsRef`,
    `listIdsRef`, `addedIdsRef`, `createdRef`, `updatedRef`).
15. Implemented `convenience.nim` — pipeline combinators
    (`addQueryThenGet` template, `addChangesToGet`, two `getBoth`
    overloads), all returning `(RequestBuilder, <Handles>)` tuples.
    Deliberately omitted from all re-export hubs.
16. Updated `src/jmap_client.nim` to import and re-export `types`,
    `serialisation`, `protocol`, and `client`. Updated `protocol.nim`
    to re-export `entity`, `methods`, `dispatch`, `builder`.
17. Wrote unit tests — `tests/unit/tclient.nim` covering pure
    scenarios; integration tests under `tests/integration/live/`
    cover Content-Length Phase 1 enforcement and the
    Stalwart / Apache James / Cyrus cross-server matrix.
18. Ran `just ci`.

---

## Appendix: RFC Section Cross-Reference

| Type/Function | RFC 8620 Section | Notes |
|---------------|-----------------|-------|
| `JmapClient` | §1.7 (lines 426-447), §2 (lines 477-721) | Client handle; RFC describes the API model |
| `initJmapClient` | §1.7 (line 429: auth required), §8.2 (auth scheme) | Bearer token |
| `discoverJmapClient` | §2.2 (lines 819-835) | `.well-known/jmap` autodiscovery |
| `fetchSession` | §2 (lines 477-721) | Session resource fetch |
| `send` | §3.1 (lines 854-863), §3.3 (lines 882-943), §3.4 (lines 975-1003) | API request/response |
| `send(RequestBuilder)` | §3.1 | Convenience overload bridging Layer 3 builder to Layer 4 IO |
| `ResponseHandle[T]` | §3.4 (lines 975-1003) | Phantom-typed handle for compile-time response dispatch (in `dispatch.nim`) |
| `callId` | §3.4 (lines 975-1003) | Extracts underlying `MethodCallId` from a `ResponseHandle[T]` (in `dispatch.nim`) |
| `get[T]` | §3.4 (lines 975-1003), §3.6.2 | Typed extraction from Response envelope, detects method errors (in `dispatch.nim`) |
| `addQueryThenGet` | §5.1 (Foo/query), §5.1 (Foo/get), §3.7 (result references) | Pipeline combinator with automatic `/ids` reference wiring (in `convenience.nim`) |
| `addChangesToGet` | §5.2 (Foo/changes), §5.1 (Foo/get), §3.7 (result references) | Sync pipeline with `/created` reference wiring (in `convenience.nim`) |
| `classifyHttpResponse` | §3.6.1 (lines 1079-1136) | Request-level errors |
| `tryParseProblemDetails` | §3.6.1 (lines 1079-1136) | RFC 7807 problem details extraction |
| `validateLimits` | §2 (CoreCapabilities), §3.6.1, §5.1, §5.3 | Pre-flight validation, public surface over `RequestLimitViolation` |
| `RequestLimitViolation` (ADT) | §2 (CoreCapabilities), §3.6.1 | Private sum type with `rlvMaxCallsInRequest`, `rlvMaxObjectsInGet`, `rlvMaxObjectsInSet`, `rlvMaxSizeRequest` (shared with `send`'s post-serialisation size check) |
| `detectGetLimit` | §5.1 | Per-/get invocation ids count check |
| `detectSetLimit` | §5.3 | Per-/set invocation object count check |
| `detectMaxCalls` | §3.6.1, §2 (CoreCapabilities) | Top-level method-call count check |
| `detectRequestLimits` | §2, §5.1, §5.3 | Composition of the three per-rule detectors |
| `isSessionStale` | §3.4 (lines 995-999) | Session state comparison |
| `expandUriTemplate` | §2 (lines 679-700), RFC 6570 | URI template expansion over parsed `UriPart` parts (in `session.nim`) |
| `resolveAgainstSession` | §2; RFC 3986 §5 | Resolves relative `apiUrl` against the session URL; absolute URLs pass through |
| `enforceContentLengthLimit` | Client-side (R9); not RFC-specified | Phase 1 response body size cap — pre-read via Content-Length header |
| `enforceBodySizeLimit` | Client-side (R9); not RFC-specified | Phase 2 response body size cap — post-read via actual body length |
| `classifyException` | N/A — maps stdlib exceptions | In `errors.nim`; maps `std/httpclient` exceptions to `ClientError` |
| `sizeLimitExceeded` | Client-side (R9) | In `errors.nim`; shared error constructor |
| `validationToClientError` | N/A — railway bridge | In `errors.nim`; DRY bridge from `ValidationError` to `ClientError` |
| `validationToClientErrorCtx` | N/A — railway bridge | In `errors.nim`; DRY bridge with context prefix |
| `serdeToMethodError` | N/A — railway bridge | In `dispatch.nim`; closure factory mapping `SerdeViolation` to `MethodError(serverFail)` with extras-preserved diagnostics |
| `RequestContext` | N/A — internal enum | In `errors.nim`; `rcSession` / `rcApi` for error messages |
| `JmapClientViolation` (ADT) | N/A — internal classification | Private sum type covering the eleven `JmapClient` construction failure modes |
| `lastRawResponseBody` | N/A — test capture | Test-only accessor exposing the most recent raw HTTP response body |
| `sendRawHttpForTesting` | N/A — test escape hatch | Test-only POST helper that bypasses `Request.toJson` and `validateLimits` |
| `NameBoundHandle[T]` | §5.4 (lines 1359-1429) | In `dispatch.nim`; binds method-name + call-id for compound implicit-call dispatch |
| `CompoundHandles`/`CompoundResults`/`getBoth` | §5.4 | In `dispatch.nim`; paired primary + implicit dispatch for §5.4 compounds |
| `ChainedHandles`/`ChainedResults`/`getBoth` | §3.7 (lines 1144-1238) | In `dispatch.nim`; paired dispatch for §3.7 back-reference chains with distinct call-ids |
| `registerCompoundMethod` / `registerChainableMethod` | §5.4, §3.7 | In `dispatch.nim`; compile-time registration templates checking the typedesc parametrises the right handle |
| Bearer token auth | §1.7 (line 429), §8.2 | `Authorization: <authScheme> {bearerToken}` — scheme defaults to ``"Bearer"``; configurable for legacy deployments |
| Content-Type: `application/json` | §3.1 (lines 860-862) | Required on request; expected on response |
| HTTPS requirement | §1.7 (line 429) | `-d:ssl` compile flag |
| Single-threaded | §3.10 (lines 1535-1539) | Sequential method processing |
