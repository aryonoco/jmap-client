# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Aryan Ameri

## Regenerates ``tests/wire_contract/public-api.txt`` — the frozen snapshot of
## every symbol reachable through ``import jmap_client`` and
## ``import jmap_client/convenience`` (A26). Emits the snapshot to stdout; the
## ``just freeze-api`` recipe redirects it into the committed file.
##
## The snapshot is the public-API contract (P1/P5): adding or removing a
## re-exported symbol changes the import graph consumers observe, so any diff
## here requires the ``[API-CHANGE]`` PR label and a deliberate review. The
## H16 lint (``tests/lint/h16_public_api_snapshot.nim``) fails CI on any
## un-frozen drift.

{.push raises: [].}

import ./api_surface

proc main() =
  echo "# Public-API surface snapshot — every symbol reachable through"
  echo "# `import jmap_client` and `import jmap_client/convenience` (A10/A26)."
  echo "# Locked by tests/lint/h16_public_api_snapshot.nim (P1/P5)."
  echo "# Regenerate with: just freeze-api"
  echo "# Update PR label: [API-CHANGE]"
  for line in snapshotLines():
    echo line

main()
