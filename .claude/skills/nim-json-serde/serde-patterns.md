# Serialisation Patterns

Patterns for this project. All serialisation and deserialisation logic uses
`proc` with standard `std/json` APIs. Exceptions propagate naturally.

## Parsing Raw JSON

Use `parseJson` directly. It raises `JsonParsingError` on malformed input,
which propagates naturally through Layers 1–4:

```nim
proc parseSession*(raw: string): Session =
  let node = parseJson(raw)
  Session.fromJson(node)
```

If you need to handle parse errors specifically at a boundary:

```nim
proc tryParseSession*(raw: string): Session =
  try:
    let node = parseJson(raw)
    Session.fromJson(node)
  except JsonParsingError as e:
    raise newException(ClientError, "malformed JSON: " & e.msg)
```

## Object toJson

Constructs a `JsonNode` from an object:

```nim
proc toJson*(s: Session): JsonNode =
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

Extract from `JsonNode` using idiomatic accessors. Raise on invalid data:

```nim
proc fromJson*(_: typedesc[Account], node: JsonNode): Account =
  if node.isNil or node.kind != JObject:
    raise newException(ValidationError, "Account: expected JSON object")

  let name = node["name"].getStr()
  if name.len == 0:
    raise newException(ValidationError, "Account: missing or empty 'name'")

  Account(
    name: name,
    isPersonal: node{"isPersonal"}.getBool(false),
    isReadOnly: node{"isReadOnly"}.getBool(false),
  )
```

**Pattern**: validate `kind` first, use `node["field"]` for required fields,
`node{"field"}.getType(default)` for optional fields with defaults, construct
and return directly.

## Case Object fromJson

Dispatch on the discriminator field, then parse the branch:

```nim
proc fromJson*(_: typedesc[TransportError], node: JsonNode): TransportError =
  if node.isNil or node.kind != JObject:
    raise newException(ValidationError, "TransportError: expected JSON object")

  let kindStr = node{"kind"}.getStr("")
  let message = node{"message"}.getStr("")

  case kindStr
  of "network":
    TransportError(kind: tekNetwork, msg: message)
  of "tls":
    TransportError(kind: tekTls, msg: message)
  of "timeout":
    TransportError(kind: tekTimeout, msg: message)
  of "httpStatus":
    let status = node{"httpStatus"}.getInt(0)
    TransportError(kind: tekHttpStatus, msg: message, httpStatus: status)
  else:
    raise newException(ValidationError, "TransportError: unknown kind: " & kindStr)
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
proc toJson*(met: MethodErrorType): JsonNode =
  %met  # produces the backing string via $
```

For deserialisation, match against the backing strings:

```nim
proc parseMethodErrorType*(raw: string): Option[MethodErrorType] =
  case raw
  of "serverFail": some(metServerFail)
  of "invalidArguments": some(metInvalidArguments)
  # ... exhaustive
  else: none(MethodErrorType)
```

**`symbolName` vs `$`**: `symbolName()` (from `std/enumutils`) returns the
Nim identifier (`"metServerFail"`). `$` returns the backing string
(`"serverFail"`). Do not confuse them.

## Invocation as 3-Element JSON Array

JMAP Invocations are serialised as JSON arrays, NOT objects (RFC 8620 §3.3):

```nim
proc toJson*(inv: Invocation): JsonNode =
  %*[inv.name, inv.arguments, string(inv.methodCallId)]

proc fromJson*(_: typedesc[Invocation], node: JsonNode): Invocation =
  if node.isNil or node.kind != JArray or node.len != 3:
    raise newException(ValidationError, "Invocation: expected 3-element JSON array")

  let name = node{0}.getStr("")
  let args = node{1}
  let callId = node{2}.getStr("")

  if name.len == 0 or args.isNil or callId.len == 0:
    raise newException(ValidationError, "Invocation: missing name, arguments, or callId")

  let mcid = parseMethodCallId(callId)
  Invocation(name: name, arguments: args, methodCallId: mcid)
```

## Optional Fields (Option[T])

Omit the field entirely when `isNone`, include when `isSome`:

```nim
proc toJson*(r: Request): JsonNode =
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
    none(Table[CreationId, Id])
  else:
    some(parseCreatedIds(node{"createdIds"}))
```

## Referencable Fields (# prefix)

Result references use `#`-prefixed field names (RFC 8620 §3.7):

```nim
proc toJson*(r: Referencable[seq[Id]]): JsonNode =
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
