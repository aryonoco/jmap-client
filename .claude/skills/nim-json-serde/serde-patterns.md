# Serialisation Patterns

Patterns for this project. All deserialisation logic is `func` with
`{.push raises: [].}` — only the raw JSON parsing boundary is a `proc`.

## Boundary Pattern: Raw JSON to JsonNode

The only place `parseJson` is called. Wraps the raising call in a `proc`,
returning `Result[JsonNode, string]`:

```nim
proc safeParseJson*(raw: string): Result[JsonNode, string] =
  ## Parse a raw JSON string. Returns err on malformed input.
  try:
    ok(parseJson(raw))
  except CatchableError as e:
    err("JSON parse error: " & e.msg)
```

Callers use `?` to propagate, then `mapErr` to lift into `JmapResult`:

```nim
proc parseSession*(raw: string): JmapResult[Session] =
  let node = ? safeParseJson(raw).mapErr(toParseError)
  Session.fromJson(node)
```

## Object toJson

Pure `func`, constructs a `JsonNode` from an object:

```nim
func toJson*(s: Session): JsonNode =
  result = %*{
    "username": s.username,
    "apiUrl": s.apiUrl,
    "downloadUrl": string(s.downloadUrl),  # unwrap distinct
    "uploadUrl": string(s.uploadUrl),
    "eventSourceUrl": string(s.eventSourceUrl),
    "state": string(s.state),
  }
  # Add capabilities array
  var caps = newJObject()
  for cap in s.capabilities:
    caps[cap.rawUri] = cap.toJson()
  result["capabilities"] = caps
  # Add accounts
  var accts = newJObject()
  for id, acct in s.accounts:
    accts[string(id)] = acct.toJson()
  result["accounts"] = accts
```

**Distinct types**: unwrap with `string(id)` or `int(val)` before passing
to `%` — the `%` operator does not auto-unwrap distinct types.

## Object fromJson

Pure `func`, extracts from `JsonNode` using raises-free accessors:

```nim
func fromJson*(_: typedesc[Account], node: JsonNode): JmapResult[Account] =
  if node.isNil or node.kind != JObject:
    return err(parseError("Account", "expected JSON object"))

  let name = node{"name"}.getStr("")
  if name.len == 0:
    return err(parseError("Account", "missing or empty 'name'"))

  ok(Account(
    name: name,
    isPersonal: node{"isPersonal"}.getBool(false),
    isReadOnly: node{"isReadOnly"}.getBool(false),
  ))
```

**Pattern**: validate `kind` first, extract with `node{"field"}.getType(default)`,
validate required fields, construct and return `ok(...)`.

## Case Object fromJson

Dispatch on the discriminator field, then parse the branch:

```nim
func fromJson*(_: typedesc[TransportError], node: JsonNode): JmapResult[TransportError] =
  if node.isNil or node.kind != JObject:
    return err(parseError("TransportError", "expected JSON object"))

  let kindStr = node{"kind"}.getStr("")
  let message = node{"message"}.getStr("")

  case kindStr
  of "network":
    ok(TransportError(kind: tekNetwork, message: message))
  of "tls":
    ok(TransportError(kind: tekTls, message: message))
  of "timeout":
    ok(TransportError(kind: tekTimeout, message: message))
  of "httpStatus":
    let status = node{"httpStatus"}.getInt(0)
    ok(TransportError(kind: tekHttpStatus, message: message, httpStatus: status))
  else:
    err(parseError("TransportError", "unknown kind: " & kindStr))
```

## Enum Serialisation

For string-backed enums, Nim's `$` operator returns the **backing string**,
not the symbolic name. This means `%` (which calls `$`) already produces
the correct wire value:

```nim
type MethodErrorType = enum
  metServerFail = "serverFail"
  metInvalidArguments = "invalidArguments"

# $metServerFail == "serverFail"  (the backing string)
# %metServerFail == JString("serverFail") — correct for wire format
```

Serialisation works automatically via `$` and `%`:

```nim
func toJson*(met: MethodErrorType): JsonNode =
  %met  # produces the backing string via $
```

For deserialisation, match against the backing strings:

```nim
func parseMethodErrorType*(raw: string): Opt[MethodErrorType] =
  case raw
  of "serverFail": Opt.some(metServerFail)
  of "invalidArguments": Opt.some(metInvalidArguments)
  # ... exhaustive
  else: Opt.none(MethodErrorType)
```

**`symbolName` vs `$`**: `symbolName()` (from `std/enumutils`) returns the
Nim identifier (`"metServerFail"`). `$` returns the backing string
(`"serverFail"`). Do not confuse them.

## Invocation as 3-Element JSON Array

JMAP Invocations are serialised as JSON arrays, NOT objects (RFC 8620 §3.3):

```nim
func toJson*(inv: Invocation): JsonNode =
  %*[inv.name, inv.arguments, string(inv.methodCallId)]

func fromJson*(_: typedesc[Invocation], node: JsonNode): JmapResult[Invocation] =
  if node.isNil or node.kind != JArray or node.len != 3:
    return err(parseError("Invocation", "expected 3-element JSON array"))

  let name = node{0}.getStr("")
  let args = node{1}
  let callId = node{2}.getStr("")

  if name.len == 0 or args.isNil or callId.len == 0:
    return err(parseError("Invocation", "missing name, arguments, or callId"))

  let mcid = ? parseMethodCallId(callId)
  ok(Invocation(name: name, arguments: args, methodCallId: mcid))
```

## Optional Fields (Opt[T])

Omit the field entirely when `isNone`, include when `isSome`:

```nim
func toJson*(r: Request): JsonNode =
  result = newJObject()
  result["using"] = %r.using
  result["methodCalls"] = %r.methodCalls.mapIt(it.toJson())
  # Only include createdIds if present
  if r.createdIds.isSome:
    let ids = newJObject()
    for k, v in r.createdIds.get():
      ids[string(k)] = %string(v)
    result["createdIds"] = ids
```

For deserialisation, check presence with `hasKey` or nil-check:

```nim
let createdIds =
  if node{"createdIds"}.isNil or node{"createdIds"}.kind == JNull:
    Opt.none(Table[CreationId, Id])
  else:
    Opt.some(? parseCreatedIds(node{"createdIds"}))
```

## Referencable Fields (# prefix)

Result references use `#`-prefixed field names (RFC 8620 §3.7):

```nim
func toJson*(r: Referencable[seq[Id]]): JsonNode =
  case r.kind
  of rkDirect:
    %r.direct.mapIt(%string(it))
  of rkReference:
    # The field name gets a # prefix — handled by the caller
    r.reference.toJson()
```

At the request-builder level, emit `#fieldName` instead of `fieldName`:

```nim
if arg.kind == rkReference:
  result["#" & fieldName] = arg.toJson()
else:
  result[fieldName] = arg.toJson()
```
