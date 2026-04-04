# Layer 4 Implementation Plan

Layer 3 is complete. Layer 4 adds the transport layer: `JmapClient` type,
HTTP session discovery and fetching, API request/response round-trips,
exception classification, pre-flight validation, body size enforcement,
URI template expansion, and session staleness detection. All code lives in
a single file `src/jmap_client/client.nim` (D4.13). Full specification:
`docs/design/06-layer-4-design.md`.

5 steps, one commit each, bottom-up through dependency. Every step passes
`just ci` before committing.

Prerequisite verified: `newClientError` ref-returning constructors exist
in `src/jmap_client/errors.nim` (lines 101–109). No prerequisite work
needed. Pure unit tests (design doc §12 scenarios 1–50) go in
`tests/unit/tclient.nim`. Integration tests (scenarios 51–81) require a
mock HTTP server and are out of scope for this plan.

---

## Step 1: client.nim — JmapClient type + constructors + accessors + mutators

**Create:** `src/jmap_client/client.nim`, `tests/unit/tclient.nim`

**Update:** `tests/mfixtures.nim`, `tests/massertions.nim`

**Design doc:** §§1.1–1.5, §9.1, §10.1–10.2, D4.1, D4.2, D4.3, D4.12

Create `src/jmap_client/client.nim` with SPDX header, module docstring,
imports (`std/httpclient`, `std/json`, `std/options`, `std/strutils`,
`./types`, `./serialisation`), and the `when not defined(ssl)` compile-time
warning (D4.12 — warning, not error, to allow testing with mock HTTP).

`JmapClient*` type: value `object` (D4.1) with six private fields —
`httpClient: HttpClient`, `sessionUrl: string`, `bearerToken: string`,
`session: Option[Session]`, `maxResponseBytes: int`, `userAgent: string`.

`initJmapClient*` (§1.2): smart constructor with 6 validation rules
(non-empty `sessionUrl`; `https://` or `http://` scheme prefix; non-empty
`bearerToken`; `timeout >= -1`; `maxRedirects >= 0` — prevents
`RangeDefect` on `Natural` field; `maxResponseBytes >= 0`). Creates
`HttpClient` via `newHttpClient` with `Authorization`, `Content-Type`,
`Accept` headers. Returns `JmapClient` with `session = none(Session)`.
Raises `ValidationError(typeName: "JmapClient")`. Does NOT fetch session
(D4.2).

`discoverJmapClient*` (§1.3, D4.3): domain validation (non-empty; no
whitespace; no `/`), constructs
`"https://" & domain & "/.well-known/jmap"`, delegates to
`initJmapClient`.

Read-only accessors (§1.4): `session*`, `sessionUrl*`, `bearerToken*`.
Mutators (§1.5): `setBearerToken*` (validates non-empty, updates both
`client.bearerToken` and `client.httpClient.headers`); `close*`
(idempotent).

Tests (scenarios 1–15): constructor happy paths (HTTPS, HTTP URLs),
validation rejections (empty URL, missing scheme, empty token,
`timeout = -2`), valid edge cases (`timeout = -1`, `maxRedirects = 0`,
`maxResponseBytes = 0`), `discoverJmapClient` domain validation (valid,
empty, path injection, whitespace), `setBearerToken` (valid, empty).
Verify accessors return expected values.

---

## Step 2: Pure helpers — URI templates, exception classification, body enforcement, JSON parsing

**Update:** `src/jmap_client/client.nim`, `tests/unit/tclient.nim`

**Design doc:** §§2.1–2.4, §7, D4.4, D4.5, D4.7, D4.11

`expandUriTemplate*` (§7, D4.11): takes `UriTemplate` and
`openArray[(string, string)]`, replaces `{name}` with value via
`strutils.replace`. Variables not in the array left unexpanded. Pure.

`classifyException*` (§2.1, D4.5): maps `ref CatchableError` to
`ref ClientError(cekTransport)`. Classification: `TimeoutError` →
`tekTimeout`; `OSError` with "ssl"/"tls"/"certificate" in
`msg.toLowerAscii` → `tekTls` (heuristic); other `OSError` →
`tekNetwork`; `IOError` → `tekNetwork`; `ValueError` → `tekNetwork`;
catch-all → `tekNetwork`. Exported for testability and consumer use.

`enforceBodySizeLimit*` (§2.2 Phase 2, D4.4): post-read rejection via
`body.len`. No-op when `maxResponseBytes == 0`. Pure. Exported for
testability.

`enforceContentLengthLimit` (§2.2 Phase 1, D4.4): pre-read rejection via
`httpResp.contentLength` header. Catches `ValueError` from malformed
Content-Length. Module-private.

`parseJsonBody` (§2.4, D4.7): wraps `parseJson`, catches
`JsonParsingError`, raises `ClientError(cekTransport, tekNetwork)`.
Module-private.

`classifyHttpResponse` (§2.3): composes `enforceContentLengthLimit`, body
read (`httpResp.body` — lazy stream), `enforceBodySizeLimit`, status code
classification, Content-Type checking, problem details detection. Returns
body `string` on 2xx with `application/json`. Module-private.

Tests (scenarios 16–20, 37–50): URI template expansion (all variables
present, missing variable, empty value, special chars, multiple
occurrences). Exception classification (`TimeoutError`, `OSError` with
SSL/TLS/certificate messages, other `OSError`, `IOError`, `ValueError`,
other `CatchableError`). Body size enforcement (within limit, exceeds
limit, limit disabled). Content-Length scenarios (48–50) deferred to
integration tests.

---

## Step 3: Pre-flight validation — validateLimits

**Update:** `src/jmap_client/client.nim`, `tests/unit/tclient.nim`

**Design doc:** §5, D4.9

`validateLimits*` (§5.1–5.2): pure proc taking `Request` and
`CoreCapabilities`. Checks: (1) `request.methodCalls.len` ≤
`maxCallsInRequest`; (2) per `/get` call (suffix-detected via
`inv.name.endsWith("/get")`): direct ids count (`args{"ids"}` as
`JArray`) ≤ `maxObjectsInGet` — reference ids (`JObject`) silently
skipped; (3) per `/set` call: `create` (`JObject.len`) + `update`
(`JObject.len`) + `destroy` (`JArray.len`) ≤ `maxObjectsInSet` —
reference destroy silently skipped. Uses nil-safe `{}` accessor. Raises
`ValidationError(typeName: "Request")` describing the first violation.
Non-standard method names have no per-invocation check.

Tests (scenarios 21–33): construct `Request` objects with `Invocation`
values containing specific `arguments: JsonNode`. Use
`realisticCoreCaps()` from `mfixtures.nim` and custom `CoreCapabilities`
with specific limits. Cover: 0/1/2 calls vs `maxCallsInRequest = 1`;
`/get` with 5/11 direct ids vs `maxObjectsInGet = 10`; `/get` with
reference ids and null ids; `/set` with 3+3+3=9 and 4+4+3=11 vs
`maxObjectsInSet = 10`; `/set` with reference destroy; empty Request;
mixed methods; non-standard method name.

---

## Step 4: IO procs — fetchSession, send, session staleness

**Update:** `src/jmap_client/client.nim`, `tests/unit/tclient.nim`

**Design doc:** §§3.1–3.2, §§4.1–4.2, §§6.1–6.2, D4.2, D4.6, D4.8,
D4.10

`fetchSession*` (§3.1–3.2): IO proc. (1) HTTP GET to
`client.sessionUrl` with `CatchableError` → `classifyException`;
(2) `classifyHttpResponse`; (3) `parseJsonBody`; (4) `Session.fromJson`;
(5) cache session on `client`. `ValidationError` from session JSON
propagates as-is (D4.6).

`send*` (§4.1–4.2): IO proc. 9-step algorithm: (1) lazy session fetch
if `client.session.isNone` (D4.2); (2) `validateLimits`; (3)
`request.toJson()` → `$`; (4) serialised size check against
`maxSizeRequest`; (5) HTTP POST with `CatchableError` →
`classifyException`; (6) `classifyHttpResponse`; (7) `parseJsonBody`;
(8) problem details on HTTP 200: `"type"` present + `"methodResponses"`
absent → `ClientError(cekRequest)` (D4.8); (9) `Response.fromJson`. Does
NOT auto-refresh session (D4.10).

`isSessionStale*` (§6.1): pure. Compares `response.sessionState` with
cached `Session.state`. Returns `false` if no session cached.

`refreshSessionIfStale*` (§6.2, D4.10): IO proc. Calls `isSessionStale`,
then `fetchSession` if stale. Returns `bool`.

For testing `isSessionStale` (scenarios 34–36): add a
`setSessionForTest*` proc or `initJmapClientWithSession*` constructor to
inject a cached session into the client for pure testing. Tests: same
state → `false`; different state → `true`; no cached session → `false`.
Integration tests (scenarios 51–81) out of scope.

---

## Step 5: Re-export hub + final verification

**Update:** `src/jmap_client.nim`

**Design doc:** §10.3

Update `src/jmap_client.nim` to add `import jmap_client/client` and
`export client`, following the existing pattern for `types`,
`serialisation`, `methods`. The `{.push raises: [].}` pragma constrains
only procs defined in that file (Layer 5 C ABI) — re-exported Layer 4
procs retain their original raise annotations.

Verify all Layer 4 public symbols are accessible through single
`import jmap_client`. Run `just ci`.

---
