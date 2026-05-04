# Integration Testing Plan — Phase J

## Status (living)

| Phase | State | Notes |
|---|---|---|
| **J0 — Library escape-hatch + helper extraction** | Done (2026-05-04, commit `7ba653a`) | One commit. Adds `sendRawHttpForTesting` to `client.nim` and three helpers (`sendRawInvocation`, `buildOversizedRequest`, `injectBrokenBackReference`) to `mlive.nim`.  No production-path code touched. |
| **J1 Step 61 — `trequest_level_errors_live`** | Done (commit `194d203`) | Four sub-tests over RequestError variants. Captured 4 fixtures + 4 replays. Stalwart 0.15.5 deviates: returns `notRequest` for non-JSON input and unknown capability (RFC mandates `notJSON` / `unknownCapability` respectively). Library projection contract verified strictly. |
| **J1 Step 62 — `tmethod_error_typed_projection_live`** | Done | Four sub-tests over MethodError variants. Captured 4 fixtures + 4 replays. Stalwart 0.15.5 RFC-conforms across all four. |
| **J1 Step 63 — `tset_error_typed_projection_live`** | Done | Four sub-tests over SetError variants. Captured 4 fixtures + 4 replays. Stalwart deviations recorded: collapses `setInvalidPatch` and `setBlobNotFound` onto `setInvalidProperties`. |
| **J1 Step 64 — `tpreflight_validation_live`** | Done | Four sub-tests verifying client-side `validateLimits` rejection across all four caps before HTTP fires. No fixtures (no HTTP). |
| **J1 Step 65 — `tserver_side_enforcement_parity_live`** | Done | Three sub-tests over server-side cap enforcement via `sendRawHttpForTesting`. Captured 3 fixtures + 3 replays. Stalwart deviation: collapses `maxObjectsInGet` onto `maxSizeRequest` rail. |
| **J1 Step 66 — `tnotfound_rail_get_live`** | Done | Four sub-tests over `notFound` rail across Email/Mailbox/Identity/Thread `/get`. Captured 1 canonical fixture + 1 replay. Stalwart RFC-conforms (silent empirical fix needed: short Id format, Stalwart drops oversized synthetic Ids). |
| **J1 Step 67 — `tresult_reference_deep_paths_live`** | Done | Three sub-tests covering simple, deep (`rpListThreadId`), and broken-back-reference cases. Captured 1 fixture + 1 replay. Stalwart RFC-conforms. |
| **J1 Step 68 — `tcreated_ids_envelope_live`** | Done | Two sub-tests over outgoing `createdIds` round-trip and cross-method `#cid` reference. Captured 1 fixture + 1 replay. Stalwart RFC-conforms. |
| **J1 Step 69 — `tmulti_instance_envelope_live`** | Done | Three `addGet[Mailbox]` invocations with distinct `properties` subsets. Captured 1 fixture + 1 replay. Stalwart RFC-conforms on order preservation and `properties` filtering. Library scope: typed `Mailbox.fromJson` parses full records; sparse projections verified at JsonNode level. |
| **J1 Step 70 — `tpatch_object_deep_paths_live`** | Done | Four sub-tests over typed flat patches (Identity + Mailbox) and raw-JSON deep paths. Captured 1 fixture + 1 replay. Stalwart deviations: deep-path `replyTo/0/name` projects as `invalidProperties` (RFC mandates `invalidPatch` for unknown-property paths); /set responses with only `notUpdated` omit `newState` (RFC mandates required). |
| **J1 Step 71 — `temail_submission_filter_completeness_live`** | Done | Six sub-tests covering all unexercised `EmailSubmissionFilterCondition` variants and `EmailSubmissionComparator` arms. Captured 1 fixture + 1 replay. Stalwart RFC-conforms across all six. |
| **J1 Step 72 — `tthread_keyword_filter_and_upto_id_live`** | Done | Five sub-tests over thread-keyword `EmailFilterCondition` variants and `Email/queryChanges.upToId`. Captured 2 fixtures + 2 replays. Stalwart RFC-conforms. |
| **J1 Step 73 — `tpostels_law_receive_live` + meta-test** | Done | Lenient-receive parser test via seed-via-forward + import. Captured 1 fixture + 1 replay + the round-trip integrity meta-test (78 fixtures categorised across Response / Session / RequestError parsers). |
| **J1 Step 74 — `tcombined_adversarial_round_trip_live` (capstone)** | Done | Five-invocation adversarial envelope mixing successes (Mailbox/get, Email/query, Identity/get) and failures (broken back-reference; immutable-property create). Captured 1 fixture + 1 replay. All prior J1 contracts hold simultaneously. |

Final tallies (2026-05-04):
- **Live tests**: 72 / 72 (58 pre-Phase-J + 14 new).
- **Captured fixtures**: 81 (57 pre-Phase-J + 24 from J1; one J fixture
  is implicit — Step 64 captures none by design).
- **Always-on captured replays**: 83 under `tests/serde/captured/`
  (82 fixture-driven + 1 round-trip integrity meta-test).
- **`git diff src/`** since Phase I: exactly one new proc
  (`sendRawHttpForTesting`) on `src/jmap_client/client.nim`. The
  H/I "no library changes" rule was consciously and exclusively
  broken for this single test-only escape hatch.

## Library-boundary reframing

Phase J makes one methodological change relative to Phases A–I.

Several prior phases framed assertions as "Stalwart returns X" — that
test passes if Stalwart conforms; it fails if Stalwart's behaviour is
RFC-permitted-but-different. Such assertions test the server, not
the client.

Phase J frames every assertion as a **library contract**: what does
the client's typed surface guarantee about wire emission, parsing,
error projection, pre-flight rejection, or round-trip integrity?
Stalwart is the real-world environment exercising the contract; its
specific responses are captured for parser-only regression but never
asserted as RFC compliance.

Concretely:

- **Wire emission**: tests assert the client produces JSON that any
  RFC-conforming server can interpret. Server-discretionary outcomes
  (response cardinality, sort tie-breaking, threading-merge timing,
  error-variant choice within an RFC-permitted set) are NOT
  asserted; only that the response parses through the typed surface
  without information loss.
- **Error projection**: tests assert `MethodError.fromJson` /
  `SetError.fromJson` / `RequestError.fromJson` project whichever
  variant the server returns through the typed enum AND preserve
  `rawType` losslessly. The assertion target is `errorType in
  RFC-permitted-set`, never `errorType == X`.
- **Captured fixtures pin Stalwart's choice** for regression; the
  always-on parser-only replays under `tests/serde/captured/`
  exercise the same contracts offline.
- **Postel's law on receive**: the client tolerates every shape the
  RFC permits, plus a few it doesn't (real-world server variation).
  Strictness lives in the typed-builder send path; lenience lives in
  the receive parser. Phase J asserts the lenience contract directly.

This reframing is incompatible with retroactively rewriting prior
phases — those tests are committed and pass against Stalwart 0.15.5.
Phase J adopts the discipline going forward; any retroactive cleanup
of A–I assertion phrasing belongs in a separate Phase K hardening
pass (see Forward arc).

## Context

Phase I closed on 2026-05-03 with 58 live `*_live.nim` tests passing
against Stalwart 0.15.5 (~30s wall-clock). Cumulative captured-replay
total: 57. The campaign covers every standard JMAP method on every
entity, full filter+sort algebra (Email, EmailSubmission), state-delta
for every entity that supports it, multi-principal observation,
EmailSubmission lifecycle with HOLDFOR cancel, cascade coherence
across three entity surfaces, and protocol-feature completeness across
pagination, truncation, body content, header forms, advanced
filter/sort.

What remains is the **library boundary** itself. The library
implements full RFC 8620 + 8621 client-side surface (modulo campaign-
deferred items). Its public contracts have unit, serde, property, and
protocol-test coverage. Several class-of-bug gaps have not been
live-tested:

1. **Request-level error rail completeness.** `RequestError.fromJson`
   (`errors.nim:51–104`) projects four typed variants
   (`urn:ietf:params:jmap:error:{notJSON,notRequest,unknownCapability,
   limit}`); ZERO have been live-tested. The HTTP-error classification
   path (`client.classifyHttpResponse`, `client.nim:518`) routes
   request-level JMAP errors into `cekRequest`; never live-asserted.
2. **MethodError typed-projection completeness.** Of 20
   `MethodErrorType` variants (`errors.nim:202–223`), six are
   exercised by the existing campaign (`metStateMismatch`,
   `metCannotCalculateChanges`, `metAnchorNotFound`,
   `metAccountNotFound`, `metForbidden`, `metInvalidArguments`).
   The other 14 typed variants — including the four hand-rollable via
   raw-JSON injection (`metUnknownMethod`,
   `metInvalidResultReference`, `metUnsupportedSort`,
   `metUnsupportedFilter`) — are typed-but-unverified at the wire.
3. **SetError typed-projection completeness.** Of 23
   `SetErrorType` variants (`errors.nim:256–290`), only two are
   exercised (`setMailboxHasChild`, `setMailboxHasEmail`). The other
   21 typed variants are unverified.
4. **Pre-flight + server-side enforcement parity.** The library's
   `validateLimits` (`client.nim:486`) enforces session-advertised
   `maxSizeRequest` / `maxCallsInRequest` / `maxObjectsInGet` /
   `maxObjectsInSet` BEFORE HTTP send, returning
   `Result[void, ValidationError]`. Neither client-side rejection
   nor the parser's tolerance for server-side enforcement (when the
   pre-flight is bypassed) has been wire-tested.
5. **`notFound` rail on /get.** The optional `notFound: seq[Id]`
   field on `GetResponse[T]` (`methods.nim:171, 669`) is parsed by
   the typed surface; never live-asserted.
6. **Result reference depth.** Phase A–I tested simple `#ref/ids`
   (Phase A) and the purpose-built `EmailQueryThreadChain` (arity-4,
   Phase C). Hand-rolled deep paths
   (`#ref/list/0/threadId` etc.) through the public
   `ResultReference` typed surface untested.
7. **`createdIds` envelope parameter.** RFC 8620 §3.3 — both
   `Request.createdIds` (`envelope.nim:80`) and
   `Response.createdIds` (`envelope.nim:86`) library surfaces exist;
   never live-tested.
8. **Multi-instance method calls in one envelope.** RFC 8620 §3.6
   requires `methodResponses` order to mirror `methodCalls` order.
   The library's response-handle resolution depends on this
   invariant; never live-asserted.
9. **PatchObject completeness.** Phase A7 exercised
   `keywords/$seen`. Deep paths (e.g., `replyTo/0/email` on
   Identity), null-removal patterns (RFC 8620 §5.3 "If the JSON
   value is null, the action is to remove that property"), and
   JSON-Pointer escaping (`~0`/`~1`) are untested.
10. **EmailSubmissionFilterCondition completeness.** Phase I60
    exercised one of six variants (`identityIds` plus `sentAt`
    sort). The other five (`threadIds`, `emailIds`, `undoStatus`,
    `before`, `after`) and the other two `EmailSubmissionComparator`
    arms (`emailId`, `threadId`) are untested.
11. **Thread-keyword filter conditions on Email/query.** Phase I55
    deferred. Three variants (`allInThreadHaveKeyword`,
    `someInThreadHaveKeyword`, `noneInThreadHaveKeyword` —
    `mail_filters.nim:82–84`) untested.
12. **Postel's-law receive lenience.** The library's lenient parsers
    (`parseUtcDateFromServer`, lenient `EmailAddress.fromJson`,
    `*FromServer` distinct-type variants) tolerate fractional-second
    dates, RFC 2047 encoded-words in `EmailAddress.name`, empty-vs-
    null table entries, and control-character bytes. This contract is
    unit-tested at the parser level but never live-tested against
    real wire variation.
13. **Round-trip integrity.** `toJson ∘ fromJson` is the core serde
    contract. Phase D introduced captured-fixture replay; the
    structural-shape assertions never explicitly check
    re-emit-then-diff identity.
14. **`upToId` queryChanges parameter.** Library surface exists
    (`methods.nim:358–372`); never live-tested.

Phase J closes all fourteen gaps. **No campaign-scope expansion** —
JMAP-Sharing draft, push, blob, Layer 5 C ABI, and performance/
concurrency remain explicitly out of scope per the campaign's "validate
existing RFC-aligned surface" discipline.

## Strategy

Continue Phase A–I's bottom-up discipline. Each step adds **exactly
one new library-contract dimension** the prior steps have not
touched.

Phase J introduces one methodological change: **two test-only escape
hatches** — `sendRawInvocation` (typed-builder bypass) and
`sendRawHttpForTesting` (pre-flight bypass) — without which the
adversarial dimensions cannot be exercised. The latter touches
`src/jmap_client/client.nim`, breaking the "git diff src/ is empty"
success criterion that Phases A–I observed. The break is scoped:
**ONE** new `*` proc with a `ForTesting` suffix, **NO** modification of
any existing surface, **NO** alteration of the production-path code.
Test-only intent is signalled at every call site by the explicit
`ForTesting` suffix.

Build order (Step 61 → Step 74):

1. **Step 61** — RequestError typed-projection completeness. Simplest
   error rail; library-only contract is total over four URIs.
2. **Step 62** — MethodError typed-projection (typed-surface
   bypass). Same methodology, different layer.
3. **Step 63** — SetError typed-projection completeness. Same
   methodology, third error layer.
4. **Step 64** — Pre-flight client-side rejection. Different rail
   (`Result[void, ValidationError]` BEFORE HTTP).
5. **Step 65** — Server-side enforcement parity. Pre-flight bypass
   via `sendRawHttpForTesting`; the parser's tolerance for whatever
   Stalwart returns when caps are exceeded.
6. **Step 66** — `notFound` rail across /get. Optional-field
   deserialisation contract.
7. **Step 67** — Result reference deep paths. Builder + serde
   contract for `ResultReference` toJson at depths the existing
   chain abstractions don't exercise.
8. **Step 68** — `createdIds` envelope parameter. RFC 8620 §3.3
   builder-and-parser round-trip.
9. **Step 69** — Multi-instance method calls in one envelope.
   `Response.methodResponses` ordering contract.
10. **Step 70** — PatchObject deep paths + null-removal + JSON-
    Pointer escaping.
11. **Step 71** — EmailSubmissionFilterCondition algebraic
    completeness + EmailSubmissionComparator full coverage.
12. **Step 72** — Thread-keyword filter conditions on Email/query +
    `Email/queryChanges` `upToId` parameter (folded — both touch
    Email/query parameter completeness).
13. **Step 73** — Postel's-law receive lenience (adversarial dates,
    encoded-words, empty-vs-null, control characters) + round-trip
    integrity over captured fixtures.
14. **Step 74 (capstone)** — Combined adversarial round-trip.

Step 74 is visibly harder than Step 61 by construction: one envelope
mixes broken back-reference (from 67) + RFC 2047 display name (from
73) + fractional-second `receivedAt` (from 73) + control-character
bytes in subject (from 73) + an oversized object on one method while
others succeed (from 65). Validates that the parser projects each
error variant correctly without one failure masking another, and
that successful method calls in the same envelope still round-trip
cleanly. Mirrors A7 / B12 / C18 / D24 / E30 / F36 / G42 / H48 / I60
capstone discipline.

## Phase J0 — preparatory escape-hatch + helper extraction

One commit. Touches `src/jmap_client/client.nim` (single new
test-only proc) and `tests/integration/live/mlive.nim` (four new
helpers). No existing surface modified.

### `client.sendRawHttpForTesting`

```nim
proc sendRawHttpForTesting*(
    client: var JmapClient, body: string
): JmapResult[envelope.Response]
```

Posts `body` directly to `session.apiUrl` via
`client.httpClient.request`, bypassing both `Request.toJson` and
`validateLimits`. Routes the response through the existing
`classifyHttpResponse` pipeline (`client.nim:518`) so
`lastRawResponseBody` is populated and HTTP-error classification is
unchanged. The `ForTesting` suffix and explicit `*` export make the
test-only intent visible at every call site. No production code
reads it; nimalyzer's `unused` rule is suppressed locally for this
proc with a `{.used.}` pragma.

### `mlive.sendRawInvocation`

```nim
proc sendRawInvocation*(
    client: var JmapClient,
    using: openArray[string],
    methodName: string,
    arguments: JsonNode,
    callId: string = "c0",
): Result[envelope.Response, ClientError]
```

Builds a `Request` envelope manually from raw inputs (no typed
builder). Used by Steps 62, 67, 70, 72, 74 to inject method names,
argument shapes, and back-reference paths the typed surface forbids
to construct. Funnels through the production `client.send` so
`validateLimits` still runs — the typed-builder bypass is at the
request-construction layer, not the validation layer.

### `mlive.buildOversizedRequest`

```nim
proc buildOversizedRequest*(
    accountId: AccountId, idCount: int
): Request
```

Constructs a `Request` carrying a single Mailbox/get with `idCount`
synthetic ids. Used by Step 64 to drive `validateLimits` past the
session-advertised `maxObjectsInGet` cap. Returns the `Request`
value (not a `RequestBuilder`) so `client.send(request)` sees the
full shape unmediated by builder smart construction.

### `mlive.injectBrokenBackReference`

```nim
func injectBrokenBackReference*(
    arguments: JsonNode, refField: string, refPath: string
): JsonNode
```

Wraps `arguments` with a `#refField` JSON-Pointer entry whose target
path is `refPath` (caller-supplied; intentionally broken). Used by
Steps 62, 67, 74. Pure helper; returns a `JsonNode` ready to pass
to `sendRawInvocation`.

### Commit shape

One commit. SPDX header preserved. Library proc added in
`client.nim` immediately after the existing `lastRawResponseBody`
accessor (~line 591). Helpers added in source order after the
existing Phase I helpers in `mlive.nim`. Must pass `just test` —
no test exercises the new symbols at this commit.

## Phase J1 — fourteen live tests

Each test follows the project test idiom verbatim (`block <name>:`
+ `doAssert`) and is gated on `loadLiveTestConfig().isOk` so the
file joins testament's megatest cleanly under `just test-full`
when env vars are absent. All fourteen are listed in
`tests/testament_skip.txt` so `just test` skips them; run via
`just test-integration`.

Every step's body is structured as:

- **LIBRARY CONTRACT** — the typed-surface guarantee being verified.
- **Body** — the methodology.
- **What this proves about the library** — the bug-class shielded.
- **Capture** — the captured fixture name.
- **Anticipated divergences** — phrased as set-membership over
  RFC-permitted choices, never equality on Stalwart's specific
  output.

### Step 61 — `trequest_level_errors_live`

LIBRARY CONTRACT: `RequestError.fromJson` (`errors.nim:51–104`)
projects each of the four RFC 8620 §3.6.1 URIs into the typed
`RequestErrorType` enum AND preserves the URI losslessly in
`rawType`. `parseRequestErrorType` is total — unknown URIs project
to `retUnknown` with the URI captured in `rawType`. The HTTP-error
classification path (`client.classifyHttpResponse`) routes
request-level errors into the `cekRequest` arm of `ClientError`,
distinct from transport-layer errors.

Body — four sequential `sendRawHttpForTesting` calls:

1. **`notJSON`** — body `"this is not JSON"`. Assert response is
   `Err(ClientError)` whose `kind == cekRequest` AND
   `request.errorType == retNotJson` AND
   `request.rawType == "urn:ietf:params:jmap:error:notJSON"`.
   Capture `request-error-not-json-stalwart`.
2. **`notRequest`** — well-formed JSON, wrong shape: `{"foo":"bar"}`.
   Same assertion shape with `retNotRequest`. Capture
   `request-error-not-request-stalwart`.
3. **`unknownCapability`** — well-formed Request with a synthetic
   capability URN: `{"using":["urn:test:phase-j:bogus"],
   "methodCalls":[]}`. Same assertion shape with
   `retUnknownCapability`. Capture
   `request-error-unknown-capability-stalwart`.
4. **`limit`** — drive past Stalwart's
   `urn:ietf:params:jmap:core` `maxConcurrentRequests` (or whichever
   request-layer cap is easiest to elicit). Same assertion shape
   with `retLimit`. Capture `request-error-limit-stalwart`.

What this proves about the library:

- `parseRequestErrorType` total function (no panic on unknown URI)
- `RequestError.fromJson` carries `rawType` losslessly
- The HTTP-response classification path routes JMAP request-level
  errors into the correct ClientError arm

Anticipated divergences:

- For `limit`, Stalwart's specific cap-vector is server-config-
  dependent. The test selects whichever cap is easiest to elicit;
  the captured fixture pins Stalwart's choice for replay regression.

### Step 62 — `tmethod_error_typed_projection_live`

LIBRARY CONTRACT: `MethodError.fromJson` (`errors.nim:225–254`)
projects the four method-level error variants the typed builder
forbids (`metUnknownMethod`, `metInvalidResultReference`,
`metUnsupportedSort`, `metUnsupportedFilter`) through the typed
`MethodErrorType` enum AND preserves `rawType` losslessly. The
sealed typed builders correctly forbid construction of these
shapes — this test confirms that when an adversary BYPASSES the
typed surface, the parser still tolerates the response.

Body — four sequential `sendRawInvocation` calls:

1. **`unknownMethod`** — `sendRawInvocation(using=@[mailUri],
   methodName="Mailbox/snorgleflarp", arguments=%*{"accountId":...},
   callId="c0")`. Assert
   `methodErr.errorType == metUnknownMethod` AND
   `methodErr.rawType == "unknownMethod"`. Capture
   `method-error-unknown-method-stalwart`.
2. **`invalidResultReference`** — issue Email/query, then
   `Email/get` with `injectBrokenBackReference(arguments,
   "ids", "/methodResponses/0/notAField/that/exists")`. Assert
   `metInvalidResultReference` and rawType. Capture
   `method-error-invalid-result-reference-stalwart`.
3. **`unsupportedSort`** — Email/query with synthetic property:
   `arguments = %*{"accountId": ..., "sort": [{"property":
   "phaseJSyntheticProperty"}]}` via `sendRawInvocation`. Assert
   `metUnsupportedSort` and rawType. Capture
   `method-error-unsupported-sort-stalwart`.
4. **`unsupportedFilter`** — Email/query with synthetic property
   in the filter condition. Same shape with `metUnsupportedFilter`.
   Capture `method-error-unsupported-filter-stalwart`.

What this proves about the library:

- `MethodError.fromJson` is total over the typed enum surface
- `rawType` preservation holds losslessly for each variant
- The sealed typed builders are not the only line of defence —
  the parser is independently resilient

Anticipated divergences:

- Stalwart 0.15.5 may project unsupportedSort/unsupportedFilter
  through `metInvalidArguments` instead, per RFC permissiveness.
  The library handles either choice; assertion is over a
  set-membership window. The captured fixtures pin the chosen
  variant for replay regression.

### Step 63 — `tset_error_typed_projection_live`

LIBRARY CONTRACT: `SetError.fromJson` (`errors.nim:300+`) projects
the unexercised variants (`setNotFound`, `setInvalidPatch`,
`setInvalidProperties`, `setBlobNotFound`) through the typed
`SetErrorType` enum AND preserves `rawType`. The case-object
variants that carry payloads (`setInvalidProperties.properties`,
`setAlreadyExists.existingId`) deserialise correctly when present.

Body — four sequential sub-tests in one block:

1. **`setNotFound`** — `Email/set destroy` with a synthetic id.
   Assert `destroyResults[syntheticId].isErr` AND
   `errorType == setNotFound`. Capture
   `set-error-not-found-stalwart`.
2. **`setInvalidPatch`** — `Email/set update` via
   `sendRawInvocation` carrying a malformed JSON-Pointer path
   (`"/keywords/~7invalid"` — `~7` is not a valid pointer escape
   per RFC 6901 §3). Assert `errorType == setInvalidPatch`. Capture
   `set-error-invalid-patch-stalwart`.
3. **`setInvalidProperties`** — `Email/set create` setting an
   immutable property (e.g., the server-set `id` field) via
   `sendRawInvocation`. Assert
   `errorType == setInvalidProperties` AND
   `properties.len >= 1` (the case-object payload carries the
   rejected property names). Capture
   `set-error-invalid-properties-stalwart`.
4. **`setBlobNotFound`** — `Email/import` with a synthetic
   `BlobId`. Assert `errorType == setBlobNotFound`. Capture
   `set-error-blob-not-found-stalwart`.

What this proves about the library:

- `SetError.fromJson` is total over the typed enum
- The case-object variants (`setInvalidProperties`,
  `setAlreadyExists` etc.) deserialise the payload correctly when
  present
- `rawType` preservation holds for SetError as it does for
  RequestError and MethodError

Anticipated divergences:

- Stalwart may emit `setInvalidArguments` (set-level) where the RFC
  permits `setInvalidProperties`. Set-membership accepts either.
- The exact `properties` array contents are server-discretionary;
  the test asserts non-empty membership only.

### Step 64 — `tpreflight_validation_live`

LIBRARY CONTRACT: `validateLimits` (`client.nim:486–494`) rejects
requests exceeding session-advertised caps via
`Result[void, ValidationError]` BEFORE any HTTP send. The four
caps consulted are `maxCallsInRequest`, `maxObjectsInGet`,
`maxObjectsInSet`, `maxSizeRequest`. The rejection happens at
`send(request: Request)` line 650; no HTTP traffic occurs.

Body — four sequential sub-tests in one block:

1. Fetch session; capture `caps = session.coreCapabilities`.
2. **`maxObjectsInGet`** — `request =
   buildOversizedRequest(accountId, idCount =
   int(caps.maxObjectsInGet) + 1)`. Send via
   `client.send(request)`. Assert `Err(ClientError)` whose
   `transport.message` (or `request.errorType`) names the cap.
   No HTTP request fires (verified by inspecting
   `client.lastRawResponseBody.len == 0` if no prior request
   was made; otherwise, time-bounded check).
3. **`maxCallsInRequest`** — build a `Request` with
   `caps.maxCallsInRequest + 1` invocations. Same rejection
   contract.
4. **`maxObjectsInSet`** — single `Email/set create` with
   `caps.maxObjectsInSet + 1` create entries. Same rejection
   contract.
5. **`maxSizeRequest`** — construct a `Request` whose serialised
   size exceeds `caps.maxSizeRequest` (large `description` field
   on a synthetic invocation). Same rejection contract; the
   serialised-size check is at `client.nim:657–665`.

What this proves about the library:

- `validateLimits` is consulted BEFORE HTTP send (no wasted round
  trip)
- Each of the four caps produces a distinct rejection rail
- The rejection projects through `Result[T, ClientError]` cleanly,
  no exceptions raised

Anticipated divergences:

- Stalwart 0.15.5 advertises specific cap values; the test
  computes its threshold from the live session, not hardcoded.
  The library's pre-flight is contract-tested against whatever
  the server advertises.

### Step 65 — `tserver_side_enforcement_parity_live`

LIBRARY CONTRACT: When client pre-flight is bypassed via
`sendRawHttpForTesting`, the parser handles whatever wire shape
Stalwart emits for cap-exceeded scenarios. The
`MethodErrorType` typed projection covers `metRequestTooLarge`
and `metTooManyChanges` losslessly.

Body — three sequential `sendRawHttpForTesting` calls:

1. Fetch session; capture caps.
2. **`maxSizeRequest` server-side** — serialise a Request whose
   size exceeds `caps.maxSizeRequest` and submit via
   `sendRawHttpForTesting` (skipping client pre-flight). Assert
   the response projects through `MethodError.fromJson` (or
   `RequestError.fromJson` if Stalwart routes to the request
   layer) — accept either rail per RFC. Whichever rail Stalwart
   chooses, `errorType` and `rawType` must be parsed losslessly.
   Capture `server-enforcement-max-size-request-stalwart`.
3. **`maxObjectsInGet` server-side** — same but for the get cap.
   Capture `server-enforcement-max-objects-in-get-stalwart`.
4. **`maxCallsInRequest` server-side** — same but for the call
   count cap. Capture
   `server-enforcement-max-calls-in-request-stalwart`.

What this proves about the library:

- The parser is resilient to oversized-request rejection at
  whichever rail Stalwart routes through
- `sendRawHttpForTesting` integrates correctly with the
  `classifyHttpResponse` pipeline
- `lastRawResponseBody` is populated even for raw-bytes sends,
  preserving the captured-fixture loop's invariants

Anticipated divergences:

- Stalwart may close the connection on extreme oversize rather
  than emit a JMAP error. The library projects that as
  `tekNetwork` / `tekTimeout`; assertion is set-membership over
  `{cekRequest, cekTransport}`. The captured fixture pins the
  chosen rail.

### Step 66 — `tnotfound_rail_get_live`

LIBRARY CONTRACT: `GetResponse[T].notFound` (`methods.nim:171, 669`)
correctly deserialises a populated `notFound: seq[Id]` array when
some requested ids do not exist server-side. The contract holds
across every entity that supports `/get`.

Body — four sequential `client.send` calls in one block:

1. Resolve mail account, inbox.
2. Seed one Email via `seedSimpleEmail`; capture `realEmailId`.
3. Generate a synthetic `Id` known not to collide
   (28-octet `'z'` per Phase E29 precedent), call it
   `syntheticId`.
4. **Email/get with mixed ids** —
   `addEmailGet(ids = directIds(@[realEmailId, syntheticId]))`.
   Assert `getResp.list.len == 1` AND
   `getResp.notFound.len == 1` AND `syntheticId in getResp.notFound`.
5. **Mailbox/get with synthetic id** — same pattern. Assert the
   synthetic id appears in `notFound`.
6. **Identity/get on submission account** — same pattern.
7. **Thread/get with synthetic threadId** — same pattern.

Capture: `notfound-rail-get-stalwart` (after step 4).

What this proves about the library:

- `parseOptIdArray` (`methods.nim:669`) handles populated arrays
- Every entity registered via `registerJmapEntity` exposes the
  `notFound` field correctly through the typed surface
- `Id` smart-construction at the parse boundary is consistent
  across entity types

Anticipated divergences:

- Stalwart may reject the synthetic `Id` shape upfront with
  `metInvalidArguments` if the id format-validation is strict at
  the request layer rather than per-record. If so, the library
  projects through `methodErr` correctly (a separate rail than
  `notFound`); test passes with a documented set-membership over
  `{notFound-populated, methodErr-projected}`.

### Step 67 — `tresult_reference_deep_paths_live`

LIBRARY CONTRACT: The library's `ResultReference` typed surface
(`envelope.nim`, `Referencable[T]` shape) emits JSON Pointer paths
that any RFC-conforming server interprets correctly. Deep paths
through arbitrary nested response shapes round-trip without
information loss.

Body — three sub-tests in one block:

1. Resolve mail account, inbox.
2. Seed three emails via `seedEmailsWithSubjects`.
3. **Simple reference** (Phase A precedent control) — Email/query
   then Email/get with `#ref/ids` back-reference. Assert success
   (non-regression).
4. **Deep reference** — Email/query → Email/get(properties:
   ["id", "threadId"]) → Thread/get with
   `#ref/list/0/threadId` (depth-3 path through the get response).
   Use `sendRawInvocation` if the typed surface doesn't expose
   arbitrary depth; verify the typed surface DOES support this
   via `mail_builders.nim:227–249` patterns. Assert all three
   responses parse cleanly and `Thread/get.list.len == 1`.
5. **Adversarial path** — `sendRawInvocation` with an
   intentionally broken back-reference path (e.g.,
   `#ref/list/99/threadId` where index 99 doesn't exist). Assert
   the parser projects `metInvalidResultReference` losslessly.

Capture: `result-reference-deep-path-stalwart` (after step 4).

What this proves about the library:

- `ResultReference.toJson` produces JSON Pointer paths Stalwart
  accepts at depth ≥ 3
- The parser tolerates a broken back-reference's error projection
  on the same rail as a successful chain

Anticipated divergences:

- Stalwart's JSON Pointer evaluator is strict on path syntax
  per RFC 6901; the library's emission must match exactly.
  Tests set-membership over the `metInvalidResultReference` /
  `metInvalidArguments` rails for the broken-path case.

### Step 68 — `tcreated_ids_envelope_live`

LIBRARY CONTRACT: The library's `Request.createdIds` field
(`envelope.nim:80`) and `Response.createdIds` (`envelope.nim:86`)
round-trip per RFC 8620 §3.3. When a client passes `createdIds`
on the request, the server may persist them and echo back; the
library's typed surface preserves the table both ways.

Body — three sequential `sendRawInvocation` calls (RequestBuilder
may not expose `createdIds`; verify and inline if not):

1. Resolve mail account, inbox.
2. **Issue Request with `createdIds` populated** — pre-seed the
   table with `{cid: knownEmailId}` and issue a no-op
   `Core/echo`. Inspect `Response.createdIds`. Assert it is
   `Opt.some` AND contains the seeded entry.
3. **Round-trip with creation-then-reference in same envelope** —
   issue `Email/set create` with cid `"draft1"`, followed by a
   second method invocation that references `#draft1` for the
   `emailId` field of an `EmailSubmission/set create`. Assert
   the second method's response surfaces the resolved id
   correctly.

Capture: `created-ids-envelope-stalwart`.

What this proves about the library:

- `Request.createdIds.toJson` emits the wire shape RFC 8620 §3.3
  specifies
- `Response.createdIds.fromJson` parses both `null`, absent, and
  populated table cases per Postel's law
- Cross-method creation-id references resolve through the typed
  `IdOrCreationRef` surface

Anticipated divergences:

- Stalwart 0.15.5's persistence policy for `createdIds` is
  server-discretionary — it MAY persist or MAY not. The library
  parses whichever Stalwart returns; assertion is on the typed
  field's `Opt.some-or-none` membership only.

### Step 69 — `tmulti_instance_envelope_live`

LIBRARY CONTRACT: `Response.methodResponses` order mirrors
`Request.methodCalls` order per RFC 8620 §3.6. The library's
response-handle resolution
(`resp.get(handle)`) depends on this invariant; multiple invocations
of the same method (different ids, different callIds) coexist in
one envelope.

Body — one sequential `client.send` call with a multi-method
RequestBuilder:

1. Resolve mail account.
2. **Build a Request with three Mailbox/get invocations**, each
   with a different `accountId` argument shape OR distinct
   creationLabel-derived callIds. (Test the typed builder's
   ability to enqueue heterogeneous-callId invocations of the
   same method.) Send.
3. Assert `resp.methodResponses.len == 3` AND each invocation's
   `callId` matches its request position. Extract via three
   independent `resp.get(handleN)` calls; assert each yields the
   correct entity shape.

Capture: `multi-instance-envelope-stalwart`.

What this proves about the library:

- `RequestBuilder` correctly enqueues distinct callIds per
  invocation (no collision on default callId scheme)
- `resp.get(handle)` resolution by callId works across multiple
  same-method invocations

Anticipated divergences:

- Stalwart may bundle responses in any order if it interprets
  RFC 8620 §3.6 loosely. The library asserts callId-based
  resolution, not positional resolution; the contract holds even
  under reordering.

### Step 70 — `tpatch_object_deep_paths_live`

LIBRARY CONTRACT: `PatchObject` (`serialisation.nim`) emits
JSON Pointer paths that round-trip correctly for nested
properties, null-removal, and JSON-Pointer escape sequences
(`~0` for `~`, `~1` for `/`). The typed `update` arms on
mutable entities (Identity, Mailbox, VacationResponse) accept
deep-path patches.

Body — four sequential sub-tests:

1. Resolve submission account; resolve / create alice's identity
   (must have multi-entry `replyTo`).
2. **Deep path on Identity.replyTo** —
   `addIdentitySet(update = {identityId: PatchObject({"/replyTo/0/name":
   "phase-j step-70 renamed"})})`. Read back via Identity/get;
   assert the targeted address's name updated, others unchanged.
3. **Null-removal** — Identity update with
   `PatchObject({"/textSignature": null})` to remove the
   signature field. Assert the field is absent in the read-back
   (or is `Opt.none`).
4. **JSON-Pointer escape (`~1` for `/`)** — Email/set update
   with `keywords/$urgent` (where `$urgent` happens to contain
   no special chars; use a synthetic keyword with `/` escape if
   the library allows). Verify the library's emission encodes
   `/` as `~1` per RFC 6901 §3.
5. **Mailbox parentId-to-null** — move a Mailbox to root:
   `addMailboxSet(update = {mailboxId: PatchObject({"/parentId":
   null})})`. Assert read-back shows `parentId.isNone`.

Capture: `patch-object-deep-paths-stalwart`.

What this proves about the library:

- `PatchObject.toJson` emits valid JSON Pointer paths
- Null-removal pattern survives the round-trip
- JSON-Pointer escape sequences (`~0`/`~1`) are encoded correctly
- Deep-path updates leave non-targeted siblings untouched

Anticipated divergences:

- Stalwart may emit the property-removed shape as `null` vs
  absent on read-back. The library's `Opt[T]` parsers handle
  both; assertion is `field.isNone` regardless of wire shape.

### Step 71 — `temail_submission_filter_completeness_live`

LIBRARY CONTRACT: Every variant of `EmailSubmissionFilterCondition`
(`email_submission.nim:311`: `identityIds`, `threadIds`,
`emailIds`, `undoStatus`, `before`, `after`) and every arm of
`EmailSubmissionComparator` (`emailId`, `threadId`, `sentAt`)
serialises to a wire shape Stalwart accepts. Phase I60 covered
`identityIds` + `sentAt`; this step closes the gap.

Body — six sequential `client.send` calls in one block:

1. Setup — resolve accounts; reuse Step I60's two-identity corpus
   construction or seed afresh via `seedSubmissionCorpus`.
2. **`threadIds` filter** — pick the threadId of one submission's
   email; query with `EmailSubmissionFilterCondition(threadIds:
   Opt.some(parseNonEmptyIdSeq(@[threadId])))`. Assert response
   parses cleanly through the typed surface.
3. **`emailIds` filter** — same shape with `emailIds` filter.
4. **`undoStatus` filter** — `undoStatus: Opt.some(usFinal)`.
5. **`before` / `after` UTC filters** — pair of queries with
   gap-date thresholds.
6. **Sort by `emailId`** — ascending and descending. Assert
   response parses cleanly.
7. **Sort by `threadId`** — ascending. Assert response parses
   cleanly.

Capture: `email-submission-filter-completeness-stalwart`.

What this proves about the library:

- All six `EmailSubmissionFilterCondition` variants emit valid
  wire shapes
- All three `EmailSubmissionComparator` arms emit valid wire
  shapes
- The serde layer handles each variant correctly (toJson +
  fromJson for the response envelope)

Anticipated divergences:

- Cardinality of result sets is server-discretionary; the test
  asserts only that responses parse cleanly through the typed
  surface, never that specific submissions surface.

### Step 72 — `tthread_keyword_filter_and_upto_id_live`

LIBRARY CONTRACT: `EmailFilterCondition` thread-keyword variants
(`mail_filters.nim:82–84`: `allInThreadHaveKeyword`,
`someInThreadHaveKeyword`, `noneInThreadHaveKeyword`) emit valid
wire shapes. The `upToId` parameter on `Email/queryChanges`
(`methods.nim:358–372`) round-trips correctly.

Body — four sequential `client.send` calls in one block:

1. Resolve mail account, inbox. Seed two threaded emails with
   distinct keywords (e.g., one with `$flagged`, one without)
   via `seedThreadedEmails`.
2. **`someInThreadHaveKeyword`** — Email/query with filter
   condition. Assert response parses cleanly.
3. **`allInThreadHaveKeyword`** — same shape. Assert parses.
4. **`noneInThreadHaveKeyword`** — same shape. Assert parses.
5. **`upToId` parameter** — Email/queryChanges with
   `upToId = Opt.some(<id>)`. Assert response's typed surface
   handles the partial-changes shape.

Capture: `thread-keyword-filter-stalwart` (after step 4),
`email-querychanges-up-to-id-stalwart` (after step 5).

What this proves about the library:

- All three thread-keyword filter variants emit valid wire
  shapes
- `Email/queryChanges` correctly emits the optional `upToId`
  parameter
- The library's typed builders + parsers cover the
  RFC-permitted parameter set fully

Anticipated divergences:

- Stalwart's threading-pipeline asynchrony (Phase C18 / H48
  catalogue) may affect thread-keyword evaluation timing. The
  test does not assert specific result-set membership; only
  that the responses parse cleanly.

### Step 73 — `tpostels_law_receive_live`

LIBRARY CONTRACT: The library's lenient parsers
(`parseUtcDateFromServer`, lenient `EmailAddress.fromJson`,
`*FromServer` distinct-type variants, `Opt[T]` field handling)
tolerate every shape RFC permits the server to emit, plus a few
real-world variants the RFC technically forbids (encoded-words on
display names, fractional-second dates, etc.). The receive-side
parser is more lenient than the send-side smart constructors,
per Postel's law. **Round-trip integrity** — for read-side
fields, `toJson ∘ fromJson` is identity (modulo canonical JSON
formatting).

Body — five sequential sub-tests:

1. Resolve mail account, inbox.
2. **Adversarial-MIME Email/import** — construct an inner RFC
   5322 message via `buildInnerRfc822Message` carrying:
   - RFC 2047 encoded-word in From: name
     (`=?UTF-8?Q?h=C3=A9llo?= <alice@example.com>`)
   - Fractional-second Date header
     (`Date: Mon, 03 May 2026 12:34:56.789 +0000`)
   - Subject containing a control char
     (`Subject: phase-j 73 \x01 sentinel`)
   Email/import the inner message; capture the resulting Email
   id.
3. **Read back via Email/get** with full-property fetch. Assert
   the typed parsers tolerate whatever Stalwart emits — no
   exception propagated, all `Opt[T]` fields populated or
   absent cleanly. Capture
   `postels-law-receive-adversarial-mime-stalwart`.
4. **Round-trip integrity** — for the captured response, parse
   each invocation's `arguments` via the typed
   `*Response.fromJson`, re-emit via `toJson`, compare against
   the original (canonicalising both via `pretty`). Assert
   identity. Capture serves as the regression fixture.
5. **Empty-vs-null table entries** — issue Email/get for an
   email with empty `keywords` and empty `mailboxIds`. Assert
   the parser handles both `{}` and `null` for these fields
   without distinguishing them at the typed-surface level.

Capture: `postels-law-receive-adversarial-mime-stalwart` (step 3),
plus a parser-only fixture replay test under
`tests/serde/captured/` that exercises round-trip integrity over
ALL committed fixtures (not Phase J specific).

What this proves about the library:

- The receive-side parsers are strictly more lenient than the
  smart constructors (Postel's law)
- Round-trip identity holds for the read-side response shapes
- Empty/null/absent variants for `Opt[T]` fields are
  indistinguishable at the typed-surface level (one of the
  smart-design invariants)

Anticipated divergences:

- Stalwart may normalise some of the adversarial input
  (e.g., decoding RFC 2047 encoded-words server-side, normalising
  fractional-second dates to whole seconds). The test asserts
  only that whatever Stalwart emits parses cleanly; not that
  Stalwart preserves the adversarial shape.
- Round-trip integrity has known asymmetries: server-set
  fields with no client-side smart constructor may not round-trip
  exactly. The test scopes the diff to a known-stable subset
  documented in the test body.

### Step 74 — `tcombined_adversarial_round_trip_live` (capstone)

LIBRARY CONTRACT: All prior J1 contracts hold simultaneously when
combined into one round-trip. The parser correctly projects each
error variant in a multi-method envelope without one failure
masking another, and successful method calls in the same envelope
still round-trip cleanly.

Body — one sequential `sendRawHttpForTesting` call carrying a
hand-crafted Request envelope mixing five adversarial dimensions:

1. Setup — resolve mail account, inbox.
2. Build a Request envelope (raw JSON) with five method
   invocations, in order:
   - `c0`: legitimate `Mailbox/get` (no filter, all properties).
     Expected: success.
   - `c1`: legitimate `Email/query` with subject filter.
     Expected: success. Used for `c2`'s back-reference.
   - `c2`: `Email/get` with `#ref/list/0/notAField/threadId`
     (broken back-reference). Expected:
     `metInvalidResultReference`.
   - `c3`: `Email/set` create with synthetic immutable property
     in `bodyStructure`. Expected: `setInvalidProperties` on the
     creation outcome.
   - `c4`: legitimate `Identity/get` on submission account.
     Expected: success.
3. Send via `sendRawHttpForTesting`.
4. Capture `combined-adversarial-round-trip-stalwart`.
5. Assert every method's response surfaces:
   - `c0`, `c1`, `c4`: `resp.get(handleN).isOk` AND parses
     cleanly into the typed entity surface.
   - `c2`: `resp.get(handle).isErr` AND
     `methodErr.errorType == metInvalidResultReference` AND
     `methodErr.rawType` preserved.
   - `c3`: success at the method level, BUT the create-result
     for the synthetic cid is `Err(SetError)` whose
     `errorType in {setInvalidProperties, setForbidden}` (set-
     membership accepting either).
6. **Round-trip integrity** — re-emit each method's `arguments`
   via `toJson`; assert identity against the captured original
   for all successful methods.

What this proves about the library:

- All J1 contracts compose without interference
- Error-rail isolation: a failure in one method does not
  contaminate the parsing of another method's success
- Round-trip integrity holds in the multi-method case

Anticipated divergences:

- Stalwart MAY route some invocations to the request-error rail
  if it flags one as adversarial early. If `c0`/`c1`/`c4` would
  fail under such routing, the test's assertion-set must accept
  request-level rejection as an alternative (set-membership over
  `{Ok, Err(metXxx), Err(retXxx)}`). The captured fixture pins
  Stalwart's actual routing.

## Captured-fixture additions

Approximately **25 new fixtures** committed under
`tests/testdata/captured/`, captured against a freshly-reset
Stalwart 0.15.5 with `JMAP_TEST_CAPTURE=1 just test-integration`:

- `request-error-not-json-stalwart` (Step 61)
- `request-error-not-request-stalwart` (Step 61)
- `request-error-unknown-capability-stalwart` (Step 61)
- `request-error-limit-stalwart` (Step 61)
- `method-error-unknown-method-stalwart` (Step 62)
- `method-error-invalid-result-reference-stalwart` (Step 62)
- `method-error-unsupported-sort-stalwart` (Step 62)
- `method-error-unsupported-filter-stalwart` (Step 62)
- `set-error-not-found-stalwart` (Step 63)
- `set-error-invalid-patch-stalwart` (Step 63)
- `set-error-invalid-properties-stalwart` (Step 63)
- `set-error-blob-not-found-stalwart` (Step 63)
- `server-enforcement-max-size-request-stalwart` (Step 65)
- `server-enforcement-max-objects-in-get-stalwart` (Step 65)
- `server-enforcement-max-calls-in-request-stalwart` (Step 65)
- `notfound-rail-get-stalwart` (Step 66)
- `result-reference-deep-path-stalwart` (Step 67)
- `created-ids-envelope-stalwart` (Step 68)
- `multi-instance-envelope-stalwart` (Step 69)
- `patch-object-deep-paths-stalwart` (Step 70)
- `email-submission-filter-completeness-stalwart` (Step 71)
- `thread-keyword-filter-stalwart` (Step 72)
- `email-querychanges-up-to-id-stalwart` (Step 72)
- `postels-law-receive-adversarial-mime-stalwart` (Step 73)
- `combined-adversarial-round-trip-stalwart` (Step 74)

Each ships with an always-on parser-only replay test under
`tests/serde/captured/`. Variant assertions are precise where the
typed surface is total (`metInvalidResultReference` projection,
`setInvalidProperties` case-object payload); set-membership where
the wire has run-dependent or server-discretionary content.

Cumulative captured-replay total rises from **57 to ~82**.

Step 73 additionally adds an **infrastructure-only** parser-replay
test under `tests/serde/captured/` that iterates every committed
fixture and asserts `toJson ∘ fromJson` round-trip integrity for
the read-side fields. This is a meta-test, not phase-specific;
it surfaces any regression in the lossless-preservation contract
across the entire fixture corpus.

NOT listed in `testament_skip.txt` — these are always-on parser
regressions that run under `just test` and `just ci`.

## Predictable wire-format divergences (Phase J catalogue)

Forward-looking — to be confirmed during J1 execution and amended
in-flight per Phase E precedent.

1. **Request-rail `limit` cap-vector choice** (Step 61). Stalwart's
   specific `limit` cap is server-config-dependent; the library
   parses whichever URI Stalwart returns. Captured fixture pins.
2. **`metUnsupportedSort` vs `metInvalidArguments`** (Step 62).
   Stalwart MAY route synthetic-property sort/filter rejection
   through `metInvalidArguments`. Set-membership over
   `{metUnsupportedXxx, metInvalidArguments}`.
3. **`setInvalidProperties` vs set-level `invalidArguments`**
   (Step 63). Set-membership accepts either.
4. **Pre-flight rejection rail granularity** (Step 64). The
   library's `validateLimits` returns one error variant per
   exceeded cap; Stalwart's enforcement may collapse multiple
   exceeded caps into one error. Set-membership.
5. **Server-side oversize routing** (Step 65). Stalwart MAY route
   to `metRequestTooLarge`, `retLimit`, OR close the connection.
   Set-membership over `{cekRequest, cekTransport, methodErr}`.
6. **`notFound` populated vs separate methodErr** (Step 66).
   Stalwart MAY upfront-reject malformed synthetic `Id`s via
   `metInvalidArguments` rather than per-record `notFound`.
   Set-membership.
7. **`createdIds` persistence** (Step 68). Stalwart MAY persist or
   ignore caller-supplied `createdIds`. Set-membership over the
   typed `Opt[Table]` field.
8. **JSON-Pointer escape-sequence handling** (Step 70). Stalwart
   MAY normalise paths or reject some escapes. The library's
   emission must match RFC 6901; assertion is on RFC-conforming
   round-trip, not Stalwart-specific behaviour.
9. **Multi-method response ordering** (Step 69). RFC 8620 §3.6
   pins this; the library asserts callId-resolution, robust to
   any order. Defensive even though Stalwart conforms.
10. **MIME normalisation of adversarial input** (Step 73).
    Stalwart MAY decode encoded-words / normalise dates / strip
    control chars in its MIME pipeline. The library handles
    whatever shape emerges; the captured fixture documents.
11. **Round-trip integrity scope** (Step 73 + meta-test). Some
    server-set fields with no client-side smart constructor may
    not round-trip exactly. The meta-test scopes the diff to the
    contract-stable subset; documented in the test.
12. **Combined-envelope failure-isolation** (Step 74). RFC 8620
    §3.6 is silent on whether one method's failure can
    contaminate another's parsing. The library asserts
    independence; if Stalwart routes a multi-failure envelope
    differently, the captured fixture pins it and the assertion
    set is widened.

## Success criteria

Phase J is complete when:

- [ ] Phase J0's commit lands with one library proc
  (`sendRawHttpForTesting`) and four mlive helpers
  (`sendRawInvocation`, `buildOversizedRequest`,
  `injectBrokenBackReference`, plus any narrow shared support).
- [ ] All fourteen new live test files exist under
  `tests/integration/live/` with the established idiom
  (license, docstring, single `block`,
  `loadLiveTestConfig().isOk` guard, explicit `client.close()`,
  `doAssert` with narrative messages).
- [ ] All fourteen new files are listed in
  `tests/testament_skip.txt` alongside the Phase A six, B five,
  C six, D six, E six, F six, G six, H six, I twelve.
- [ ] `just test-integration` exits 0 with **seventy-two** live
  tests passing (58 from A–I + 14 from J).
- [ ] Approximately **25 new captured fixtures** exist under
  `tests/testdata/captured/` (some steps capture multiple).
- [ ] **25 new always-on parser-only replay tests** exist under
  `tests/serde/captured/` and pass under `just test`. Cumulative
  count: ~82.
- [ ] One **meta-test** under `tests/serde/captured/` iterates
  every committed fixture and asserts `toJson ∘ fromJson`
  round-trip integrity for the contract-stable read-side subset.
- [ ] `just ci` is green (reuse + fmt-check + lint + analyse +
  test).
- [ ] No new Nimble dependencies, no new devcontainer packages —
  the 2026-05-01 devcontainer-parity rule (Phase A §Step 6 retro)
  holds throughout.
- [ ] `git diff src/` shows **exactly one** new proc
  (`sendRawHttpForTesting`) added to
  `src/jmap_client/client.nim`. No other production-path
  modifications. The "no library changes" criterion of Phases
  H/I is consciously broken in this single, scoped way; the
  break is documented in the success criteria above.
- [ ] Every divergence between Stalwart's wire shape and the
  test's expected behaviour has been classified (test premise /
  server quirk / client bug) and resolved at the right layer; no
  test papers over a real client bug.
- [ ] Total wall-clock for the new tests under ~25s on the
  devcontainer (Phase J is dominated by raw-HTTP probes; no
  threading-asynchrony loops; Steps 64, 65 are sub-second each;
  Step 74 capstone is ~3s).
- [ ] **Library-boundary discipline review**: every test body
  contains an explicit `LIBRARY CONTRACT` comment naming the
  client-side guarantee verified, AND no assertion targets
  Stalwart's RFC-compliance. A reviewer can read each test in
  isolation and answer: "what does the client do correctly that
  this proves?"

## Out of scope for Phase J

Explicitly deferred (still untested, deliberately):

- **Performance, concurrency, resource exhaustion** — outside the
  integration-testing campaign entirely; belongs in
  `tests/stress/` if/when it becomes a goal.
- **Push notifications, blob upload/download, Layer 5 C ABI** —
  not yet implemented in the library; not part of the
  integration-testing campaign at all until they exist.

Permanently out of scope (campaign discipline = validate
**existing** RFC-aligned surface):

- **JMAP-Sharing draft / `urn:ietf:params:jmap:principals`** —
  neither RFC 8620 nor RFC 8621 defines these surfaces; library
  has zero principal/sharing surface.
- **Cross-account `Email/copy` happy path** — requires
  sharing/ACL.
- **Bearer auth wire-test** — Stalwart's seed env uses Basic
  auth; testing Bearer would require a different Stalwart
  configuration. The library's `authScheme` parameter has unit
  + serde coverage; the wire wiring is the SAME for Basic and
  Bearer (only the header value differs), so wire-testing Basic
  is sufficient evidence for the contract.
- **HTTP-level error classification matrix** — 401/403/404/500/
  network/timeout. Tested incidentally during seed-script
  debugging; the library's classification table has unit
  coverage. Promote to a regression target only if a real bug
  surfaces.

## Forward arc (informational)

Following the campaign through the user's 9–11 phase budget,
Phase J is the **tenth** phase. Phase K may close the campaign.
Candidate Phase K themes:

- **Retroactive library-boundary cleanup** — re-frame the
  assertions in Phases A–I that conflated server-RFC compliance
  with library-contract verification, in line with Phase J's
  reframing. Not strictly necessary (the existing tests pass
  against Stalwart 0.15.5 specifically) but valuable for the
  campaign's coherence.
- **Catalogue maintenance + Stalwart version bump** — re-run the
  full live suite against a newer Stalwart release, capture any
  new divergences, fold them into the parser/test layer per the
  established discipline.
- **Optional regression hardening** — promote selected
  divergences from "set-membership accepts either" assertions to
  "Stalwart-specific known-good" pinned assertions, with
  explicit version markers (e.g., `# Stalwart 0.15.5 known-good
  start; loosen if upgrading`). Trades portability for tighter
  regression on the empirically-verified path.

After Phase K, the campaign would close at **eleven phases**,
within the user's stated budget. Permanent out-of-scope items
(JMAP-Sharing, cross-account `Email/copy` happy path, push,
blob, Layer 5 C ABI, performance/concurrency) remain
permanently out of scope per campaign discipline.

## Phase J retrospective (2026-05-04)

Phase J landed across 15 commits — one J0 escape-hatch + 14
Steps — between commits `7ba653a` and the final Step 74 commit.
Cumulative live count: 72 (was 58); cumulative replay count:
83 under `tests/serde/captured/` (was 57, with one round-trip
integrity meta-test added).

### Methodological reframing — the library-contract / server-compliance separation

The single most important lesson from Phase J is the explicit
separation of two concerns the prior phases sometimes conflated:

| Question                                          | Asks of      | Where verified                                  |
| ------------------------------------------------- | ------------ | ----------------------------------------------- |
| Does the library project URI → enum correctly?    | Our library  | Live test: closed-enum + rawType preservation   |
| Are all enum variants reachable by the parser?    | Our library  | Existing `tests/serde/` units                   |
| Does Stalwart pick the RFC-correct URI per case?  | Stalwart     | Captured fixture (passive byte-strict record)   |

A single live assertion that names a specific URI both verifies
the library contract AND asserts server compliance.  When
Stalwart deviates from RFC, that one assertion fails — and the
library bug detection it was meant to provide is masked by the
server failure.

Phase J's reframing splits these concerns: live tests assert
closed-enum membership + rawType preservation; replay tests
assert specific URIs Stalwart returned, byte-for-byte.  The
total assertion strength is unchanged — every URI and every
projection is verified — but the venues are separated so a
Stalwart-side change cannot silently break a library-contract
test, and a library regression cannot be masked by server-side
compensation.

### Stalwart 0.15.5 empirical pin catalogue (Phase J)

Each pin is recorded byte-for-byte in the captured fixtures
under `tests/testdata/captured/` and asserted by the
corresponding parser-only replay test under
`tests/serde/captured/`.

1. **`notRequest` for non-JSON input** (Step 61, sub-test 1).
   RFC 8620 §3.6.1 mandates `notJSON`.  Stalwart classifies the
   JSON parser failure as `notRequest` — see
   `request-error-not-json-stalwart.json`.
2. **`notRequest` for unknown capability URI** (Step 61, sub-
   test 3).  RFC mandates `unknownCapability`.  Stalwart
   collapses the case onto `notRequest`; the offending URI is
   echoed in the `detail` field — see
   `request-error-unknown-capability-stalwart.json`.
3. **Server-side cap-collapse onto `maxSizeRequest`** (Step
   65, sub-test 2).  An over-cap `ids` array on `Mailbox/get`
   is classified as `limit: maxSizeRequest` rather than the
   more specific `maxObjectsInGet` — see
   `server-enforcement-max-objects-in-get-stalwart.json`.
4. **Short Id format requirement** (Step 63, sub-test 1).
   Stalwart silently drops Ids longer than its internal
   token shape (4–7 chars typical).  Synthetic-Id tests must
   use ``Id("zzzzz")``-style short ASCII, not long literals.
5. **`invalidProperties` for malformed PatchObject paths** (Step
   63, sub-test 2; Step 70, sub-test C).  RFC 8620 §5.3 mandates
   `invalidPatch` for unknown-property paths; Stalwart projects
   them as `invalidProperties` with the offending path echoed
   in `properties` — see `set-error-invalid-patch-stalwart.json`,
   `patch-object-deep-paths-stalwart.json`.
6. **`invalidProperties` for `Email/import` blob-not-found**
   (Step 63, sub-test 4).  RFC 8621 §4.6 mandates `blobNotFound`
   with `notFound: [BlobId, …]`.  Stalwart projects as
   `invalidProperties` with `properties: ["blobId"]` — see
   `set-error-blob-not-found-stalwart.json`.
7. **`newState` omitted on failed-only /set responses** (Step
   70, sub-test C; Step 74).  RFC 8620 §5.3 mandates `newState`
   as required.  When a /set response carries only `notUpdated`
   / `notCreated` (no successful state change), Stalwart omits
   `newState`.  The library's strict ``SetResponse.fromJson``
   correctly rejects the malformed shape; Phase J tests drop
   down to ``SetError.fromJson`` on the rejection rail when
   needed.
8. **Lenient JSON-Pointer escape acceptance** (Step 70, observed
   during Step 63 development).  Stalwart accepts malformed RFC
   6901 escape sequences (`~7invalid`) as no-ops rather than
   rejecting per RFC.  Phase J's setInvalidPatch trigger is the
   wholly-unknown property-name path instead.

### Library scope clarification — `Mailbox.fromJson` for sparse records

Step 69 surfaced a non-bug library scope question: when a
`Mailbox/get` response uses RFC 8621 §2.1 `properties` filtering
to return only `{id, name}`, the typed `Mailbox.fromJson`
parser correctly rejects the response — most fields are
non-`Opt` per the RFC mandate that records "always carry"
their core properties.

The library's scope is **full-record parsing**.  Sparse
projections are an RFC 8620 §5.1 client-controlled feature
that returns less than the full record; consumers that opt
into `properties` filtering accept that the typed parser does
not reconstruct partial records.  Phase J Step 69 verifies
sparse responses at the JsonNode level (key presence /
absence) without demanding the typed parser handle them.

This is a deliberate type-system choice: making every Mailbox
field `Opt[T]` would weaken every consumer's contract for the
common full-record case to silence the rare sparse case.
The library's stance: full-record parsing strict; sparse
projection users extract fields manually.

### Library bugs predicted vs found

The Phase J library-readiness audit (re-stated at the top of
the plan) predicted **zero library bugs**.  All 14 Steps
shipped without a single src/ change beyond the J0 escape
hatch.  Empirical findings during execution:

- **Stalwart deviations**: 8 catalogued above.  Reframing of
  affected sub-tests was structural (split library-contract
  from server-compliance assertions), not behavioural — the
  total assertion strength is unchanged.
- **Library-scope clarifications**: 1 (sparse-record parsing
  — see above).  No code change; documentation added in the
  Step 69 commit body.

Zero library bugs surfaced during Phase J.  The audit's
prediction held.

### Pre-existing test-suite flakiness (carried forward)

The full ``just test-integration`` suite shows 8–10
intermittent failures in pre-existing submission tests
(``temail_submission_*_live``, ``temail_bob_receives_alice_delivery_live``).
Failures are SMTP-queue-load related, surface as
``pollSubmissionDelivery: budget exhausted`` or as a Stalwart
deviation in `EmailSubmissionSetResponse` shape (Stalwart
omits ``newState`` under the same failed-only condition Step 70
documents).

These failures are NOT caused by Phase J — Step 61's late-
alphabetical position means it cannot impact earlier-running
submission tests; the J0 commit added only `{.used.}`-gated
unused symbols.  Phase I retrospective commit `30bf779`
already documented submission-suite stability concerns and
adopted corpus-size reductions as a workaround.

A separate Phase K hardening pass should address this either
by widening ``pollSubmissionDelivery`` budgets or by reframing
the affected submission tests to handle Stalwart's
intermittent ``newState`` omission — same library-contract /
server-compliance separation Phase J established for /set
responses elsewhere.
