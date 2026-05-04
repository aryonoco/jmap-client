# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Parser-only replay test for the captured ``Email/get`` response
## under ``maxBodyValueBytes`` truncation
## (``tests/testdata/captured/email-get-max-body-value-bytes-truncated-stalwart.json``).
## Verifies that ``EmailBodyValue.isTruncated`` parses true and the
## ``value`` string respects the requested byte budget.

{.push raises: [].}

import std/tables

import jmap_client
import ./mloader

const TruncationCap = 64

block tcapturedEmailGetMaxBodyValueBytesTruncated:
  forEachCapturedServer("email-get-max-body-value-bytes-truncated", j):
    let resp = envelope.Response.fromJson(j).expect("envelope.Response.fromJson")
    doAssert resp.methodResponses.len == 1
    let inv = resp.methodResponses[0]
    doAssert inv.rawName == "Email/get"

    let getResp =
      GetResponse[Email].fromJson(inv.arguments).expect("GetResponse[Email].fromJson")
    doAssert getResp.list.len == 1, "captured Email/get must carry one record"
    let email = Email.fromJson(getResp.list[0]).expect("Email.fromJson")
    doAssert email.bodyValues.len >= 1,
      "fetchBodyValues=bvsText must populate at least the text leaf"
    var anyTruncated = false
    for partId, bv in email.bodyValues.pairs:
      doAssert bv.value.len <= TruncationCap,
        "bodyValue under maxBodyValueBytes=" & $TruncationCap &
          " must satisfy value.len <= cap (got " & $bv.value.len & " for partId=" &
          string(partId) & ")"
      if bv.isTruncated:
        anyTruncated = true
    doAssert anyTruncated,
      "at least one bodyValue must carry isTruncated=true under truncation"
