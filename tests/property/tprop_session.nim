# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Property-based tests for Session and UriTemplate.

import std/random
import std/tables

import jmap_client/internal/types/capabilities
import jmap_client/internal/types/framework
import jmap_client/internal/types/identifiers
import jmap_client/internal/types/primitives
import jmap_client/internal/types/session
import jmap_client/internal/types/validation
import ../mfixtures
import ../mproperty
import ../mtestblock

# --- UriTemplate properties ---

testCase propUriTemplateTotality:
  checkProperty "parseUriTemplate never crashes on arbitrary string":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseUriTemplate(s)
testCase propUriTemplateMaliciousTotality:
  checkProperty "parseUriTemplate never crashes on malicious input":
    let s = genMaliciousString(rng, trial)
    lastInput = s
    discard parseUriTemplate(s)
testCase propUriTemplateNonEmpty:
  checkProperty "valid UriTemplate round-trips to non-empty string":
    let s = genValidUriTemplateParametric(rng)
    lastInput = s
    let tmpl = parseUriTemplate(s).get()
    doAssert ($tmpl).len > 0

testCase propUriTemplateRoundTrip:
  checkProperty "$(parseUriTemplate(s)) == s for valid s":
    let s = genValidUriTemplateParametric(rng)
    lastInput = s
    doAssert $(parseUriTemplate(s).get()) == s

testCase propHasVariablePresent:
  let tmpl = parseUriTemplate("https://example.com/{foo}/bar").get()
  doAssert hasVariable(tmpl, "foo") == true

testCase propHasVariableAbsent:
  let tmpl = parseUriTemplate("https://example.com/{bar}/baz").get()
  doAssert hasVariable(tmpl, "foo") == false

# --- Session properties ---

testCase propSessionCoreCapabilitiesTotal:
  checkPropertyN "coreCapabilities(validSession) never crashes", QuickTrials:
    let args = makeSessionArgs()
    let session = parseSession(
        args.capabilities, args.accounts, args.primaryAccounts, args.username,
        args.apiUrl, args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
      )
      .get()
    discard coreCapabilities(session)

testCase propSessionFindCoreCapability:
  let args = makeSessionArgs()
  let session = parseSession(
      args.capabilities, args.accounts, args.primaryAccounts, args.username,
      args.apiUrl, args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
    )
    .get()
  doAssert findCapability(session, ckCore).isSome

testCase propSessionPrimaryAccountUnknown:
  let args = makeSessionArgs()
  let session = parseSession(
      args.capabilities, args.accounts, args.primaryAccounts, args.username,
      args.apiUrl, args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
    )
    .get()
  doAssert primaryAccount(session, ckUnknown).isNone

# --- Session cross-consistency properties ---

testCase propSessionFindCapabilityAgreesWithByUri:
  checkPropertyN "propSessionFindCapabilityAgreesWithByUri", QuickTrials:
    ## For known kinds, findCapability and findCapabilityByUri agree.
    let args = makeSessionArgs()
    let session = parseSession(
        args.capabilities, args.accounts, args.primaryAccounts, args.username,
        args.apiUrl, args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
      )
      .get()
    for kind in CapabilityKind:
      if kind != ckUnknown:
        let byKind = session.findCapability(kind)
        let uri = capabilityUri(kind)
        if uri.isSome:
          let byUri = session.findCapabilityByUri(uri.get())
          doAssert byKind.isSome == byUri.isSome

testCase propUriTemplateEqImpliesHashEq:
  checkPropertyN "propUriTemplateEqImpliesHashEq", QuickTrials:
    let s = genValidUriTemplateParametric(rng)
    lastInput = s
    let a = parseUriTemplate(s).get()
    let b = parseUriTemplate(s).get()
    doAssert hash(a) == hash(b)

testCase propUriTemplateDoubleRoundTrip:
  checkPropertyN "propUriTemplateDoubleRoundTrip", QuickTrials:
    let s = genValidUriTemplateParametric(rng)
    lastInput = s
    let first = parseUriTemplate(s).get()
    let second = parseUriTemplate($first).get()
    doAssert first == second

# --- Session post-construction invariants ---

testCase propSessionPostConstructionInvariants:
  ## Verifies all five structural invariants guaranteed by parseSession.
  let session = parseSessionFromArgs(makeSessionArgs())
  doAssert findCapability(session, ckCore).isSome
  doAssert session.apiUrl.len > 0
  doAssert session.downloadUrl.hasVariable("accountId")
  doAssert session.downloadUrl.hasVariable("blobId")
  doAssert session.downloadUrl.hasVariable("type")
  doAssert session.downloadUrl.hasVariable("name")
  doAssert session.uploadUrl.hasVariable("accountId")
  doAssert session.eventSourceUrl.hasVariable("types")
  doAssert session.eventSourceUrl.hasVariable("closeafter")
  doAssert session.eventSourceUrl.hasVariable("ping")

# --- Totality tests for Session/Account methods ---

testCase propAccountFindCapabilityTotality:
  checkPropertyN "Account.findCapability never crashes", QuickTrials:
    let account = genValidAccount(rng)
    let kind =
      rng.oneOf([ckCore, ckMail, ckSubmission, ckContacts, ckCalendars, ckUnknown])
    lastInput = $kind
    discard account.findCapability(kind)

testCase propAccountFindCapabilityByUriTotality:
  checkPropertyN "Account.findCapabilityByUri never crashes", QuickTrials:
    let account = genValidAccount(rng)
    let uri = genArbitraryString(rng)
    lastInput = uri
    discard account.findCapabilityByUri(uri)

testCase propAccountHasCapabilityTotality:
  checkPropertyN "Account.hasCapability never crashes", QuickTrials:
    let account = genValidAccount(rng)
    let kind =
      rng.oneOf([ckCore, ckMail, ckSubmission, ckContacts, ckCalendars, ckUnknown])
    lastInput = $kind
    discard account.hasCapability(kind)

testCase propUriTemplateHasVariableTotality:
  checkPropertyN "UriTemplate.hasVariable never crashes", QuickTrials:
    let s = genValidUriTemplateParametric(rng)
    let tmpl = parseUriTemplate(s).get()
    let varName = genArbitraryString(rng)
    lastInput = varName
    discard tmpl.hasVariable(varName)

# --- Randomised session generation properties ---

testCase propSessionWithRandomCapabilities:
  checkPropertyN "parseSession with random capabilities succeeds", QuickTrials:
    let coreCap = ServerCapability(
      rawUri: "urn:ietf:params:jmap:core", kind: ckCore, core: genCoreCapabilities(rng)
    )
    var caps = @[coreCap]
    let extraCount = rng.rand(0 .. 3)
    for _ in 0 ..< extraCount:
      let sc = genServerCapability(rng)
      if sc.kind != ckCore:
        caps.add sc
    var args = makeSessionArgs()
    args.capabilities = caps
    let session = parseSessionFromArgs(args)
    doAssert findCapability(session, ckCore).isSome

testCase propSessionCoreCapabilitiesPreserved:
  checkPropertyN "random CoreCapabilities round-trip through session", QuickTrials:
    let randomCore = genCoreCapabilities(rng)
    var args = makeSessionArgs()
    args.capabilities = @[
      ServerCapability(
        rawUri: "urn:ietf:params:jmap:core", kind: ckCore, core: randomCore
      )
    ]
    let session = parseSessionFromArgs(args)
    let extracted = coreCapabilities(session)
    doAssert extracted.maxSizeUpload == randomCore.maxSizeUpload
    doAssert extracted.maxConcurrentUpload == randomCore.maxConcurrentUpload
    doAssert extracted.maxCallsInRequest == randomCore.maxCallsInRequest
    doAssert extracted.maxObjectsInGet == randomCore.maxObjectsInGet

testCase propSessionWithRandomAccounts:
  checkPropertyN "findAccount returns added accounts", QuickTrials:
    var args = makeSessionArgs()
    let acctCount = rng.rand(1 .. 5)
    for i in 0 ..< acctCount:
      let acctId = parseAccountId("rnd" & $i).get()
      args.accounts[acctId] = genValidAccount(rng)
    let session = parseSessionFromArgs(args)
    for acctId in args.accounts.keys:
      doAssert findAccount(session, acctId).isSome

# --- Session structural invariants (property-based) ---

testCase propSessionUrlVariablesPresent:
  checkPropertyN "generated Session URLs contain required variables", ThoroughTrials:
    let session = genSession(rng)
    ## downloadUrl must contain {accountId}, {blobId}, {name}, {type}.
    doAssert session.downloadUrl.hasVariable("accountId"),
      "downloadUrl missing {accountId}"
    doAssert session.downloadUrl.hasVariable("blobId"), "downloadUrl missing {blobId}"
    doAssert session.downloadUrl.hasVariable("name"), "downloadUrl missing {name}"
    doAssert session.downloadUrl.hasVariable("type"), "downloadUrl missing {type}"
    ## uploadUrl must contain {accountId}.
    doAssert session.uploadUrl.hasVariable("accountId"), "uploadUrl missing {accountId}"
    ## eventSourceUrl must contain {types}, {closeafter}, {ping}.
    doAssert session.eventSourceUrl.hasVariable("types"),
      "eventSourceUrl missing {types}"
    doAssert session.eventSourceUrl.hasVariable("closeafter"),
      "eventSourceUrl missing {closeafter}"
    doAssert session.eventSourceUrl.hasVariable("ping"), "eventSourceUrl missing {ping}"

testCase propSessionPrimaryAccountsConsistency:
  checkPropertyN "primaryAccounts reference valid AccountIds in accounts",
    ThoroughTrials:
    let session = genSession(rng)
    ## Every value in primaryAccounts must be a key in accounts.
    for uri, acctId in session.primaryAccounts:
      doAssert session.accounts.hasKey(acctId),
        "primaryAccounts references unknown AccountId: " & string(acctId)
