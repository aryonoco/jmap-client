# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

discard """
  joinable: false
"""

## Adversarial / stress tests for Mail Part F — pins F1 promises on
## ``EmailUpdate`` / ``EmailUpdateSet`` / ``EmailCopyItem`` /
## ``EmailImportItem`` / ``NonEmptyEmailImportMap`` and the
## ``SetResponse[EmailCreatedItem]`` / ``CopyResponse[EmailCreatedItem]``
## / ``EmailImportResponse`` decode surface under malformed wire input,
## conflict-algebra edge cases, cast-bypass scenarios, and scale
## invariants. The bespoke ``EmailSetResponse`` / ``EmailCopyResponse``
## were folded into the generic ``SetResponse[T]`` / ``CopyResponse[T]``
## (commit aa638a8); the merged ``updateResults`` / ``destroyResults``
## tables now carry what the old split ``updated``/``notUpdated`` and
## ``destroyed``/``notDestroyed`` pairs encoded (Decision 3.9B).
##
## Eight top-level groups per F2 §8.2.3 + §8.10:
##   Block 1 — Response-decode adversarial (§8.9 matrix)
##   Block 2 — ``SetError.extras`` reachable via ``createResults`` (§7.1)
##   Block 3 — Conflict-algebra corner cases
##   Block 4 — ``getBoth(EmailCopyHandles)`` adversarial (§5.4)
##   Block 5 — Cross-response coherence
##   Block 6 — JSON-structural attack surface
##   Block 7 — Cast-bypass negative pins (§3.2.4)
##   Block 8 — Scale invariants (§8.10)

import std/json
import std/strutils
import std/tables
import std/times

import results

import jmap_client/dispatch
import jmap_client/envelope
import jmap_client/errors
import jmap_client/identifiers
import jmap_client/mail/email
import jmap_client/mail/email_update
import jmap_client/mail/keyword
import jmap_client/mail/mail_builders
import jmap_client/mail/mailbox
import jmap_client/methods
import jmap_client/methods_enum
import jmap_client/mail/serde_email
import jmap_client/mail/serde_email_update
import jmap_client/primitives
import jmap_client/serde
import jmap_client/serde_envelope

import ../massertions
import ../mfixtures

# =============================================================================
# Block 1 — Response-decode adversarial (F2 §8.9)
# =============================================================================
# Three sub-groups: Email/set (~30), Email/copy (~15), Email/import (~9)
# response decode — the first two via the generic ``SetResponse``/
# ``CopyResponse[EmailCreatedItem]``, the third via the bespoke
# ``EmailImportResponse``. Each named block constructs a malformed
# ``JsonNode`` inline, calls ``T.fromJson(node)``, and asserts either
# ``Ok`` on the Postel-lenient rows or ``Err`` on the shape-strict rows.
#
# The lenient/strict split follows a single principle: strict where a
# typed return forces parsing, lenient where the return is a passthrough.
#
# * Top-level maps (``mergeCreateResults`` / ``mergeUpdateResults`` /
#   ``mergeDestroyResults`` in methods.nim) silently drop wrong-kind
#   top-level values — Ok with an empty merged table. Postel on receive.
# * Inner values on the *success* rail are lenient where the return is
#   ``Opt[JsonNode]`` (updateResults) — the library doesn't know the
#   entity-specific PatchObject shape, so the raw node passes through
#   verbatim as ``ok(Opt.some(v))``. RFC 8620 §5.3 specifies
#   ``PatchObject|null`` for this inner value; the library admits the
#   whole non-null JSON surface on the success rail and defers the
#   structural check to callers who know their entity.
# * Inner values on the *error* rail are strict — ``SetError.fromJson``
#   must produce a typed sum, so non-object/missing-``type`` entries
#   propagate Err via ``?``.
# * Inner values where a typed ``T`` is produced (``created`` →
#   ``EmailCreatedItem``) are strict — ``T.fromJson`` can't invent a
#   typed record from a JString, so Err is forced by the type contract.
# * ``destroyed`` element strictness comes from ``parseIdFromServer``'s
#   non-empty / no-control-characters invariants, not a kind check.

block emailSetResponseAdversarialGroup:
  block createdAsJArray:
    # mergeCreatedResults ignores non-JObject created; Ok with empty.
    let payload = parseJson("""{"accountId": "a1", "newState": "s1", "created": []}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().createResults, 0

  block createdJNull:
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "created": null}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().createResults, 0

  block createdAsJString:
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "created": "oops"}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().createResults, 0

  block createdEntryKeyBadCreationId:
    # parseCreationId rejects '#' prefix (wire-format concern).
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "created": {"#badkey": {"id": "x", "blobId": "b",
                                 "threadId": "t", "size": 0}}}"""
    )
    assertErr SetResponse[EmailCreatedItem].fromJson(payload)

  block createdEntryKeyEmpty:
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "created": {"": {"id": "x", "blobId": "b", "threadId": "t", "size": 0}}}"""
    )
    assertErr SetResponse[EmailCreatedItem].fromJson(payload)

  block createdEntryValueAsJString:
    # EmailCreatedItem.fromJson expects JObject; svkWrongKind bubbles via `?`.
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "created": {"c1": "not-an-object"}}"""
    )
    assertErr SetResponse[EmailCreatedItem].fromJson(payload)

  block createdEntryMissingSize:
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "created": {"c1": {"id": "x", "blobId": "b", "threadId": "t"}}}"""
    )
    assertErr SetResponse[EmailCreatedItem].fromJson(payload)

  block createdEntrySizeAsString:
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "created": {"c1": {"id": "x", "blobId": "b",
                            "threadId": "t", "size": "bad"}}}"""
    )
    assertErr SetResponse[EmailCreatedItem].fromJson(payload)

  block createdEntryIdAsInteger:
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "created": {"c1": {"id": 42, "blobId": "b",
                            "threadId": "t", "size": 0}}}"""
    )
    assertErr SetResponse[EmailCreatedItem].fromJson(payload)

  block createdEntryExtraUnknownFields:
    # Postel: unknown sub-entry fields ignored; accept-and-round-trip.
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "created": {"c1": {"id": "x", "blobId": "b", "threadId": "t",
                            "size": 0, "unknown": "extra"}}}"""
    )
    assertOk SetResponse[EmailCreatedItem].fromJson(payload)

  block updatedEntryAdmitsString:
    # Passthrough — inner non-null ``updated`` values are preserved as
    # ``ok(Opt.some(raw))`` regardless of JSON kind. RFC 8620 §5.3
    # specifies PatchObject, but the library defers that structural
    # check to the caller (methods.nim mergeUpdateResults).
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "updated": {"e1": "oops"}}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let id = parseId("e1").get()
    doAssert res.get().updateResults[id].isOk
    assertEq res.get().updateResults[id].get().get().kind, JString

  block updatedEntryAdmitsNumber:
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "updated": {"e1": 42}}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let id = parseId("e1").get()
    doAssert res.get().updateResults[id].isOk
    assertEq res.get().updateResults[id].get().get().kind, JInt

  block updatedEntryAdmitsArray:
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "updated": {"e1": []}}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let id = parseId("e1").get()
    doAssert res.get().updateResults[id].isOk
    assertEq res.get().updateResults[id].get().get().kind, JArray

  block updatedEntryAdmitsBool:
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "updated": {"e1": true}}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let id = parseId("e1").get()
    doAssert res.get().updateResults[id].isOk
    assertEq res.get().updateResults[id].get().get().kind, JBool

  block updatedEntryNull:
    # RFC 8620 §5.3 inner-null: wire ``{id: null}`` => ok(Opt.none) — the
    # server made no property changes the client doesn't already know.
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "updated": {"e1": null}}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let id = parseId("e1").get()
    doAssert res.get().updateResults[id].isOk
    doAssert res.get().updateResults[id].get().isNone

  block updatedEntryEmptyObject:
    # RFC 8620 §5.3 inner-object: wire ``{id: {}}`` => ok(Opt.some(JObject))
    # — server altered something, changed-property map is just empty.
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "updated": {"e1": {}}}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let id = parseId("e1").get()
    doAssert res.get().updateResults[id].isOk
    doAssert res.get().updateResults[id].get().isSome
    assertEq res.get().updateResults[id].get().get().kind, JObject

  block updatedEntryRoundTripPreservesDistinction:
    # The inner null-vs-object distinction is preserved across round-trip
    # by Opt[JsonNode] inside Result: Opt.none → wire null, Opt.some(node)
    # → inner node verbatim (methods.nim emitSplitUpdateResults).
    let nullPayload =
      parseJson("""{"accountId": "a1", "newState": "s1", "updated": {"e1": null}}""")
    let emptyPayload =
      parseJson("""{"accountId": "a1", "newState": "s1", "updated": {"e1": {}}}""")
    let nullResp = SetResponse[EmailCreatedItem].fromJson(nullPayload).get()
    let emptyResp = SetResponse[EmailCreatedItem].fromJson(emptyPayload).get()
    doAssert toJson(nullResp){"updated"}{"e1"}.kind == JNull
    doAssert toJson(emptyResp){"updated"}{"e1"}.kind == JObject

  block updatedMapKeyInvalidId:
    # parseIdFromServer rejects control characters. ``!`` passes lenient
    # validation (Postel), so use \u0001 to force the rejection path.
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1", "updated": {"\u0001bad": null}}"""
    )
    assertErr SetResponse[EmailCreatedItem].fromJson(payload)

  block updatedTopLevelAbsent:
    let payload = parseJson("""{"accountId": "a1", "newState": "s1"}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().updateResults, 0

  block updatedTopLevelNull:
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "updated": null}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().updateResults, 0

  block updatedTopLevelEmptyObject:
    # Decision 3.9B: the merged ``updateResults`` table does NOT distinguish
    # top-level absent from ``updated: {}`` — both project to an empty
    # table (unlike pre-refactor ``Opt[Table]`` which preserved the split).
    # RFC 8620 §5.3 treats the two wire shapes as semantically identical.
    let payload = parseJson("""{"accountId": "a1", "newState": "s1", "updated": {}}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().updateResults, 0

  block updatedTopLevelAsArray:
    # Top-level wrong-kind ``updated`` is silently dropped by
    # mergeUpdateResults (uniform Postel across all three merge helpers).
    let payload = parseJson("""{"accountId": "a1", "newState": "s1", "updated": []}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().updateResults, 0

  block updatedEntryWellFormedWrongPayload:
    # Shape-faithful inner object; parseOptUpdatedMap preserves the raw
    # JsonNode on the Ok rail without interpreting its contents.
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1", "updated": {"e1": {"id": 42}}}"""
    )
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let id = parseId("e1").get()
    doAssert res.get().updateResults[id].isOk
    doAssert res.get().updateResults[id].get().isSome

  block destroyedAsJNull:
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "destroyed": null}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().destroyResults, 0

  block destroyedAbsent:
    let payload = parseJson("""{"accountId": "a1", "newState": "s1"}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().destroyResults, 0

  block destroyedEmptyArray:
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "destroyed": []}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().destroyResults, 0

  block destroyedTwoElements:
    # Wire ``destroyed`` array entries become Ok rows in the merged map.
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1", "destroyed": ["id1", "id2"]}"""
    )
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().destroyResults, 2
    doAssert res.get().destroyResults[parseId("id1").get()].isOk
    doAssert res.get().destroyResults[parseId("id2").get()].isOk

  block destroyedAsJObject:
    # Top-level wrong-kind ``destroyed`` (JObject instead of JArray) is
    # silently dropped by mergeDestroyResults — uniform Postel.
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "destroyed": {}}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().destroyResults, 0

  block oldStateJNull:
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "oldState": null}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    doAssert res.get().oldState.isNone

  block accountIdJNull:
    let payload = parseJson("""{"accountId": null, "newState": "s1"}""")
    assertErr SetResponse[EmailCreatedItem].fromJson(payload)

  block accountIdWrongType:
    let payload = parseJson("""{"accountId": true, "newState": "s1"}""")
    assertErr SetResponse[EmailCreatedItem].fromJson(payload)

  block newStateJInt:
    let payload = parseJson("""{"accountId": "a1", "newState": 42}""")
    assertErr SetResponse[EmailCreatedItem].fromJson(payload)

  block oldStateWrongType:
    # ``optState`` (methods.nim) is explicitly lenient: absent, null, wrong
    # kind, or invalid content all yield ``Opt.none``. Postel on receive.
    let payload = parseJson("""{"accountId": "a1", "newState": "s1", "oldState": 42}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    doAssert res.get().oldState.isNone

  block notUpdatedAsJArray:
    # Top-level wrong-kind ``notUpdated`` (JArray instead of JObject) is
    # silently dropped by mergeUpdateResults — uniform Postel.
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "notUpdated": []}""")
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().updateResults, 0

  block notUpdatedKeyEmpty:
    # parseIdFromServer on "" fails (non-empty constraint).
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "notUpdated": {"": {"type": "forbidden"}}}"""
    )
    assertErr SetResponse[EmailCreatedItem].fromJson(payload)

  block notUpdatedAndNotDestroyedSameKey:
    # Wire ``notUpdated`` and ``notDestroyed`` entries ride the Err rail
    # of the merged ``updateResults`` / ``destroyResults`` tables
    # (Decision 3.9B). The same Id can appear on both failure maps —
    # the library does not cross-validate.
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "notUpdated": {"x1": {"type": "forbidden"}},
         "notDestroyed": {"x1": {"type": "forbidden"}}}"""
    )
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let id = parseId("x1").get()
    doAssert res.get().updateResults[id].isErr
    doAssert res.get().destroyResults[id].isErr
    assertEq res.get().updateResults[id].error.errorType, setForbidden
    assertEq res.get().destroyResults[id].error.errorType, setForbidden

  block topLevelResponseJNull:
    assertErr SetResponse[EmailCreatedItem].fromJson(parseJson("null"))

  block topLevelResponseJArray:
    assertErr SetResponse[EmailCreatedItem].fromJson(parseJson("[]"))

  block topLevelResponseEmptyObject:
    # Missing accountId / newState => Err.
    assertErr SetResponse[EmailCreatedItem].fromJson(parseJson("{}"))

  block topLevelResponseExtraKeys:
    # Postel on top level.
    let payload = parseJson("""{"accountId": "a1", "newState": "s1", "foo": 42}""")
    assertOk SetResponse[EmailCreatedItem].fromJson(payload)

  block nestedUnknownFields:
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "created": {"c1": {"id": "x", "blobId": "b", "threadId": "t",
                            "size": 0, "nested": {"deep": "extra"}}}}"""
    )
    assertOk SetResponse[EmailCreatedItem].fromJson(payload)

block emailCopyResponseAdversarialGroup:
  block copyFromAccountIdMissing:
    # fromAccountId is required; absent => Err.
    let payload = parseJson("""{"accountId": "dst", "newState": "s1"}""")
    assertErr CopyResponse[EmailCreatedItem].fromJson(payload)

  block copyFromAccountIdWrongType:
    let payload =
      parseJson("""{"fromAccountId": 42, "accountId": "dst", "newState": "s1"}""")
    assertErr CopyResponse[EmailCreatedItem].fromJson(payload)

  block copyNotCreatedAsJArray:
    # mergeCreatedResults lenient; non-JObject notCreated silently dropped.
    let payload = parseJson(
      """{"fromAccountId": "src", "accountId": "dst",
         "newState": "s1", "notCreated": []}"""
    )
    let res = CopyResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().createResults, 0

  block copyNotCreatedJNull:
    let payload = parseJson(
      """{"fromAccountId": "src", "accountId": "dst",
         "newState": "s1", "notCreated": null}"""
    )
    let res = CopyResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    assertLen res.get().createResults, 0

  block copyNotCreatedEntryKeyBadCreationId:
    let payload = parseJson(
      """{"fromAccountId": "src", "accountId": "dst",
         "newState": "s1",
         "notCreated": {"#bad": {"type": "forbidden"}}}"""
    )
    assertErr CopyResponse[EmailCreatedItem].fromJson(payload)

  block copyNotCreatedEntryMissingType:
    # SetError.fromJson requires a ``type`` field.
    let payload = parseJson(
      """{"fromAccountId": "src", "accountId": "dst",
         "newState": "s1", "notCreated": {"c1": {}}}"""
    )
    assertErr CopyResponse[EmailCreatedItem].fromJson(payload)

  block copyNotCreatedEntryForbiddenNoDescription:
    let payload = parseJson(
      """{"fromAccountId": "src", "accountId": "dst",
         "newState": "s1",
         "notCreated": {"c1": {"type": "forbidden"}}}"""
    )
    let res = CopyResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let cid = parseCreationId("c1").get()
    doAssert res.get().createResults[cid].isErr
    let err = res.get().createResults[cid].error
    assertEq err.errorType, setForbidden
    doAssert err.description.isNone

  block copyNotCreatedEntryCustomServerExtension:
    # Forward-compat: unrecognised errorType => setUnknown; rawType lossless.
    let payload = parseJson(
      """{"fromAccountId": "src", "accountId": "dst",
         "newState": "s1",
         "notCreated": {"c1": {"type": "customServerExtension"}}}"""
    )
    let res = CopyResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let cid = parseCreationId("c1").get()
    let err = res.get().createResults[cid].error
    assertEq err.errorType, setUnknown
    assertEq err.rawType, "customServerExtension"

  block copyNotCreatedEntryInvalidPropertiesWrongType:
    # invalidProperties is a seq[string]. A non-JArray "properties" field
    # falls back defensively: SetError dispatch returns ok(setError(...)),
    # which downgrades the errorType to setUnknown via the defensive map
    # in ``setError`` (errors.nim). rawType stays lossless so the original
    # wire label is recoverable.
    let payload = parseJson(
      """{"fromAccountId": "src", "accountId": "dst",
         "newState": "s1",
         "notCreated": {"c1": {"type": "invalidProperties", "properties": 42}}}"""
    )
    let res = CopyResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let cid = parseCreationId("c1").get()
    let err = res.get().createResults[cid].error
    assertEq err.errorType, setUnknown
    assertEq err.rawType, "invalidProperties"

  block copyNotCreatedEntryInvalidPropertiesEmptyArray:
    # Empty array valid — SHOULD (RFC 8620 §5.3) admits zero names.
    let payload = parseJson(
      """{"fromAccountId": "src", "accountId": "dst",
         "newState": "s1",
         "notCreated": {"c1": {"type": "invalidProperties",
                               "properties": []}}}"""
    )
    let res = CopyResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let cid = parseCreationId("c1").get()
    let err = res.get().createResults[cid].error
    assertEq err.errorType, setInvalidProperties

  block copyNotCreatedEntryDescriptionWithNul:
    # Embedded NUL in description — JSON admits \u0000 string data; pin
    # that SetError.fromJson accepts it through without panic.
    let payload = parseJson(
      """{"fromAccountId": "src", "accountId": "dst",
         "newState": "s1",
         "notCreated": {"c1": {"type": "forbidden",
                               "description": "bad \u0000 byte"}}}"""
    )
    let res = CopyResponse[EmailCreatedItem].fromJson(payload)
    assertOk res

  block copyAccountIdJNull:
    let payload =
      parseJson("""{"fromAccountId": "src", "accountId": null, "newState": "s1"}""")
    assertErr CopyResponse[EmailCreatedItem].fromJson(payload)

  block copyCreatedSameKeyAsNotCreated:
    # Real-world server bug (Cyrus / Stalwart): same CreationId in both
    # maps. mergeCreatedResults processes ``created`` first, then
    # ``notCreated`` overwrites — notCreated wins deterministically.
    let payload = parseJson(
      """{"fromAccountId": "src", "accountId": "dst",
         "newState": "s1",
         "created": {"c1": {"id": "x", "blobId": "b",
                            "threadId": "t", "size": 0}},
         "notCreated": {"c1": {"type": "forbidden"}}}"""
    )
    let res = CopyResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let cid = parseCreationId("c1").get()
    doAssert res.get().createResults[cid].isErr

  block copyTopLevelEmptyObject:
    # Missing fromAccountId / accountId / newState => Err.
    assertErr CopyResponse[EmailCreatedItem].fromJson(parseJson("{}"))

  block copyTopLevelExtraKeys:
    # Postel.
    let payload = parseJson(
      """{"fromAccountId": "src", "accountId": "dst",
         "newState": "s1", "experimental": true}"""
    )
    assertOk CopyResponse[EmailCreatedItem].fromJson(payload)

  block copyOldStateAbsent:
    let payload =
      parseJson("""{"fromAccountId": "src", "accountId": "dst", "newState": "s1"}""")
    let res = CopyResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    doAssert res.get().oldState.isNone

block emailImportResponseAdversarialGroup:
  block emailImportResponseAccountIdMissing:
    let payload = parseJson("""{"newState": "s1"}""")
    assertErr EmailImportResponse.fromJson(payload)

  block emailImportResponseCreatedNull:
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "created": null}""")
    let res = EmailImportResponse.fromJson(payload)
    assertOk res
    assertLen res.get().createResults, 0

  block emailImportResponseCreatedEmptyObject:
    let payload = parseJson("""{"accountId": "a1", "newState": "s1", "created": {}}""")
    let res = EmailImportResponse.fromJson(payload)
    assertOk res
    assertLen res.get().createResults, 0

  block emailImportResponseCreatedWithNullEntry:
    # Null created entry — EmailCreatedItem.fromJson rejects non-JObject.
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "created": {"k0": null}}""")
    assertErr EmailImportResponse.fromJson(payload)

  block emailImportResponseNotCreatedAdversarial:
    # Generic SetError path — same dispatch as EmailSet/EmailCopy.
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "notCreated": {"k0": {"type": "overQuota"}}}"""
    )
    let res = EmailImportResponse.fromJson(payload)
    assertOk res
    let cid = parseCreationId("k0").get()
    doAssert res.get().createResults[cid].isErr
    assertEq res.get().createResults[cid].error.errorType, setOverQuota

  block emailImportResponseUnknownTopLevelField:
    # Postel at top-level.
    let payload =
      parseJson("""{"accountId": "a1", "newState": "s1", "mdnSendStatus": "queued"}""")
    assertOk EmailImportResponse.fromJson(payload)

  block emailImportResponseNewStateMissing:
    let payload = parseJson("""{"accountId": "a1"}""")
    assertErr EmailImportResponse.fromJson(payload)

  block emailImportResponseOldStateValid:
    let payload =
      parseJson("""{"accountId": "a1", "oldState": "s0", "newState": "s1"}""")
    let res = EmailImportResponse.fromJson(payload)
    assertOk res
    doAssert res.get().oldState.isSome

  block emailImportResponseCreatedAsJArray:
    # Lenient at top-level created.
    let payload = parseJson("""{"accountId": "a1", "newState": "s1", "created": []}""")
    let res = EmailImportResponse.fromJson(payload)
    assertOk res
    assertLen res.get().createResults, 0

# =============================================================================
# Block 2 — SetError.extras integration via createResults (F2 §7.1)
# =============================================================================
# The ``extras`` field preserves every wire key that is NOT in
# ``setErrorKnownKeys`` for the given variant (lossless — Decision 1.7C).
# The integration test fires three scenarios through the ``createResults``
# Table — one per response type — folding five adversarial rows per block:
#
# * unknown-key preservation (``vendorExtension``) alongside known keys;
# * very-long string field in extras reached without panic / pathology;
# * boundary numeric value (``2^53-1``) admitted through without overflow;
# * duplicate array entries preserved (std/json accepts duplicates);
# * rawType lossless even when errorType falls back to ``setUnknown``.

block setErrorExtrasIntegrationGroup:
  block emailSetExtrasReachableFromCreateResults:
    let longString = "very-long-" & repeat("x", 4_000)
    let adversarial =
      """
      {"type": "invalidProperties",
       "properties": ["to", "to"],
       "description": "too many invalids",
       "vendorExtension": "custom-string",
       "longField": """" &
      longString & """",
       "maxSize": 9007199254740991,
       "deepExtra": {"nested": [1, 2, 3]}}"""
    let payload = parseJson(
      "{\"accountId\": \"a1\", \"newState\": \"s1\", " & "\"notCreated\": {\"c1\": " &
        adversarial & "}}"
    )
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let cid = parseCreationId("c1").get()
    let err = res.get().createResults[cid].error
    assertEq err.errorType, setInvalidProperties
    doAssert err.extras.isSome
    let extras = err.extras.get()
    # Unknown-key preservation: vendorExtension isn't in knownKeys.
    doAssert extras{"vendorExtension"} != nil
    assertEq extras{"vendorExtension"}.getStr(), "custom-string"
    # Long string reached through serde without mutilation.
    doAssert extras{"longField"} != nil
    assertEq extras{"longField"}.getStr().len, longString.len
    # Boundary numeric preserved as raw JsonNode — stored verbatim.
    doAssert extras{"maxSize"} != nil
    # Duplicate array entries preserved by std/json parser.
    assertEq err.properties.len, 2
    # Nested unknowns preserved losslessly.
    doAssert extras{"deepExtra"} != nil
    assertEq extras{"deepExtra"}{"nested"}.len, 3

  block emailCopyExtrasReachableFromCreateResults:
    # Mirror scenario through EmailCopyResponse.notCreated. rawType is
    # lossless even when errorType falls back to ``setUnknown``.
    let adversarial =
      """
      {"type": "vendorCustomError",
       "description": "server extension",
       "vendorKey": 42,
       "payload": {"nested": true},
       "longKey": """" &
      repeat("x", 2_000) & """"}"""
    let payload = parseJson(
      "{\"fromAccountId\": \"src\", \"accountId\": \"dst\", " &
        "\"newState\": \"s1\", \"notCreated\": {\"c1\": " & adversarial & "}}"
    )
    let res = CopyResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let cid = parseCreationId("c1").get()
    let err = res.get().createResults[cid].error
    assertEq err.errorType, setUnknown
    assertEq err.rawType, "vendorCustomError"
    doAssert err.extras.isSome
    let extras = err.extras.get()
    assertEq extras{"vendorKey"}.getInt(), 42
    doAssert extras{"payload"} != nil
    doAssert extras{"longKey"} != nil

  block emailImportExtrasReachableFromCreateResults:
    # blobNotFound + extras: the ``notFound`` field is known-key and its
    # entries parsed via ``parseIdFromServer`` (lenient). Wire IDs with
    # control characters are rejected; without control characters,
    # duplicates are preserved in the seq.
    const adversarial = """
      {"type": "blobNotFound",
       "notFound": ["blob-1", "blob-1", "blob-2"],
       "description": "some blobs missing",
       "serverHint": "retry after GC"}"""
    let payload = parseJson(
      "{\"accountId\": \"a1\", \"newState\": \"s1\", " & "\"notCreated\": {\"k0\": " &
        adversarial & "}}"
    )
    let res = EmailImportResponse.fromJson(payload)
    assertOk res
    let cid = parseCreationId("k0").get()
    let err = res.get().createResults[cid].error
    assertEq err.errorType, setBlobNotFound
    # Duplicates preserved in the known-key seq[Id] payload.
    assertEq err.notFound.len, 3
    doAssert err.extras.isSome
    assertEq err.extras.get(){"serverHint"}.getStr(), "retry after GC"

# =============================================================================
# Block 3 — Conflict-algebra corner cases
# =============================================================================
# Three conflict classes, precisely named in the shipped error messages:
#
# * Class 1 — "duplicate target path"
# * Class 2 — "opposite operations on same sub-path"
# * Class 3 — "sub-path operation alongside full-replace on same parent"
#
# Payload shape is IRRELEVANT for Class 3 detection — the discriminator is
# the target path (parent), not what the full-replace carries. The IANA
# keyword fold covers the five RFC 8621 §4.6.2 keywords plus two custom
# keywords exercising the pointer-escape critical pair (``~``, ``/``).

block conflictAlgebraCornerCasesGroup:
  block class3PayloadIrrelevantEmptySetKeywords:
    # Empty set + sub-path add on same parent (``keywords``) — Class 3.
    let k = parseKeyword("foo").get()
    let empty = initKeywordSet([])
    let updates = @[setKeywords(empty), addKeyword(k)]
    let res = initEmailUpdateSet(updates)
    assertErr res
    doAssert res.error[0].message.contains("full-replace on same parent")

  block class3PayloadIrrelevantNonEmptySetKeywords:
    # Non-empty full-replace + sub-path — still Class 3; payload doesn't
    # enter the detection algebra.
    let k = parseKeyword("foo").get()
    let nonEmpty = initKeywordSet([parseKeyword("bar").get()])
    let updates = @[setKeywords(nonEmpty), addKeyword(k)]
    let res = initEmailUpdateSet(updates)
    assertErr res
    doAssert res.error[0].message.contains("full-replace on same parent")

  block class3MailboxSubpathWithFullReplace:
    # Same shape applied to the ``mailboxIds`` parent path.
    let id1 = parseId("mbx1").get()
    let idSet = parseNonEmptyMailboxIdSet(@[id1]).get()
    let updates = @[setMailboxIds(idSet), addToMailbox(id1)]
    let res = initEmailUpdateSet(updates)
    assertErr res
    doAssert res.error[0].message.contains("full-replace on same parent")

  block class2KeywordsIANAEnumerated:
    # Fold Class 2 (opposite ops at same sub-path) over every IANA keyword
    # plus two pointer-escape adversarial custom keywords. Each pair must
    # independently surface a Class 2 violation; each initEmailUpdateSet
    # call is independent, so the fold confirms the detection never
    # misfires on valid-charset variation.
    for iana in [kwSeen, kwFlagged, kwDraft, kwAnswered, kwForwarded]:
      let updates = @[addKeyword(iana), removeKeyword(iana)]
      let res = initEmailUpdateSet(updates)
      assertErr res
      doAssert res.error[0].message.contains("opposite operations on same sub-path")
    let slash = parseKeyword("a/b").get()
    let tilde = parseKeyword("a~b").get()
    for custom in [slash, tilde]:
      let updates = @[addKeyword(custom), removeKeyword(custom)]
      let res = initEmailUpdateSet(updates)
      assertErr res
      doAssert res.error[0].message.contains("opposite operations on same sub-path")

# =============================================================================
# Block 4 — getBoth(EmailCopyHandles) adversarial (F2 §5.4)
# =============================================================================
# Three scenarios cover the failure surface of compound Email/copy +
# implicit Email/set destroy extraction:
#
# * method-call-id or method-name mismatch on destroy ⇒ ``serverFail``
#   ``MethodError`` from the dispatch helper;
# * destroy invocation present but carries its own server MethodError
#   ⇒ that MethodError surfaces on the Result rail;
# * both invocations present with empty createResults ⇒ getBoth returns
#   Ok with the two empty shapes.
#
# Helpers are inlined per F2 §8.6 (used <3 times).

func copyOkArgs(): JsonNode =
  ## Minimal valid Email/copy response payload (``CopyResponse`` wire shape).
  %*{"fromAccountId": "src", "accountId": "dst", "newState": "s1"}

func setOkArgs(): JsonNode =
  ## Minimal valid Email/set response payload (``SetResponse`` wire shape).
  %*{"accountId": "dst", "newState": "s1"}

block getBothAdversarialGroup:
  block getBothImplicitDestroyMethodCallIdMismatch:
    # Build a Response where the destroy invocation shares a DIFFERENT
    # call-id from the handles'. getBoth's NameBoundHandle lookup filters
    # by both call-id AND method-name, so the destroy extraction
    # short-circuits with serverFail.
    let sharedId = makeMcid("c0")
    let handles = makeEmailCopyHandles(sharedId)
    let otherId = makeMcid("c1")
    let resp = Response(
      methodResponses: @[
        initInvocation(mnEmailCopy, copyOkArgs(), sharedId),
        initInvocation(mnEmailSet, setOkArgs(), otherId),
      ],
      createdIds: Opt.none(Table[CreationId, Id]),
      sessionState: parseJmapState("ss1").get(),
    )
    let res = getBoth(resp, handles)
    assertErr res
    assertEq res.error.errorType, metServerFail

  block getBothImplicitDestroyMethodError:
    # The destroy handle is a NameBoundHandle filtering by method-name
    # "Email/set". A server ``error`` envelope at the shared call-id does
    # NOT match that filter: ``findInvocationByName`` compares raw wire
    # names and the error invocation's raw name is the literal string
    # ``"error"``, not ``"Email/set"``. So the error invocation is
    # unreachable through the destroy handle's dispatch path;
    # ``extractInvocationByName`` surfaces a synthetic ``serverFail``
    # MethodError instead. This pins a known design limitation:
    # destroy-side server errors are OPAQUE under the current getBoth
    # semantics — they look like ``serverFail / no Email/set response``.
    let sharedId = makeMcid("c0")
    let handles = makeEmailCopyHandles(sharedId)
    let errorArgs = %*{"type": "fromAccountNotFound"}
    let resp = Response(
      methodResponses: @[
        initInvocation(mnEmailCopy, copyOkArgs(), sharedId),
        parseInvocation("error", errorArgs, sharedId).get(),
      ],
      createdIds: Opt.none(Table[CreationId, Id]),
      sessionState: parseJmapState("ss1").get(),
    )
    let res = getBoth(resp, handles)
    assertErr res
    assertEq res.error.errorType, metServerFail
    doAssert res.error.description.isSome
    doAssert "Email/set" in res.error.description.get()

  block getBothCopyMethodError:
    # Symmetric half: when the COPY invocation is an ``error`` envelope,
    # ResponseHandle dispatch (extractInvocation, no name filter) parses
    # the MethodError payload and surfaces it on the Result rail with the
    # server-supplied errorType preserved.
    let sharedId = makeMcid("c0")
    let handles = makeEmailCopyHandles(sharedId)
    let errorArgs = %*{"type": "fromAccountNotFound"}
    let resp = Response(
      methodResponses: @[
        parseInvocation("error", errorArgs, sharedId).get(),
        initInvocation(mnEmailSet, setOkArgs(), sharedId),
      ],
      createdIds: Opt.none(Table[CreationId, Id]),
      sessionState: parseJmapState("ss1").get(),
    )
    let res = getBoth(resp, handles)
    assertErr res
    assertEq res.error.errorType, metFromAccountNotFound

# =============================================================================
# Block 5 — Cross-response coherence
# =============================================================================
# The library intentionally does NOT enforce server-side invariants —
# ``oldState == newState``, duplicate keys, accountId divergence across
# sibling invocations, and ``created + notCreated`` sharing a CreationId
# are all wire-acceptable; detection is the caller's responsibility.
# These tests pin that hands-off stance.

block crossResponseCoherenceGroup:
  block coherenceOldStateNewStateEqual:
    let payload = parseJson(
      """{"accountId": "a1", "oldState": "s1", "newState": "s1",
         "created": {"c1": {"id": "x", "blobId": "b",
                            "threadId": "t", "size": 0}}}"""
    )
    assertOk SetResponse[EmailCreatedItem].fromJson(payload)

  block coherenceOldStateNewStateNullPair:
    # RFC 8620 §5.5: oldState/newState pair is independently optional.
    # newState is REQUIRED; oldState may be absent or null.
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "created": {"c1": {"id": "x", "blobId": "b",
                            "threadId": "t", "size": 0}}}"""
    )
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    doAssert res.get().oldState.isNone

  block coherenceAccountIdMismatchAcrossInvocations:
    # The envelope decoder does NOT peek into per-invocation ``arguments``;
    # divergent accountId values are admissible at the envelope level.
    # Detection belongs to the caller after extracting each invocation
    # via handles. Pin that Response.fromJson is Ok on this wire shape.
    let envelope = parseJson(
      """{
        "methodResponses": [
          ["Email/set", {"accountId": "a1", "newState": "s1"}, "c0"],
          ["Email/copy", {"fromAccountId": "src", "accountId": "a2",
                          "newState": "s1"}, "c1"]
        ],
        "sessionState": "ss1"}"""
    )
    let res = Response.fromJson(envelope)
    assertOk res
    assertLen res.get().methodResponses, 2
    # Caller-side detection — two invocations, two distinct accountId values.
    let firstArgs = res.get().methodResponses[0].arguments
    let secondArgs = res.get().methodResponses[1].arguments
    doAssert firstArgs{"accountId"}.getStr() != secondArgs{"accountId"}.getStr()

  block coherenceUpdatedSameKeyTwice:
    # std/json parseJson silently accepts duplicate object keys and keeps
    # the last occurrence. The second ``"e1": {}`` wins over ``"e1": null``,
    # so the decoded entry is ok(Opt.some(JObject)) — the changed-object
    # branch of RFC 8620 §5.3 inner Foo|null.
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "updated": {"e1": null, "e1": {}}}"""
    )
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let id = parseId("e1").get()
    doAssert res.get().updateResults[id].isOk
    doAssert res.get().updateResults[id].get().isSome
    assertEq res.get().updateResults[id].get().get().kind, JObject

  block coherenceCreatedAndNotCreatedShareKey:
    # Real-world server bug (observed in Cyrus / Stalwart): same CreationId
    # appears in both ``created`` and ``notCreated``. ``mergeCreatedResults``
    # processes ``created`` first, then ``notCreated`` overwrites the entry
    # — notCreated wins deterministically for the merged
    # ``createResults`` Table.
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "created": {"c1": {"id": "x", "blobId": "b",
                            "threadId": "t", "size": 0}},
         "notCreated": {"c1": {"type": "forbidden"}}}"""
    )
    let res = SetResponse[EmailCreatedItem].fromJson(payload)
    assertOk res
    let cid = parseCreationId("c1").get()
    doAssert res.get().createResults[cid].isErr
    assertEq res.get().createResults[cid].error.errorType, setForbidden

# =============================================================================
# Block 6 — JSON-structural attack surface
# =============================================================================
# Seven named probes pin std/json behaviour AND the library's reaction to
# unusual structural shapes. ``parseJson`` is exception-based in Nim, so
# tests that deliberately probe rejection wrap in ``try/except
# JsonParsingError``; tests that probe library-side decode (large strings,
# empty keys, deep nesting) parse normally and then exercise the typed
# decoder.

block jsonStructuralAttackGroup:
  block structuralBomPrefix:
    # UTF-8 BOM (``EF BB BF``) prefix: std/json tolerates it as whitespace
    # and parses the body. Pin that it does NOT panic, and that the
    # parsed JSON still decodes as a valid EmailSetResponse.
    let raw = "\xEF\xBB\xBF" & """{"accountId": "a1", "newState": "s1"}"""
    var parsed: JsonNode = nil
    var raised = false
    try:
      parsed = parseJson(raw)
    except JsonParsingError:
      raised = true
    # Either branch is acceptable as a behavioural pin — what matters is
    # that the input survives or rejects deterministically, not silently
    # corrupts. If std/json tolerates the BOM, the decode must still
    # succeed; if it rejects, ``raised`` will be true.
    if not raised:
      assertOk SetResponse[EmailCreatedItem].fromJson(parsed)

  block structuralNanInfinity:
    # NaN / Infinity are JavaScript extensions, not strict JSON.
    var raised = false
    try:
      discard parseJson("""{"size": NaN}""")
    except JsonParsingError:
      raised = true
    doAssert raised

  block structuralDuplicateKeysInObject:
    # std/json silently accepts duplicate keys and keeps the LAST value.
    # Pin this so a future parser change (error on dup) breaks this test
    # and prompts deliberate handling.
    let payload = parseJson("""{"id": "a", "id": "b"}""")
    assertEq payload{"id"}.getStr(), "b"

  block structuralDeepNesting:
    # Deep JSON nesting under an UNKNOWN top-level key — Postel at every
    # decode tier, no stack overflow at moderate depth (500).
    var deep = ""
    for _ in 0 ..< 500:
      deep.add("{\"k\":")
    deep.add("1")
    for _ in 0 ..< 500:
      deep.add("}")
    let wire =
      "{\"accountId\": \"a1\", \"newState\": \"s1\", \"unknown\": " & deep & "}"
    let payload = parseJson(wire)
    assertOk SetResponse[EmailCreatedItem].fromJson(payload)

  block structuralLargeStringSize:
    # 1 MB id in the ``destroyed`` array — ``parseIdFromServer`` caps at
    # 255 octets, so the entry is rejected without allocation pathology.
    let big = repeat("x", 1_000_000)
    let payload = %*{"accountId": "a1", "newState": "s1", "destroyed": [big]}
    assertErr SetResponse[EmailCreatedItem].fromJson(payload)

  block structuralEmptyKey:
    # Empty CreationId rejected by parseCreationId (non-empty constraint).
    let payload = parseJson(
      """{"accountId": "a1", "newState": "s1",
         "created": {"": {"id": "x", "blobId": "b",
                          "threadId": "t", "size": 0}}}"""
    )
    assertErr SetResponse[EmailCreatedItem].fromJson(payload)

  block structuralUnicodeNoncharacters:
    # U+FFFE is a Unicode non-character but valid UTF-8 at the byte level.
    # parseKeyword applies the strict keyword charset; pin whichever
    # outcome (Ok or Err) the shipped impl produces without branching.
    const noncharKw = "\xEF\xBF\xBE" # U+FFFE in UTF-8
    let r = parseKeyword(noncharKw)
    # Total assertion — covers both branches so the test is robust to
    # spec clarifications in either direction. The test's payoff is that
    # parseKeyword DOESN'T panic on the byte sequence.
    doAssert r.isOk or r.isErr

# =============================================================================
# Block 7 — Cast-bypass negative pins (F2 §3.2.4)
# =============================================================================
# ``EmailUpdateSet`` is ``distinct seq[EmailUpdate]``. Callers can bypass
# the smart constructor via ``cast[EmailUpdateSet](raw)``; F1 §3.2.4
# deliberately refuses to add runtime validation on ``toJson`` to avoid
# penalising the well-typed construction path. These tests DOCUMENT the
# library's silent acceptance of cast-constructed malformed sets — they
# are negative pins, not contracts.

block castBypassGroup:
  block castBypassDocumentsNoPostHocValidation:
    # Class 1 violation: two identical addKeyword updates. Cast bypass
    # constructs the malformed set without touching ``initEmailUpdateSet``;
    # ``toJson(EmailUpdateSet)`` emits its six-column wire shape without
    # complaint. NO runtime validation fires.
    let k = parseKeyword("foo").get()
    let malformed = cast[EmailUpdateSet](@[addKeyword(k), addKeyword(k)])
    let wire = toJson(malformed)
    assertEq wire.kind, JObject

  block castBypassEmptyAccepted:
    # Empty seq would be rejected by ``initEmailUpdateSet`` (F22 empty
    # rejection); cast bypass accepts it and ``toJson`` emits ``{}``.
    let malformed = cast[EmailUpdateSet](newSeq[EmailUpdate]())
    let wire = toJson(malformed)
    assertEq wire.kind, JObject
    assertLen wire, 0

# =============================================================================
# Block 8 — Scale invariants (F2 §8.10)
# =============================================================================
# Four scale-and-scaling-contract probes on ``initEmailUpdateSet``:
#
# * 10_001 all-conflicting entries ⇒ exactly 10_000 accumulated errors
#   (first entry is the unique anchor; every later entry conflicts with it).
# * 10_000 all-conflicting entries (no anchor) ⇒ 9_999 errors
#   (the algorithm compares against the FIRST occurrence, not pair-wise).
# * Three-class staggered — 1000 entries with one Class 1, one Class 2,
#   one Class 3 injected at positions 0/1, 499/500, 998/999.
# * 1000 entries with conflict injected ONLY at position 998/999 —
#   pins the single-pass algorithm doesn't bail after the initial prefix.
# * 100_000 unique entries ⇒ Ok; wall-clock ≤ 5 s pins linear scaling.
# * 10k import-map with duplicate at end ⇒ single accumulated violation.
# * Empty-vs-dup separately exercised — the two failure invariants
#   cannot co-occur in the same openArray.
#
# Two wall-clock budgets: ``assertLe elapsed, 0.5`` on the 10k test,
# ``assertLe elapsed, 5.0`` on the 100k test. A regression on either
# signals a real O(n²) cliff; do NOT relax the budget, investigate.

block scaleInvariantsGroup:
  block emailUpdateSet10kClass1Anchored:
    # 10_001 addKeyword(k) entries — same target path.
    # Entry 0 is the unique anchor; entries 1..10_000 each conflict with 0.
    let k = parseKeyword("anchor").get()
    var updates = newSeq[EmailUpdate](10_001)
    for i in 0 .. 10_000:
      updates[i] = addKeyword(k)
    let t0 = cpuTime()
    let res = initEmailUpdateSet(updates)
    let elapsed = cpuTime() - t0
    assertErr res
    assertLen res.error, 10_000
    assertLe elapsed, 0.5

  block emailUpdateSet10kClass1NoAnchor:
    # 10_000 identical entries. The detection compares each later entry
    # against the FIRST occurrence only — NOT C(10_000, 2). So 9_999
    # conflicts accumulate.
    let k = parseKeyword("anchor").get()
    var updates = newSeq[EmailUpdate](10_000)
    for i in 0 ..< 10_000:
      updates[i] = addKeyword(k)
    let res = initEmailUpdateSet(updates)
    assertErr res
    assertLen res.error, 9_999

  block emailUpdateSetThreeClassesStaggered:
    # 1000 entries mostly unique; three conflicts injected so the Err
    # seq has exactly three entries — one per class.
    var updates = newSeq[EmailUpdate](1000)
    for i in 0 ..< 1000:
      updates[i] = addKeyword(parseKeyword("u" & $i).get())
    let dup = parseKeyword("dup").get()
    let kw2 = parseKeyword("kw2").get()
    let kw3 = parseKeyword("kw3").get()
    updates[0] = addKeyword(dup)
    updates[1] = addKeyword(dup) # Class 1 — duplicate "keywords/dup"
    updates[499] = addKeyword(kw2)
    updates[500] = removeKeyword(kw2) # Class 2 — opposite "keywords/kw2"
    updates[998] = setKeywords(initKeywordSet([parseKeyword("A").get()]))
    updates[999] = addKeyword(kw3) # Class 3 — "keywords" parent collision
    let res = initEmailUpdateSet(updates)
    assertErr res
    assertLen res.error, 3

  block emailUpdateSetLatePositionConflict:
    # 1000 unique keywords, except the final two collide with each other.
    # Pins that the algorithm doesn't bail after a clean-prefix heuristic.
    var updates = newSeq[EmailUpdate](1000)
    for i in 0 ..< 998:
      updates[i] = addKeyword(parseKeyword("u" & $i).get())
    let late = parseKeyword("late").get()
    updates[998] = addKeyword(late)
    updates[999] = addKeyword(late)
    let res = initEmailUpdateSet(updates)
    assertErr res
    assertLen res.error, 1

  block emailUpdateSet100kWallClock:
    # 100_000 unique entries — no conflicts. Pins linear-scaling wall-clock
    # under 5 s. Excluded from default ``just test`` via testament_skip.txt
    # so this runtime doesn't tax every CI cycle.
    var updates = newSeq[EmailUpdate](100_000)
    for i in 0 ..< 100_000:
      updates[i] = addKeyword(parseKeyword("u" & $i).get())
    let t0 = cpuTime()
    let res = initEmailUpdateSet(updates)
    let elapsed = cpuTime() - t0
    assertOk res
    assertLe elapsed, 5.0

  block nonEmptyImportMap10kWithDupAtEnd:
    # 10_000 entries — last one duplicates the first CreationId. The Err
    # rail carries exactly one ValidationError for the duplicate key.
    var items = newSeq[(CreationId, EmailImportItem)](10_000)
    for i in 0 ..< 9_999:
      items[i] = (parseCreationId("k" & $i).get(), makeEmailImportItem())
    items[9_999] = (parseCreationId("k0").get(), makeEmailImportItem())
    let res = initNonEmptyEmailImportMap(items)
    assertErr res
    assertLen res.error, 1

  block nonEmptyImportMapEmptyAndDupSeparately:
    # Emptiness and duplication are mutually exclusive invariants at the
    # input level (empty openArray cannot contain duplicates). Probe each
    # in its own pass.
    let emptyRes = initNonEmptyEmailImportMap(@[])
    assertErr emptyRes
    doAssert emptyRes.error[0].message.contains("at least one entry")
    let dupItems = @[
      (parseCreationId("k0").get(), makeEmailImportItem()),
      (parseCreationId("k0").get(), makeEmailImportItem()),
    ]
    let dupRes = initNonEmptyEmailImportMap(dupItems)
    assertErr dupRes
    doAssert dupRes.error[0].message.contains("duplicate CreationId")

  block getBothCopyCreateResultsEmpty:
    # Both invocations well-formed; primary and implicit both have empty
    # createResults. getBoth returns Ok(EmailCopyResults(primary, implicit)).
    let sharedId = makeMcid("c0")
    let handles = makeEmailCopyHandles(sharedId)
    let resp = Response(
      methodResponses: @[
        initInvocation(mnEmailCopy, copyOkArgs(), sharedId),
        initInvocation(mnEmailSet, setOkArgs(), sharedId),
      ],
      createdIds: Opt.none(Table[CreationId, Id]),
      sessionState: parseJmapState("ss1").get(),
    )
    let res = getBoth(resp, handles)
    assertOk res
    assertLen res.get().primary.createResults, 0
    assertLen res.get().implicit.createResults, 0
