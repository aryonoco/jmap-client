# std/json Accessor Reference

## Raises-Free (safe inside `func` / `{.raises: [].}`)

These accessors never raise `CatchableError`. They return defaults or `nil`
when data is missing or the wrong kind. Use ONLY these in serialisation code.

### Navigation (nil-safe)

| Accessor | Returns | Behaviour on missing/wrong kind |
|----------|---------|--------------------------------|
| `node{key}` | `JsonNode` | `nil` if node is nil, not JObject, or key missing |
| `node{key1, key2, ...}` | `JsonNode` | `nil` if any key missing or wrong kind at any level |
| `node{index}` (int varargs) | `JsonNode` | `nil` if node is nil, not JArray, or index OOB |
| `node.getOrDefault(key)` | `JsonNode` | `nil` if node is nil, not JObject, or key missing |

**Nil-safe chaining**: `node{"a"}{"b"}{"c"}.getStr("")` — returns `""` if any
level is missing. This is the primary navigation pattern in this project.

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
| `node.len` | `int` | Element count for JArray/JObject, 0 for others |

### Membership Testing

| Accessor | Returns | Notes |
|----------|---------|-------|
| `node.hasKey(key)` | `bool` | True if JObject contains key. Asserts JObject kind. |
| `node.contains(key)` | `bool` | Same as hasKey for JObject |
| `node.contains(val)` | `bool` | True if JArray contains val |

### Construction

| Constructor | Creates | Notes |
|-------------|---------|-------|
| `%val` | `JsonNode` | Auto-converts string, int, float, bool, seq, Table, Option |
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
| `==` | Deep equality. Explicitly `{.raises: [].}`. |
| `hash` | Deep hash. `{.noSideEffect.}`. |

---

## Raises-Prone (NEVER use in this project)

These accessors raise `CatchableError` subtypes. Using them inside `func` or
`{.push raises: [].}` is a compile error. Avoid them entirely.

| Accessor | Raises | Alternative |
|----------|--------|-------------|
| `node["key"]` | `KeyError` if key missing | `node{"key"}` |
| `node[index]` (int) | `IndexDefect` if OOB | `node{index}` or bounds check first |
| `node.str` | `JsonKindError` if not JString | `node.getStr("")` |
| `node.num` | `JsonKindError` if not JInt | `node.getInt(0)` |
| `node.fnum` | `JsonKindError` if not JFloat | `node.getFloat(0.0)` |
| `node.bval` | `JsonKindError` if not JBool | `node.getBool(false)` |
| `to[T](node)` | `KeyError`, `JsonKindError` | Manual extraction with raises-free accessors |
| `parseJson(s)` | `JsonParsingError`, `IOError` | Boundary proc with try/except (see serde-patterns.md) |
| `parseFile(path)` | `IOError`, `JsonParsingError` | Not used in this library (no file I/O) |
| `delete(obj, key)` | `KeyError` if key missing | Check `hasKey` first, or skip |

### The `assert` Caveat

Several raises-free procs (`hasKey`, `contains`, `items`, `pairs`, `keys`) use
`assert` to check the node kind. Under `--assertions:on` (debug builds, which
this project uses), a failed assertion raises `AssertionDefect` — a `Defect`,
not a `CatchableError`. Defects are NOT tracked by `{.raises: [].}` and will
crash the process. Always verify `node.kind` before calling these.
