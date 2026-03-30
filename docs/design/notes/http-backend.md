# HTTP Backend Analysis

## Decision: `std/httpclient` (Architecture 4.1A) — Confirmed

Source code analysis of Nim 2.2.8's `std/httpclient` (1443 lines) confirms it is
usable for JMAP with defensive wrapping at the transport boundary:

- **TLS:** OpenSSL via `-d:ssl`. Default `CVerifyPeer`, Mozilla cipher suites
  (intermediate profile for TLS 1.2, modern for 1.3), SNI support, platform CA
  cert discovery. Sufficient for Fastmail et al.
- **Bearer tokens:** `client.headers["Authorization"]` persists across requests.
  Authorization header correctly stripped on cross-domain redirects (security
  correct for `.well-known/jmap` discovery).
- **Timeouts:** Per-socket-operation only, not whole-request. Acceptable for v1;
  a slow-drip server will not timeout.
- **`{.raises.}`:** Zero annotations on any public proc. The transport boundary
  `proc send` must `try/except CatchableError` broadly and convert to
  `TransportError`. This is already prescribed by the architecture.
- **`strictFuncs`:** `httpcore.nim` (which `httpclient` imports) fails under
  `strictFuncs`. Not a problem because the transport layer is `proc` (IO).
- **`--mm:arc`:** Synchronous `HttpClient` works. `AsyncHttpClient` leaks under
  arc (closure cycles). Sync-only is the correct choice.

## Third-Party Survey

Surveyed: Curly, Chronos HTTP, Puppy, HyperX, Harpoon, yahttp, Araq/libcurl.

**Curly** (guzba/curly, 1239 lines) is the most mature alternative. Source code
analysis revealed disqualifying constraints for a `.so` library:

- Requires `--threads:on` unconditionally (Lock/Cond types throughout).
- `newCurly()` spawns a background thread — a shared library must not force a
  threading model on its host process.
- Structured curl error codes (`E_COULDNT_RESOLVE_HOST`, `E_OPERATION_TIMEDOUT`,
  `E_SSL_CERTPROBLEM`) are stringified and discarded — cannot map to
  `TransportError` variants without forking.
- Unconditional `zippy` dependency (gzip) unnecessary for JMAP `application/json`.

**Chronos HTTP** has full `{.push raises: [].}` discipline but is async-only and
pulls in the entire Chronos ecosystem. Unsuitable for a synchronous C ABI library.

No other candidate improves meaningfully on `std/httpclient` for this use case.

## Future Enhancement: Option B — Direct libcurl Easy API Wrapper

If `std/httpclient` limitations become blocking (e.g. whole-request timeout needed,
TLS configuration beyond OpenSSL defaults), the upgrade path is a thin custom
wrapper over the `libcurl` Nim bindings (Araq/libcurl, ~300 lines of C FFI).

The wrapper would be ~200-300 lines providing:

- `{.push raises: [].}` throughout
- `Result[Response, TransportError]` return type with structured error mapping
  from curl `Code` enum values directly to `TransportError` variants
- Single-threaded `easy_init`/`easy_setopt`/`easy_perform`/`easy_cleanup` flow
- Configurable TLS (CA paths, minimum version, client certs) via `easy_setopt`
- Proper whole-request timeout via `CURLOPT_TIMEOUT`
- SIGPIPE blocking on Unix (per Curly's pattern, lines 1074-1131)
- No zippy, no webby, no threading, no background thread

The libcurl `easy_*` API follows the same pattern as this library's transport
layer: synchronous, blocking, caller-managed concurrency. System dependency on
`libcurl.so` is ubiquitous on Linux and acceptable.

This is not needed for the initial release. `std/httpclient` with the prescribed
`try/except CatchableError` boundary is sufficient.
