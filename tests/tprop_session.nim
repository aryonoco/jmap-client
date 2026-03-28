# SPDX-License-Identifier: BSL-1.0
# Copyright (c) 2026 Aryan Ameri

{.push raises: [].}

## Property-based tests for Session and UriTemplate.

import std/hashes
import std/random

import pkg/results

import jmap_client/capabilities
import jmap_client/session
import ./mfixtures
import ./mproperty

# --- UriTemplate properties ---

block propUriTemplateTotality:
  checkProperty "parseUriTemplate never crashes on arbitrary string":
    discard parseUriTemplate(genArbitraryString(rng))

block propUriTemplateNonEmpty:
  checkProperty "valid UriTemplate has len > 0":
    let s = genValidUriTemplate(rng)
    let tmpl = parseUriTemplate(s).get()
    doAssert tmpl.len > 0

block propUriTemplateRoundTrip:
  checkProperty "$(parseUriTemplate(s).get()) == s for valid s":
    let s = genValidUriTemplate(rng)
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

block propUriTemplateReflexivity:
  checkPropertyN "propUriTemplateReflexivity", QuickTrials:
    let s = genValidUriTemplate(rng)
    let a = parseUriTemplate(s).get()
    doAssert a == a

block propUriTemplateEqImpliesHashEq:
  checkPropertyN "propUriTemplateEqImpliesHashEq", QuickTrials:
    let s = genValidUriTemplate(rng)
    let a = parseUriTemplate(s).get()
    let b = parseUriTemplate(s).get()
    doAssert hash(a) == hash(b)

block propUriTemplateDoubleRoundTrip:
  checkPropertyN "propUriTemplateDoubleRoundTrip", QuickTrials:
    let s = genValidUriTemplate(rng)
    let first = parseUriTemplate(s).get()
    let second = parseUriTemplate($first).get()
    doAssert first == second
