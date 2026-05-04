# Replace mixin resolution; extract JSON combinators

## 1. Replace mixin-based resolution with explicit callback parameters

### What mixin does today

Seven sites in the core protocol layer use `mixin` to resolve per-entity
overloads at the caller's instantiation scope:

| File | Site | mixin symbols |
|------|------|---------------|
| `builder.nim:addGet[T]` (line 164) | `methodName`, `capabilityUri` | `getMethodName`, `capabilityUri` |
| `builder.nim:addSet[T,C,U,R]` (line 226) | `methodName`, `capabilityUri`, `C.toJson`, `U.toJson` | `setMethodName`, `capabilityUri`, `toJson` |
| `builder.nim:addCopy[T,I,R]` (line 260) | `methodName`, `capabilityUri`, `I.toJson` | `copyMethodName`, `capabilityUri`, `toJson` |
| `builder.nim:addQuery[T,C,S]` (line 293) | `methodName`, `capabilityUri`, `C.toJson` | `queryMethodName`, `capabilityUri`, `toJson` |
| `builder.nim:addQueryChanges[T,C,S]` (line 321) | `methodName`, `capabilityUri`, `C.toJson` | `queryChangesMethodName`, `capabilityUri`, `toJson` |
| `methods.nim:mergeCreateResults[T]` (line 591) | `T.fromJson` | `fromJson` |
| `dispatch.nim:get[T]` (line 203) | `T.fromJson` | `fromJson` |
| `dispatch.nim:get[T](NameBoundHandle)` (line 232) | `T.fromJson` | `fromJson` |

Each of these generic functions takes a type parameter `T` (or `C`, `U`,
`CopyItem`, `SortT`) whose associated operations are _not_ constrained in the
signature.  The compiler resolves `mixin` symbols by re-opening overload
resolution at the instantiation site rather than the definition site.

### The fragility

The problem is not that `mixin` is wrong — it is that the failure mode is
indirect.  Three concrete failure scenarios:

**Scenario A — Missing import at call site.** A user writes:
```nim
import jmap_client
let (b, h) = b.addSet[Mailbox](accountId)
```
The compiler emits:
```
Error: undeclared identifier: 'setMethodName'
```
The diagnostic names the symbol and the file, but does _not_ name the missing
import (`jmap_client/mail/mail_entities`) or explain _why_ this symbol is
needed.  The user must reverse-engineer the `mixin` chain to understand
that `mail_entities` defines the overload.

**Scenario B — Wrong entity type at call site.** A user writes:
```nim
let (b, h) = b.addSet[Thread](accountId)   # Thread has no /set
```
The compiler emits:
```
Error: undeclared identifier: 'setMethodName'  # undefined for Thread
```
The diagnostic names the missing overload but does not explain that `Thread`
doesn't support `/set`.  The `registerSettableEntity` macro would produce a
better error, but the call site never reaches it — the `mixin` resolution fails
first with an opaque message.

**Scenario C — toJson overload shadowing.** If two `toJson` overloads are
visible at the call site (one for entity-layer types, one for some unrelated
type), the compiler may pick the wrong one or emit an ambiguity error.  The
`mixin` mechanism silently widens the candidate set to everything visible at
the call site.

### The existing good pattern

The codebase already contains the correct solution in one place:
`serde_framework.nim:Filter[C].fromJson` (line 146–158).  It accepts the
condition deserialiser as an explicit callback parameter:

```nim
func fromJson*[C](
    T: typedesc[Filter[C]],
    node: JsonNode,
    fromCondition: proc(n: JsonNode, p: JsonPath): Result[C, SerdeViolation] {.
      noSideEffect, raises: []
    .},
    path: JsonPath = emptyJsonPath(),
): Result[Filter[C], SerdeViolation]
```

And in `serde_envelope.nim:fromJsonField[T]` (line 197–231), the direct-value
deserialiser is also an explicit callback:

```nim
func fromJsonField*[T](
    fieldName: string,
    node: JsonNode,
    fromDirect: proc(n: JsonNode): T {.noSideEffect, raises: [].},
    path: JsonPath = emptyJsonPath(),
): Result[Referencable[T], SerdeViolation]
```

And `dispatch.nim:get[T]` already has a callback overload (line 211–221):
```nim
func get*[T](
    resp: Response,
    handle: ResponseHandle[T],
    fromArgs: proc(node: JsonNode): Result[T, SerdeViolation] {.
      noSideEffect, raises: []
    .},
): Result[T, MethodError]
```

These three sites demonstrate the pattern: **accept the operation as a
parameter, let the caller supply it explicitly**.  The compiler error moves
from "undeclared identifier inside a generic expansion" to "wrong argument
type at the call site" — a direct, local diagnostic.

### Proposed change

Replace every `mixin` resolution site with an explicit callback parameter
following the `Filter[C].fromJson` precedent.  For example, `addSet` changes
from:

```nim
# Today: mixin-based
func addSet*[T, C, U, R](
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, C]] = Opt.none(Table[CreationId, C]),
    update: Opt[U] = Opt.none(U),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    extras: seq[(string, JsonNode)] = @[],
): (RequestBuilder, ResponseHandle[R]) =
  mixin setMethodName, capabilityUri, toJson    # implicit
  ...
```

to:

```nim
# Proposed: callback-based
func addSet*[T, C, U, R](
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, C]] = Opt.none(Table[CreationId, C]),
    update: Opt[U] = Opt.none(U),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    extras: seq[(string, JsonNode)] = @[],
    methodName: proc(T: typedesc[T]): MethodName {.noSideEffect, raises: [].},
    capabilityUri: proc(T: typedesc[T]): string {.noSideEffect, raises: [].},
    valueToJson: proc(v: JsonNode): JsonNode {.noSideEffect, raises: [].},
): (RequestBuilder, ResponseHandle[R]) =
  ...
```

But accepting `typedesc` callbacks requires Nim's `typedesc` parameter passing
which has compiler ergonomic friction.  A simpler approach: make the callback
take the _concrete method name_ and _concrete capability URI_ directly as
plain values, since those are always known at the call site:

```nim
func addSet*[T, C, U, R](
    b: RequestBuilder,
    accountId: AccountId,
    ifInState: Opt[JmapState] = Opt.none(JmapState),
    create: Opt[Table[CreationId, C]] = Opt.none(Table[CreationId, C]),
    update: Opt[U] = Opt.none(U),
    destroy: Opt[Referencable[seq[Id]]] = Opt.none(Referencable[seq[Id]]),
    extras: seq[(string, JsonNode)] = @[],
    methodName: MethodName,
    capability: string,
    createToJson: proc(v: C): JsonNode {.noSideEffect, raises: [].},
    updateToJson: proc(v: U): JsonNode {.noSideEffect, raises: [].},
): (RequestBuilder, ResponseHandle[R])
```

The existing convenience templates in `builder.nim:addSet[T]` (line 360) and
the entity-specific builders in `mail_builders.nim` already own the per-entity
knowledge — they know `setMethodName(Email)`, `capabilityUri(Email)`,
`C.toJson`, `U.toJson`.  These sites would become the single point where the
callbacks are constructed, making the dependency chain explicit and auditable.

The existing `addSet[Mailbox]` template (line 360) would become:

```nim
template addSet*[T](b: RequestBuilder, accountId: AccountId): untyped =
  addSet[T, createType(T), updateType(T), setResponseType(T)](
    b, accountId,
    methodName = setMethodName(T),
    capability = capabilityUri(T),
    createToJson = proc(v: createType(T)): JsonNode = toJson(v),
    updateToJson = proc(v: updateType(T)): JsonNode = toJson(v),
  )
```

The compiler diagnostic when the `T`-bound overloads are missing would
point directly at the failing line inside the template body (e.g.
`setMethodName(Thread)` → "undeclared identifier: 'setMethodName'") with the
template expansion site clearly named in the stack trace.

### Migration order

1. Convert `dispatch.nim:get[T]` — simplest, one `mixin fromJson`, already
   has a callback overload as precedent.
2. Convert `methods.nim:mergeCreateResults[T]` — one `mixin fromJson`.
3. Convert builder functions: `addGet`, `addSet`, `addCopy`, `addQuery`,
   `addQueryChanges`.
4. Remove `mixin` stanzas from all converted sites.
5. Remove `mixin`-reliant re-exports from `mail_builders.nim` and
   `mail_methods.nim` (the `export serde_*` blocks that exist solely to
   put `fromJson` overloads into the caller's scope for `mixin` resolution).

### Risk assessment

Low.  The builder and dispatch APIs are internal to the library (consumers
call `addGet[Mailbox]` through the template layer, not the raw generic).
The template layer absorbs the callback construction, so consumer code is
unchanged.  The change is purely internal plumbing.

---

## 2. Extract a JSON combinator mini-library

### The verbose patterns

Every `fromJson` function in the codebase repeats the same ~6-line stanza
for each field:

```nim
# Pattern A: required string field with smart-constructor validation
let nameNode = ?fieldJString(node, "name", path)       # 1. extract typed node
let name = nameNode.getStr("")                          # 2. unwrap value
?nonEmptyStr(name, "name", path / "name")               # 3. validate content
return ok(MyType(name: name, ...))                      # 4. construct

# Pattern B: required integer field with smart-constructor validation
let sortOrderNode = ?fieldJInt(node, "sortOrder", path)
let sortOrder = ?UnsignedInt.fromJson(sortOrderNode, path / "sortOrder")

# Pattern C: optional field with nil/null detection
let parentId = ?parseOptId(node, "parentId", path)

# Pattern D: optional field, hand-rolled nil/null detection
let roleNode = node{"role"}
let role = Opt.none(MailboxRole)
if not roleNode.isNil and roleNode.kind != JNull:
  role = Opt.some(?MailboxRole.fromJson(roleNode, path / "role"))

# Pattern E: bool with absent→default
let haNode = node{"hasAttachment"}
if not haNode.isNil and haNode.kind != JNull and haNode.kind != JBool:
  return err(SerdeViolation(kind: svkWrongKind, ...))
let hasAttachment = haNode.getBool(false)

# Pattern F: string with absent→default
let prevNode = node{"preview"}
let preview =
  if not prevNode.isNil and prevNode.kind == JString:
    prevNode.getStr("")
  else:
    ""
```

These patterns repeat across ~15 `fromJson` functions in
`serde_email.nim`, `serde_mailbox.nim`, `serde_thread.nim`,
`serde_identity.nim`, `serde_email_blueprint.nim`, `serde_email_update.nim`,
`serde_identity_update.nim`, `serde_vacation.nim`, `serde_snippet.nim`,
`serde_submission_envelope.nim`, `serde_submission_status.nim`,
`serde_email_submission.nim`, `serde_headers.nim`, `serde_body.nim`,
`serde_session.nim`, `serde_envelope.nim`, `serde_framework.nim`,
`serde_errors.nim`, and `methods.nim`.

A representative example — `serde_mailbox.nim:fromJson[Mailbox]` (lines
211–253) — spends 35 of its 43 lines on field-by-field extraction.  Only
8 lines are the actual type constructor.

### The cost

- **Visual noise.**  The extraction boilerplate obscures the data-flow
  structure: which fields are required vs optional, which are validated.
- **Inconsistent handling of absent-to-default.**  `Mailbox.fromJson` uses
  `getBool(false)` for `hasAttachment` with a custom nil/null/non-bool guard;
  `Email.fromJson` uses a nearly identical 6-line block in `parseBodyFields`.
  These two implementations could drift.
- **Repetition of the same error.**  Every hand-rolled nil-check-and-wrong-kind
  block is another chance to get the path argument wrong or miss a null case.

### Proposed combinators

Extract field-access patterns into a small set of pure combinator functions
in `serde.nim`.  Each combinator returns `Result[T, SerdeViolation]` and
composes with `?`:

```nim
# ---- Required fields ----

func reqString*(
    node: JsonNode, key: string, path: JsonPath
): Result[string, SerdeViolation] =
  ## Required JSON string field. Missing, null, or wrong kind → error.
  let child = ?fieldJString(node, key, path)
  return ok(child.getStr(""))

func reqStringNonEmpty*(
    node: JsonNode, key: string, path: JsonPath
): Result[string, SerdeViolation] =
  ## Required non-empty JSON string field.
  let s = ?reqString(node, key, path)
  ?nonEmptyStr(s, key, path / key)
  return ok(s)

func reqInt*(
    node: JsonNode, key: string, path: JsonPath
): Result[int64, SerdeViolation] =
  ## Required JSON integer field as int64 raw value.
  let child = ?fieldJInt(node, key, path)
  return ok(child.getBiggestInt(0))

func reqBool*(
    node: JsonNode, key: string, path: JsonPath
): Result[bool, SerdeViolation] =
  ## Required JSON bool field.
  let child = ?fieldJBool(node, key, path)
  return ok(child.getBool(false))

# ---- Required parsed fields ----

func reqParsed*[T](
    node: JsonNode, key: string,
    parse: proc(n: JsonNode, p: JsonPath): Result[T, SerdeViolation] {.
      noSideEffect, raises: []
    .},
    path: JsonPath,
): Result[T, SerdeViolation] =
  ## Required field parsed through a typed fromJson callback.
  let child = node{key}
  if child.isNil:
    return err(SerdeViolation(
      kind: svkMissingField, path: path, missingFieldName: key))
  return parse(child, path / key)

# ---- Optional fields ----

func optField*(
    node: JsonNode, key: string, kind: JsonNodeKind, path: JsonPath
): Result[Opt[JsonNode], SerdeViolation] =
  ## Optional JSON field of a specific kind. Absent or null → none.
  ## Wrong kind (not null) → error.
  let child = node{key}
  if child.isNil or child.kind == JNull:
    return ok(Opt.none(JsonNode))
  if child.kind != kind:
    return err(SerdeViolation(
      kind: svkWrongKind, path: path / key,
      expectedKind: kind, actualKind: child.kind))
  return ok(Opt.some(child))

func optParsed*[T](
    node: JsonNode, key: string,
    parse: proc(n: JsonNode, p: JsonPath): Result[T, SerdeViolation] {.
      noSideEffect, raises: []
    .},
    path: JsonPath,
): Result[Opt[T], SerdeViolation] =
  ## Optional field parsed through a callback. Absent or null → none.
  let child = node{key}
  if child.isNil or child.kind == JNull:
    return ok(Opt.none(T))
  return ok(Opt.some(?parse(child, path / key)))

func optString*(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[string], SerdeViolation] =
  ## Optional string field. Absent or null → none.
  let child = node{key}
  if child.isNil or child.kind == JNull:
    return ok(Opt.none(string))
  ?expectKind(child, JString, path / key)
  return ok(Opt.some(child.getStr("")))

func optBool*(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[bool], SerdeViolation] =
  ## Optional bool field. Absent or null → none.
  let child = node{key}
  if child.isNil or child.kind == JNull:
    return ok(Opt.none(bool))
  ?expectKind(child, JBool, path / key)
  return ok(Opt.some(child.getBool(false)))

func optInt*(
    node: JsonNode, key: string, path: JsonPath
): Result[Opt[int64], SerdeViolation] =
  ## Optional int field. Absent or null → none.
  let child = node{key}
  if child.isNil or child.kind == JNull:
    return ok(Opt.none(int64))
  ?expectKind(child, JInt, path / key)
  return ok(Opt.some(child.getBiggestInt(0)))
```

These are pure — no IO, no mutation, `{.noSideEffect, raises: [].}`.
They compose with `?`:

```nim
let name = ?reqStringNonEmpty(node, "name", path)
let parentId = ?optParsed[Id](node, "parentId", Id.fromJson, path)
let sortOrderUI = ?reqParsed[UnsignedInt](node, "sortOrder", UnsignedInt.fromJson, path)
let isSubscribed = ?reqBool(node, "isSubscribed", path)
```

### Before/after: Mailbox.fromJson

**Before (43 lines of extraction):**

```nim
func fromJson*(
    T: typedesc[Mailbox], node: JsonNode, path: JsonPath
): Result[Mailbox, SerdeViolation] =
  discard $T
  ?expectKind(node, JObject, path)
  let idNode = ?fieldJString(node, "id", path)
  let id = ?Id.fromJson(idNode, path / "id")
  let nameNode = ?fieldJString(node, "name", path)
  let name = nameNode.getStr("")
  ?nonEmptyStr(name, "name", path / "name")
  let parentId = ?parseOptId(node, "parentId", path)
  let role = ?parseOptMailboxRole(node, "role", path)
  let sortOrderNode = ?fieldJInt(node, "sortOrder", path)
  let sortOrder = ?UnsignedInt.fromJson(sortOrderNode, path / "sortOrder")
  let totalEmailsNode = ?fieldJInt(node, "totalEmails", path)
  let totalEmails = ?UnsignedInt.fromJson(totalEmailsNode, path / "totalEmails")
  let unreadEmailsNode = ?fieldJInt(node, "unreadEmails", path)
  let unreadEmails = ?UnsignedInt.fromJson(unreadEmailsNode, path / "unreadEmails")
  let totalThreadsNode = ?fieldJInt(node, "totalThreads", path)
  let totalThreads = ?UnsignedInt.fromJson(totalThreadsNode, path / "totalThreads")
  let unreadThreadsNode = ?fieldJInt(node, "unreadThreads", path)
  let unreadThreads = ?UnsignedInt.fromJson(unreadThreadsNode, path / "unreadThreads")
  let myRightsNode = ?fieldJObject(node, "myRights", path)
  let myRights = ?MailboxRights.fromJson(myRightsNode, path / "myRights")
  let isSubscribed = ?parseBoolField(node, "isSubscribed", path)
  return ok(Mailbox(
    id: id, name: name, parentId: parentId, role: role,
    sortOrder: sortOrder, totalEmails: totalEmails, unreadEmails: unreadEmails,
    totalThreads: totalThreads, unreadThreads: unreadThreads,
    myRights: myRights, isSubscribed: isSubscribed,
  ))
```

**After (combinators, ~18 lines of extraction):**

```nim
func fromJson*(
    T: typedesc[Mailbox], node: JsonNode, path: JsonPath
): Result[Mailbox, SerdeViolation] =
  discard $T
  ?expectKind(node, JObject, path)
  let id = ?reqParsed[Id](node, "id", Id.fromJson, path)
  let name = ?reqStringNonEmpty(node, "name", path)
  let parentId = ?optParsed[Id](node, "parentId", Id.fromJson, path)
  let role = ?optParsed[MailboxRole](node, "role", MailboxRole.fromJson, path)
  let sortOrder = ?reqParsed[UnsignedInt](node, "sortOrder", UnsignedInt.fromJson, path)
  let totalEmails = ?reqParsed[UnsignedInt](node, "totalEmails", UnsignedInt.fromJson, path)
  let unreadEmails = ?reqParsed[UnsignedInt](node, "unreadEmails", UnsignedInt.fromJson, path)
  let totalThreads = ?reqParsed[UnsignedInt](node, "totalThreads", UnsignedInt.fromJson, path)
  let unreadThreads = ?reqParsed[UnsignedInt](node, "unreadThreads", UnsignedInt.fromJson, path)
  let myRights = ?reqParsed[MailboxRights](node, "myRights", MailboxRights.fromJson, path)
  let isSubscribed = ?reqBool(node, "isSubscribed", path)
  return ok(Mailbox(
    id: id, name: name, parentId: parentId, role: role,
    sortOrder: sortOrder, totalEmails: totalEmails, unreadEmails: unreadEmails,
    totalThreads: totalThreads, unreadThreads: unreadThreads,
    myRights: myRights, isSubscribed: isSubscribed,
  ))
```

### What the combinators replace

After migration, the following hand-rolled helpers become dead code and can
be deleted:

| Module | Helpers to delete |
|--------|-------------------|
| `serde_mailbox.nim` | `parseBoolField`, `parseOptId`, `parseOptMailboxRole`, `parseOptUnsignedInt`, `parseOptBool` |
| `serde_email.nim` | `parseOptId`, `parseOptBlobId`, `parseOptStringSeq`, `parseOptUnsignedInt`, `parseOptUTCDate`, `parseOptMailboxIdSet`, `parseOptKeywordSet`, `parseOptBodyPart`, `parseOptAddresses`, `parseOptDate`, `parseOptString` |
| `serde_identity.nim` | Same pattern — `parseOpt*` helpers |
| `serde_email_blueprint.nim` | Same pattern |
| `serde_identity_update.nim` | Same pattern |
| `serde_email_update.nim` | Same pattern |

The existing `optJsonField` and `fieldOfKind`/`fieldJString` etc. in
`serde.nim` remain as the low-level building blocks the combinators
delegate to.  Nothing is removed from the foundation — only built on top.

### Typed field spec (stretch goal)

For sites with 4+ identical `reqParsed[X](node, "field", X.fromJson, path)`
calls (e.g. `MailboxRights` with 9 boolean fields, `Mailbox` with 5
`UnsignedInt` fields), a small template could compress further:

```nim
template fields(node, path, body: untyped): untyped =
  ?expectKind(node, JObject, path)
  body

# Usage:
fields(node, path):
  let id = req(Id, "id")
  let name = reqStr("name")
  let parentId = opt(Id, "parentId")
```

But this is a stretch goal — the combinator functions alone eliminate
~200 lines of hand-rolled extraction helpers and make every `fromJson`
body a flat list of typed field declarations.

### Migration order

1. Implement the combinator functions in `serde.nim` alongside the existing
   `fieldOfKind`/`optField` foundation.  Pure, no breaking changes.
2. Convert one `fromJson` as a proof-of-concept (suggest `Mailbox.fromJson`
   in `serde_mailbox.nim` — self-contained, ~12 fields, no recursive
   sub-parsers).
3. Convert remaining `fromJson` functions in order of decreasing field count.
4. Delete the per-module `parseOpt*` helpers as they become unused.
5. Run `just ci` after each conversion module.

### Risk assessment

Low.  The combinators are pure functions that wrap the existing `fieldOfKind`
/ `expectKind` / `optField` primitives.  They produce the same
`SerdeViolation` variants at the same paths.  Existing serde tests pin down
the exact error paths and messages — any deviation will fail the test suite.
