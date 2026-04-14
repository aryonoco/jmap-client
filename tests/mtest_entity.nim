# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Complete reference test entity demonstrating the full entity module pattern.
## Exercises entity registration, filter conditions, serialisation, and the
## builder/dispatch pipeline. NOT a real JMAP entity — test-only.
##
## Entity module checklist (Layer 3 design §4.6):
## 1. Entity type definition
## 2. methodEntity overload
## 3. capabilityUri overload
## 4. filterType template (queryable)
## 5. filterConditionToJson callback
## 6. registerJmapEntity at module scope
## 7. registerQueryableEntity at module scope
## 8. toJson/fromJson for the entity type

{.push raises: [].}
{.push ruleOff: "hasDoc".}
{.push ruleOff: "objects".}
{.push ruleOff: "params".}

import std/json

import jmap_client/types
import jmap_client/serde
import jmap_client/entity

# =============================================================================
# Entity type
# =============================================================================

type TestWidget* = object ## A minimal entity with typed fields for integration testing.
  id*: Id
  name*: string

# =============================================================================
# Filter condition type
# =============================================================================

type TestWidgetFilter* = object ## Filter condition for TestWidget/query.
  name*: Opt[string]

# =============================================================================
# Entity framework overloads
# =============================================================================

func methodEntity*(T: typedesc[TestWidget]): MethodEntity =
  meTest

func capabilityUri*(T: typedesc[TestWidget]): string =
  "urn:test:widget"

func getMethodName*(T: typedesc[TestWidget]): MethodName =
  mnMailboxGet

func changesMethodName*(T: typedesc[TestWidget]): MethodName =
  mnMailboxChanges

func setMethodName*(T: typedesc[TestWidget]): MethodName =
  mnMailboxSet

func queryMethodName*(T: typedesc[TestWidget]): MethodName =
  mnEmailQuery

func queryChangesMethodName*(T: typedesc[TestWidget]): MethodName =
  mnEmailQueryChanges

func copyMethodName*(T: typedesc[TestWidget]): MethodName =
  mnEmailCopy

template filterType*(T: typedesc[TestWidget]): typedesc =
  TestWidgetFilter

func filterConditionToJson*(f: TestWidgetFilter): JsonNode {.raises: [].} =
  result = newJObject()
  for n in f.name:
    result["name"] = %n

registerJmapEntity(TestWidget)
registerQueryableEntity(TestWidget)

# =============================================================================
# Serialisation
# =============================================================================

func toJson*(w: TestWidget): JsonNode =
  result = newJObject()
  result["id"] = w.id.toJson()
  result["name"] = %w.name

func fromJson*(
    R: typedesc[TestWidget], node: JsonNode
): Result[TestWidget, ValidationError] =
  ?checkJsonKind(node, JObject, "TestWidget")
  let id = ?parseIdFromServer(node{"id"}.getStr(""))
  let nameNode = node{"name"}
  ?checkJsonKind(nameNode, JString, "TestWidget", "name must be string")
  ok(TestWidget(id: id, name: nameNode.getStr("")))

{.pop.} # params
{.pop.} # objects
{.pop.} # hasDoc
