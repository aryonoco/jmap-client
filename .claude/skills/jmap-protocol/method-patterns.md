# JMAP Standard Methods

All 6 standard methods from RFC 8620 §5. Each method is generic over an entity
type (e.g. `Mailbox`, `Email`, `Thread`). The method name follows the pattern
`EntityType/methodName`.

## 1. /get (§5.1)

Fetch complete objects by ID.

**Request fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `accountId` | Id | yes | Account to query |
| `ids` | Id[] \| null | yes | IDs to fetch. `null` = fetch all. |
| `properties` | string[] \| null | no | Properties to return. `null` = all. |

**Response fields:**

| Field | Type | Description |
|-------|------|-------------|
| `accountId` | Id | Echo of request |
| `state` | string | Current server state for this type |
| `list` | object[] | Array of objects with requested properties |
| `notFound` | Id[] | IDs that were not found |

**Method errors:** `requestTooLarge` (too many IDs for server to process)

**Example:**
```json
["Mailbox/get", {
  "accountId": "A13824",
  "ids": ["MBX1", "MBX2"],
  "properties": ["name", "parentId", "role"]
}, "call-0"]
```

## 2. /changes (§5.2)

Fetch incremental changes since a known state.

**Request fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `accountId` | Id | yes | Account to query |
| `sinceState` | string | yes | State token from previous /get or /changes |
| `maxChanges` | UnsignedInt \| null | no | Max changes to return |

**Response fields:**

| Field | Type | Description |
|-------|------|-------------|
| `accountId` | Id | Echo of request |
| `oldState` | string | State at start (should match `sinceState`) |
| `newState` | string | Current state after changes |
| `hasMoreChanges` | boolean | If true, call /changes again with `newState` |
| `created` | Id[] | IDs of newly created objects |
| `updated` | Id[] | IDs of modified objects |
| `destroyed` | Id[] | IDs of deleted objects |

**Method errors:** `cannotCalculateChanges` (server cannot compute diff from given state)

**Example:**
```json
["Mailbox/changes", {
  "accountId": "A13824",
  "sinceState": "S1",
  "maxChanges": 100
}, "call-0"]
```

## 3. /set (§5.3)

Create, update, and destroy objects in a single call.

**Request fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `accountId` | Id | yes | Account to modify |
| `ifInState` | string \| null | no | Reject if server state differs (optimistic locking) |
| `create` | Map[CreationId, object] \| null | no | Objects to create, keyed by client-assigned CreationId |
| `update` | Map[Id, PatchObject] \| null | no | Partial updates keyed by server Id |
| `destroy` | Id[] \| null | no | IDs to delete |

**Response fields:**

| Field | Type | Description |
|-------|------|-------------|
| `accountId` | Id | Echo of request |
| `oldState` | string | State before changes |
| `newState` | string | State after changes |
| `created` | Map[CreationId, object] \| null | Created objects (server-assigned fields) |
| `updated` | Map[Id, object \| null] \| null | Updated objects (server-set fields, or null) |
| `destroyed` | Id[] \| null | Successfully destroyed IDs |
| `notCreated` | Map[CreationId, SetError] \| null | Per-item create errors |
| `notUpdated` | Map[Id, SetError] \| null | Per-item update errors |
| `notDestroyed` | Map[Id, SetError] \| null | Per-item destroy errors |

**PatchObject**: A JSON object where keys are property paths (e.g. `"name"`,
`"keywords/$seen"`) and values are the new values. A `null` value means
"remove this property" (for per-item or set-type properties).

**Back-references in create**: Use `#creationId` as an Id value to reference
an object being created in the same /set call.

**Method errors:** `stateMismatch` (ifInState does not match)

**Example:**
```json
["Mailbox/set", {
  "accountId": "A13824",
  "ifInState": "S1",
  "create": {
    "new-mbx-1": {"name": "Invoices", "parentId": "MBX1"}
  },
  "update": {
    "MBX2": {"name": "Renamed Folder"}
  },
  "destroy": ["MBX3"]
}, "call-0"]
```

## 4. /query (§5.5)

Search and sort objects, returning IDs with pagination.

**Request fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `accountId` | Id | yes | Account to query |
| `filter` | FilterOperator \| FilterCondition \| null | no | Filter criteria |
| `sort` | Comparator[] \| null | no | Sort order |
| `position` | Int | no | 0-based index to start from (default 0) |
| `anchor` | Id \| null | no | Start relative to this Id |
| `anchorOffset` | Int | no | Offset from anchor (default 0) |
| `limit` | UnsignedInt \| null | no | Max results to return |
| `calculateTotal` | boolean | no | Whether to compute total count (default false) |

**Response fields:**

| Field | Type | Description |
|-------|------|-------------|
| `accountId` | Id | Echo of request |
| `queryState` | string | State for this query (for /queryChanges) |
| `canCalculateChanges` | boolean | Whether /queryChanges is supported |
| `position` | UnsignedInt | 0-based position of first result |
| `ids` | Id[] | Matching IDs in sort order |
| `total` | UnsignedInt | Total matching count (if calculateTotal was true) |
| `limit` | UnsignedInt | Server-applied limit |

**FilterOperator**: `{"operator": "AND"|"OR"|"NOT", "conditions": [...]}`

**Comparator**: `{"property": "receivedAt", "isAscending": true, "collation": "..."}`

**Method errors:** `unsupportedSort`, `unsupportedFilter`, `anchorNotFound`

## 5. /queryChanges (§5.6)

Incremental sync of query results since a previous query state.

**Request fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `accountId` | Id | yes | Account to query |
| `filter` | FilterOperator \| FilterCondition \| null | no | Same filter as original query |
| `sort` | Comparator[] \| null | no | Same sort as original query |
| `sinceQueryState` | string | yes | queryState from previous /query or /queryChanges |
| `maxChanges` | UnsignedInt \| null | no | Max changes to return |
| `upToId` | Id \| null | no | Only report changes up to this Id |
| `calculateTotal` | boolean | no | Whether to compute total count |

**Response fields:**

| Field | Type | Description |
|-------|------|-------------|
| `accountId` | Id | Echo of request |
| `oldQueryState` | string | State at start |
| `newQueryState` | string | Current state |
| `removed` | Id[] | IDs no longer in the query results |
| `added` | AddedItem[] | Items added to results: `{"id": Id, "index": UnsignedInt}` |
| `total` | UnsignedInt | Total matching count (if requested) |

**Method errors:** `cannotCalculateChanges`, `tooManyChanges`

## 6. /copy (§5.4)

Copy objects from one account to another.

**Request fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `fromAccountId` | Id | yes | Source account |
| `accountId` | Id | yes | Destination account |
| `ifFromInState` | string \| null | no | Reject if source state differs |
| `ifInState` | string \| null | no | Reject if destination state differs |
| `create` | Map[CreationId, object] | yes | Objects to copy with any overrides |
| `onSuccessDestroyOriginal` | boolean | no | Destroy source after copy (move) |
| `destroyFromIfInState` | string \| null | no | State check for source destroy |

**Response fields:**

| Field | Type | Description |
|-------|------|-------------|
| `fromAccountId` | Id | Echo of request |
| `accountId` | Id | Echo of request |
| `oldState` | string | Destination state before |
| `newState` | string | Destination state after |
| `created` | Map[CreationId, object] \| null | Successfully copied objects |
| `notCreated` | Map[CreationId, SetError] \| null | Per-item copy errors |

**Method errors:** `fromAccountNotFound`, `fromAccountNotSupportedByMethod`,
`stateMismatch` (for either account)
