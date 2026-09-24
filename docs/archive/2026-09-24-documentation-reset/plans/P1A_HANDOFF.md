# P1-A implementation handoff — 2026-09-14

Concurrent normal playback, reference/instant modes, lifecycle protection,
profiling improvements and actual-release diagnostics are implemented. **Full
P1-A latency acceptance remains open:** the 5 ms complete-action p95 target is
not met. Do not treat passed functional/frame checks as closing that gate.
The [post-P2 intervention trial](P2_INTERVENTION_TRIAL.md) is required future
work; adopting its mechanic into the expedition remains optional.

## Delivered batches and limits

| Batch | Result |
|---|---|
| A0 evidence | Original 2,000 P1 checkpoint pairs preserved in `tests/game/p1-checkpoints.json`; registered motion and actual-action probes added; debug/release CPU, frame, response and playback data separated |
| A1 motion | Pure MotionPlan; full stable-instance journeys and spaced incoming stacks animate concurrently on ordinary rectangular DOWN boards; coherent cubic distance/duration; individual landing effects |
| A2 lifecycle | Concurrent player is default; serial and instant retained. In-flight spawn ownership, atomic cell-map publication and cancellation preserve skip/restart/error/navigation/destruction behavior |
| A3 optimization | Unused intermediate compatibility hashes disabled in normal transactions; direct diagnostics retained and repeated settled hashes shared. Canonical encoding uses native string sorting, per-call string reuse and a native stream buffer. Matching/physics avoid redundant query work; complete identity/admission remain |
| A4 optional overlap | Deferred. Whole settling-wave barriers remain; no transient visual match or cross-wave early clear. This is an explicit visual compromise, not changed simulation ordering |
| A5 package and review | Clean package audit/probe, actual-executable action/corpus/lifecycle runs, matching serial/concurrent recordings and frame inspection complete. Player acceptance of feel and the CPU target remain open |

Custom holes, sideways/upward zones, fill edges, movement locks/immovable pieces
and portals retain ordered path playback. Portals fade at departure/landing;
custom spawning fades at the logical entry rather than inventing a route through
obstacles. These paths are correct conservative fallbacks, not equivalent fluidity
to the ordinary columns. P6 extends their presentation. Basic default-board
fluidity no longer waits for P4.

Automatic upgrade-created matches still resolve and appear before gravity. All
rules finish before normal playback; cosmetic timing cannot affect simulation.
There is no mid-cascade player input in P1-A.

## Verification

The [integrated report](../artifacts/game/p1a/integrated-checks.json) passed all
12 registered Godot stages: import, source_check, board_consumer, run_delivery,
smoke, RNG, rules, state, transaction, replay, playback and motion. Each reported
its required completion marker; source identity was stable throughout the run.
The [GPU report](../artifacts/game/p1a/gpu-checks.json) separately passed the
registered actual-action probe. Exact logs are in
[P1-A logs](../artifacts/game/p1a/logs).

The [final verification report](../artifacts/game/p1a/verification.json) confirms
release/movie checkpoint equivalence, all 137 packaged source hashes, all 19
frozen files, 16 archived documents and current local links. `git diff --check`
still reports five pre-existing blank-line-at-EOF warnings in the broader working
tree; this is not a clean whitespace-check claim. No commit was made and unrelated
user changes were retained.

- Replay: 100 seeds, 2,000 accepted actions, original P1 checkpoint comparisons,
  fresh replay and midpoint restore; **3,301 assertions, zero failures**.
- Motion: **864 assertions, zero failures**, including L-shaped holes, same-frame
  release, shorter falls landing first, sampled lane spacing, long entry-only
  refill, disconnected columns, full custom paths and positive pre-gravity chains.
- Scene tests cover serial/concurrent equality, skip during travel/landing,
  untracked spawn cleanup, restart, rejected bounce, delivery error, stale work
  and scene destruction.
- Actual release lifecycle checks passed invalid-input purity, committed skip,
  initial-state restart, error locking and navigation cancellation.
- Independent codec byte vectors and the fixed action vector remain unchanged.
  No protocol, rule RNG sequence, Work cost or checkpoint expectation was revised.

Reproduce the integrated run:

```powershell
& ./tools/check_engine.ps1 -Only import,source_check,test_smoke,test_rng_cross_platform,test_board_consumer,test_run_delivery,test_game_rules,test_game_state,test_game_transaction,test_game_replay,test_game_playback,test_game_motion
& ./tools/check_engine.ps1 -Gpu -Only game_action_probe
```

## Measurements and acceptance status

Godot 4.6.1, Windows, workstation identity retained in each probe. The release
renderer used Vulkan / NVIDIA GeForce RTX 4060 Laptop GPU. Measurements are not
movie runs; movie capture uses a fixed clock and is excluded from performance.

| Measurement | Result | Meaning |
|---|---|---|
| Original P1 headless complete action, 100 seeds | p95 131.716 ms; max 313.257 ms | Preserved historical baseline |
| P1-A headless editor complete action, same corpus | p95 **53.152 ms**; max 113.511 ms | About 60% lower p95; 5 ms target missed |
| Actual release headless complete action, same corpus | p95 **39.907 ms**; max 77.934 ms | 5 ms target missed in release too |
| Actual release full legal enumeration | p95 11.769 ms; max 29.148 ms | Measured separately; not included in complete-action timing |
| Actual release 20-action frame sample | p95 **8.496 ms**; max 21.315 ms; 2/2,949 frames above 16.7 ms | Frame p95 target met; worst stalls remain visible in report |
| Same 20 actions, actual simulation spot maximum | 20.788 ms | Smaller visual workload, not replacement for 100-seed CPU corpus |
| Planned falling, same 20 actions | 25.8 seconds serial → **6.824 seconds concurrent** | About 74% less scheduled falling; other presentation phases excluded |
| Actual normal playback, those 20 actions | **24.126 seconds total** | Includes swaps, removal, promotion, travel and landing; excludes separate loading/lifecycle phases |
| Warmed action asset loads | **0 additional pages** | Actual-action residency check, separate from the older gem-view burst |
| Input to first visible motion, 20 release actions | p95 **19.615 ms**; max 21.847 ms | Includes synchronous commit and first observed swap movement |

Reports: [debug corpus](../artifacts/game/p1a/replay-corpus.json),
[release corpus](../artifacts/game/p1a/release-corpus.json),
[release action/frame/lifecycle data](../artifacts/game/p1a/release-action.json),
[registered GPU probe](../artifacts/game/p1a/registered-action-probe.json).
Input-to-first-motion and individual action/frame distributions are retained in
the action report; p95 frame time alone does not hide the commit frame.

Remaining CPU work is material. Full canonical state/event encoding, full final
re-admission and repeated rule scans still cost time; larger cascades amplify
them. The [post-change small diagnostic](../artifacts/game/p1a/stream-profile.json)
separates these stages. No allocation attribution or equivalent trusted-state
validator has been established. Removing validation, partial hashing, changing
event order or changing admission limits would not be a valid optimization.
Retain the 5 ms target as an open gate; a lower measured number alone does not
authorize declaring it achieved. P2 content work can proceed, but full P1-A
latency acceptance needs further work or an explicit milestone decision.

## Package and visual evidence

Clean desktop package:
[Facets.exe](../generated/desktop/20260914-170557-9822/Facets.exe), with its sibling
`Facets.pck` and `gem-assets.pck` retained together. Build/audit evidence is the
[package report](../artifacts/package-build/20260914-170557-9822/report.json).
The actual executable, not an editor script override, ran the release probes.

```powershell
& ./tools/build_game_package.ps1 -AssetPack generated/gem-assets.pck -Probe -FrameBudgetMs 16.7
& ./generated/desktop/20260914-170557-9822/Facets.exe -- --action-probe=C:/GIT/facets/artifacts/game/p1a/release-action.json
& ./generated/desktop/20260914-170557-9822/Facets.exe --headless -- --action-probe=C:/GIT/facets/artifacts/game/p1a/release-corpus.json --probe-corpus
```

Separate 60 FPS movie runs captured the same 20-action command sequence and
lifecycle checks. Native 1600×900 recordings contain 1,646 frames / 27.43 seconds
concurrent and 2,693 frames / 44.88 seconds serial, including startup and lifecycle
work. The requested window resolution was overridden by project window settings;
report the actual encoded size. These durations do not establish CPU/GPU speed.

- [Concurrent animation preview](../artifacts/game/p1a/concurrent.webp)
- [Serial reference preview](../artifacts/game/p1a/serial.webp)
- [Concurrent native recording](../artifacts/game/p1a/concurrent.avi)
- [Serial native recording](../artifacts/game/p1a/serial.avi)
- [Sampled concurrent frames](../artifacts/game/p1a/concurrent-contact.png)

Frame inspection shows stable gem identity, incoming stack staging and the
restored concurrent motion progression. Analytical and scene tests establish
release/spacing/ordering behavior. This is agent inspection and recorded evidence,
not a claim that the user or a player panel has accepted the feel. Use these
recordings and the executable for that review.

## Evidence provenance and downstream ownership

Prior active documents were archived with verified hashes in
[the P1-A archive](../docs/archive/p1a-implementation-2026-09-14/manifest.json).
The original 19 P0 frozen files and the complete original P1 corpus remain intact.
The first 40-action review diagnostic's raw timings were accidentally overwritten
when that helper was reused; its recorded original aggregates were retained with
an explicit provenance note. The second original diagnostic and both full
100-seed baseline/checkpoint sets were not lost or regenerated. New runs have
separate P1-A paths.

An initial sandboxed import could not write normal Godot editor caches; the
registered import and later validation ran successfully with the normal cache
access. Completed offline sandbox probes emitted the existing certificate-store
warning. These environmental attempts are separate from the passing registered
and release evidence.

Next owners: P2 builds the tactical room on concurrent presentation; the required
post-P2 trial compares paused/timed intervention with an explicit adoption
decision. P3 extends episode/save/replay contracts only if the trial is adopted.
P4 owns broader UI/art/audio/accessibility polish; P5 repeats actual-action
acceptance under expedition load; P6 extends custom transport motion. Whole-wave
overlap and freely reactive falling remain separately scoped work.
