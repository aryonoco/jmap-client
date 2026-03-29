# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based tests for Session and UriTemplate.

import std/hashes
import std/random
import std/tables

import results

import jmap_client/capabilities
import jmap_client/framework
import jmap_client/identifiers
import jmap_client/primitives
import jmap_client/session
import ./mfixtures
import ./mproperty

# --- UriTemplate properties ---

block propUriTemplateTotality:
  checkProperty "parseUriTemplate never crashes on arbitrary string":
    let s = genArbitraryString(rng)
    lastInput = s
    discard parseUriTemplate(s)

block propUriTemplateMaliciousTotality:
  checkProperty "parseUriTemplate never crashes on malicious input":
    let s = genMaliciousString(rng, trial)
    lastInput = s
    discard parseUriTemplate(s)

block propUriTemplateNonEmpty:
  checkProperty "valid UriTemplate has len > 0":
    let s = genValidUriTemplateParametric(rng)
    lastInput = s
    let tmpl = parseUriTemplate(s).get()
    doAssert tmpl.len > 0

block propUriTemplateRoundTrip:
  checkProperty "$(parseUriTemplate(s).get()) == s for valid s":
    let s = genValidUriTemplateParametric(rng)
    lastInput = s
    doAssert $(parseUriTemplate(s).get()) == s

block propHasVariablePresent:
  let tmpl = parseUriTemplate("https://example.com/{foo}/bar").get()
  doAssert hasVariable(tmpl, "foo") == true

block propHasVariableAbsent:
  let tmpl = parseUriTemplate("https://example.com/{bar}/baz").get()
  doAssert hasVariable(tmpl, "foo") == false

# --- Session properties ---

block propSessionCoreCapabilitiesTotal:
  checkPropertyN "coreCapabilities(validSession) never crashes", QuickTrials:
    let args = makeSessionArgs()
    let session = parseSession(
        args.capabilities, args.accounts, args.primaryAccounts, args.username,
        args.apiUrl, args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
      )
      .get()
    discard coreCapabilities(session)

block propSessionFindCoreCapability:
  let args = makeSessionArgs()
  let session = parseSession(
      args.capabilities, args.accounts, args.primaryAccounts, args.username,
      args.apiUrl, args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
    )
    .get()
  doAssert findCapability(session, ckCore).isSome

block propSessionPrimaryAccountUnknown:
  let args = makeSessionArgs()
  let session = parseSession(
      args.capabilities, args.accounts, args.primaryAccounts, args.username,
      args.apiUrl, args.downloadUrl, args.uploadUrl, args.eventSourceUrl, args.state,
    )
    .get()
  doAssert primaryAccount(session, ckUnknown).isNone

# --- Session cross-consistency properties ---

block propSessionFindCapabilityAgreesWithByUri:
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

block propUriTemplateEqImpliesHashEq:
  checkPropertyN "propUriTemplateEqImpliesHashEq", QuickTrials:
    let s = genValidUriTemplateParametric(rng)
    lastInput = s
    let a = parseUriTemplate(s).get()
    let b = parseUriTemplate(s).get()
    doAssert hash(a) == hash(b)

block propUriTemplateDoubleRoundTrip:
  checkPropertyN "propUriTemplateDoubleRoundTrip", QuickTrials:
    let s = genValidUriTemplateParametric(rng)
    lastInput = s
    let first = parseUriTemplate(s).get()
    let second = parseUriTemplate($first).get()
    doAssert first == second

# --- Session post-construction invariants ---

block propSessionPostConstructionInvariants:
  ## Verifies all five structural invariants guaranteed by parseSession.
  let session = parseSessionFromArgs(makeSessionArgs()).get()
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

block propAccountFindCapabilityTotality:
  checkPropertyN "Account.findCapability never crashes", QuickTrials:
    let account = genValidAccount(rng)
    let kind =
      rng.oneOf([ckCore, ckMail, ckSubmission, ckContacts, ckCalendars, ckUnknown])
    lastInput = $kind
    discard account.findCapability(kind)

block propAccountFindCapabilityByUriTotality:
  checkPropertyN "Account.findCapabilityByUri never crashes", QuickTrials:
    let account = genValidAccount(rng)
    let uri = genArbitraryString(rng)
    lastInput = uri
    discard account.findCapabilityByUri(uri)

block propAccountHasCapabilityTotality:
  checkPropertyN "Account.hasCapability never crashes", QuickTrials:
    let account = genValidAccount(rng)
    let kind =
      rng.oneOf([ckCore, ckMail, ckSubmission, ckContacts, ckCalendars, ckUnknown])
    lastInput = $kind
    discard account.hasCapability(kind)

block propUriTemplateHasVariableTotality:
  checkPropertyN "UriTemplate.hasVariable never crashes", QuickTrials:
    let s = genValidUriTemplateParametric(rng)
    let tmpl = parseUriTemplate(s).get()
    let varName = genArbitraryString(rng)
    lastInput = varName
    discard tmpl.hasVariable(varName)

block propPatchObjectGetKeyTotality:
  checkPropertyN "PatchObject.getKey never crashes", QuickTrials:
    let p = genPatchObject(rng, rng.rand(0 .. 5))
    let key = genArbitraryString(rng)
    lastInput = key
    discard p.getKey(key)

# --- Randomised session generation properties ---

block propSessionWithRandomCapabilities:
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
    doAssert session.isOk
    doAssert findCapability(session.get(), ckCore).isSome

block propSessionCoreCapabilitiesPreserved:
  checkPropertyN "random CoreCapabilities round-trip through session", QuickTrials:
    let randomCore = genCoreCapabilities(rng)
    var args = makeSessionArgs()
    args.capabilities = @[
      ServerCapability(
        rawUri: "urn:ietf:params:jmap:core", kind: ckCore, core: randomCore
      )
    ]
    let session = parseSessionFromArgs(args).get()
    let extracted = coreCapabilities(session)
    doAssert extracted.maxSizeUpload == randomCore.maxSizeUpload
    doAssert extracted.maxConcurrentUpload == randomCore.maxConcurrentUpload
    doAssert extracted.maxCallsInRequest == randomCore.maxCallsInRequest
    doAssert extracted.maxObjectsInGet == randomCore.maxObjectsInGet

block propSessionWithRandomAccounts:
  checkPropertyN "findAccount returns added accounts", QuickTrials:
    var args = makeSessionArgs()
    let acctCount = rng.rand(1 .. 5)
    for i in 0 ..< acctCount:
      let acctId = parseAccountId("rnd" & $i).get()
      args.accounts[acctId] = genValidAccount(rng)
    let session = parseSessionFromArgs(args).get()
    for acctId in args.accounts.keys:
      doAssert findAccount(session, acctId).isSome
