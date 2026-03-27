# JMAP Wire Format Reference

All JSON structures derived from RFC 8620 (JMAP Core).

## Data Types (RFC 8620 §1.2–1.4)

| Type | JSON | Constraints |
|------|------|-------------|
| `Id` | string | 1–255 chars, only `[A-Za-z0-9_-]` |
| `Int` | number | integer in range `[-(2^53-1), 2^53-1]` |
| `UnsignedInt` | number | integer in range `[0, 2^53-1]` |
| `Date` | string | UTC date `"2014-10-30T06:12:00Z"` (RFC 3339) |
| `UTCDate` | string | same as Date but always UTC |

## Session Object (§2)

Discovered via `GET /.well-known/jmap` or direct URL.

```json
{
  "capabilities": {
    "urn:ietf:params:jmap:core": {
      "maxSizeUpload": 50000000,
      "maxConcurrentUpload": 4,
      "maxSizeRequest": 10000000,
      "maxConcurrentRequests": 4,
      "maxCallsInRequest": 16,
      "maxObjectsInGet": 500,
      "maxObjectsInSet": 500,
      "collationAlgorithms": ["i;ascii-casemap", "i;ascii-numeric"]
    },
    "urn:ietf:params:jmap:mail": {}
  },
  "accounts": {
    "A13824": {
      "name": "john@example.com",
      "isPersonal": true,
      "isReadOnly": false,
      "accountCapabilities": {
        "urn:ietf:params:jmap:core": {},
        "urn:ietf:params:jmap:mail": {
          "maxMailboxesPerEmail": null,
          "maxMailboxDepth": 10
        }
      }
    }
  },
  "primaryAccounts": {
    "urn:ietf:params:jmap:core": "A13824",
    "urn:ietf:params:jmap:mail": "A13824"
  },
  "username": "john@example.com",
  "apiUrl": "https://jmap.example.com/api/",
  "downloadUrl": "https://jmap.example.com/download/{accountId}/{blobId}/{name}?accept={type}",
  "uploadUrl": "https://jmap.example.com/upload/{accountId}/",
  "eventSourceUrl": "https://jmap.example.com/eventsource/?types={types}&closeafter={closeafter}&ping={ping}",
  "state": "cyrus-12345"
}
```

Key fields:
- `capabilities` — server-level capabilities keyed by URI string
- `accounts` — keyed by AccountId, each with name, flags, per-account capabilities
- `primaryAccounts` — keyed by capability URI → AccountId
- `apiUrl` — POST requests here
- `downloadUrl`, `uploadUrl`, `eventSourceUrl` — RFC 6570 Level 1 URI templates
- `state` — changes when Session data changes

## Request Envelope (§3.3)

POST to `apiUrl` with `Content-Type: application/json`.

```json
{
  "using": [
    "urn:ietf:params:jmap:core",
    "urn:ietf:params:jmap:mail"
  ],
  "methodCalls": [
    ["Mailbox/get", {"accountId": "A13824", "ids": null}, "call-0"],
    ["Email/query", {"accountId": "A13824", "filter": {"inMailbox": "MBX1"}}, "call-1"]
  ],
  "createdIds": {}
}
```

- `using` — array of capability URI strings (required)
- `methodCalls` — array of Invocations (required)
- `createdIds` — optional map of CreationId → server Id (for back-references)

## Invocation Format (§3.2)

**3-element JSON ARRAY, NOT an object:**

```json
["methodName", {"arg1": "value1", "arg2": "value2"}, "methodCallId"]
```

- Element 0: method name string (e.g. `"Mailbox/get"`)
- Element 1: arguments object
- Element 2: method call ID string (client-assigned, unique within request)

## Response Envelope (§3.4)

```json
{
  "methodResponses": [
    ["Mailbox/get", {"accountId": "A13824", "state": "S1", "list": [...], "notFound": []}, "call-0"],
    ["Email/query", {"accountId": "A13824", "queryState": "Q1", "ids": [...], "position": 0, "total": 42}, "call-1"]
  ],
  "createdIds": {},
  "sessionState": "cyrus-12345"
}
```

- `methodResponses` — array of Invocations (same 3-element array format)
- `sessionState` — compare with Session.state to detect Session changes

## Result References (§3.7)

Allow one method call to reference the result of a previous call in the same
request. The argument name gets a `#` prefix:

```json
{
  "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
  "methodCalls": [
    ["Email/query", {"accountId": "A13824", "filter": {"inMailbox": "MBX1"}}, "call-0"],
    ["Email/get", {
      "accountId": "A13824",
      "#ids": {
        "resultOf": "call-0",
        "name": "Email/query",
        "path": "/ids"
      }
    }, "call-1"]
  ]
}
```

Reference object fields:
- `resultOf` — methodCallId of the source invocation
- `name` — method name of the source invocation (must match)
- `path` — JSON Pointer into the source result (RFC 6901), with `*` wildcard

Common path constants:
- `/ids` — from /query response
- `/list/*/id` — from /get response (all IDs in list)
- `/added/*/id` — from /queryChanges response
- `/created` — from /set response (map of CreationId → object)
- `/updated` — from /set response (map of Id → object or null)
- `/updatedProperties` — from /changes response

## Error Hierarchy

### Request-Level Errors (§3.6.1)

Returned instead of the entire response when the request itself is malformed.
HTTP status codes with JSON body:

| Type | HTTP | Description |
|------|------|-------------|
| `urn:ietf:params:jmap:error:unknownCapability` | 400 | `using` contains unrecognised URI |
| `urn:ietf:params:jmap:error:notJSON` | 400 | Request body is not valid JSON |
| `urn:ietf:params:jmap:error:notRequest` | 400 | JSON is valid but not a valid Request |
| `urn:ietf:params:jmap:error:limit` | 400 | Request exceeds a server limit |

```json
{
  "type": "urn:ietf:params:jmap:error:unknownCapability",
  "status": 400,
  "detail": "The capability 'urn:foo:bar' is not supported"
}
```

### Method-Level Errors (§3.6.2)

Returned as an invocation in `methodResponses` when a specific method call fails.
The method name is `"error"`:

```json
["error", {"type": "unknownMethod", "description": "No method 'Foo/bar'"}, "call-0"]
```

Common method error types:
- `unknownMethod` — method name not recognised
- `invalidArguments` — arguments are invalid
- `invalidResultReference` — result reference could not be resolved
- `forbidden` — no permission for this method
- `accountNotFound` — accountId does not exist
- `accountNotSupportedByMethod` — account does not support this data type
- `accountReadOnly` — account is read-only but modification requested
- `serverFail` — internal server error
- `serverUnavailable` — server temporarily unavailable
- `serverPartialFail` — some but not all changes applied
- `cannotCalculateChanges` — server cannot compute changes from given state

### Set-Level Errors (§5.3)

Per-item errors in `/set` responses. Each item that failed has an entry in
`notCreated`, `notUpdated`, or `notDestroyed`:

```json
{
  "notCreated": {
    "creationId1": {
      "type": "invalidProperties",
      "description": "The 'name' property is required",
      "properties": ["name"]
    }
  },
  "notDestroyed": {
    "MBX1": {
      "type": "mailboxHasChild",
      "description": "Cannot destroy mailbox with children"
    }
  }
}
```

Common set error types:
- `invalidProperties` — one or more properties are invalid (has `properties` array)
- `singleton` — only one object of this type may exist
- `notFound` — the Id does not exist
- `forbidden` — no permission
- `overQuota` — would exceed quota
- `alreadyExists` — conflicts with existing object (has `existingId`)
- `tooLarge` — object too large
- `rateLimit` — too many changes too quickly
- `stateMismatch` — `ifInState` does not match current state

## Capabilities

### Core (urn:ietf:params:jmap:core)

| Field | Type | Description |
|-------|------|-------------|
| `maxSizeUpload` | UnsignedInt | Max size of a single uploaded blob |
| `maxConcurrentUpload` | UnsignedInt | Max concurrent blob uploads |
| `maxSizeRequest` | UnsignedInt | Max size of a single API request |
| `maxConcurrentRequests` | UnsignedInt | Max concurrent API requests |
| `maxCallsInRequest` | UnsignedInt | Max method calls in a single request |
| `maxObjectsInGet` | UnsignedInt | Max IDs in a single /get call |
| `maxObjectsInSet` | UnsignedInt | Max objects in a single /set call |
| `collationAlgorithms` | string[] | Supported collation algorithms |

### Other Registered Capabilities

- `urn:ietf:params:jmap:mail` — RFC 8621 (Mailbox, Email, Thread, etc.)
- `urn:ietf:params:jmap:submission` — RFC 8621 (EmailSubmission)
- `urn:ietf:params:jmap:vacationresponse` — RFC 8621 (VacationResponse)
- `urn:ietf:params:jmap:websocket` — RFC 8887
- `urn:ietf:params:jmap:mdn` — RFC 9007
- `urn:ietf:params:jmap:smimeverify` — RFC 9219
- `urn:ietf:params:jmap:blob` — RFC 9404
- `urn:ietf:params:jmap:quota` — RFC 9425
