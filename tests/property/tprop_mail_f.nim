# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for Mail Part F — ``EmailUpdate`` /
## ``EmailUpdateSet`` / ``NonEmptyEmailImportMap`` / RFC 6901 escape /
## ``moveToMailbox`` equivalence.
##
## Defends F1 promises §3.2.3.1 (moveToMailbox ≡ setMailboxIds),
## §3.2.4 (initEmailUpdateSet totality), §3.2.5 (pointer escape
## bijectivity), §6.2 (NonEmptyEmailImportMap duplicate-key rejection),
## and §5.3-shaped wire patch (toJson(EmailUpdateSet) post-condition).
##
## Five groups per F2 §8.2.1:
## * B — ``initEmailUpdateSet`` totality (``DefaultTrials``)
## * C — ``initNonEmptyEmailImportMap`` duplicate-key invariant
##       (``DefaultTrials``)
## * D — RFC 6901 escape bijectivity over adversarial pairs
##       (``DefaultTrials``)
## * E — ``toJson(EmailUpdateSet)`` RFC 8620 §5.3 shape post-condition
##       (``DefaultTrials``)
## * F — ``moveToMailbox(id) ≡ setMailboxIds(@[id]-set)`` quantified
##       over the full ``Id`` charset (``QuickTrials``)

import std/json
import std/random
import std/sets
import std/strutils

import results

import jmap_client/internal/types/identifiers
import jmap_client/internal/mail/email
import jmap_client/internal/mail/email_update
import jmap_client/internal/mail/mailbox
import jmap_client/internal/mail/serde_email_update
import jmap_client/internal/types/primitives
import jmap_client/internal/serialisation/serde
import jmap_client/internal/serialisation/serde_diagnostics

import ../massertions
import ../mproperty
import ../mtestblock

# =============================================================================
# B — initEmailUpdateSet totality
# =============================================================================

testCase propTotalityInitEmailUpdateSet: # B
  ## Property: ``initEmailUpdateSet`` is total — for every
  ## ``openArray[EmailUpdate]`` the ctor returns ``Ok`` xor ``Err``,
  ## never panicking. ``Result[_, _]``'s type already encodes the
  ## Ok-xor-Err disjunction; the assertion below is operational —
  ## completion without panic constitutes the proof.
  ## Edge-bias: trial 0 = ``@[]`` (totality probe, F22 empty rejection);
  ## trials 1–4 = Class 1/2/3/mixed via ``genInvalidEmailUpdateSet``;
  ## trials ≥ 5 = random mix of valid (``genEmailUpdate``) and invalid
  ## (``genInvalidEmailUpdateSet``) shapes.
  checkProperty "initEmailUpdateSet totality on arbitrary openArray":
    var inputs: seq[EmailUpdate]
    if trial == 0:
      inputs = @[]
    elif trial < 5:
      inputs = rng.genInvalidEmailUpdateSet(trial)
    else:
      if rng.rand(0 .. 1) == 0:
        let size = rng.rand(0 .. 8)
        inputs = @[]
        for _ in 0 ..< size:
          inputs.add(rng.genEmailUpdate(-1))
      else:
        inputs = rng.genInvalidEmailUpdateSet(-1)
    lastInput = "trial=" & $trial & " len=" & $inputs.len
    let res = initEmailUpdateSet(inputs)
    doAssert res.isOk or res.isErr,
      "initEmailUpdateSet neither Ok nor Err — totality violated"

# =============================================================================
# C — initNonEmptyEmailImportMap duplicate-key invariant
# =============================================================================

func hasDuplicateCreationId(entries: openArray[(CreationId, EmailImportItem)]): bool =
  ## Precondition probe — returns true iff at least one ``CreationId``
  ## appears ≥ 2 times. The property's invariant is conditional on
  ## this holding; random trials that generate all-unique maps are
  ## vacuously true and skipped.
  var seen = initHashSet[CreationId]()
  for (cid, _) in entries:
    if cid in seen:
      return true
    seen.incl cid
  return false

testCase propNonEmptyEmailImportMapDuplicateKey: # C
  ## Property: if the input has ≥ 1 duplicated ``CreationId``, then
  ## ``initNonEmptyEmailImportMap`` rejects with ≥ 1 accumulated
  ## violation.
  ## Edge-bias: property trials 0..3 map to generator trials 1, 2, 3, 5
  ## (early/late/three-occ/cluster); property trials ≥ 4 pass ``-1``
  ## to the generator for random sampling, with a conditional skip if
  ## the random shape happens to be all-unique.
  checkProperty "initNonEmptyEmailImportMap rejects duplicate CreationId":
    let genTrial =
      case trial
      of 0: 1
      of 1: 2
      of 2: 3
      of 3: 5
      else: -1
    let inputs = rng.genNonEmptyEmailImportMap(genTrial)
    lastInput = "propTrial=" & $trial & " genTrial=" & $genTrial & " len=" & $inputs.len
    if inputs.hasDuplicateCreationId():
      let res = initNonEmptyEmailImportMap(inputs)
      assertErr res
      doAssert res.error.len >= 1,
        "expected ≥ 1 accumulated violation, got " & $res.error.len

# =============================================================================
# D — RFC 6901 escape bijectivity
# =============================================================================

testCase propEscapeBijectivity: # D
  ## Property: ``jsonPointerEscape`` is injective — distinct inputs
  ## produce distinct outputs, so the RFC 6901 wire form round-trips
  ## adversarial keyword pairs without collision.
  ## Edge-bias (mandatory): trial 0 = ``("a/b", "a~1b")``; trial 1 =
  ## ``("~", "~0")``; trial 2 = ``("/", "~1")``. These three pairs
  ## collide under a bugged swapped-replace-order escape; random
  ## sampling on the generator's non-``~``/``/`` charset exercises the
  ## property harness without meaningfully probing the escape.
  checkProperty "jsonPointerEscape bijectivity on adversarial keyword pairs":
    let (k1, k2) = rng.genKeywordEscapeAdversarialPair(trial)
    lastInput = "k1=" & k1 & " k2=" & k2
    if k1 != k2:
      let e1 = jsonPointerEscape(k1)
      let e2 = jsonPointerEscape(k2)
      doAssert e1 != e2,
        "escape collision on distinct inputs: k1=" & k1 & " k2=" & k2 & " escaped=" & e1

# =============================================================================
# E — toJson(EmailUpdateSet) RFC 8620 §5.3 shape post-condition
# =============================================================================

func isValidSection53Key(key: string): bool =
  ## RFC 8620 §5.3 wire-key shape check — matches the six toJson
  ## patterns emitted by ``serde_email_update.toJson(EmailUpdate)``.
  ## Full-replace: ``"keywords"`` or ``"mailboxIds"``. Sub-path:
  ## ``"keywords/<…>"`` or ``"mailboxIds/<…>"`` (sub-path must be
  ## non-empty after the ``/``).
  if key == "keywords" or key == "mailboxIds":
    return true
  if key.startsWith("keywords/") and key.len > len("keywords/"):
    return true
  if key.startsWith("mailboxIds/") and key.len > len("mailboxIds/"):
    return true
  false

func isValidSection53Value(key: string, value: JsonNode): bool =
  ## RFC 8620 §5.3 value-shape check paired with the key. Full-replace
  ## keys carry a ``JObject`` (the set); sub-path keys carry a
  ## ``JBool(true)`` (add) or ``JNull`` (remove).
  if key == "keywords" or key == "mailboxIds":
    return value.kind == JObject
  if key.startsWith("keywords/") or key.startsWith("mailboxIds/"):
    return value.kind == JBool or value.kind == JNull
  false

testCase propToJsonEmailUpdateSetShape: # E
  ## Property: ``toJson(EmailUpdateSet)`` produces a ``JObject`` whose
  ## key count equals the input's update count (all-distinct keys,
  ## preserving ``initEmailUpdateSet``'s Class 1 conflict rejection
  ## transitively through serde), and every (key, value) pair is
  ## RFC 8620 §5.3-shaped.
  ## Edge-bias: ``genEmailUpdateSet`` already biases trial 0 to a
  ## single-element set and trial 1 to a two-element disjoint set; this
  ## property inherits those via the generator's internal schedule.
  checkProperty "toJson(EmailUpdateSet) emits RFC 8620 §5.3-shaped pairs":
    let updateSet = rng.genEmailUpdateSet(trial)
    let inputLen = updateSet.toSeq.len
    lastInput = "trial=" & $trial & " len=" & $inputLen
    let node = updateSet.toJson()
    doAssert node.kind == JObject,
      "toJson(EmailUpdateSet) must return JObject, got " & $node.kind
    var keyCount = 0
    for key, value in node.pairs:
      inc keyCount
      doAssert key.isValidSection53Key(), "key violates RFC 8620 §5.3 shape: " & key
      doAssert key.isValidSection53Value(value),
        "value for key " & key & " violates §5.3 shape: kind=" & $value.kind
    doAssert keyCount == inputLen,
      "toJson key count " & $keyCount & " ≠ input update count " & $inputLen &
        " — serde collapsed distinct updates onto one key"

# =============================================================================
# F — moveToMailbox ≡ setMailboxIds over full Id charset
# =============================================================================

testCase propMoveToMailboxEquivSetMailboxIds: # F
  ## Property: ``moveToMailbox(id)`` and
  ## ``setMailboxIds(parseNonEmptyMailboxIdSet(@[id]).get())`` produce
  ## structurally-equal ``EmailUpdate`` values for every ``id`` in the
  ## full ``Id`` charset ``[A-Za-z0-9_-]``.
  ## F1 §3.2.3.1 promises this equivalence; the unit test at §8.3
  ## fixes a single ``id`` value, so this property widens the
  ## quantification to the full ``genValidIdStrict`` image.
  ## Tier: ``QuickTrials`` — cheap predicate (two ctors + one ``==``),
  ## ~0.5 ms/trial. Any divergence would surface within the first
  ## handful of trials.
  ## Implementation note: Nim's auto-``==`` for case objects uses a parallel
  ## ``fields`` iterator that rejects case-object equality at compile time,
  ## so structural equivalence is asserted field-wise. Both constructors
  ## produce ``kind == euSetMailboxIds``; equivalence then reduces to
  ## ``mailboxes`` equality via the borrowed ``==`` on
  ## ``NonEmptyMailboxIdSet``.
  checkPropertyN "moveToMailbox(id) ≡ setMailboxIds(@[id]-set)", QuickTrials:
    let raw = rng.genValidIdStrict(trial)
    let id = parseIdFromServer(raw).get()
    lastInput = "id=" & raw
    let viaMove = moveToMailbox(id)
    let viaSet = setMailboxIds(parseNonEmptyMailboxIdSet(@[id]).get())
    doAssert viaMove.kind == viaSet.kind,
      "kind divergence for id=" & raw & " moveKind=" & $viaMove.kind & " setKind=" &
        $viaSet.kind
    doAssert viaMove.kind == euSetMailboxIds,
      "moveToMailbox must produce euSetMailboxIds, got " & $viaMove.kind
    doAssert viaMove.mailboxes == viaSet.mailboxes, "mailboxes divergence for id=" & raw
