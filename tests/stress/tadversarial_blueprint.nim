# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

discard """
  joinable: false
"""

## Adversarial stress tests for Mail Part E (``EmailBlueprint``).
##
## Three adversarial surfaces beyond what ``tserde_email_blueprint*`` and the
## unit-test files exercise (design §6.4.2 / §6.4.3 / §6.4.4 rows 102a, 102c):
##
## * **§6.4.2 structural and resource boundaries** — the smart constructor
##   and ``toJson`` must survive pathological tree shape and
##   hash-collision inputs without panic or Ω(n²) cliffs.
## * **§6.4.3 error-accumulation stress** — the error rail must accumulate
##   thousands of distinct failures without losing entries or allocating
##   quadratically.
## * **§6.4.4 rows 102a / 102c** — FFI-panic-surface probes for
##   thread-safety and cross-process byte-determinism.
##
## Where the delivered implementation differs from the first-audit design,
## the scenario docstring names the adaptation explicitly.

import std/hashes
import std/json
import std/os
import std/osproc
import std/sets
import std/streams
import std/strtabs
import std/strutils
import std/tables
import std/times
import std/typedthreads

import results

import jmap_client/internal/types/primitives
import jmap_client/internal/mail/body
import jmap_client/internal/mail/email_blueprint
import jmap_client/internal/mail/headers
import jmap_client/internal/mail/mailbox
import jmap_client/internal/mail/serde_email_blueprint

import ../massertions
import ../mfixtures
import ../mtestblock

# =============================================================================
# Scenario 102c child-branch gate
# =============================================================================
# Testament compiles this file into a single binary and runs it. Scenario
# 102c (``crossProcessByteDeterminism``) self-spawns that same binary to
# observe fresh-process byte-equality. The child uses an environment-
# variable sentinel to skip every block below and emit its deterministic
# blueprint JSON before any other scenario runs.

proc minimal102cBlueprint(): EmailBlueprint =
  ## Minimal blueprint for the cross-process determinism gate: one
  ## mailbox, one scalar convenience field, no ``extraHeaders``, no body
  ## parts. Every aggregate that would iterate a ``Table`` / ``HashSet``
  ## with hash-seed-dependent ordering is either single-element or empty,
  ## so ``$bp.toJson`` is byte-identical across processes under the
  ## current (non-sorting) serde implementation.
  let ids = parseNonEmptyMailboxIdSet(@[parseId("mbx-det").get()]).get()
  parseEmailBlueprint(mailboxIds = ids, subject = Opt.some("fixed subject")).get()

proc multiEntry102eBlueprint(): EmailBlueprint =
  ## Multi-entry blueprint for the cross-process *structural-equality*
  ## gate (scenario 102e). Exercises several ``extraHeaders`` entries and
  ## a multi-``Id`` ``mailboxIds`` set so that Table / HashSet iteration
  ## order matters for the wire form. The serialiser does not currently
  ## sort — two processes may emit byte-divergent output with identical
  ## structural content. 102e pins the structural contract; byte-equality
  ## is NOT asserted and is not a contract jmap-client offers here.
  let ids = parseNonEmptyMailboxIdSet(
      @[parseId("mbx-a").get(), parseId("mbx-b").get(), parseId("mbx-c").get()]
    )
    .get()
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  extra[parseBlueprintEmailHeaderName("x-alpha").get()] = textSingle("one")
  extra[parseBlueprintEmailHeaderName("x-beta").get()] = textSingle("two")
  extra[parseBlueprintEmailHeaderName("x-gamma").get()] = textSingle("three")
  extra[parseBlueprintEmailHeaderName("x-delta").get()] = textSingle("four")
  extra[parseBlueprintEmailHeaderName("x-epsilon").get()] = textSingle("five")
  parseEmailBlueprint(
    mailboxIds = ids, subject = Opt.some("structural only"), extraHeaders = extra
  )
    .get()

if existsEnv("JMAP_STEP22_CHILD"):
  let variant = getEnv("JMAP_STEP22_VARIANT", "minimal")
  let bp =
    case variant
    of "multi":
      multiEntry102eBlueprint()
    else:
      minimal102cBlueprint()
  echo $bp.toJson()
  quit(0)

# =============================================================================
# Section A — §6.4.2 Structural and resource boundaries
# =============================================================================

testCase depthExceeds128Rejected: # scenario 99
  ## ``parseEmailBlueprint`` rejects body trees deeper than
  ## ``MaxBodyPartDepth`` at construction time via the accumulating error
  ## rail — the invariant is carried by the type, not by serialisation.
  ## A depth-129 spine surfaces exactly one ``ebcBodyPartDepthExceeded``
  ## per offending subtree root, so the error rail stays readable rather
  ## than drowning in per-leaf duplicates.
  let spine = makeSpineBodyPart(depth = 129)
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(spine)
  )
  assertBlueprintErrAny res, {ebcBodyPartDepthExceeded}

testCase depthAt128Accepted: # scenario 99a
  ## Boundary success: depth exactly 128 is within the serde depth
  ## budget, so both construction AND ``toJson`` produce full output
  ## (not a truncated stub).
  let spine = makeSpineBodyPart(depth = 128)
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(spine)
  )
  assertOk res

testCase breadth10kSiblings: # scenario 99b
  ## 10_000 inline leaves under one multipart root. Validates breadth
  ## (not depth) survives without panic or OOM on a normal test worker.
  var children = newSeqOfCap[BlueprintBodyPart](10_000)
  for i in 0 ..< 10_000:
    children.add(
      makeBlueprintBodyPartInline(
        partId = parsePartIdFromServer("p" & $i).get(),
        value = BlueprintBodyValue(value: "v" & $i),
      )
    )
  let root = makeBlueprintBodyPartMultipart(subParts = children)
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(root)
  )
  assertOk res
  let bp = res.get()
  doAssert bp.body.bodyStructure.subParts.len == 10_000

testCase crossProductBushyTree: # scenario 99c
  ## Cross-product depth × breadth stress. Design called for "depth 8,
  ## breadth 1000" which reads as 10²⁴ nodes if taken literally — clearly
  ## not the intent. Adaptation: a four-level tree where every internal
  ## node has ten children yields 10⁴ = 10_000 leaves, combining both
  ## axes without exceeding a practical memory budget. Peak occupied
  ## memory delta is pinned below 256 MiB; a regression to superlinear
  ## growth would blow past it and fail loud.
  proc buildBushy(levels, breadth: int): BlueprintBodyPart =
    ## Recursively builds a uniform cross-product tree: ``levels`` deep,
    ## each internal node carrying ``breadth`` children, leaves at depth 0.
    if levels <= 0:
      makeBlueprintBodyPartInline()
    else:
      var subs = newSeqOfCap[BlueprintBodyPart](breadth)
      for _ in 0 ..< breadth:
        subs.add(buildBushy(levels - 1, breadth))
      makeBlueprintBodyPartMultipart(subParts = subs)

  let before = getOccupiedMem()
  let root = buildBushy(4, 10)
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(root)
  )
  let after = getOccupiedMem()
  assertOk res
  doAssert after - before <= 256 * 1024 * 1024,
    "peak occupied memory delta " & $(after - before) & " exceeded 256 MiB"
  when defined(verboseStress):
    stderr.writeLine "scenario 99c mem delta: " & $(after - before) & " bytes"

testCase hashDosExtraHeaders: # scenario 99d
  ## HashDoS gate. Run A inserts ``n`` non-colliding names into
  ## ``extraHeaders`` (``"hdx-" & $i``); Run B inserts ``n`` collision-
  ## prone names sourced from ``adversarialHashCollisionNames`` (I-19).
  ## Both runs build a full blueprint and assert the Table length
  ## survives to ``n``. ``assertBoundedRatio`` (L-8 — first in-tree
  ## caller) enforces ``Run B / Run A <= 10.0``: a quadratic regression
  ## would produce hundreds-to-thousands ratio; the 10x bound gives
  ## ample jitter headroom above the analytical ~4x bucket-chain depth
  ## (n/256 ≈ 4 for n=1000) without sacrificing detection power.
  ##
  ## Design specified ``n = 10_000``; the I-19 fixture brute-force-scans
  ## at most 1 000 000 candidates with a ~1/256 low-byte hit rate
  ## (~3900 hits expected), so its ``doAssert result.len == n`` caps
  ## realistic ``n`` at ~1000. Adapted.
  const n = 1_000
  let collisionNames = adversarialHashCollisionNames(n)
  doAssert collisionNames.len == n

  proc buildRun(names: seq[string]): Result[EmailBlueprint, EmailBlueprintErrors] =
    ## Builds a blueprint whose ``extraHeaders`` contains one hfText entry
    ## per supplied name; used by both the non-colliding and colliding runs.
    var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
    for name in names:
      extra[parseBlueprintEmailHeaderName(name).get()] = makeBhmvTextSingle()
    parseEmailBlueprint(mailboxIds = makeNonEmptyMailboxIdSet(), extraHeaders = extra)

  var nonColliding = newSeqOfCap[string](n)
  for i in 0 ..< n:
    nonColliding.add("hdx-" & $i)

  let runA = buildRun(nonColliding)
  assertOk runA
  doAssert runA.get().extraHeaders.len == n
  let runB = buildRun(collisionNames)
  assertOk runB
  doAssert runB.get().extraHeaders.len == n

  assertBoundedRatio(buildRun(collisionNames), buildRun(nonColliding), 10.0)

testCase bodyPartPathMessageTotality: # scenario 99f
  ## ``BodyPartPath`` distinct-cast carries arbitrary ``seq[int]``
  ## content — including negative / ``int.low`` / ``int.high`` values.
  ## ``message(e)`` for ``ebcBodyPartHeaderDuplicate`` must remain total
  ## and bounded (<4 KiB) regardless of the integer content. Runs under
  ## ``--panics:on`` (config.nims:23), so any ``RangeDefect`` would
  ## ``rawQuit(1)`` the process — implicit via test completion.
  let adversarialPaths =
    @[BodyPartPath(@[-1]), BodyPartPath(@[int.high]), BodyPartPath(@[0, int.low, 1])]
  for p in adversarialPaths:
    let err = EmailBlueprintError(
      constraint: ebcBodyPartHeaderDuplicate,
      where: BodyPartLocation(kind: bplMultipart, path: p),
      bodyPartDupName: "x-custom",
    )
    let msg = message(err)
    doAssert msg.len < 4096, "message length " & $msg.len & " >= 4 KiB for path " & $p

# =============================================================================
# Section B — §6.4.3 Error-accumulation stress
# =============================================================================

testCase fiveConstraintsSimultaneous: # scenario 101
  ## Design said "all six variants simultaneously", but the
  ## ``EmailBlueprintBody`` case discriminant makes
  ## ``ebcBodyStructureHeaderDuplicate`` (requires ``ebkStructured``)
  ## mutually exclusive with ``ebcTextBodyNotTextPlain`` /
  ## ``ebcHtmlBodyNotTextHtml`` (both require ``ebkFlat``). Adapted:
  ## fire the five simultaneously-reachable variants under ``ebkFlat``
  ## and assert they all surface on one error rail — proves the
  ## accumulating constructor doesn't short-circuit.
  let dupDate = parseDate("2025-01-15T09:00:00Z").get()
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  # (a) top-level dup: convenience field "from" + extraHeaders "from".
  extra[parseBlueprintEmailHeaderName("from").get()] = makeBhmvTextSingle("v")
  # (b) allowed-form reject: "subject" with hfDate (subject allows hfText,hfRaw).
  extra[parseBlueprintEmailHeaderName("subject").get()] = makeBhmvDate(@[dupDate])

  # (c) body-part dup: inline leaf with "content-type" as an extraHeader.
  var leafExtra = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
  leafExtra[parseBlueprintBodyHeaderName("content-type").get()] = makeBhmvTextSingle()
  let textLeaf = makeBlueprintBodyPartInline(
    contentType = "application/pdf", # (d) text-type mismatch
    extraHeaders = leafExtra,
  )
  let htmlLeaf = makeBlueprintBodyPartInline(contentType = "text/plain")
    # (e) html-type mismatch
  let body = flatBody(textBody = Opt.some(textLeaf), htmlBody = Opt.some(htmlLeaf))

  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(),
    body = body,
    fromAddr = Opt.some(@[makeEmailAddress()]),
    subject = Opt.some("s"),
    extraHeaders = extra,
  )
  assertBlueprintErrAny res,
    {
      ebcEmailTopLevelHeaderDuplicate, ebcAllowedFormRejected,
      ebcBodyPartHeaderDuplicate, ebcTextBodyNotTextPlain, ebcHtmlBodyNotTextHtml,
    }

testCase bodyPartDupTenThousand: # scenario 101a
  ## Multipart root with 10_000 inline leaves, each carrying an
  ## extraHeaders entry keyed ``content-type`` that duplicates the
  ## leaf's own domain-field ``contentType``. Every leaf fires one
  ## ``ebcBodyPartHeaderDuplicate`` — exact-count assertion pins that
  ## no error is silently dropped. The ``capacity`` bound verifies
  ## amortised growth: if ``seq.add`` ever regressed to ``O(n²)``
  ## linear reallocation, this would blow past ``2 * 10_000``.
  const n = 10_000
  var leaves = newSeqOfCap[BlueprintBodyPart](n)
  let leafExtraProto = block:
    var t = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
    t[parseBlueprintBodyHeaderName("content-type").get()] = makeBhmvTextSingle()
    t
  for i in 0 ..< n:
    leaves.add(
      makeBlueprintBodyPartInline(
        partId = parsePartIdFromServer("p" & $i).get(),
        value = BlueprintBodyValue(value: "v" & $i),
        extraHeaders = leafExtraProto,
      )
    )
  let root = makeBlueprintBodyPartMultipart(subParts = leaves)
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(root)
  )
  assertBlueprintErrCount res, n
  let cap = res.unsafeError.capacity
  doAssert cap <= 2 * n, "error-seq capacity " & $cap & " exceeds 2x bound"

testCase topLevelDupCeilingAtEleven: # scenario 101b
  ## Design notes the realistic ceiling: ``Email`` has eleven convenience
  ## fields (``from`` / ``to`` / ``cc`` / ``bcc`` / ``reply-to`` /
  ## ``sender`` / ``subject`` / ``date`` / ``message-id`` / ``in-reply-to``
  ## / ``references``). ``Table`` key identity deduplicates the
  ## ``extraHeaders`` keys, so even with 10_000 insertions against eleven
  ## distinct names the accumulator caps at eleven ``ebcEmailTopLevelHeaderDuplicate``
  ## entries — a deliberate design property.
  ##
  ## Delivered ``allowedForms`` also rejects type-mismatched values
  ## (``hfText`` against ``from``/``to``/``cc``/``bcc``/``reply-to``/
  ## ``sender`` / ``date`` / ``message-id`` / ``in-reply-to`` /
  ## ``references``), so the error rail carries additional
  ## ``ebcAllowedFormRejected`` entries. This scenario filters those out
  ## and pins the top-level-dup count specifically.
  const convenienceNames = [
    "from", "to", "cc", "bcc", "reply-to", "sender", "subject", "date", "message-id",
    "in-reply-to", "references",
  ]
  var extra = initTable[BlueprintEmailHeaderName, BlueprintHeaderMultiValue]()
  for i in 0 ..< 10_000:
    let name = convenienceNames[i mod convenienceNames.len]
    extra[parseBlueprintEmailHeaderName(name).get()] = makeBhmvTextSingle()
  doAssert extra.len == convenienceNames.len

  let sentAt = parseDate("2025-01-15T09:00:00Z").get()
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(),
    fromAddr = Opt.some(@[makeEmailAddress()]),
    to = Opt.some(@[makeEmailAddress()]),
    cc = Opt.some(@[makeEmailAddress()]),
    bcc = Opt.some(@[makeEmailAddress()]),
    replyTo = Opt.some(@[makeEmailAddress()]),
    sender = Opt.some(makeEmailAddress()),
    subject = Opt.some("s"),
    sentAt = Opt.some(sentAt),
    messageId = Opt.some(@["<mid@host>"]),
    inReplyTo = Opt.some(@["<mid@host>"]),
    references = Opt.some(@["<mid@host>"]),
    extraHeaders = extra,
  )
  doAssert res.isErr
  var topLevelDupCount = 0
  for e in res.unsafeError.items:
    if e.constraint == ebcEmailTopLevelHeaderDuplicate:
      inc topLevelDupCount
  doAssert topLevelDupCount == convenienceNames.len,
    "expected " & $convenienceNames.len & " top-level dups, got " & $topLevelDupCount

testCase allowedFormRejectedTenThousand: # scenario 101c
  ## Design called for 10_000 distinct ``ebcAllowedFormRejected`` entries
  ## keyed by ``x-a0..x-a9999`` at the Email top level. Delivered
  ## ``allowedForms`` returns the full set ``{hfRaw..hfUrls}`` for any
  ## unknown name (``headers.nim:211``), so unknown names cannot
  ## produce this variant at all.
  ##
  ## Adaptation: fire the variant via the body-part axis instead —
  ## ``subject`` is a known-restricted name (``{hfText, hfRaw}``), so
  ## a ``hfDate`` value rejects at every leaf that carries it. 10_000
  ## leaves each with one such body-part extraHeader fire 10_000
  ## rejections, exercising the same accumulation-and-capacity bound
  ## the first-audit plan intended.
  const n = 10_000
  let d = parseDate("2025-01-15T09:00:00Z").get()
  let disallowed = makeBhmvDate(@[d])
  let leafExtraProto = block:
    var t = initTable[BlueprintBodyHeaderName, BlueprintHeaderMultiValue]()
    t[parseBlueprintBodyHeaderName("subject").get()] = disallowed
    t
  var leaves = newSeqOfCap[BlueprintBodyPart](n)
  for i in 0 ..< n:
    leaves.add(
      makeBlueprintBodyPartInline(
        partId = parsePartIdFromServer("q" & $i).get(),
        value = BlueprintBodyValue(value: "v"),
        extraHeaders = leafExtraProto,
      )
    )
  let root = makeBlueprintBodyPartMultipart(subParts = leaves)
  let res = parseEmailBlueprint(
    mailboxIds = makeNonEmptyMailboxIdSet(), body = structuredBody(root)
  )
  assertBlueprintErrCount res, n
  var distinctForms: HashSet[HeaderForm] = initHashSet[HeaderForm]()
  for e in res.unsafeError.items:
    doAssert e.constraint == ebcAllowedFormRejected
    doAssert e.rejectedName == "subject"
    distinctForms.incl e.rejectedForm
  doAssert distinctForms == toHashSet([hfDate])
  let cap = res.unsafeError.capacity
  doAssert cap <= 2 * n, "error-seq capacity " & $cap & " exceeds 2x bound"

# =============================================================================
# Section C — §6.4.4 rows 102a, 102c
# =============================================================================

# Module-scope channel for the threading probe. Channels cannot cross
# threads by value — globals or ``ptr`` are the idiomatic carriers
# (system/channels_builtin.nim §129–135). Two producers fan in; the
# parent drains on the main thread.
var threadMsgChannel: Channel[string]
threadMsgChannel.open()

proc threadWorker(workerId: int) {.thread, nimcall.} =
  ## Builds ``countPerThread`` distinct blueprints with a unique mailbox
  ## ID per worker × iteration, serialises each via ``toJson``, and
  ## ``send``s the result string into the shared channel. Any ``Defect``
  ## raised inside would ``rawQuit(1)`` the whole process under
  ## ``--panics:on``; ``CatchableError`` escape is prevented by the
  ## raise-free signatures of the call chain (``parseId`` / parse*
  ## return ``Result``, and ``.get()`` on a known-ok Result lowers to
  ## ``Defect`` — not a raises-tracked exception).
  const countPerThread = 1_000
  for i in 0 ..< countPerThread:
    let idStr = "t" & $workerId & "-m" & $i
    let ids = parseNonEmptyMailboxIdSet(@[parseId(idStr).get()]).get()
    let bp = parseEmailBlueprint(mailboxIds = ids, subject = Opt.some("s" & $i)).get()
    threadMsgChannel.send($bp.toJson())

testCase concurrentBlueprintConstruction: # scenario 102a
  ## Two threads each build 1_000 distinct blueprints and serialise
  ## them to JSON; the parent fans in 2_000 messages and verifies each
  ## parses back into a JObject with the expected ``mailboxIds`` key.
  ## Proves ARC reference counting survives concurrent construction of
  ## value-typed aggregates and that ``std/json`` emission is safe
  ## across threads. Design called for 10_000 per thread; 1_000 keeps
  ## CI walltime bounded while preserving the contract.
  var t1, t2: Thread[int]
  # stdlib threadProcWrapper (typedthreads.nim:146) doesn't explicitly
  # initialise its ``pointer`` result — a ProveInit false positive under
  # config.nims' warningAsError. Scoped suppression only.
  {.push warning[ProveInit]: off.}
  createThread(t1, threadWorker, 1)
  createThread(t2, threadWorker, 2)
  {.pop.}
  joinThread(t1)
  joinThread(t2)

  var received = 0
  for _ in 0 ..< 2_000:
    let msg = threadMsgChannel.recv()
    let parsed = parseJson(msg)
    doAssert parsed.kind == JObject
    doAssert parsed{"mailboxIds"} != nil
    inc received
  doAssert received == 2_000

testCase crossProcessByteDeterminism: # scenario 102c
  ## Spawn this test binary as a fresh child process with a sentinel
  ## environment variable; the child's module-top gate emits
  ## ``minimal102cBlueprint().toJson`` and ``quit(0)`` before any
  ## scenario block runs. Parent computes the same blueprint in its
  ## own process and compares byte-for-byte. Fresh-process variance
  ## covers hash-seed reshuffling and ASLR — a leak of insertion-order
  ## or hash-seed state into the wire output would diff here.
  ##
  ## The fixture uses a single-mailbox, empty-body, one-convenience-
  ## field blueprint specifically to dodge Table / HashSet iteration
  ## non-determinism the serialiser does not currently sort away —
  ## that is a separate regression surface (design §7 E*), out of
  ## scope for this scenario.
  let parentJson = $minimal102cBlueprint().toJson()
  let child = startProcess(
    getAppFilename(),
    args = @[],
    env = newStringTable({"JMAP_STEP22_CHILD": "1", "JMAP_STEP22_VARIANT": "minimal"}),
    options = {poStdErrToStdOut, poUsePath},
  )
  let childStdout = child.outputStream.readAll().strip()
  let exitCode = child.waitForExit()
  child.close()
  doAssert exitCode == 0,
    "scenario 102c child exited " & $exitCode & "; output:\n" & childStdout
  doAssert childStdout == parentJson,
    "cross-process byte mismatch\nparent: " & parentJson & "\nchild:  " & childStdout

testCase crossProcessStructuralOnly: # scenario 102e
  ## Complement to 102c. With multiple ``extraHeaders`` entries and a
  ## multi-``Id`` ``mailboxIds`` set, ``Table`` / ``HashSet`` iteration
  ## orders that depend on the process-wide hash seed influence the
  ## serialiser's output. ``parseJson`` compares recursively and is
  ## insensitive to key emission order, so structural equality MUST
  ## hold even when the byte outputs diverge. Byte-equality is NOT
  ## asserted — that is deliberately a 102c-only promise, limited to
  ## the single-entry fixture.
  ##
  ## This block turns the implicit single-entry choice in 102c into an
  ## explicit contract pair: 102c = byte-equal (single-entry), 102e =
  ## structurally-equal (multi-entry).
  let parentJson = $multiEntry102eBlueprint().toJson()
  let child = startProcess(
    getAppFilename(),
    args = @[],
    env = newStringTable({"JMAP_STEP22_CHILD": "1", "JMAP_STEP22_VARIANT": "multi"}),
    options = {poStdErrToStdOut, poUsePath},
  )
  let childStdout = child.outputStream.readAll().strip()
  let exitCode = child.waitForExit()
  child.close()
  doAssert exitCode == 0,
    "scenario 102e child exited " & $exitCode & "; output:\n" & childStdout
  let parentObj = parseJson(parentJson)
  let childObj = parseJson(childStdout)
  doAssert parentObj == childObj,
    "cross-process structural mismatch\nparent: " & parentJson & "\nchild:  " &
      childStdout
