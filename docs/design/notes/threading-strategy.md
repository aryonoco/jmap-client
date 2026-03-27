# Threading Strategy

Single-threaded initially. Layers 1-3 are pure functions — inherently thread-safe,
no rework needed.

When adding multi-threading later, the work is confined to Layer 4 (transport) and
Layer 5 (C ABI handles). The standard C library pattern applies:

- **Core API**: synchronous with internal locking. Consumer calls from any thread.
  `jmap_send()` blocks and returns. Library handles synchronisation.
- **Push API** (EventSource/WebSocket): separate surface. `jmap_eventsource_connect()`
  takes a callback, manages its own connection thread internally, invokes the
  callback when state changes arrive.

Precedent: libcurl — `curl_easy_perform()` for synchronous, `curl_multi_perform()`
with callbacks for async. Two patterns, two concerns, cleanly separated.
