# std/json Accessor Reference

## Idiomatic Accessors (preferred for required fields)

These accessors raise on missing or wrong-type data. Exceptions propagate
naturally through Layers 1–4 and are caught at the Layer 5 C ABI boundary.

| Accessor | Raises | Use case |
|----------|--------|----------|
| `node["key"]` | `KeyError` if key missing | Required object fields |
| `to[T](node)` | `KeyError`, `JsonKindError` | Simple object deserialisation |
| `parseJson(s)` | `JsonParsingError`, `IOError` | Parsing raw JSON strings |

```nim
# Required field extraction:
let name = node["name"].getStr()
let count = node["count"].getInt()

# Simple object deserialisation:
let response = node.to(ChangesResponse)
```

Types with custom wire formats (e.g., `Invocation` as a 3-element JSON array,
`Referencable[T]` with `#`-prefixed keys) still require manual serialisation.

---

## Nil-Safe Accessors (for optional fields and defensive access)

These accessors never raise `CatchableError`. They return defaults or `nil`
when data is missing or the wrong kind. Use these for optional fields where
absent data is a valid state, not an error.

### Navigation (nil-safe)

| Accessor | Returns | Behaviour on missing/wrong kind |
|----------|---------|--------------------------------|
| `node{key}` | `JsonNode` | `nil` if node is nil, not JObject, or key missing |
| `node{key1, key2, ...}` | `JsonNode` | `nil` if any key missing or wrong kind at any level |
| `node{index}` (int varargs) | `JsonNode` | `nil` if node is nil, not JArray, or index OOB |
| `node.getOrDefault(key)` | `JsonNode` | `nil` if node is nil, not JObject, or key missing |

**Nil-safe chaining**: `node{"a"}{"b"}{"c"}.getStr("")` — returns `""` if any
level is missing. This is the primary navigation pattern for optional fields.

### Value Extraction (nil-safe, with defaults)

| Accessor | Returns | Default | Notes |
|----------|---------|---------|-------|
| `getStr(default = "")` | `string` | `""` | Returns default if nil or not JString |
| `getInt(default = 0)` | `int` | `0` | Returns default if nil or not JInt |
| `getBiggestInt(default = 0)` | `BiggestInt` | `0` | Returns default if nil or not JInt |
| `getFloat(default = 0.0)` | `float` | `0.0` | Returns default if nil, not JFloat/JInt |
| `getBool(default = false)` | `bool` | `false` | Returns default if nil or not JBool |
| `getFields(default = ...)` | `OrderedTable[string, JsonNode]` | empty table | Returns default if nil or not JObject |
| `getElems(default = @[])` | `seq[JsonNode]` | `@[]` | Returns default if nil or not JArray |

### Kind Checking

| Accessor | Returns | Notes |
|----------|---------|-------|
| `node.kind` | `JsonNodeKind` | `JNull`, `JBool`, `JInt`, `JFloat`, `JString`, `JObject`, `JArray` |
| `node.isNil` | `bool` | True if the JsonNode ref is nil |
| `node.len` | `int` | Element count for JArray/JObject, 0 for others. **Not nil-safe** — crashes on nil. |

### Membership Testing

| Accessor | Returns | Notes |
|----------|---------|-------|
| `node.hasKey(key)` | `bool` | True if JObject contains key. Asserts JObject kind. |
| `node.contains(key)` | `bool` | Same as hasKey for JObject |
| `node.contains(val)` | `bool` | True if JArray contains val |

### Construction

| Constructor | Creates | Notes |
|-------------|---------|-------|
| `%val` | `JsonNode` | Auto-converts string, int, float, bool, seq, Table, `Option[T]` |
| `%*{...}` | `JsonNode` | Compile-time JSON literal macro |
| `newJString(s)` | `JsonNode` | JString |
| `newJInt(n)` | `JsonNode` | JInt |
| `newJFloat(n)` | `JsonNode` | JFloat |
| `newJBool(b)` | `JsonNode` | JBool |
| `newJNull()` | `JsonNode` | JNull |
| `newJObject()` | `JsonNode` | Empty JObject |
| `newJArray()` | `JsonNode` | Empty JArray |

### Mutation

| Mutator | Notes |
|---------|-------|
| `obj[key] = val` | Set field on JObject |
| `arr.add(child)` | Append to JArray |
| `obj.add(key, val)` | Add field to JObject |

### Serialisation

| Proc | Returns | Notes |
|------|---------|-------|
| `$node` | `string` | Compact JSON string |
| `node.pretty(indent)` | `string` | Pretty-printed JSON |
| `node.toUgly(result)` | `void` | Compact JSON into existing string (avoids alloc) |

### Iteration

| Iterator | Yields | Notes |
|----------|--------|-------|
| `items(node)` | `JsonNode` | Iterate JArray elements. Asserts JArray kind. |
| `pairs(node)` | `(string, JsonNode)` | Iterate JObject key-value pairs. Asserts JObject kind. |
| `keys(node)` | `string` | Iterate JObject keys. Asserts JObject kind. |

### Comparison

| Proc | Notes |
|------|-------|
| `==` | Deep equality. Explicitly `{.raises: [].}`. Nil-safe. |
| `hash` | Deep hash. `{.noSideEffect.}`. **Not nil-safe** — crashes on nil (unlike `==`). |

---

## Defect-Raising Accessors (avoid)

These raise `Defect` subtypes which crash the process and cannot be caught.

| Accessor | Raises | Alternative |
|----------|--------|-------------|
| `node[index]` (int) | `AssertionDefect` / `IndexDefect` | `node{index}` or bounds check first |
| `node.str` | `FieldDefect` if not JString | `node.getStr("")` |
| `node.num` | `FieldDefect` if not JInt | `node.getInt(0)` |
| `node.fnum` | `FieldDefect` if not JFloat | `node.getFloat(0.0)` |
| `node.bval` | `FieldDefect` if not JBool | `node.getBool(false)` |

Note: `str`, `num`, `fnum`, `bval` are case object **fields**, not procs.
Accessing the wrong branch's field raises `FieldDefect`. Do not confuse these
with the `parsejson` re-exports (`str`, `getInt`, `getFloat`) which operate on
`JsonParser`, not `JsonNode`.

### The `assert` Caveat

Many nil-safe procs use `assert` to check the node kind before operating.
Under `--assertions:on` (debug builds, which this project uses), a failed
assertion raises `AssertionDefect` — a `Defect`, not a `CatchableError`.
Defects crash the process. Always verify `node.kind` before calling these:

- **Membership**: `hasKey`, `contains`
- **Iteration**: `items`, `pairs`, `keys`
- **Mutation**: `add(father, child)`, `add(obj, key, val)`, `obj[key] = val`
- **Deletion**: `delete` (also raises `KeyError`)
