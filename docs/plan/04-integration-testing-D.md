# Integration Testing Plan — Phase D

## Status (living)

| Phase | State | Notes |
|---|---|---|
| **D0 — `mlive` factor + Phase D seed helpers** | **Done** (2026-05-01) | `LeafPartSpec` + `makeLeafPart` + `buildAliceAddr` extracted; `seedSimpleEmail` and `seedThreadedEmails` re-routed through the factory; three new structured-body seeds added (`seedAlternativeEmail`, `seedMixedEmail`, `seedForwardedEmail`). Live tests pass byte-for-byte through the refactor. Commit `feabbc6`. |
| **D0.5 — `EmailParseResponse.fromJson` typedesc wrapper** | **Done** (2026-05-01) | Mixin-discoverable wrapper added in `src/jmap_client/mail/mail_methods.nim` (commit `434020b`); mirrors the `SearchSnippetGetResponse.fromJson` pattern landed in `3fca63d` for Phase C Step 16. Without it, `resp.get(parseHandle)` cannot resolve `fromJson` for Step 24. |
| **D1 — Body content + header forms + Email/parse (six steps)** | **Done** (2026-05-01) | Steps 19–24 landed and pass against Stalwart 0.15.5. Cumulative live tests: 22/22. Wall-clock for the full live suite: ~28 s on the devcontainer, well under the ≤180 s budget. |
| **Captured-fixture loop** | **Done** (2026-05-01) | `tests/integration/live/mcapture.nim`, `tests/serde/captured/mloader.nim`, `just capture-fixtures` recipe; capture call sites in 9 A/B/C live tests plus 4 Phase D sites; 15 fixtures committed under `tests/testdata/captured/`; 15 always-on parser-only replay tests under `tests/serde/captured/`. Megatest now joins 107 specs (up from 92). |

Live-test pass rate (cumulative across Phase A + B + C + D): **22 / 22**.
Parser-layer fix landed in this phase:
- `EmailParseResponse.fromJson` typedesc wrapper added in
  `src/jmap_client/mail/mail_methods.nim` ahead of Step 24
  (commit `434020b`).

## Context

Phase C closed on 2026-05-01 with 17 live tests passing in ~21 s against
Stalwart 0.15.5. Phase D extends the campaign onto the most structurally
complex wire payloads the project produces — multipart MIME trees, the
seven typed `HeaderForm` variants, and `Email/parse` against a
`message/rfc822` blob.

Phase D also lands the captured-fixture loop. Phases A–C shipped 17 live
tests but every fixture under `tests/` not driven from a network
round-trip is LLM-authored — most parser tests close the loop against
the same author's interpretation of the RFC, which means a divergence
between Stalwart's wire shape and our schema only surfaces when Stalwart
is reachable. The captured-fixture loop persists Stalwart's most
interesting payloads as committed JSON and replays them through the
parser on every `just test` run, so the parser-vs-wire contract stays
green even when the server is offline.

The retrofit timing is intentional: Phase D produces the most
structurally complex payloads the project has exercised live (recursive
multipart trees, typed-header forms, `Email/parse` results with
recursive parsed-email shape), so it is the natural moment to pin those
shapes down.

## Strategy

D1 follows Phase C's "one new dimension per step" discipline. Each step
adds exactly one body-content or header-form dimension that prior steps
have not touched, so a failure isolates to the new dimension. The
captured-fixture loop is orthogonal — every step that produces a
non-trivial wire shape adds a single capture call line, so the same
test execution that proves the live path also seeds the always-on
parser regression.

D1's dimensions, in build order:

1. **Step 19** — single text/plain body via `bvsText`. Smallest possible
   body shape: one leaf in `textBody`, one entry in `bodyValues`. Pins
   the charset / size assertions before any multipart structure is
   exercised.
2. **Step 20** — multipart/alternative (text + html). Two siblings under
   one wrapper; verifies that `bvsTextAndHtml` populates both leaves and
   the `bodyValues` table is keyed by both `partId` values.
3. **Step 21** — multipart/mixed (body + attachment). The first
   non-body leaf surfaces in `attachments`; `disposition`,
   `name`, and `blobId` are validated.
4. **Step 22** — typed-header forms. Three of seven `HeaderForm`
   variants (`hfUrls`, `hfDate`, `hfAddresses`) round-trip through
   `parseHeaderValue`. Builds on the address-parsing path proved in
   Steps 13–18.
5. **Step 23** — UTF-8 display names. Pins the byte-passthrough contract
   between the client (no RFC 2047 decoding per
   `addresses.nim:24-32`) and Stalwart 0.15.5 (decoded UTF-8 in JSON).
6. **Step 24** — `Email/parse` against a `message/rfc822` attachment.
   The capstone: `seedForwardedEmail` produces a multipart/mixed seed
   carrying an inner email; `Email/get attachments` discovers the
   attachment's `BlobId`; `Email/parse` parses that blob into a
   `ParsedEmail`. Depends on D0.5's typedesc-wrapper fix.

## Phase D0 — preparatory `mlive` refactor and seeds

Three new structured-body seeds need the same boilerplate that
`seedSimpleEmail` and `seedThreadedEmails` already carry, so the existing
inline `BlueprintBodyPart` construction is extracted before any new seed
lands.

### `LeafPartSpec` + `makeLeafPart` + `buildAliceAddr`

Inputs object plus a pure factory plus a literal-Alice convenience.
`seedSimpleEmail` (lines 64–78 pre-refactor) and `seedThreadedEmails`
(lines 154–168 pre-refactor) both build identical `BlueprintBodyPart`
shapes; both now funnel through `makeLeafPart`.

### `seedAlternativeEmail`, `seedMixedEmail`, `seedForwardedEmail`

Three new exported procs, each ~50 LoC, all returning `Result[Id,
string]` and short-circuiting on the railway. They internally compose
`makeLeafPart` and `buildAliceAddr`; the per-seed difference is the
content-type set and the structured `flatBody(...)` arrangement.

### `emailSetCreate` (private)

Single-create `Email/set` and outcome unwrap, factored out so each new
seed stays under ~30 LoC. Private to `mlive.nim`.

## Phase D0.5 — `EmailParseResponse.fromJson` typedesc wrapper

Discovered while drafting Step 24: `resp.get(parseHandle)` resolves
`fromJson` via Nim's `mixin` discovery, which only finds overloads
matching the `T.fromJson(node)` typedesc shape. The named function
`emailParseResponseFromJson` is the implementation; the typedesc
wrapper exposes it through the mixin path.

Mirrors the `SearchSnippetGetResponse.fromJson` wrapper landed in
commit `3fca63d` for Phase C Step 16. Single-commit fix; lands ahead of
the test that surfaces the gap.

## Phase D1 — six live tests

Each test follows the project test idiom (`block <name>:` + `doAssert`)
and is gated on `loadLiveTestConfig().isOk` so the file joins
testament's megatest cleanly under `just test-full` when env vars are
absent. All six are listed in `tests/testament_skip.txt` so `just test`
skips them.

### Step 19 — `temail_get_text_body_live`

Seeds via `seedSimpleEmail`; `Email/get` with
`bodyFetchOptions = EmailBodyFetchOptions(fetchBodyValues: bvsText)`.
Asserts `textBody.len == 1`, content-type `text/plain`, charset
`"utf-8"` (case-insensitive), `size > 0`, `bodyValues.len == 1`.

The response is partial (`properties = [id, textBody, bodyValues]`)
because Stalwart's default property set excludes `bodyStructure`, which
`emailFromJson` requires. Field-level extraction via
`EmailBodyPart.fromJson` is the right granularity.

No capture site — Step 19's structural assertions are subsumed by the
multipart fixture in Step 20.

### Step 20 — `temail_get_html_body_live`

Seeds via `seedAlternativeEmail`; `bvsTextAndHtml`. Asserts the MIME
tree exposes both `text/plain` and `text/html` leaves, `bodyValues` has
exactly two entries keyed by both `partId` values, and the html
`EmailBodyValue.value` round-trips byte-for-byte with the injected
string.

Capture: `email-multipart-alternative-stalwart` after the `Email/get`.

### Step 21 — `temail_get_attachments_live`

Seeds via `seedMixedEmail` with a 32-byte ASCII sentinel
("phase-d step-21 sentinel 32-byte"). Inline body values flow through
`Email/set create` as JSON strings, so high-bit bytes do not survive
the quoted-string round-trip — the plan-level intent ("verify attachment
shape") is preserved; the byte content of the sentinel is changed from
the originally-planned binary PNG header.

Asserts `attachments.len == 1`, `disposition == cdAttachment`, `name
== injected`, `string(blobId).len > 0`, `size == UnsignedInt(32)`.

Capture: `email-multipart-mixed-attachment-stalwart` after the
`Email/get`.

### Step 22 — `temail_get_header_forms_live`

The seed builds an `EmailBlueprint` directly because Step 22 is the
only test that needs a top-level `extraHeaders` entry (`List-Post:
<mailto:list@example.com>`); folding the variant into `mlive` would be
premature abstraction. `Date` is set via `sentAt` rather than
`extraHeaders` because Stalwart auto-generates a Date header that
would collide with a manually injected one; `From` flows through
`fromAddr` as in every seed.

Fetched via `properties = [id, header:List-Post:asURLs,
header:Date:asDate, header:From:asAddresses]`. Each dynamic key parses
through `parseHeaderValue(<form>, node)`; the discriminator and the
populated payload (`urls.unsafeGet.len == 1`, `date.isSome`,
`addresses.len == 1`) are both asserted.

Capture: `email-header-forms-stalwart` after the `Email/get`.

### Step 23 — `temail_get_unicode_name_live`

Pins the byte-passthrough contract for display names: the seed sets
`From` to `parseEmailAddress("alice@example.com", Opt.some("héllo
wörld"))`; the read-back asserts byte equality on the UTF-8 octets.

If Stalwart ever stopped decoding encoded-words, or this client ever
started doing so, the assertion would catch the divergence — exactly
the contract the catalogued-divergence entry calls out.

No capture site: structural address-shape fixtures in Steps 20 / 21 /
24 already cover the wire shape generally.

### Step 24 — `temail_parse_live`

The capstone. Three-step wire flow:

1. `seedForwardedEmail` produces a multipart/mixed message whose
   attachment is a `message/rfc822` payload built from an inner
   subject / from / body.
2. `Email/get attachments` discovers the attachment's `BlobId`.
3. `Email/parse` is issued against that blob with `properties =
   [bodyStructure, subject, from]`. `bodyStructure` is required so
   `parsedEmailFromJson` succeeds; the other two narrow the surface.

Asserts the typed `EmailParseResponse.parsed` table carries one entry
keyed by the requested blob, the parsed inner email's `subject ==
innerSubject`, and `fromAddr.unsafeGet[0].email == innerEmail`.

Depends on D0.5's typedesc wrapper.

Capture: `email-parse-rfc822-stalwart` after the `Email/parse` send.

## Captured-fixture loop

### Capture mechanism on `JmapClient`

`classifyHttpResponse` (in `src/jmap_client/client.nim`) takes a `var
capturedBody: string` out-parameter. The body string is assigned into
that out-parameter immediately after `httpResp.body` is read, before
any 4xx/5xx classification, so byte fidelity is preserved.

`fetchSession` and `send` populate `client.lastRawResponseBody` via
the out-parameter; a public `lastRawResponseBody*` accessor exposes
the bytes for test reach-in.

The field is unconditional rather than gated on a build flag. One
heap-allocated string per `JmapClient` is trivial in exchange for
eliminating "compiles with -d but not without" breakage; production
code never reads the field, and the only reader is the test-only
helper that consults a runtime env var.

### `mcapture.captureIfRequested`

`tests/integration/live/mcapture.nim`. Writes
`client.lastRawResponseBody` to `tests/testdata/captured/<name>.json`
when `JMAP_TEST_CAPTURE == "1"`; no-op otherwise. Refuses to overwrite
an existing fixture unless `JMAP_TEST_CAPTURE_FORCE == "1"`. A `proc`
(not `func`) because every operation in the body is IO.

### `tests/serde/captured/mloader.nim`

Compile-time fixture loader: `loadCapturedFixture(name)` template
expands to `parseJson(staticRead("../../testdata/captured/<name>.json"))`
via two `const` indirections (path concatenation and `staticRead`
result both bound at compile time, then `parseJson` runs at runtime
over the embedded literal).

Path uses `tests/testdata/captured/` rather than the originally-planned
`tests/fixtures/captured/`. Testament's category-walker treats each
direct subdir of `tests/` as a category and asserts that empty
categories appear in its hardcoded `["deps", "htmldocs", "pkgs"]`
whitelist; `testdata` is testament's hardcoded "non-category" name
(empirically verified) so JSON fixtures can sit there without confusing
`just test` enumeration.

### Capture call sites

10 capture calls in 9 A/B/C live tests plus 4 in Phase D1 (Steps 20–22,
24). Each call is a single line inserted immediately after the
`client.send` whose response is the capture target; the env-var gate
inside the helper keeps `just test-integration` byte-for-byte unchanged
when capture is not requested.

`temail_query_changes_live.nim` carries two captures because the
"total absent" wire shape is materially distinct from the "total
present" shape; an extra `Email/queryChanges` call without
`calculateTotal` is added so the captured-fixture loop records both,
with an assertion that `total.isNone` to keep the extra send honest.

The session fixture is captured once by hand via `curl`, not by the
recipe — the live suite never issues `Session.fetchSession` against an
arbitrary URL pattern, so there is no natural wiring point for a
session-replacement capture.

### Parser-only replay tests

15 always-on tests under `tests/serde/captured/`, one per fixture.
Each loads its fixture via `loadCapturedFixture`, parses the response
envelope, drills into the target method invocation, and asserts the
structural shape that the live producer pinned down. Variant
assertions are precise where the RFC pins the wire shape
(`stateMismatch` → `metStateMismatch`, `mailboxHasChild` →
`setMailboxHasChild`); set-membership where the spec permits a choice
(`email-changes-bogus-state` accepts either `cannotCalculateChanges`
or `invalidArguments` per RFC 8620 §5.5).

NOT listed in `testament_skip.txt` — these are always-on parser
regressions that run by `just test` and `just ci`.

## Catalogued divergences

Concrete observations and the assertions they drive.

1. **Charset case** — `serde_body.parseCharsetField` is byte-passthrough
   (`f.get().getStr("")`); tests assert
   `charset.unsafeGet.toLowerAscii == "utf-8"` so either Stalwart
   capitalisation passes.
2. **Empty `bodyValues`** — `serde_email.parseBodyValues` collapses
   absent / null / `{}` identically; Step 19 (`bvsText`) asserts
   `bodyValues.len == 1`; the implicit `bvsNone` default in Steps 21 /
   22 produces `bodyValues.len == 0`.
3. **`message/rfc822` `BlobId` reuse** — RFC 8621 §4.9 mandates that
   the `BlobId` returned in `Email/get` is reusable for `Email/parse`.
   Step 24 asserts this end-to-end: the blob id from `Email/get
   attachments` is passed verbatim to `Email/parse blobIds` and
   `parsed[blobId]` is non-empty.
4. **Method-error variant for `Email/changes` with unknown state** —
   per Phase B precedent, Stalwart returns one of
   `metCannotCalculateChanges` / `metInvalidArguments`; both are RFC
   8620 §5.5 compliant. The captured-fixture replay asserts set
   membership, not a specific variant.
5. **`EmailParseResponse` typedesc-dispatch gap** — pre-empted in D0.5.
6. **Inline body-size cap** — Phase D seeds use bodies under 4 KB and a
   32-byte attachment, well below Stalwart's default
   `maxBodyValueBytes` (256 KB) and `maxSizeRequest` (10 MB). No
   truncation possible in the D1 envelope; truncation semantics are
   out of scope (deferred to Phase H).
7. **Step 21 attachment payload** — JSON-string serialisation of
   inline body values does not preserve high-bit bytes. The
   originally-planned 32-byte raw PNG header is replaced with a
   32-byte ASCII sentinel; the test's structural assertions (size,
   name, disposition, blobId) are unchanged. Real binary attachment
   workflows route through blob upload, which is out of scope for the
   body-content test.
8. **Stalwart `Mailbox/get` numeric defaults** — captured fixture
   shows Stalwart returning concrete values for `myRights` flags and
   `totalEmails` / `unreadEmails`; the parser-only replay round-trips
   `Mailbox.toJson` and asserts `mayReadItems == true`, but does not
   pin specific numeric values that depend on deployment config.

## Success criteria

- 22 live tests pass: the 17 carried over from Phase C plus Steps
  19–24 (one per Phase D step). Cumulative `just test-integration`
  budget ≤180 s on the devcontainer (achieved: ~28 s).
- 15 parser-only replay tests pass under `just test`. Megatest joins
  ≥ 107 specs.
- `just ci` is green (reuse + fmt-check + lint + analyse + test).
- Every divergence between Stalwart's wire shape and the parser is
  catalogued in §"Catalogued divergences" above with the
  commit that fixed it (or the assertion shape that accommodates it).

## Out of scope for Phase D

- RFC 2047 encoded-word decoding (server responsibility per
  `addresses.nim:24-32`; covered as a *contract* by Step 23 but not as
  a parser feature).
- `header:Name:all` ordering semantics — Step 22 uses single-value
  forms only.
- `maxBodyValueBytes` truncation marker — deferred to Phase H,
  adversarial.
- `Email/import` — deferred to Phase E.
- `EmailSubmission` end-to-end — deferred to Phase F.
- Push notifications, blob upload/download, L5 C ABI — project-deferred
  per the campaign plan.
