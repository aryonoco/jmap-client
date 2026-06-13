<!--
SPDX-License-Identifier: BSD-2-Clause
Copyright (c) 2026 Aryan Ameri
-->

# 15. Error Surface

## 1. Why this exists

`jmap-client` returns `Result[T, E]` from every fallible operation with a
named-variant `E`. The error rail is the contract — never collapse a
variant to a string (**P13**), never raise from a domain function (**P6**),
never present a second public way to ask "what went wrong" (**P5**).

The reference points are libcurl's `curl_easy_strerror(CURLcode)` and
SQLite's `sqlite3_errmsg(db)`: one stable enum discriminator, one bounded
diagnostic string projection per error type, one set of producers
(the library), one set of consumers (the application). The cautionary
counter-examples are OpenSSL's twenty `*_CTX` types and libdbus's
parallel error/exception surfaces — both failures of **P5**.

The decisions in this document operationalise that contract for the
seven error types the library carries — `ValidationError`,
`TransportError`, `RequestError`, `ClientError`, `MethodError`,
`SetError`, `GetError` — and the gate that keeps the projection stable.

Principle coverage: **P1** (lock contract before 1.0), **P2** (stability
bought with tests), **P5** (one name per concept), **P7** (watch the
wrap rate), **P13** (one error rail, name every variant), **P15** (raw
constructors private), **P18** (sum types, exhaustive `case`), **P20**
(additive variants), **P28** (long-form first-party docs).

| Section | Decision range | Scope |
| --- | --- | --- |
| §2 Discriminator naming | D11 | `kind` across all error types |
| §3 Enum suffix | D12 | `*Kind` across all classification enums |
| §4 Constructor surface | D13, D13a, D13b | Library-private smart constructors |
| §5 Diagnostic format | D1, D2, D4, D6, D7, D8, D9, D10, D14 | `message()` / `$` per type |
| §6 Redaction rule | D4 | `ValidationError.value` is not in `message` |
| §7 Change classification | D15 | Patch / minor / major rules for the projection |
| §8 PR-label contract | D15 | `[ERR-MSG-CHANGE]` workflow |
| §9 FFI implication | D10 (FFI plan), forward to L5 | Bounded length as prerequisite |

## 2. Discriminator naming (D11)

Every error type names its categorical discriminator `kind`. The backing
enum carries the `*Kind` suffix. Application developers dispatch on
`err.kind` uniformly across the seven types — the dispatch shape is the
same whether the underlying object is a case object
(`TransportError`, `ClientError`, `SetError`, `GetError`) or a flat
object with a derived accessor (`RequestError`, `MethodError`).

```nim
case err.kind
of cekTransport: …
of cekRequest:   …
```

The case-vs-flat distinction is internal implementation detail. The
application developer never needs to learn it. Switching across two
discriminator names (`kind` vs the legacy `errorType`) was the OpenSSL
trap: same concept, two names, two `case` shapes, two failure paths.

## 3. Enum suffix convention (D12)

Every classification enum carries the `*Kind` suffix:
`TransportErrorKind`, `RequestErrorKind`, `ClientErrorKind`,
`MethodErrorKind`, `SetErrorKind`, `GetErrorKind`. Total parser
functions follow the same suffix: `parseRequestErrorKind`,
`parseMethodErrorKind`, `parseSetErrorKind`.

Variant prefixes (`ret`, `met`, `set`, `tek`, `cek`, `gek`) stay
unchanged. `setForbidden` / `metInvalidArguments` / `retNotJson` are
concise mnemonics; renaming each variant would churn the codebase
without changing the API contract. The wire format is unaffected:
variants serialise via their `=` literal which is RFC-fixed, and the
enum's symbolic name is internal.

## 4. Constructor surface (D13)

App developers receive error values; they do not construct them. The
library-internal error constructors are filtered off the hub at
`src/jmap_client/internal/types.nim` via the same `export … except …`
mechanism A14 uses for `addInvocation`.

Filtered (hub-private):

- `validationError`, `toValidationError` (the L1 `TokenViolation`
  translator)
- `requestError`, `methodError`, `setError`
- `setErrorInvalidProperties`, `setErrorAlreadyExists`,
  `setErrorBlobNotFound`, `setErrorInvalidEmail`,
  `setErrorTooManyRecipients`, `setErrorInvalidRecipients`,
  `setErrorTooLarge`
- `clientError` (both overloads)
- `validationToClientError`, `validationToClientErrorCtx`
- `getErrorMethod`, `getErrorHandleMismatch`

Retained on the hub (Transport-contract producers, **A19**):

- `transportError`, `httpStatusError`, `sizeLimitExceeded`
- `classifyTransportException`, `classifyException`
- `enforceBodySizeLimit`

These last six are public because **custom `Transport` implementations
MUST return a `TransportError` on failure** — the producers are part of
the implementer contract, not the application-developer contract.

The companion compile audits at
`tests/compile/tcompile_a12_error_constructor_surface.nim` and
`tcompile_a12_error_constructor_internal_access.nim` lock both halves of
this seal.

## 5. Diagnostic format conventions (D1–D10)

Every error type exposes:

- `func message*(e: T): string` — the canonical projection
- `func \`$\`*(e: T): string` — delegating to `message`

The format is per-type-and-variant. The full corpus is locked by
`tests/wire_contract/error-messages.txt`; the rule per type:

### 5.1 ValidationError

`message() == typeName & ": " & reason`. The raw `value` is **not** in
the message — see §6.

The raw `reason` text is exposed as a public field; consumers needing
to compose a more specific diagnostic (e.g. embedding `value` after a
call-site redaction decision) read the field directly.

```
validationError("AccountId", "contains control characters", "abc\x01")
→ "AccountId: contains control characters"
```

### 5.2 TransportError

Exhaustive `case te.kind`:

- `tekHttpStatus`: `"HTTP " & $te.httpStatus & ": " & te.detail`
- `tekNetwork`, `tekTls`, `tekTimeout`: `te.detail`

The raw wire/exception text is exposed as `te.detail` (renamed from the
former `message` field). The `tekHttpStatus` projection prefixes the
status code; consumers must not lose it.

```
httpStatusError(503, "Service Unavailable")
→ "HTTP 503: Service Unavailable"
transportError(tekNetwork, "connection refused")
→ "connection refused"
```

### 5.3 RequestError

Cascade `detail > title > rawType`. RFC 7807 defines `title` as a
short human-readable description and `detail` as a longer one; the
detail (when present) is preferred.

```
requestError("…limit", title=Opt.some("Limit Exceeded"),
             detail=Opt.some("maxCallsInRequest=500"))
→ "maxCallsInRequest=500"
requestError("…notJSON", title=Opt.some("Not JSON"))
→ "Not JSON"
requestError("urn:example:vendor:custom")
→ "urn:example:vendor:custom"
```

### 5.4 ClientError

Delegates to the wrapped variant:

- `cekTransport`: `err.transport.message`
- `cekRequest`: `err.request.message`

### 5.5 MethodError

`rawType & ": " & description` when `description` is `Opt.some` and
non-empty; `rawType` alone otherwise.

```
methodError("serverFail", Opt.some("internal error"))
→ "serverFail: internal error"
methodError("forbidden")
→ "forbidden"
methodError("serverFail", Opt.some(""))   # empty description falls through
→ "serverFail"
```

### 5.6 SetError

Exhaustive `case se.kind`. Adding a `SetErrorKind` variant forces a
compile error at this case statement (**P18** anti-pattern lockout,
**H9**).

Seven payload-bearing arms format with the RFC field:

- `setInvalidProperties`: `rawType & ": " & properties.join(", ")`
- `setAlreadyExists`: `rawType & ": " & $existingId`
- `setBlobNotFound`: `rawType & ": " & notFound.join(", ")`
- `setInvalidEmail`: `rawType & ": " & invalidEmailPropertyNames.join(", ")`
- `setTooManyRecipients`: `rawType & ": max=" & $maxRecipientCount`
- `setInvalidRecipients`: `rawType & ": " & invalidRecipients.join(", ")`
- `setTooLarge`:
  - with cap: `rawType & ": maxSize=" & $cap & " octets"`
  - without cap: `rawType` (with optional description suffix)

Sixteen payload-less variants take the rawType-with-optional-description
shape:

- with non-empty description: `rawType & ": " & description`
- without description (or empty): `rawType`

### 5.7 GetError

Two arms:

- `gekMethod`: delegates to `ge.methodErr.message`
- `gekHandleMismatch`: `"handle from a different builder (expected X; got Y; callId=…)"`

The `gekMethod` arm intentionally delegates rather than re-formatting:
there is one source of truth for the MethodError diagnostic.

## 6. Redaction rule (D4)

`ValidationError.value` is the raw input that failed validation. It is
**not** included in the `message()` projection.

The reason is provenance: `value` is untrusted input — tokens, URLs,
attacker-controlled strings, binary fragments. Default-including it in
log lines would route attacker content into observability pipelines
indiscriminately; the cure is to make the call site decide.

Consumers that have determined redaction is safe compose the value
explicitly:

```nim
log.error err.message & " (value=" & err.value & ")"
```

This makes the redaction decision visible at the composition site, not
hidden inside the projection.

## 7. Change classification

The diagnostic projection format is part of the public API. Changes are
classified by their breaking-ness, the same way wire-format changes are:

| Change | SemVer level | Workflow |
| --- | --- | --- |
| Typo fix in an existing message | patch | freeze + `[ERR-MSG-CHANGE]` PR label |
| Whitespace adjustment in an existing message | patch | freeze + `[ERR-MSG-CHANGE]` |
| Append a payload field to an existing variant | patch | freeze + `[ERR-MSG-CHANGE]` |
| Add a new variant + new sample | minor | freeze + `[ERR-MSG-CHANGE]` |
| Structural reformat (separator, ordering) | major | freeze + `[ERR-MSG-CHANGE]` + CHANGELOG breaking entry |
| Remove a payload field | major | freeze + `[ERR-MSG-CHANGE]` + CHANGELOG breaking entry |
| Rename `kind`, `message`, `$`, or any `*Kind` enum | major | freeze + `[ERR-MSG-CHANGE]` + CHANGELOG breaking entry |

The H15 lint (`tests/lint/h15_error_message_snapshot.nim`) enforces
the snapshot's invariant: any divergence between the live
`message()` projection and `tests/wire_contract/error-messages.txt`
fails CI. The regenerator (`scripts/freeze_error_messages.nim`,
exposed as `just freeze-error-messages`) updates the snapshot
deterministically. Together they make the format change reviewable
as a diff.

## 8. PR-label contract

A PR that includes a non-empty `git diff` of
`tests/wire_contract/error-messages.txt` MUST carry the
`[ERR-MSG-CHANGE]` label.

Reviewer obligations:

- Verify each diff is intentional.
- Verify the change classification (§7) matches the SemVer level the PR
  targets.
- For major-level changes, verify the CHANGELOG carries a breaking entry
  scoped to the diagnostic projection.

## 9. FFI implication

The `message()` projection is bounded above by 4096 bytes
(asserted by the `propMessageBoundedLength` property check). This is the
prerequisite for an L5 FFI surface modelled on libcurl's
`CURLOPT_ERRORBUFFER` — a caller-supplied fixed-size string buffer that
the library populates with the diagnostic.

The discriminator `kind` is the prerequisite for the `CURLcode`
analogue: a stable, finite enum that consumer code can dispatch on
without parsing the diagnostic string. The forward design is captured
in the deferred D10 entry; A12 supplies both halves of the
prerequisite.
