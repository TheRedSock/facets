# Runtime gemstone delivery

`GemAssetLibrary` reads version 1 bounded-page libraries. It has no dependency
on optical resources, compilers, workers or artifact stores. `GemDeliveryFormat`
owns the existing page wire identity; moving the reader did not change page keys.
Every frame and page must be reachable from a clip; orphaned records are rejected.

`GemDeliveryCatalog` explicitly maps logical tile IDs to asset IDs and semantic
roles. `rest` must be a still or loop; `upgrade` must complete. Every declared
role must resolve in the library. Simulation never reads this mapping or derives
game state from asset names. The default catalog is `data/presentation/default.tres`.

GemForge opens metadata transactionally with `open_library(path, catalog)`.
Failed admission preserves the previous library. `prepare_required(tiles, roles)`
validates and retains the declared upcoming page set before the run shows tiles.
Run startup includes the selected ladder and reachable upgrades. Missing packs,
roles, corrupt pages and memory admission failures produce loading errors. There
is no production substitute image; synthetic assets exist only in test fixtures.

The LRU owns at most 32 MiB by default. View and prefetch references can outlive
LRU ownership, so weak residency tracking counts all live uploads, including old
libraries held during replacement. A live page is reused after LRU eviction.
`prefetch_budget_bytes` separately defaults to 128 MiB; preparation rejects a
projected residency above that limit before uploading the requested pages.
The value is an explicit desktop resource cap, not a measured content budget.
Reports distinguish required-set bytes, cache ownership and total live residency.
Final-content performance/memory acceptance remains a P5 gate.

TileView exposes `play_role(role, restart)`, `return_to_rest`, completion and
interruption signals. A completed oneshot returns to rest; replacement and restart
interrupt active playback. Hidden views pause elapsed time. Rest stills do not
process frames. Board movement/choreography remains outside optical clips.

## Clean desktop packaging

Run `tools/fetch_export_templates.ps1` to provision the pinned official Godot
4.6.1 Windows templates. An existing archive may be supplied with `-Archive`.
Archive and executable SHA256 values are verified; only the two Windows templates
are extracted into ignored artifacts. No global installation is needed.

Build optical delivery first, then run:

```powershell
tools/build_game_package.ps1 -AssetPack generated/gem-assets.pck -Probe -FrameBudgetMs 16.7
```

The tracked export preset enumerates runtime sources. The build copies those
files into a fresh staging project, imports it and exports the release executable.
This avoids shipping the developer class cache's excluded authoring entries.
The output directory must be new/empty and contains only `Facets.exe`, `Facets.pck`
and `gem-assets.pck`. Logs, source hashes and audit reports stay outside it.

`audit_game_package.gd` runs externally against the exact PCK, checks allowed
runtime entries/classes, validates all tile roles and decodes/checksums every page.
The gem PCK must contain exactly the manifest and its referenced pages. The
optional runtime probe tests 64 views, upgrade completion and prefetched bursts.
Both execute from the package directory and reject source-tree visibility.
The probe prepares every declared tile and measures repeated animation bursts
and steady rest separately. `-FrameBudgetMs 16.7` enforces the agreed desktop
p95 budget; a probe without a budget only establishes functional behavior.

Godot's standard export templates disable `--script` and `--main-pack` overrides.
These external automated harnesses use the matching editor executable. Actual
release-executable navigation, missing/corrupt-pack errors and final performance
are separate acceptance evidence; a package probe cannot claim that evidence.
Synthetic package integration uses `tools/create_delivery_test_pack.gd` and never
promotes its test images into the production content catalog.

`tools/measure_release_frames.ps1 -ProcessId <Facets.exe PID>` records external
per-present ETW timings from the unmodified release process. Its pinned standalone
PresentMon binary requires an administrative or Performance Log Users token.
No service or group change is performed. Capture the foreground game with no
other optical workload and retain interaction evidence beside its raw CSV and
package checksums. These intervals measure application presentation; compositor
drop/display information remains available separately in the raw capture.
