# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

discard """
  joinable: false
"""

## Property-based tests for Mail Part E ``EmailBlueprint`` — foundational
## totality / determinism / shape, adversarial totality / purity / harvest,
## second-audit hash-seed / bounded-rendering / re-parsability /
## depth-coupling / insertion-order.
##
## Defends R-decisions R1-1, R1-3, R3-1, R3-3, R4-1, R4-2, R4-3 per
## design §6.3.1–§6.3.4. 18 properties grouped A..D:
## * A (85-91) foundational: totality, determinism, shape, injectivity.
## * B (92-94) supplementary: bodyValues correspondence, header-name
##   normalisation idempotence, error-ordering determinism.
## * C (95-97) adversarial: totality, message purity, harvest correctness.
## * D (97a-97e) second-audit: cross-process structural equality (97a
##   reframed from byte-equality — see block docstring), bounded rendering,
##   round-trip re-parseability, depth-coupling, insertion-order
##   insensitivity.

import std/json
import std/os
import std/osproc
import std/random
import std/sets
import std/streams
import std/strtabs
import std/strutils
import std/tables

import results

import jmap_client/mail/body
import jmap_client/mail/email_blueprint
import jmap_client/mail/headers
import jmap_client/mail/serde_email_blueprint

import ../mproperty
import ../mfixtures

# =============================================================================
# Property 97a child-spawn sentinel
# =============================================================================
# When the parent spawns a child for the cross-process structural-equality
# property, the child re-derives the same blueprint from the trial seed
# embedded in the environment, emits its own ``$toJson`` render, and quits.
# The gate runs before any ``block prop*:`` so the child never enters the
# property matrix.

if existsEnv("JMAP_E_97A_CHILD"):
  let seed = parseInt(getEnv("JMAP_E_97A_SEED"))
  var childRng = initRand(seed)
  let bp = childRng.genEmailBlueprint(seed mod 3)
  echo $bp.toJson()
  quit(0)

# =============================================================================
# A — Foundational (85-91)
# =============================================================================

block propTotalityParseEmailBlueprint: # 85
  ## Uses ``QuickTrials`` because each trial walks an adversarial body tree
  ## (up to ``MaxBodyPartDepth``-nested parts) through every validator in
  ## ``parseEmailBlueprint`` — ~25 ms/trial in release. Totality is a
  ## smoke-level invariant: any failure is a crash and surfaces in the first
  ## handful of trials, so 200 runs is amply sufficient and the adversarial
  ## space is re-exercised by property 95 at ``DefaultTrials``.
  checkPropertyN "parseEmailBlueprint totality on adversarial argument shapes",
    QuickTrials:
    let args = rng.genAdversarialBlueprintArgs(trial)
    lastInput = args.digest
    discard parseEmailBlueprint(
      mailboxIds = args.mailboxIds,
      body = args.body,
      keywords = args.keywords,
      receivedAt = args.receivedAt,
      fromAddr = args.fromAddr,
      to = args.to,
      cc = args.cc,
      bcc = args.bcc,
      replyTo = args.replyTo,
      sender = args.sender,
      subject = args.subject,
      sentAt = args.sentAt,
      messageId = args.messageId,
      inReplyTo = args.inReplyTo,
      references = args.references,
      extraHeaders = args.extraHeaders,
    )

block propTotalityToJson: # 86
  checkProperty "toJson totality on random EmailBlueprint":
    let bp = rng.genEmailBlueprint(trial)
    lastInput = "trial " & $trial
    discard bp.toJson()

block propDeterminism: # 87
  ## Uses ``QuickTrials`` because each trial calls ``parseEmailBlueprint``
  ## *twice* on adversarial inputs — ~50 ms/trial in release. Purity is a
  ## structural invariant of the function (no global state, no RNG,
  ## iteration over insertion-ordered ``Table``); divergence would surface
  ## on any trial, and the error-ordering leg is re-exercised by property
  ## 94 (``propErrorOrderingDeterminism``) with the same validator stack.
  checkPropertyN "parseEmailBlueprint is a pure function of its arguments", QuickTrials:
    let args = rng.genAdversarialBlueprintArgs(trial)
    lastInput = args.digest
    let r1 = parseEmailBlueprint(
      mailboxIds = args.mailboxIds,
      body = args.body,
      subject = args.subject,
      extraHeaders = args.extraHeaders,
    )
    let r2 = parseEmailBlueprint(
      mailboxIds = args.mailboxIds,
      body = args.body,
      subject = args.subject,
      extraHeaders = args.extraHeaders,
    )
    doAssert r1.isOk == r2.isOk, "isOk diverged across identical-arg invocations"
    if r1.isOk:
      doAssert emailBlueprintEq(r1.unsafeValue, r2.unsafeValue),
        "Ok rail diverged across identical-arg invocations"
    else:
      doAssert emailBlueprintErrorsOrderedEq(r1.unsafeError, r2.unsafeError),
        "Err rail diverged (non-determinism in accumulated ordering)"

block propErrorAccumulation: # 88
  checkProperty "parseEmailBlueprint accumulates every triggered variant":
    let trig = rng.genBlueprintErrorTrigger(trial)
    lastInput = "expected=" & $trig.expected
    let res = parseEmailBlueprint(
      mailboxIds = trig.mailboxIds,
      body = trig.body,
      fromAddr = trig.fromAddr,
      subject = trig.subject,
      extraHeaders = trig.extraHeaders,
    )
    doAssert res.isErr, "trigger did not fire on Err rail"
    var seen: set[EmailBlueprintConstraint] = {}
    for e in res.unsafeError.items:
      seen.incl e.constraint
    let missing = trig.expected - seen
    doAssert missing == {},
      "expected variants " & $trig.expected & " missing " & $missing

block propToJsonShapeInvariants: # 89
  checkProperty "toJson emits only known keys and respects body XOR":
    let bp = rng.genEmailBlueprint(trial)
    lastInput = "trial " & $trial
    let obj = bp.toJson()
    doAssert obj.kind == JObject
    const knownKeys = [
      "mailboxIds", "keywords", "receivedAt", "from", "to", "cc", "bcc", "replyTo",
      "sender", "subject", "sentAt", "messageId", "inReplyTo", "references",
      "bodyStructure", "textBody", "htmlBody", "attachments", "bodyValues",
    ]
    for key, _ in obj.pairs:
      var ok = key.startsWith("header:")
      if not ok:
        for k in knownKeys:
          if k == key:
            ok = true
            break
      doAssert ok, "unexpected top-level JSON key: " & key
    let hasStructured = obj{"bodyStructure"} != nil
    let hasFlat =
      obj{"textBody"} != nil or obj{"htmlBody"} != nil or obj{"attachments"} != nil
    doAssert not (hasStructured and hasFlat),
      "bodyStructure XOR flat-list violated (both present)"

block propToJsonKeyOmission: # 90
  checkProperty "toJson omits keys for Opt.none / empty convenience fields":
    # Minimal blueprint — only ``mailboxIds`` is non-empty. Every other
    # convenience key should be absent from the rendered object.
    let ids = rng.genNonEmptyMailboxIdSet(trial = 0)
    let bp = parseEmailBlueprint(mailboxIds = ids).unsafeValue
    lastInput = "minimal blueprint"
    let obj = bp.toJson()
    const absentKeys = [
      "keywords", "receivedAt", "from", "to", "cc", "bcc", "replyTo", "sender",
      "subject", "sentAt", "messageId", "inReplyTo", "references", "bodyStructure",
      "textBody", "htmlBody", "attachments", "bodyValues",
    ]
    for k in absentKeys:
      doAssert obj{k} == nil, "expected key '" & k & "' absent on minimal blueprint"
    for key, _ in obj.pairs:
      doAssert not key.startsWith("header:"), "unexpected header:* on minimal blueprint"

block propToJsonInjectivity: # 91
  checkPropertyN "distinct blueprints produce distinct $toJson wire strings",
    ThoroughTrials:
    let pair = rng.genEmailBlueprintDelta(trial)
    lastInput = "trial " & $trial
    doAssert not emailBlueprintEq(pair.a, pair.b),
      "delta generator produced equal blueprints — precondition violated"
    let sa = $pair.a.toJson()
    let sb = $pair.b.toJson()
    doAssert sa != sb, "injectivity violated: distinct blueprints hash to same $toJson"

# =============================================================================
# B — Supplementary (92-94)
# =============================================================================

proc collectInlineLeafPartIds(part: BlueprintBodyPart): seq[PartId] =
  ## Walks ``part`` depth-first and returns every inline leaf's ``partId``.
  ## Blob-ref leaves contribute no entry; multipart containers recurse.
  ## Parallels ``collectInlineValues`` in ``email_blueprint.nim`` —
  ## property 92 uses this as the oracle against the real accessor.
  result = @[]
  if part.isMultipart:
    for c in part.subParts:
      result.add collectInlineLeafPartIds(c)
  elif part.source == bpsInline:
    result.add part.partId

proc harvestInlinePartIds(bp: EmailBlueprint): seq[PartId] =
  ## Dispatches ``collectInlineLeafPartIds`` across whichever
  ## ``EmailBodyKind`` the blueprint carries — single-entry for
  ## ``ebkStructured`` or over the three ``ebkFlat`` slots. Shared
  ## between properties 92 (bodyValues correspondence) and 97 (harvest
  ## correctness) because both need the same ground-truth walk.
  result = @[]
  case bp.body.kind
  of ebkStructured:
    result.add collectInlineLeafPartIds(bp.body.bodyStructure)
  of ebkFlat:
    for tb in bp.body.textBody:
      result.add collectInlineLeafPartIds(tb)
    for hb in bp.body.htmlBody:
      result.add collectInlineLeafPartIds(hb)
    for att in bp.body.attachments:
      result.add collectInlineLeafPartIds(att)

block propBodyValuesCorrespondence: # 92
  checkProperty "bodyValues keys are exactly the inline-leaf partIds":
    let bp = rng.genEmailBlueprint(trial)
    lastInput = "trial " & $trial
    let walked = harvestInlinePartIds(bp)
    # Table insert-last-wins on duplicate partIds (§7 E30 documented gap)
    # means the accessor's keyset is the walked keyset *de-duplicated*.
    var walkedSet = initHashSet[PartId]()
    for p in walked:
      walkedSet.incl p
    let accessor = bp.bodyValues
    var accessorSet = initHashSet[PartId]()
    for k in accessor.keys:
      accessorSet.incl k
    doAssert walkedSet == accessorSet,
      "bodyValues key-set diverged from inline-leaf walk"

block propHeaderNameNormalisationIdempotence: # 93
  checkProperty "blueprint header-name parsers fold case and round-trip":
    let raw = rng.genBlueprintEmailHeaderName(trial)
    lastInput = string(raw)
    let rawStr = string(raw)
    let lower = parseBlueprintEmailHeaderName(rawStr.toLowerAscii)
    let upper = parseBlueprintEmailHeaderName(rawStr.toUpperAscii)
    let mixed = parseBlueprintEmailHeaderName(rawStr)
    doAssert lower.isOk and upper.isOk and mixed.isOk,
      "case-folding variants should all parse since the generator produces valid names"
    doAssert lower.unsafeValue == upper.unsafeValue,
      "parser is not case-insensitive: lower != upper"
    doAssert lower.unsafeValue == mixed.unsafeValue,
      "parser is not case-insensitive: lower != mixed"
    # Round-trip: parsing the canonical form yields the canonical form.
    let canon = parseBlueprintEmailHeaderName(string(mixed.unsafeValue))
    doAssert canon.isOk and canon.unsafeValue == mixed.unsafeValue,
      "parser not idempotent under re-parse of canonical form"

block propErrorOrderingDeterminism: # 94
  checkProperty "error rail emission order is deterministic across runs":
    let trig = rng.genBlueprintErrorTrigger(trial)
    lastInput = "expected=" & $trig.expected
    let r1 = parseEmailBlueprint(
      mailboxIds = trig.mailboxIds,
      body = trig.body,
      fromAddr = trig.fromAddr,
      subject = trig.subject,
      extraHeaders = trig.extraHeaders,
    )
    let r2 = parseEmailBlueprint(
      mailboxIds = trig.mailboxIds,
      body = trig.body,
      fromAddr = trig.fromAddr,
      subject = trig.subject,
      extraHeaders = trig.extraHeaders,
    )
    doAssert r1.isErr and r2.isErr, "trigger did not fire twice"
    doAssert emailBlueprintErrorsOrderedEq(r1.unsafeError, r2.unsafeError),
      "error emission order is non-deterministic across two runs of the same inputs"

# =============================================================================
# C — Adversarial (95-97)
# =============================================================================

block propAdversarialTotality: # 95
  ## Uses ``DefaultTrials`` rather than ``ThoroughTrials`` because each
  ## trial runs the full ``parseEmailBlueprint`` + ``toJson`` pipeline on
  ## a ``genAdversarialBlueprintArgs`` payload — ~70 ms/trial in release
  ## when the generator emits a ``MaxBodyPartDepth``-nested body and a
  ## large ``extraHeaders`` map. At ``ThoroughTrials`` this block alone
  ## took ~137 s, eclipsing every other test in CI; 500 trials keeps the
  ## adversarial coverage broad while holding wall-clock under ~35 s.
  checkPropertyN "parseEmailBlueprint + toJson survive adversarial inputs at scale",
    DefaultTrials:
    let args = rng.genAdversarialBlueprintArgs(trial)
    lastInput = args.digest
    let res = parseEmailBlueprint(
      mailboxIds = args.mailboxIds,
      body = args.body,
      keywords = args.keywords,
      receivedAt = args.receivedAt,
      fromAddr = args.fromAddr,
      to = args.to,
      cc = args.cc,
      bcc = args.bcc,
      replyTo = args.replyTo,
      sender = args.sender,
      subject = args.subject,
      sentAt = args.sentAt,
      messageId = args.messageId,
      inReplyTo = args.inReplyTo,
      references = args.references,
      extraHeaders = args.extraHeaders,
    )
    if res.isOk:
      discard res.unsafeValue.toJson()

block propMessagePurity: # 96
  checkProperty "message(e) is byte-identical across two invocations":
    let e = rng.genEmailBlueprintError(trial)
    lastInput = "constraint=" & $e.constraint
    let m1 = message(e)
    let m2 = message(e)
    doAssert m1 == m2, "message() is not a pure function: two invocations diverged"

block propHarvestCorrectness: # 97
  checkProperty "toJson bodyValues matches the inline-leaf walk":
    let bp = rng.genEmailBlueprint(trial)
    lastInput = "trial " & $trial
    let obj = bp.toJson()
    let walked = harvestInlinePartIds(bp)
    var walkedSet = initHashSet[PartId]()
    for p in walked:
      walkedSet.incl p
    let bv = obj{"bodyValues"}
    if walkedSet.len == 0:
      doAssert bv == nil,
        "toJson emitted bodyValues despite no inline leaves in the tree"
    else:
      doAssert bv != nil and bv.kind == JObject,
        "toJson omitted bodyValues despite inline leaves present"
      var wireSet = initHashSet[PartId]()
      for k, _ in bv.pairs:
        wireSet.incl parsePartIdFromServer(k).unsafeValue
      doAssert wireSet == walkedSet,
        "bodyValues wire keys diverged from inline-leaf walk"

# =============================================================================
# D — Second-audit (97a-97e)
# =============================================================================

block propCrossProcessStructuralEquality: # 97a
  ## Reframed from design §6.3.4's byte-equality wording to structural
  ## equality (``parseJson(child) == parseJson(parent)``). The serialiser
  ## does not currently sort Table keys, so byte-equality across processes
  ## is not a contract jmap-client offers except for the single-entry
  ## fixture in scenario 102c. Consumers parse on receipt and compare
  ## structurally; that is the invariant this property pins.
  ##
  ## Uses ``CrossProcessTrials`` rather than ``ThoroughTrials`` because
  ## each trial forks a fresh Nim binary — subprocess spawn at ~100 ms
  ## dominates the trial cost by ~5×, so the budget is expressed in
  ## wall-clock seconds, not statistical breadth. Non-determinism in the
  ## serialiser would surface in the first handful of trials if it
  ## existed; 100 spawns is amply sufficient to catch it.
  checkPropertyN "cross-process structural equality of $toJson on random blueprints",
    CrossProcessTrials:
    var localRng = initRand(trial)
    let bp = localRng.genEmailBlueprint(trial mod 3)
    lastInput = "trial " & $trial
    let parentJson = $bp.toJson()
    let child = startProcess(
      getAppFilename(),
      args = @[],
      env = newStringTable({"JMAP_E_97A_CHILD": "1", "JMAP_E_97A_SEED": $trial}),
      options = {poStdErrToStdOut, poUsePath},
    )
    let childStdout = child.outputStream.readAll().strip()
    let exitCode = child.waitForExit()
    child.close()
    doAssert exitCode == 0,
      "97a child exited " & $exitCode & "; output:\n" & childStdout
    let parentObj = parseJson(parentJson)
    let childObj = parseJson(childStdout)
    doAssert parentObj == childObj,
      "cross-process structural mismatch\nparent: " & parentJson & "\nchild:  " &
        childStdout

block propMessageBoundedLength: # 97b
  ## ``message(e)`` composes at most six ``clipForMessage``-512 slots plus
  ## fixed-size scaffolding, so every rendering is well under 8 KiB even
  ## when every payload slot is a 64 KiB adversarial string.
  checkProperty "message(e) output stays under the 8 KiB budget":
    let e = rng.genEmailBlueprintError(trial)
    lastInput = "constraint=" & $e.constraint
    let m = message(e)
    doAssert m.len <= 8 * 1024, "message() exceeded 8 KiB budget: " & $m.len & " bytes"

block propToJsonReParseable: # 97c
  ## ``toJson`` output must be a JSON value ``std/json.parseJson`` accepts
  ## and re-serialises to the structurally-equal JsonNode. Guards against
  ## the emission of NaN, bare control bytes, or other non-JSON shapes.
  checkPropertyN "toJson output parses back to an equivalent JsonNode", ThoroughTrials:
    let bp = rng.genEmailBlueprint(trial)
    lastInput = "trial " & $trial
    let j1 = bp.toJson()
    let reparsed = parseJson($j1)
    doAssert reparsed == j1,
      "re-parse of toJson wire string did not round-trip to the original JsonNode"

block propBodyPartPathDepthCoupling: # 97d
  checkProperty "BodyPartPath stays bounded by MaxBodyPartDepth":
    let path = rng.genBodyPartPath(trial)
    lastInput = $path
    doAssert path.len <= MaxBodyPartDepth,
      "path length exceeds MaxBodyPartDepth: " & $path.len
    for idx in path.items:
      doAssert idx >= 0, "path contains negative index: " & $idx

block propEqInsertionOrderInsensitive: # 97e
  checkProperty "emailBlueprintEq ignores extraHeaders insertion order":
    let pair = rng.genBlueprintInsertionPermutation(trial)
    lastInput = "trial " & $trial
    doAssert emailBlueprintEq(pair.a, pair.permuted),
      "emailBlueprintEq reported inequality after extraHeaders Table was permuted"
