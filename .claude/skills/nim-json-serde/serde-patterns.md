# Serialisation Patterns

Patterns for this project. Serialisation and deserialisation use `func` with
`std/json` nil-safe accessors and return `Result[T, ValidationError]` via
nim-results. The `?` operator provides early-return error propagation.
`{.push raises: [].}` is on every module.

## Parsing Raw JSON

`parseJson` is side-effectful and can raise — it belongs in `proc` code
(Layer 4 transport). Serde `func` code operates on pre-parsed `JsonNode`:

```nim
# L4 proc — wraps parseJson in try/except, returns Result
proc parseJsonBody(body: string, context: string): Result[JsonNode, ClientError] =
  try:
    {.cast(raises: [CatchableError]).}:
      ok(parseJson(body))
  except CatchableError as e:
    err(clientError(transportError(tekNetwork, "invalid JSON: " & e.msg)))

# L2 func — operates on pre-parsed JsonNode, returns Result
func fromJson*(T: typedesc[Session], node: JsonNode): Result[Session, ValidationError] =
  ?checkJsonKind(node, JObject, "Session")
  # ...
```

## Object toJson

Constructs a `JsonNode` from an object. Uses `func`:

```nim
func toJson*(s: Session): JsonNode =
  result = newJObject()
  result["username"] = %s.username
  result["apiUrl"] = %s.apiUrl
  result["downloadUrl"] = %(string(s.downloadUrl))  # unwrap distinct
  result["state"] = %(string(s.state))
  # Add capabilities
  var caps = newJObject()
  for cap in s.capabilities:
    caps[cap.rawUri] = cap.toJson()
  result["capabilities"] = caps
```

**Distinct types**: unwrap with `string(id)` or `int64(val)` before passing
to `%` — the `%` operator does not auto-unwrap distinct types.

## Object fromJson

Extract from `JsonNode` using nil-safe accessors. Return `Result`:

```nim
func fromJson*(_: typedesc[Account], node: JsonNode): Result[Account, ValidationError] =
  ?checkJsonKind(node, JObject, "Account")
  let name = node{"name"}.getStr("")
  if name.len == 0:
    return err(validationError("Account", "missing or empty 'name'", ""))
  ok(Account(
    name: name,
    isPersonal: node{"isPersonal"}.getBool(false),
    isReadOnly: node{"isReadOnly"}.getBool(false),
  ))
```

**Pattern**: `checkJsonKind` with `?` first, use `node{"field"}.getType(default)`
for extraction, smart constructors with `?` for validated types, wrap in `ok()`.

## Case Object fromJson

Dispatch on the discriminator field, then parse the branch:

```nim
func fromJson*(_: typedesc[TransportError], node: JsonNode): Result[TransportError, ValidationError] =
  ?checkJsonKind(node, JObject, "TransportError")
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
    err(validationError("TransportError", "unknown kind: " & kindStr, kindStr))
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

For deserialisation, use `parseEnum` with a default (raises-free):

```nim
func parseMethodErrorType*(raw: string): MethodErrorType =
  strutils.parseEnum[MethodErrorType](raw, metUnknown)
```

**`symbolName` vs `$`**: `symbolName()` (from `std/enumutils`) returns the
Nim identifier (`"metServerFail"`). `$` returns the backing string
(`"serverFail"`). Do not confuse them.

## Invocation as 3-Element JSON Array

JMAP Invocations are serialised as JSON arrays, NOT objects (RFC 8620 §3.3):

```nim
func toJson*(inv: Invocation): JsonNode =
  var arr = newJArray()
  arr.add(%inv.name)
  arr.add(if inv.arguments.isNil: newJObject() else: inv.arguments)
  arr.add(inv.methodCallId.toJson())
  arr

func fromJson*(_: typedesc[Invocation], node: JsonNode): Result[Invocation, ValidationError] =
  ?checkJsonKind(node, JArray, "Invocation")
  if node.len != 3:
    return err(validationError("Invocation", "expected 3-element array", ""))
  let name = node.getElems(@[])[0].getStr("")
  let args = node.getElems(@[])[1]
  let callId = ?parseMethodCallId(node.getElems(@[])[2].getStr(""))
  ok(Invocation(name: name, arguments: args, methodCallId: callId))
```

## Optional Fields (Option[T])

Omit the field entirely when `isNone`, include when `isSome`:

```nim
func toJson*(r: Request): JsonNode =
  result = newJObject()
  result["using"] = %r.using
  var calls = newJArray()
  for mc in r.methodCalls:
    calls.add(mc.toJson())
  result["methodCalls"] = calls
  if r.createdIds.isSome:
    var ids = newJObject()
    for k, v in r.createdIds.get():
      ids[string(k)] = %(string(v))
    result["createdIds"] = ids
```

For deserialisation, check presence with nil-check:

```nim
let createdIds =
  if node{"createdIds"}.isNil or node{"createdIds"}.kind == JNull:
    none(Table[CreationId, Id])
  else:
    some(?parseCreatedIds(node{"createdIds"}))
```

## Referencable Fields (# prefix)

Result references use `#`-prefixed field names (RFC 8620 §3.7):

```nim
func referencableKey*[T](fieldName: string, r: Referencable[T]): string =
  case r.kind
  of rkDirect: fieldName
  of rkReference: "#" & fieldName
```

At the request-builder level, emit `#fieldName` instead of `fieldName`:

```nim
if arg.kind == rkReference:
  result["#" & fieldName] = arg.reference.toJson()
else:
  result[fieldName] = arg.value.toJson()
```
