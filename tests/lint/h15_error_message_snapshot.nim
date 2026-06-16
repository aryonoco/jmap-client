# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## H15 error-message snapshot lock lint.
##
## Verifies that the canonical ``message()`` projection over the
## 43 representative error values matches the locked snapshot
## committed at ``tests/wire_contract/error-messages.txt`` exactly.
##
## Bidirectional:
##   - MISSING: a label is in the snapshot but the live computation
##     omits it (a sample dropped without going through freeze).
##   - EXTRA: a live label is not in the snapshot (a sample added
##     without freezing).
##   - CHANGED: the label exists in both but the projected message
##     differs.
##
## See ``docs/design/15-error-surface.md`` and A12 in
## ``docs/TODO/pre-1.0-api-alignment.md``.

import std/[os, strutils, tables]

import jmap_client
import jmap_client/internal/types/validation
import jmap_client/internal/types/errors
import jmap_client/internal/types/capabilities
import jmap_client/internal/types/identifiers
import jmap_client/internal/protocol/jmap_error

const
  RepoRoot = currentSourcePath().parentDir.parentDir.parentDir
  SnapshotRel = "tests/wire_contract/error-messages.txt"

proc samples(): seq[(string, string)] =
  ## Inline declaration of the 43 (label, projected message) pairs in the
  ## same order as ``scripts/freeze_error_messages.nim``. Keeping the two
  ## listings byte-aligned is the source-of-truth contract; the lint
  ## fails loudly when they drift.
  result = @[]
  result.add(
    (
      "validationError(\"AccountId\", \"contains control characters\", \"\")",
      validationError("AccountId", "contains control characters", "").message,
    )
  )
  result.add(
    (
      "validationError(\"Id\", \"length must be 1-255 octets\", \"\")",
      validationError("Id", "length must be 1-255 octets", "").message,
    )
  )
  result.add(
    (
      "validationError(\"UnsignedInt\", \"must be non-negative\", \"-1\")",
      validationError("UnsignedInt", "must be non-negative", "-1").message,
    )
  )
  result.add(
    (
      "validationError(\"Keyword\", \"contains forbidden character\", \"\")",
      validationError("Keyword", "contains forbidden character", "").message,
    )
  )
  result.add(
    (
      "validationError(\"Account\", \"name contains control characters\", \"bad\\x01name\")",
      validationError("Account", "name contains control characters", "bad\x01name").message,
    )
  )
  result.add(
    (
      "validationError(\"ServerCapability\", \"ckCore requires CoreCapabilities\", \"urn:ietf:params:jmap:core\")",
      validationError(
        "ServerCapability", "ckCore requires CoreCapabilities",
        "urn:ietf:params:jmap:core",
      ).message,
    )
  )
  result.add(
    (
      "validationError(\"AccountCapabilityEntry\", \"ckMail requires MailAccountCapabilities\", \"urn:ietf:params:jmap:mail\")",
      validationError(
        "AccountCapabilityEntry", "ckMail requires MailAccountCapabilities",
        "urn:ietf:params:jmap:mail",
      ).message,
    )
  )
  result.add(
    (
      "validationError(\"AccountCapabilityEntry\", \"ckSubmission requires SubmissionAccountCapabilities\", \"urn:ietf:params:jmap:submission\")",
      validationError(
        "AccountCapabilityEntry", "ckSubmission requires SubmissionAccountCapabilities",
        "urn:ietf:params:jmap:submission",
      ).message,
    )
  )
  result.add(
    (
      "validationError(\"MailAccountCapabilities\", \"maxMailboxesPerEmail must be >= 1\", \"0\")",
      validationError(
        "MailAccountCapabilities", "maxMailboxesPerEmail must be >= 1", "0"
      ).message,
    )
  )
  result.add(
    (
      "validationError(\"MailAccountCapabilities\", \"maxSizeMailboxName must be >= 100\", \"99\")",
      validationError(
        "MailAccountCapabilities", "maxSizeMailboxName must be >= 100", "99"
      ).message,
    )
  )
  result.add(
    (
      "transportError(tekNetwork, \"connection refused\")",
      transportError(tekNetwork, "connection refused").message,
    )
  )
  result.add(
    (
      "transportError(tekTls, \"certificate verify failed\")",
      transportError(tekTls, "certificate verify failed").message,
    )
  )
  result.add(
    (
      "transportError(tekTimeout, \"operation timed out\")",
      transportError(tekTimeout, "operation timed out").message,
    )
  )
  result.add(
    (
      "httpStatusError(503, \"Service Unavailable\")",
      httpStatusError(503, "Service Unavailable").message,
    )
  )
  result.add(
    (
      "requestError(\"urn:ietf:params:jmap:error:unknownCapability\", detail = Opt.some(\"missing urn:ietf:params:jmap:contacts\"))",
      requestError(
        "urn:ietf:params:jmap:error:unknownCapability",
        detail = Opt.some("missing urn:ietf:params:jmap:contacts"),
      ).message,
    )
  )
  result.add(
    (
      "requestError(\"urn:ietf:params:jmap:error:notJSON\", title = Opt.some(\"Not JSON\"))",
      requestError("urn:ietf:params:jmap:error:notJSON", title = Opt.some("Not JSON")).message,
    )
  )
  result.add(
    (
      "requestError(\"urn:ietf:params:jmap:error:notRequest\")",
      requestError("urn:ietf:params:jmap:error:notRequest").message,
    )
  )
  result.add(
    (
      "requestError(\"urn:ietf:params:jmap:error:limit\", title = Opt.some(\"Limit Exceeded\"), detail = Opt.some(\"maxCallsInRequest=500\"))",
      requestError(
        "urn:ietf:params:jmap:error:limit",
        title = Opt.some("Limit Exceeded"),
        detail = Opt.some("maxCallsInRequest=500"),
      ).message,
    )
  )
  result.add(
    (
      "requestError(\"urn:example:vendor:custom\")",
      requestError("urn:example:vendor:custom").message,
    )
  )
  result.add(
    (
      "methodError(\"serverFail\", Opt.some(\"internal error\"))",
      methodError("serverFail", Opt.some("internal error")).message,
    )
  )
  result.add(
    (
      "methodError(\"invalidArguments\", Opt.some(\"missing field 'accountId'\"))",
      methodError("invalidArguments", Opt.some("missing field 'accountId'")).message,
    )
  )
  result.add(
    (
      "methodError(\"accountNotFound\", Opt.some(\"no account 'A1'\"))",
      methodError("accountNotFound", Opt.some("no account 'A1'")).message,
    )
  )
  result.add(("methodError(\"forbidden\")", methodError("forbidden").message))
  result.add(("methodError(\"stateMismatch\")", methodError("stateMismatch").message))
  result.add(
    (
      "methodError(\"serverFail\", Opt.some(\"\"))",
      methodError("serverFail", Opt.some("")).message,
    )
  )
  result.add(
    (
      "setErrorInvalidProperties(\"invalidProperties\", @[\"from\", \"to\"])",
      setErrorInvalidProperties("invalidProperties", @["from", "to"]).message,
    )
  )
  result.add(
    (
      "setErrorAlreadyExists(\"alreadyExists\", parseId(\"abc123\").get())",
      setErrorAlreadyExists("alreadyExists", parseId("abc123").get()).message,
    )
  )
  result.add(
    (
      "setErrorBlobNotFound(\"blobNotFound\", @[parseBlobId(\"blob-1\").get(), parseBlobId(\"blob-2\").get()])",
      setErrorBlobNotFound(
        "blobNotFound", @[parseBlobId("blob-1").get(), parseBlobId("blob-2").get()]
      ).message,
    )
  )
  result.add(
    (
      "setErrorInvalidEmail(\"invalidEmail\", @[\"headers\", \"subject\"])",
      setErrorInvalidEmail("invalidEmail", @["headers", "subject"]).message,
    )
  )
  result.add(
    (
      "setErrorTooManyRecipients(\"tooManyRecipients\", parseUnsignedInt(100).get())",
      setErrorTooManyRecipients("tooManyRecipients", parseUnsignedInt(100'i64).get()).message,
    )
  )
  result.add(
    (
      "setErrorInvalidRecipients(\"invalidRecipients\", @[\"bad@\", \"@example\"])",
      setErrorInvalidRecipients("invalidRecipients", @["bad@", "@example"]).message,
    )
  )
  result.add(
    (
      "setErrorTooLarge(\"tooLarge\", Opt.some(parseUnsignedInt(1048576).get()))",
      setErrorTooLarge("tooLarge", Opt.some(parseUnsignedInt(1048576'i64).get())).message,
    )
  )
  result.add(
    (
      "setError(\"forbidden\", Opt.some(\"not allowed\"))",
      setError("forbidden", Opt.some("not allowed")).message,
    )
  )
  result.add(("setError(\"overQuota\")", setError("overQuota").message))
  result.add(
    (
      "jmapTransport(httpStatusError(503, \"Service Unavailable\"))",
      jmapTransport(httpStatusError(503, "Service Unavailable")).message,
    )
  )
  result.add(
    (
      "jmapRequest(requestError(\"urn:ietf:params:jmap:error:limit\", title = Opt.some(\"Limit Exceeded\")))",
      jmapRequest(
        requestError(
          "urn:ietf:params:jmap:error:limit", title = Opt.some("Limit Exceeded")
        )
      ).message,
    )
  )
  result.add(
    (
      "jmapValidation(validationError(\"AccountId\", \"contains control characters\", \"\"))",
      jmapValidation(validationError("AccountId", "contains control characters", "")).message,
    )
  )
  result.add(
    ("jmapSession(sessionFault(ckMail))", jmapSession(sessionFault(ckMail)).message)
  )
  result.add(
    (
      "jmapMisuse(initBuilderId(1'u64, 1'u64), initBuilderId(1'u64, 2'u64), parseMethodCallId(\"c0\").get())",
      jmapMisuse(
        initBuilderId(1'u64, 1'u64),
        initBuilderId(1'u64, 2'u64),
        parseMethodCallId("c0").get(),
      ).message,
    )
  )
  result.add(
    (
      "jmapProtocol(protocolMissingCall(parseMethodCallId(\"c0\").get()))",
      jmapProtocol(protocolMissingCall(parseMethodCallId("c0").get())).message,
    )
  )
  result.add(
    (
      "jmapProtocol(protocolMalformedError(parseMethodCallId(\"c0\").get()))",
      jmapProtocol(protocolMalformedError(parseMethodCallId("c0").get())).message,
    )
  )
  result.add(
    (
      "jmapMethod(methodFault(mnEmailGet, methodError(\"serverFail\", Opt.some(\"internal error\"))))",
      jmapMethod(
        methodFault(mnEmailGet, methodError("serverFail", Opt.some("internal error")))
      ).message,
    )
  )
  result.add(
    (
      "jmapSet(setFault(mnEmailSet, setError(\"overQuota\")))",
      jmapSet(setFault(mnEmailSet, setError("overQuota"))).message,
    )
  )

proc loadSnapshot(): seq[(string, string)] =
  ## Parses the committed snapshot. Each sample is a label line in
  ## brackets followed by an indented expected-message line.
  result = @[]
  let path = RepoRoot / SnapshotRel
  let content =
    try:
      readFile(path)
    except IOError, OSError:
      stderr.writeLine "H15: cannot read snapshot at " & path
      quit(2)
  var pending = ""
  for line in content.splitLines:
    if line.startsWith("[") and line.endsWith("]"):
      pending = line[1 ..^ 2]
    elif line.startsWith("  ") and pending.len > 0:
      result.add((pending, line[2 ..^ 1]))
      pending = ""

proc diffPairs(
    snapshotPairs, livePairs: seq[(string, string)]
): tuple[
  missing, extra: seq[string], changed: seq[tuple[label, expected, actual: string]]
] =
  ## Computes the three-way diff between snapshot and live samples.
  ## Returns missing labels (snapshot but not live), extra labels (live
  ## but not snapshot), and changed pairs (both, but messages differ).
  result = (
    missing: newSeq[string](),
    extra: newSeq[string](),
    changed: newSeq[tuple[label, expected, actual: string]](),
  )
  var snapshotMap = initTable[string, string]()
  for (k, v) in snapshotPairs:
    snapshotMap[k] = v
  var liveMap = initTable[string, string]()
  for (k, v) in livePairs:
    liveMap[k] = v
  for (label, expected) in snapshotPairs:
    if not liveMap.hasKey(label):
      result.missing.add label
    elif liveMap[label] != expected:
      result.changed.add (label, expected, liveMap[label])
  for (label, _) in livePairs:
    if not snapshotMap.hasKey(label):
      result.extra.add label

proc reportDivergence(
    missing, extra: seq[string], changed: seq[tuple[label, expected, actual: string]]
) =
  ## Emits the three divergence kinds to stderr with their labels and
  ## the standard ``just freeze-error-messages`` fix-it pointer.
  if missing.len > 0:
    stderr.writeLine "H15: MISSING from live (in snapshot, no backing sample):"
    for p in missing:
      stderr.writeLine "  " & p
  if extra.len > 0:
    stderr.writeLine "H15: EXTRA in live (sample emitted, not in snapshot):"
    for p in extra:
      stderr.writeLine "  " & p
  if changed.len > 0:
    stderr.writeLine "H15: CHANGED message projection:"
    for c in changed:
      stderr.writeLine "  " & c.label
      stderr.writeLine "    expected: " & c.expected
      stderr.writeLine "    actual:   " & c.actual
  stderr.writeLine ""
  stderr.writeLine "If this is an intentional message-format change:"
  stderr.writeLine "  1. just freeze-error-messages"
  stderr.writeLine "  2. review the diff"
  stderr.writeLine "  3. tag the PR [ERR-MSG-CHANGE]"
  stderr.writeLine ""
  stderr.writeLine "See A12 in docs/TODO/pre-1.0-api-alignment.md."

proc main() =
  ## Entry point: loads the snapshot, computes live samples, diffs them,
  ## and exits non-zero on any divergence.
  let snapshotPairs = loadSnapshot()
  let livePairs = samples()
  let diff = diffPairs(snapshotPairs, livePairs)
  if diff.missing.len == 0 and diff.extra.len == 0 and diff.changed.len == 0:
    echo "H15 error-message snapshot: ",
      snapshotPairs.len, " samples match committed snapshot"
    return
  reportDivergence(diff.missing, diff.extra, diff.changed)
  quit(1)

when isMainModule:
  main()
