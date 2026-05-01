# Integration Testing Plan — Phase A

## Status (living)

| Phase | State | Notes |
|---|---|---|
| **0 — Validate the orchestration layer** | **Done** (2026-05-01) | Step 1 commit `b02830f`, Step 2 commit `b02830f` (justfile recipe-scoping fix in `934e191`). `just test-integration` exits 0 with `tsession_discovery` PASS in 1.09s. |
| **1 — Five foundational live tests** | Not started | Steps 3–7 below. Will need an SMTP-deliver helper before Step 6. |

Live-test pass rate: **1 / 6**. Wire-format divergences root-caused at the `fromJson` layer: 0 (none discovered yet — discovery happens in Phase 1).

## Context

The project has been developed in isolation for over a month: roughly
17,000 lines of application code and 40,000 lines of test code. Every
existing test validates the library against itself. Unit tests exercise
pure functions. Serde tests round-trip JSON through internally
constructed types. Property tests fuzz parsers against their own
output. Compliance tests feed RFC-quoted example JSON into parsers and
inspect the resulting values.

None of this establishes what the library does against a real JMAP
server.

A Stalwart JMAP devcontainer service and a single session-discovery
smoke test were added in commit `9c0935b` on 2026-04-22. They sat
unexercised through the H1 type-lift campaign until the orchestration
layer was validated end-to-end on 2026-05-01 (Phase 0, below).

RFC 8620 (Core) and RFC 8621 (Mail) client-side coverage is
approximately 95% and 90% respectively. Push notifications (§7 of both
RFCs) and blob upload/download helpers are deferred. Layer 5 (C ABI) is
likewise deferred.

## Strategy

Stop writing tests. Start running what you have.

Two layers of untested code are stacked: the Stalwart orchestration
(`docker-compose.yml`, `seed-stalwart.sh`, the `authScheme` wiring in
`client.nim`) and the JMAP client library itself. Writing a live test
for `Mailbox/get` before validating the orchestration layer means every
failure is ambiguous — is the bug in the transport, the auth header,
the JSON shape Stalwart emits, or the client's parser?

Validate the layers bottom-up. When Step N fails, Steps 1..N-1 have
been proven, so the bug is isolated.

## Phase 0 — Validate the orchestration layer

### Step 1: Boot Stalwart — DONE (2026-05-01, commit `b02830f`)

    just stalwart-up

Observable success (all met):

- `docker compose up` pulls `stalwartlabs/stalwart:v0.15` and starts
  the container (running 0.15.5 on this tag)
- `seed-stalwart.sh` polling loop prints `Stalwart is ready (attempt N)`
- Three `curl` calls to `/api/principal` each print `HTTP 200` (or
  `HTTP 409` on a re-run — acceptable; the script suppresses via `|| true`)
- `/tmp/stalwart-env.sh` exists with four `export JMAP_TEST_*=...` lines
- The summary block prints the seeded credentials

What actually went wrong (none of the originally-anticipated failure
modes — admin creds, schema, health endpoint, network — were the issue):

- **Seed body missing the `roles` field.** `POST /api/principal` with
  `{"type":"individual","name":"alice",…}` succeeded with HTTP 200,
  *but* the resulting principal carries zero JMAP-method permissions.
  Symptom didn't surface until Step 2 (HTTP 403 from `/jmap/session`
  with `"You do not have enough permissions"`). Fix: add
  `"roles":["user"]` per Stalwart's role model
  (`stalw.art/docs/auth/authorization/roles`).

The recipe-level papercut in `stalwart-down` / `stalwart-reset` (using
`docker compose down` which ignores `--profile` filters and tore down
the dev container too, also wiping its named volumes) was fixed in
commit `934e191` — both recipes now use `docker compose rm -fs[v]
stalwart` and an explicit `docker volume rm` for the named volume.

### Step 2: Run the existing live session-discovery test — DONE (2026-05-01, commit `b02830f`)

    . /tmp/stalwart-env.sh
    just test-integration

Observable success (all met; `tsession_discovery` PASS in 1.09s):

- Testament builds and runs `tests/integration/live/tsession_discovery.nim`
- `loadLiveTestConfig` returns `Ok` (all four env vars present)
- `initJmapClient(sessionUrl, aliceToken, authScheme="Basic")` returns `Ok`
- `client.fetchSession()` returns `Ok` with a populated `Session`
- `session.accounts.len > 0` and `session.apiUrl.len > 0`
- The test exits 0

What this proved (first time over the wire):

- HTTP keep-alive and connection reuse work
- Basic auth with base64 `name:password` is accepted by Stalwart
  (note: **not** `email:password` — Stalwart's internal directory
  matches the username against the principal's `name` field, not its
  `emails[]`. The original plan asserted email-based auth here and
  was wrong.)
- The `authScheme` parameter added in commit `9c0935b` correctly
  substitutes `"Basic"` for the default `"Bearer"` — verified at
  `client.nim:202–302` (no client-side change needed)
- Stalwart's Session JSON satisfies the shape `Session.fromJson` expects
- `UriTemplate` parsing succeeds for Stalwart's actual `downloadUrl`,
  `uploadUrl`, `eventSourceUrl` values
- `primaryAccounts` is populated across the full RFC 8620/8621 capability
  set plus Stalwart extensions (calendars, contacts, sieve, blob,
  websocket, principals, filenode)

What actually went wrong:

1. **Login identifier mismatch (`HTTP 401`).** The seed script
   originally encoded `alice@test.local:alice123` into the bearer
   token. Stalwart 0.15.5 returned `401 "You have to authenticate
   first."` — the email form is not a recognised identifier. The
   `name`-form `alice:alice123` returned `403` instead, which cleanly
   isolated this from #2 below. Fix: encode `name:secret` in
   `seed-stalwart.sh`.
2. **Principal lacks JMAP role (`HTTP 403`).** With the correct
   identifier, `/jmap/session` still returned `403 "You do not have
   enough permissions to access this resource."` Fix: add
   `"roles":["user"]` to the seed POST body. See Step 1's retro for
   detail.

The originally-anticipated failure modes (session URL path,
`authScheme` miswiring, Session JSON shape divergence) all turned out
to be non-issues. The `authScheme` hypothesis was specifically wrong:
the wiring landed correctly in commit `9c0935b` and the 401 was
upstream of the client.

Once Step 2 was green, the foundation became real.

## Phase 1 — Five foundational live tests

Each test lives under `tests/integration/live/` and follows the
`tsession_discovery.nim` idiom: load config, guard on `isOk`, execute a
`block`, `doAssert` the invariants. All tests are added to
`tests/testament_skip.txt` so `just test` stays deterministic.

Write them in order. Each builds on the wire-format discoveries of the
previous.

### Step 3: `tcore_echo_live.nim`

Scope: the simplest possible JMAP method. Proves end-to-end
request/response envelope plumbing with zero mail semantics.

Body:

- Fetch session via `client.fetchSession()`
- Build `initRequestBuilder().addEcho(%*{"hello": true, "n": 42})`
- Send via `client.send(builder)`
- Assert response is `Ok`
- Extract the echo response from `methodResponses[0]`
- Assert its arguments equal the request arguments

What this proves:

- Request envelope (`using`, `methodCalls`, `createdIds`) serialises to
  what Stalwart accepts
- Invocation tuple `[name, args, callId]` round-trips through Stalwart
- `Response.sessionState` is populated
- Pre-flight validation (`maxSizeRequest`, `maxCallsInRequest`) respects
  session limits

### Step 4: `tmailbox_get_all_live.nim`

Scope: `Mailbox/get` with `ids: null`, fetching every mailbox in
Alice's seeded account.

Body:

- Fetch session
- Extract Alice's mail account via
  `session.primaryAccounts["urn:ietf:params:jmap:mail"]`
- Build `addMailboxGet(accountId=alice, ids=Opt.none)`
- Send
- Extract the typed response via `resp.get(mailboxHandle)`
- Assert `list.len >= 1`
- Assert at least one mailbox has a non-null `role` equal to the inbox
  role
- For each mailbox, assert `myRights` is populated

What this proves:

- `urn:ietf:params:jmap:mail` capability URI is auto-included in `using`
- Mailbox deserialisation handles Stalwart's real output (role enum,
  `MailboxRights` shape, count fields)
- IANA role strings from Stalwart match the `MailboxRole` enum exactly

Most likely first real bug: a field-name mismatch or empty-vs-null
divergence in `myRights`.

### Step 5: `tidentity_get_live.nim`

Scope: `Identity/get`, proving the submission capability pipeline
separately from the mail pipeline.

Body:

- Fetch session
- Extract submission account via
  `session.primaryAccounts["urn:ietf:params:jmap:submission"]`
- Build `addIdentityGet(accountId, ids=Opt.none)`
- Send
- Assert `list.len >= 1`
- Assert one identity has `email == "alice@test.local"`
- Assert `mayDelete` is populated

What this proves:

- Submission capability URI is auto-included
- `EmailAddress` parsing works for the `email` field
- Identity boolean permission fields deserialise correctly

If Step 4 passes and Step 5 fails, the bug is specific to the
submission URI wiring, not the mail pipeline.

### Step 6: `temail_query_get_chain_live.nim`

Scope: two chained method calls via a result reference. The single
most error-prone JMAP feature — your JSON Pointer syntax must agree
with Stalwart's evaluator.

Prerequisite: Alice's inbox needs at least one message. Either seed
one via the admin API during `seed-stalwart.sh`, or have the test
deliver via SMTP first. Prefer the SMTP helper (~20 lines) over
extending the seed script.

Body:

- Fetch session, resolve Alice's mail account
- Build two chained calls:
  1. `addEmailQuery(accountId, filter=Opt.none, sort=Opt.none, limit=Opt.some(10u))`
  2. `addEmailGet(accountId, ids=Opt.some(queryHandle.idsRef()), properties=Opt.some(["id","subject","from","receivedAt"]))`
- Send the combined request
- Assert both responses are `Ok`
- Assert `Email/get` list length matches `Email/query` ids length
- Assert every email has non-null `id`, `from`, `subject`

What this proves:

- Result reference resolution: Stalwart's JSON Pointer evaluator agrees
  with your `/ids` path
- `EmailAddress[]` parsing works against real MIME-encoded addresses
- `Date` parsing for `receivedAt` handles Stalwart's date format
- Auto-injected capability URIs satisfy a multi-method request

This is the first test that touches Stalwart's actual mail store.

### Step 7: `temail_set_keywords_live.nim`

Scope: `Email/set` with `ifInState`, flipping `$seen` on an email.

Body:

- Run Step 6's query-then-get flow; capture the `Email/get` response's
  `state`
- Pick one email id; build `Email/set` with `ifInState=Opt.some(state)`
  and `update={emailId: PatchObject({"keywords/$seen": true})}`
- Send
- Assert `updated` contains the email id
- Build another `Email/get` for the same id; verify
  `keywords[$seen] == true`
- Build a second `Email/set` with the now-stale `ifInState`; verify
  it returns a `stateMismatch` method error

What this proves:

- `ifInState` state-guard happy path
- `stateMismatch` error projection surfaces through the `Result` error
  rail (sad path)
- `PatchObject` with a JSON Pointer targeting `keywords/$seen` is
  accepted by Stalwart
- Keyword canonicalisation: `$seen` round-trips as `$seen`, not
  `$Seen`

After Step 7: every JMAP request shape (echo, get, query, set with
patch), every envelope feature (result references, state guards), and
both error rails (transport, method-level) have been exercised
end-to-end.

## Predictable wire-format divergences

Catalogue of what live testing typically reveals. The strict/lenient
boundary in serde is the right place to fix each.

1. **Date normalisation (RFC 8620 §1.4).** Spec mandates `time-secfrac`
   omitted if zero; real servers emit fractional seconds anyway.
   `fromJson` must be lenient on receive.
2. **Keyword case (RFC 8621 §4.1.1).** Lowercase on the wire,
   case-insensitive semantics. Equality checks against constants
   (`kwSeen`, `kwFlagged`) must go through a canonicalising parser.
3. **Empty-vs-null.** `notFound: []` vs absent, `keywords: {}` vs
   `null`, `mailboxIds: {}` as an empty set. `Opt[T]` plus lenient
   `fromJson` handles both.
4. **RFC 2047 encoded-word round-trip.** `EmailAddress.name` containing
   `=?UTF-8?Q?...?=` must decode on receive per RFC 8621 §4.1.2.3.
5. **Capability URI auto-injection.** If `addMailboxGet` doesn't
   auto-inject `urn:ietf:params:jmap:mail`, Stalwart returns
   `unknownCapability`. Builders in `src/jmap_client/builder.nim`
   deduplicate by design — verify entity-specific builders in
   `mail/mail_builders.nim` call the deduplicating path.

## Success criteria

Phase A is complete when:

- [x] `just stalwart-up` succeeds deterministically from a clean
  devcontainer (met 2026-05-01; verified via `just stalwart-reset`
  with the recipe-scoping fix in commit `934e191`)
- [ ] `just test-integration` exits 0 with all six live tests
  (discovery + five new) passing — currently 1 / 6 (`tsession_discovery`
  only)
- [ ] Every wire-format divergence discovered has been root-caused and
  fixed at the `fromJson` layer, not papered over in the test
- [ ] The six tests run in under 30 seconds total (baseline for
  regression tracking) — `tsession_discovery` alone runs in 1.09s

## Out of scope for Phase A

Explicitly deferred to later plan phases:

- Push notifications (RFC 8620 §7, EmailDelivery pseudo-type)
- Blob upload and download (RFC 8620 §6) — templates parse but no
  convenience methods exposed
- EmailSubmission end-to-end (requires outbound SMTP routing)
- Email/parse round-trips for attached `message/rfc822` blobs
- Query pagination and `queryChanges` delta correctness (requires a
  larger seeded corpus)
- Multi-account shared-access scenarios (requires ACL setup between
  alice and bob)
- Layer 5 C ABI (a separate plan entirely)
- Performance, concurrency, and resource exhaustion

Phase B will expand coverage to EmailSubmission and blob operations
once Phase A establishes the foundation.
