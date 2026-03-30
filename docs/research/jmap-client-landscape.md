# JMAP Client Implementation Landscape

Comprehensive survey of open-source JMAP client libraries and applications across all
languages, covering RFC coverage, codebase size, adoption, and activity status.

**Surveyed:** 2026-03-30 | **Projects:** 18 libraries + 8 applications |
**RFCs benchmarked:** 8620, 8621, 8887, 9007, 9219, 9404, 9425

---

## Table 1 -- Project Overview

| # | Project | Language | ~LoC | Type | Licence | Status |
|---|---------|----------|-----:|------|---------|--------|
| 1 | [stalwartlabs/jmap-client](https://github.com/stalwartlabs/jmap-client) | Rust | 9,800 | Library | Apache-2.0 / MIT | Maintained |
| 2 | [jeffhuen/missive](https://github.com/jeffhuen/missive) | Rust | 15,000 | Email delivery lib | MIT | New |
| 3 | [meli/melib](https://git.meli-email.org/meli/meli) | Rust | 133,000 | Email backend | EUPL-1.2 / GPL-3.0 | Active |
| 4 | [stalwartlabs/calcard](https://github.com/stalwartlabs/calcard) | Rust | 36,500 | Cal/Contact formats | Apache-2.0 / MIT | Maintained |
| 5 | [stalwartlabs/jmap-tools](https://github.com/stalwartlabs/jmap-tools) | Rust | 2,550 | Utility | Apache-2.0 / MIT | Active |
| 6 | [iNPUTmice/jmap](https://codeberg.org/iNPUTmice/jmap) | Java | 30,000 | Library + MUA | Apache-2.0 | Maintained |
| 7 | [smkent/jmapc](https://github.com/smkent/jmapc) | Python | 4,500 | Library | GPL-3.0 | Maintained |
| 8 | [linagora/jmap-client-ts](https://github.com/linagora/jmap-client-ts) | TypeScript | 1,300 | Library | MIT | Maintained |
| 9 | [htunnicliff/jmap-jam](https://github.com/htunnicliff/jmap-jam) | TypeScript | 4,500 | Library (~2 kb gz) | MIT | Active |
| 10 | [lachlanhunt/jmap-kit](https://github.com/lachlanhunt/jmap-kit) | TypeScript | 28,000 | SDK (plugin arch) | MIT | New |
| 11 | [ilyhalight/jmap-yacl](https://github.com/ilyhalight/jmap-yacl) | TypeScript | 1,300 | Library | MIT | Low activity |
| 12 | [root-fr/jmap-webmail](https://github.com/root-fr/jmap-webmail) | TypeScript | 40,000 | Application | MIT | Active |
| 13 | [rockorager/go-jmap](https://github.com/rockorager/go-jmap) | Go | 6,350 | Library | MIT | Dormant |
| 14 | [cwinters8/gomap](https://github.com/cwinters8/gomap) | Go | 1,550 | High-level client | MIT | Dormant |
| 15 | [linagora/jmap-dart-client](https://github.com/linagora/jmap-dart-client) | Dart | 19,700 | Library | Apache-2.0 | Maintained |
| 16 | [fastmail/JMAP-Tester](https://github.com/fastmail/JMAP-Tester) | Perl | 2,900 | Test harness | Perl-5 | Active |
| 17 | [tirth/JmapNet](https://github.com/tirth/JmapNet) | C# | 2,050 | Library | MIT | Dormant |
| 18 | [JMAP-Net/JMAP.Net](https://github.com/JMAP-Net/JMAP.Net) | C# | 3,060 | Library | MIT | New |

**Status key:** Active = commits within 3 months; Maintained = commits within 12 months;
Dormant = no commits 1--3 years; New = under 6 months old.

---

## Table 2 -- Adoption and Activity

| # | Project | Stars | Forks | Last Commit | Created | Notes |
|---|---------|------:|------:|-------------|---------|-------|
| 1 | stalwartlabs/jmap-client | 105 | 13 | 2025-10-19 | 2022-05 | Part of Stalwart ecosystem; crates.io v0.4.0 |
| 2 | jeffhuen/missive | 3 | 0 | 2026-01-19 | 2026-01 | JMAP is 1 of 15+ email providers (SMTP, SES, etc.) |
| 3 | meli/melib | 847 | 27 | 2026-01-25 | 2019-06 | JMAP is one backend among IMAP, mbox, notmuch, NNTP |
| 4 | stalwartlabs/calcard | 69 | 5 | 2025-12-12 | 2025-01 | NLnet/NGI0 funded; iCal/vCard/JSCalendar/JSContact |
| 5 | stalwartlabs/jmap-tools | 6 | 1 | 2026-02-15 | 2025-07 | NLnet/NGI0 funded; JSON Pointer patch utility |
| 6 | iNPUTmice/jmap | 2* | 1 | 2025-04-07 | 2022-12 | *Codeberg only (GitHub mirror deleted); by Daniel Gultsch |
| 7 | smkent/jmapc | 54 | 11 | 2025-01-15 | 2022-02 | PyPI v0.2.23; includes Fastmail MaskedEmail extension |
| 8 | linagora/jmap-client-ts | 46 | 17 | 2026-03-26 | 2020-10 | npm ~3 downloads/wk |
| 9 | htunnicliff/jmap-jam | 82 | 4 | 2026-03-29 | 2023-10 | npm ~49 downloads/wk; monorepo w/ jmap-rfc-types |
| 10 | lachlanhunt/jmap-kit | 3 | 0 | 2026-03-09 | 2026-03 | npm v1.0.3; extensible capability plugin system |
| 11 | ilyhalight/jmap-yacl | 13 | 0 | 2025-06-04 | 2024-04 | Typebox-based built-in types |
| 12 | root-fr/jmap-webmail | 127 | 22 | 2026-03-23 | 2025-12 | Full Next.js webmail app; not a reusable library |
| 13 | rockorager/go-jmap | 9 | 3 | 2023-10-01 | 2023-07 | Fork of foxcpp/go-jmap; primary dev on SourceHut |
| 14 | cwinters8/gomap | 4 | 0 | 2023-12-18 | 2022-12 | High-level wrappers for Fastmail use case |
| 15 | linagora/jmap-dart-client | 38 | 20 | 2025-11-10 | 2021-06 | Powers TMail / Twake Mail (production Flutter app) |
| 16 | fastmail/JMAP-Tester | 4 | 3 | 2026-03-09 | 2016-04 | 10-year-old project; CPAN dist; by rjbs (Fastmail) |
| 17 | tirth/JmapNet | 10 | 1 | 2025-02-09 | 2022-10 | NuGet: JmapNet; README says "WIP" with TODO list |
| 18 | JMAP-Net/JMAP.Net | 2 | 0 | 2025-12-31 | 2025-12 | Also includes JMAP Calendars (RFC 8984) |

---

## Table 3 -- RFC Coverage Matrix

Depth indicators: **Full** = comprehensive typed coverage; **Partial** = key types/methods present
but gaps remain; **Agnostic** = transport-only harness that can exercise any method
but does not model domain types; -- = not covered.

| # | Project | 8620 Core | 8621 Mail | 8887 WS | 9007 MDN | 9219 S/MIME | 9404 Blob | 9425 Quotas |
|---|---------|-----------|-----------|---------|----------|-------------|-----------|-------------|
| 1 | stalwartlabs/jmap-client | Full | Full | Full | -- | -- | -- | -- |
| 2 | jeffhuen/missive | Partial | Partial | -- | -- | -- | -- | -- |
| 3 | meli/melib | Full | Full | -- | -- | -- | -- | -- |
| 4 | stalwartlabs/calcard | -- | -- | -- | -- | -- | -- | -- |
| 5 | stalwartlabs/jmap-tools | Partial | -- | -- | -- | -- | -- | -- |
| 6 | iNPUTmice/jmap | Full | Full | Full | -- | -- | -- | -- |
| 7 | smkent/jmapc | Full | Full | -- | -- | -- | -- | -- |
| 8 | linagora/jmap-client-ts | Partial | Partial | -- | -- | -- | -- | -- |
| 9 | htunnicliff/jmap-jam | Full | Full | -- | -- | -- | -- | -- |
| 10 | lachlanhunt/jmap-kit | Full | Full | -- | Full | Full | Full | Full |
| 11 | ilyhalight/jmap-yacl | Partial | Partial | -- | -- | -- | -- | -- |
| 12 | root-fr/jmap-webmail | Partial | Full | -- | -- | -- | -- | Full |
| 13 | rockorager/go-jmap | Full | Full | -- | Full | Full | Partial | -- |
| 14 | cwinters8/gomap | Partial | Partial | -- | -- | -- | -- | -- |
| 15 | linagora/jmap-dart-client | Full | Full | -- | Full | -- | -- | Full |
| 16 | fastmail/JMAP-Tester | Full | Agnostic | Full | Agnostic | Agnostic | Agnostic | Agnostic |
| 17 | tirth/JmapNet | Partial | Partial | -- | -- | -- | -- | -- |
| 18 | JMAP-Net/JMAP.Net | Full | -- | -- | -- | -- | Partial | -- |

---

## Table 4 -- RFC Coverage Summary (ranked)

Only typed client libraries included (applications and format-only libraries excluded).

| # | Project | Lang | RFCs Covered | Coverage % | Strongest Area |
|---|---------|------|-------------|:----------:|----------------|
| 10 | lachlanhunt/jmap-kit | TS | 8620, 8621, 9007, 9219, 9404, 9425 | **86%** | Extensible plugin registry covers 6/7 RFCs |
| 13 | rockorager/go-jmap | Go | 8620, 8621, 9007, 9219, 9404 (partial) | **65%** | Broadest Go coverage; MDN + S/MIME complete |
| 15 | linagora/jmap-dart-client | Dart | 8620, 8621, 9007, 9425 | **57%** | Production-proven; MDN + Quotas |
| 1 | stalwartlabs/jmap-client | Rust | 8620, 8621, 8887 | **43%** | Only Rust lib with WebSocket support |
| 6 | iNPUTmice/jmap | Java | 8620, 8621, 8887 | **43%** | Full MUA layer + WebSocket; Android-ready |
| 9 | htunnicliff/jmap-jam | TS | 8620, 8621 | **29%** | Comprehensive Core+Mail types; tiny bundle |
| 7 | smkent/jmapc | Python | 8620, 8621 | **29%** | Only maintained Python JMAP client |
| 3 | meli/melib | Rust | 8620, 8621 | **29%** | Mature email backend (not standalone lib) |
| 16 | fastmail/JMAP-Tester | Perl | 8620, 8887 | **29%** | Transport-only; can exercise any RFC |
| 8 | linagora/jmap-client-ts | TS | 8620, 8621 (partial) | **25%** | Lightweight promise-based API |
| 17 | tirth/JmapNet | C# | 8620, 8621 (partial) | **25%** | Best .NET option; includes DNS discovery |
| 11 | ilyhalight/jmap-yacl | TS | 8620, 8621 (partial) | **21%** | Typebox schemas |
| 18 | JMAP-Net/JMAP.Net | C# | 8620, 9404 (partial) | **20%** | New; also has JMAP Calendars (RFC 8984) |
| 14 | cwinters8/gomap | Go | 8620, 8621 (partial) | **14%** | Fastmail-specific high-level wrapper |
| 2 | jeffhuen/missive | Rust | 8620, 8621 (thin slice) | **10%** | Multi-provider email delivery abstraction |
| 5 | stalwartlabs/jmap-tools | Rust | 8620 (JSON Pointer only) | **7%** | Patch utility, not a client |

---

## Table 5 -- Email Client Applications

Applications that contain or consume JMAP client code. Separated from libraries because
these are end-user products, not reusable protocol implementations (though some contain
substantial standalone JMAP client layers).

| # | Project | Language | ~LoC | Stars | Forks | Licence | Last Commit | Status | Own JMAP Code? |
|---|---------|----------|-----:|------:|------:|---------|-------------|--------|----------------|
| A1 | [iNPUTmice/lttrs-android](https://codeberg.org/iNPUTmice/lttrs-android) (Ltt.rs) | Java | 566,000 | ~187 | ~14 | Apache-2.0 | 2025 (v0.4.3) | Maintained | No (uses jmap-mua) |
| A2 | [linagora/tmail-flutter](https://github.com/linagora/tmail-flutter) (Twake Mail) | Dart | 8,760,000* | 597 | 119 | AGPL-3.0 | 2026-03-27 | Active | No (uses jmap-dart-client) |
| A3 | [bulwarkmail/webmail](https://github.com/bulwarkmail/webmail) (Bulwark) | TypeScript | 3,700,000* | 165 | 13 | AGPL-3.0 | 2026-03-29 | Active | **Yes** (~5,300 lines in lib/jmap/) |
| A4 | [jmapio/jmap-demo-webmail](https://github.com/jmapio/jmap-demo-webmail) | JavaScript | 1,670,000* | 124 | 23 | MIT | 2026-02-02 | Dormant | No (uses JMAP-JS) |
| A5 | [meli/meli](https://git.meli-email.org/meli/meli) | Rust | 5,310,000* | 847 | 27 | GPL-3.0 | 2026-01-25 | Maintained | **Yes** (~7,800 lines in melib/src/jmap/) |
| A6 | [cypht-org/cypht](https://github.com/cypht-org/cypht) | PHP/JS | 4,180,000* | 1,459 | 206 | LGPL-2.1 | 2026-03-27 | Active | **Yes** (single hm-jmap.php module) |
| A7 | [Intermesh/groupoffice](https://github.com/Intermesh/groupoffice) (Group-Office) | PHP/JS/TS | 15,200,000* | 256 | 55 | AGPL-3.0 | 2026-03-27 | Active | Server+client (JMAP-inspired internal API) |
| A8 | [mustang-im/mustang](https://github.com/mustang-im/mustang) (Parula/Mustang) | TS/Svelte | 3,240,000* | 89 | 11 | EUPL-1.2 | 2026-03-30 | Active | **Yes** (~20 JMAP files across mail/cal/contacts) |

\* bytes of primary language (not lines of code for applications; LoC estimates would require
counting across all source files, which is impractical for large apps).

---

## Table 6 -- Application RFC Coverage Matrix

How each application exercises the 7 target RFCs, whether through its own code or a
dependency library.

| # | Application | Via Library | 8620 Core | 8621 Mail | 8887 WS | 9007 MDN | 9219 S/MIME | 9404 Blob | 9425 Quotas | Overall |
|---|-------------|-------------|-----------|-----------|---------|----------|-------------|-----------|-------------|:-------:|
| A1 | Ltt.rs | jmap-mua (#6) | Partial | Partial | -- | -- | -- | -- | -- | ~30% |
| A2 | Twake Mail | jmap-dart-client (#15) | Full | Full | Partial | Full | -- | -- | Full | ~65% |
| A3 | Bulwark | Own code | Full | Full | -- | -- | Local* | -- | Full | ~50% |
| A4 | JMAP Demo | JMAP-JS (abandoned) | Partial | Full | -- | -- | -- | -- | -- | ~35% |
| A5 | meli | Own code (melib) | Full | Full | -- | -- | -- | -- | -- | ~40% |
| A6 | Cypht | Own code | Partial | Partial | -- | -- | -- | -- | Partial | ~25% |
| A7 | Group-Office | Own JMAP-inspired API | Partial | Partial | -- | -- | -- | -- | -- | ~20% |
| A8 | Mustang | Own code | Full | Partial | -- | -- | -- | Partial | -- | ~35% |

\* Bulwark implements S/MIME sign/verify/encrypt/decrypt via local JavaScript crypto
(lib/smime/), not through the RFC 9219 JMAP S/MIME extension.

### Application-specific notes

- **Ltt.rs** is a pure UI/storage layer; all JMAP logic is in iNPUTmice/jmap (#6 in Table 1).
  The Android app adds WorkManager scheduling and Room database caching around jmap-mua calls.
- **Twake Mail** is the largest JMAP-consuming application by adoption (597 stars, production
  Flutter app on Android/iOS/web). It inherits all of jmap-dart-client's RFC coverage plus
  adds its own WebSocket push layer and FCM integration.
- **Bulwark** has the most feature-rich self-contained application JMAP client (~5,300 lines
  in `lib/jmap/client.ts` alone, ~106 async methods). Targets Stalwart Mail Server.
- **meli** has the most mature standalone JMAP implementation in Rust (~7,800 lines across 19
  source files in `melib/src/jmap/`), implementing Email/get/set/query/changes/queryChanges/import,
  Mailbox/get/set, Thread/get, Identity/get/set, EmailSubmission/set, and result references.
- **Cypht** wraps JMAP behind an IMAP-compatible interface in a single PHP file (`hm-jmap.php`),
  declaring capabilities for core, mail, and quota.
- **Group-Office** is primarily a JMAP *server* -- its JS webclient consumes its own JMAP-inspired
  internal API. It uses the JMAP method patterns (get/set/query/changes/queryChanges) but the
  wire format may not be strictly RFC 8620-conformant.
- **Mustang** (continuation of Parula) is a multi-protocol desktop app (email + chat + video +
  calendar). Its JMAP client spans ~20 TypeScript files across mail, calendar, and contacts
  directories. Presented at FOSDEM 2025. Licensed under EUPL 1.2.

---

## Table 7 -- Cross-RFC Ecosystem Gaps

How many implementations (of 26 total: 18 libraries + 8 applications) provide coverage
for each RFC:

| RFC | Standard | Full (lib) | Full (app) | Partial | Total |
|-----|----------|:----------:|:----------:|--------:|------:|
| 8620 -- JMAP Core | Core | 9 | 4 | 7 | 20 |
| 8621 -- JMAP Mail | Mail | 8 | 3 | 6 | 17 |
| 8887 -- JMAP WebSocket | Transport | 2 | 0 | 1 | 3 |
| 9007 -- JMAP MDN | Extension | 3 | 1 | 0 | 4 |
| 9219 -- JMAP S/MIME Verify | Extension | 2 | 0 | 0 | 2 |
| 9404 -- JMAP Blob Management | Extension | 1 | 0 | 3 | 4 |
| 9425 -- JMAP Quotas | Extension | 3 | 2 | 1 | 6 |

---

## Ecosystem-Level Observations

### By language maturity

| Language | Best option | Coverage | Verdict |
|----------|------------|:--------:|---------|
| **Rust** | stalwartlabs/jmap-client | 43% | Strongest standalone lib; only one with WebSocket |
| **Java** | iNPUTmice/jmap | 43% | Comprehensive; MUA layer for Android; Codeberg-hosted |
| **Python** | smkent/jmapc | 29% | Only maintained option; GPL-3.0 may limit adoption |
| **TypeScript** | htunnicliff/jmap-jam (popular) / lachlanhunt/jmap-kit (broadest) | 29% / 86% | jmap-kit covers most RFCs but is brand new (3 stars) |
| **Go** | rockorager/go-jmap | 65% | Dormant on GitHub; primary dev on SourceHut |
| **Dart** | linagora/jmap-dart-client | 57% | Production-proven (TMail/Twake Mail); actively maintained |
| **Perl** | fastmail/JMAP-Tester | 29% | Testing harness, not typed client; 10 years of maintenance |
| **C# / .NET** | tirth/JmapNet | 25% | Best of 2 options but WIP/dormant; ecosystem is fragmented |

### Notable gaps across all languages

1. **No implementation covers all 7 RFCs.** The closest library is jmap-kit (TS) at 86%, missing
   only WebSocket. The closest application is Twake Mail (Dart) at ~65% via jmap-dart-client.
2. **WebSocket (RFC 8887)** is consistently the most skipped transport -- only 3 projects
   implement it at all (stalwartlabs/jmap-client, iNPUTmice/jmap, JMAP-Tester). Every
   application uses HTTP+EventSource/SSE instead.
3. **Extension RFCs** (MDN, S/MIME, Blob, Quotas) are broadly ignored across libraries.
   Applications fare slightly better on Quotas (Bulwark, Cypht, Twake Mail) since quota
   display is a visible user feature.
4. **RFC 9219 (S/MIME Verify)** remains the least adopted extension -- only 2 library
   implementations (rockorager/go-jmap, jmap-kit). Bulwark does local S/MIME crypto but
   not via the JMAP extension.

### Application ecosystem

5. **Most applications delegate JMAP to a library** rather than implementing the protocol
   themselves: Ltt.rs uses jmap-mua, Twake Mail uses jmap-dart-client, JMAP Demo uses JMAP-JS.
6. **Applications with their own JMAP client code** (Bulwark, meli, Cypht, Mustang) tend to
   implement only what they need -- typically Core + Mail + Quotas -- and skip extensions
   like MDN, S/MIME, and Blob.
7. **Twake Mail is the most widely adopted JMAP application** (597 stars, production Flutter
   app) and achieves the broadest RFC coverage (~65%) by inheriting from jmap-dart-client.
