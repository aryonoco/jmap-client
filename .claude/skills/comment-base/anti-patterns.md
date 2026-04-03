# AI Comment Anti-Patterns

Detect and eliminate every instance of these patterns. Each pattern includes a
detection heuristic and the correct response.

## 1. Tautological Comments

**Detection**: Comment restates the code on the next line in natural language.

**Before** (delete):
```
# Increment the counter
counter += 1

# Return the result
return result

# Check if the session is valid
if session.isValid:
```

**Action**: Delete the comment entirely. The code is the documentation.

## 2. Signature Restatement in Docstrings

**Detection**: Docstring repeats the function name, parameter names, parameter types,
or return type that are already expressed in the function signature or type system.

**Before** (delete or rewrite):
```nim
## Parses the account ID from the given raw string.
## Returns the AccountId or raises an error.
proc parseAccountId*(raw: string): AccountId =
```

**Action**: Delete the docstring if the function name is self-explanatory.
Rewrite only if there is a non-obvious "why" to document (e.g. validation rules,
encoding constraints, ownership semantics).

## 3. Numbered Step Narration

**Detection**: Comments follow a `# Step N:` pattern.

**Before** (delete):
```nim
# Step 1: Parse the JSON
let node = ? safeParseJson(raw)
# Step 2: Extract the session
let session = ? parseSession(node)
# Step 3: Validate capabilities
let validated = ? validateCapabilities(session)
```

**Action**: Delete all step comments. If the sequence has a non-obvious ordering
constraint, replace with a single comment explaining WHY that order matters.

## 4. Section Header ASCII Art

**Detection**: Lines of `===`, `---`, `***`, `###`, or box-drawing characters used
as visual separators between code sections.

**Before** (delete):
```
# ============================================
# ===        SESSION DISCOVERY             ===
# ============================================
```

**Action**: Delete entirely. If a file needs section headers, the file is too long.
In the rare case a section marker is genuinely needed, a bare `# --- Discovery`
suffices, but prefer splitting the file.

## 5. Generic Boilerplate Headers

**Detection**: Comments like `# Import modules`, `# Define types`, `# Helper functions`,
`# Handle errors`, `# Export`, `# This module provides...`.

**Before** (delete):
```nim
# Import necessary modules
import std/[json, tables]

# Define types
type AccountId* = distinct string
```

**Action**: Delete. These are content-free section labels.

## 6. Over-Documented Parameters

**Detection**: Every parameter is documented with a restatement of its name or type.

**Before** (delete the redundant docs):
```nim
## Validates the session object.
## Parameters:
##   session - The session to validate
##   strict - Whether to use strict validation
proc validateSession*(session: Session, strict: bool): Session =
```

**Action**: Delete parameter documentation that adds nothing beyond the signature.
Keep only where the docstring adds context the type cannot express (valid ranges,
encoding, ownership semantics, side effects).

## 7. Trailing Inline Restaters

**Detection**: End-of-line comments that restate the variable or field name.

**Before** (delete):
```nim
let name = node{"name"}.getStr("")         # Get the account name
let isPersonal = node{"isPersonal"}.getBool(false)  # Check if personal
```

**Action**: Delete. The variable name and accessor are the documentation.

## 8. Enthusiastic or Marketing Language

**Detection**: Words like "elegantly", "seamlessly", "beautifully", "leverage",
"powerful", "robust", "cutting-edge", "state-of-the-art".

**Action**: Replace with factual language or delete the sentence.

## 9. File-Level "This File Contains" Comments

**Detection**: `## This module provides...`, `## This file contains...`,
`## This module is responsible for...`.

**Action**: Rewrite to explain WHY the module exists and what architectural
role it plays, or delete if the filename and exports are self-explanatory.

## 10. Commented-Out Code Without Context

**Detection**: Blocks of commented-out code without an explanation of why they are
retained (e.g. no TODO, no issue reference).

**Action**: Do NOT delete commented-out code (that would be a functional change
in some contexts). Instead, add a brief comment explaining why it is retained,
or flag it for the developer's attention.
