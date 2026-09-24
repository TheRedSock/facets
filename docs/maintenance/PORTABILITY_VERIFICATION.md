# Source-only setup verification — 2026-09-24

Scope: recover the current baseline from versioned inputs on this Windows
machine, using the steps in [the build guide](../BUILDING.md). This is not a
new P3 gameplay, artistic, optical-accuracy or performance acceptance report.

The source-only workspace was created with `git checkout-index --all` from
the staged documentation/portability changes on top of `31ce6bf`, under
`artifacts/portability/verified-source/`. It began without `.godot/`, generated
assets, render caches or historical artifacts. The discovered topology-report
fix was then copied from the working source and rechecked. Godot was the
installed official 4.6.1 standard binary; PowerShell 7.6.5, Python 3.14 and an
NVIDIA GeForce RTX 4060 Laptop GPU were used. This isolates repository data
dependencies; it does not simulate a different GPU or verify a new OS install.

## Results

| Check | Result |
|---|---|
| Cold Godot import | Passed; indexed classes and imported tracked media without developer caches |
| Source check | Passed |
| Game rules | Passed: 1,502 assertions, zero failures after fixing report-directory creation |
| Presentation content | Passed: tracked media hashes, resource loading, vocabulary and declared budgets |
| Default gem production | Passed: 304 requested frames, 176 newly rendered masters, 48 reprints, 224 delivered frames on 16 pages; no initial render cache |
| Delivery validation | Passed: 16 logical tiles, 32 required semantic clips |
| Template provisioning | Passed from an existing official `.tpz`, verified against pinned archive and extracted-binary hashes; network download not repeated |
| Windows packaging | Passed clean runtime staging/import/export and exact-pack inventory audit |
| Packaged asset playback | Passed functional GPU probe against the exported packs using the editor executable; no frame-budget acceptance requested |
| Documentation after Git checkout | Passed: 48 active Markdown files, 321 local links and 122 archived checksum entries; 20 unavailable local-evidence links in frozen historical reports inventoried separately |

The initial sandboxed editor attempt was blocked from normal Godot user settings
and cache directories. The cold import was repeated in a second source-only
workspace with normal environment access. The first unrestricted rules run
exposed a null report writer despite printing its completion marker; the runner
correctly rejected the script error. Both the topology stress writer and the
presentation checker now create their output directories and handle write failure.
Source/gameplay rules and accepted media were otherwise unchanged by this task.

Raw local records are under the source-only workspace:

- `artifacts/checks/20260924-164048-6598/`: successful cold import and the
  initial rules-test failure.
- `artifacts/checks/20260924-164353-6240/`: passing source, rules and presentation checks.
- `artifacts/build-assets/`: prepare/render/pack/collect logs, each with its
  required positive completion marker.
- `artifacts/package-build/20260924-164409-5803/`: source/package hashes,
  exact-pack inventory and runtime probe.
- `generated/desktop/20260924-164409-5803/`: newly produced Windows package.

These raw outputs remain ignored. This compact verification record travels with
Git; reproducing the procedure creates new evidence and may produce different asset bytes
on a different GPU. It does not recover the exact earlier P3 reviewed package.

## Source-control audit

Authored gemstone inputs, runtime UI/audio, recipes, tests and fixtures were
already tracked. Previously ignored docs/plans, including user anchors and
archives, are now versioned. Archive/frozen-report Git attributes preserve exact
bytes; 122 entries across historical manifests matched their recorded SHA-256
before staging. The documentation checker validates those manifests after checkout,
including relocating old absolute manifest paths without altering their bytes.

The obsolete `native/godot-cpp` declaration was removed: the index contains no
submodule entry and the current implementation needs no native build. Generated
assets, raw evidence, `.godot/`, tool binaries and Python environments remain
ignored. A scan of staged source/documentation found no common private-key or
credential-token patterns; it is not an exhaustive security assessment.

Further phase work starts from the tracked current-state/vision/prototype route.
Original review media requires a separate transfer if the task needs to inspect
that historical evidence. Basic play and new studies can regenerate current
baseline assets using the documented recipe.
