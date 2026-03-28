# Integration Testing Strategy

Unit tests (Layer 1 `t*.nim` files) verify type construction, smart constructors,
and error round-trips in isolation. Integration tests verify the library works
end-to-end against real JMAP servers — that serialisation produces what servers
accept and deserialisation handles what servers return.

## Test Harness

A test harness is a small program that links the library and exercises it as a
real consumer would. Not a product, not interactive — an automated test fixture.

### Nim Harness

Lives in `tests/integration/`. Imports the library directly via `import jmap_client`.
Exercises the Nim API (Layers 1-4) without the C ABI indirection.

Purpose: verify protocol correctness, serialisation round-trips, error handling
against real server responses.

```
tests/integration/
  tintegration_stalwart.nim   — core test suite against Stalwart
  tintegration_fastmail.nim   — compatibility checks against Fastmail
  config.nim                  — server URLs, credentials (from env vars)
```

### C Harness

Lives in `tests/ffi/`. Links the compiled `.so`/`.dll` and calls exported C
functions. Written in plain C with no dependencies beyond the library itself.

Purpose: verify the C ABI projection works — opaque handles, error codes,
string accessors, memory lifecycle (create/destroy pairs). Catches FFI-specific
bugs: dangling pointers from string accessors, missing `=destroy` calls,
incorrect enum sizing, ARC lifetime issues.

```
tests/ffi/
  test_session.c     — discover session, inspect capabilities
  test_request.c     — build request, add methods, send, extract responses
  test_errors.c      — verify error codes and thread-local error state
  test_lifecycle.c   — create/destroy pairs, leak detection
  Makefile           — compiles against the library's .so and headers
```

## Test Servers

| Server | Deployment | Frequency | Purpose |
|--------|-----------|-----------|---------|
| Stalwart | Docker container in CI | Every commit | Primary correctness target |
| Fastmail | Paid account, real server | Daily or manual | Real-world compatibility |
| Cyrus | Docker container in CI | Weekly | Breadth |
| Apache James | Docker container in CI | Weekly | Breadth |

Stalwart is the primary target: open source, comprehensive JMAP support (core +
mail + submission + vacation + websocket + sieve), single Docker container, no
account costs.

## CI Flow

1. Spin up Stalwart container
2. Seed test account with known data (mailboxes, emails, blobs)
3. Run Nim integration harness — exercises Nim API against real server
4. Run C integration harness — exercises C ABI against real server
5. Tear down container

Fastmail, Cyrus, and Apache James run on separate schedules to avoid
rate limits and reduce per-commit CI time.

## What to Cover

- Session discovery via `.well-known/jmap`
- All 6 standard methods against Mailbox and Email entities
- Result references: query then get in a single batched request
- Set with create, update, destroy — verify per-item Result outcomes
- Error paths: invalid account ID, unknown method, state mismatch
- Lossless extension handling: unknown capabilities survive parse round-trip
- Blob upload and download
- C ABI: opaque handle lifecycle, error code propagation, string accessor safety
