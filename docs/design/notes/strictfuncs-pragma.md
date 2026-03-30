# strictFuncs Pragmatism Note

A note on if you run into issues in future with this combination of compiler settings:

`{.push raises: [].}` is the high-value constraint. It guarantees total functions,
forces Result types, and prevents exceptions from leaking across the C ABI.
Keep it everywhere, unconditionally.

`strictFuncs` is the high-cost constraint. It blocks stdlib functions that are
`proc` for no good reason (e.g., `std/times.parse`, `std/parseutils.skipWhile`),
forcing workarounds that add friction without proportional safety benefit.

**Decision:** use `func` as documentation intent ("this is designed to be pure")
throughout Layers 1-3. Keep `strictFuncs` enabled unless it forces a workaround
that is substantially worse than the stdlib function it replaces. If a stdlib
function is needed and is `proc` not `func`, the options in priority order are:

1. Replace with a raises-free alternative (e.g., `allIt` instead of `skipWhile`).
2. Write a thin wrapper module that calls the `proc` and re-exports as `func`.
3. Drop to `proc` in that specific function with a comment explaining why.

Document every workaround. They are valuable data for the Nim community about
what `strictFuncs` adoption looks like in practice.
