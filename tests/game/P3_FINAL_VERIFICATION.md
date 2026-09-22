# P3 engineering verification — 2026-09-22

All seven P3 engineering batches pass their required exits on the declared
current-machine profile. `artifacts/game/p3/final-completion-audit.json` verifies
the complete gate inventory and exact runtime/package identities. Human learning,
balance, listening and reaction comfort remain deferred under the sole-reviewer
policy.

## Runtime and compatibility

Runtime checkpoint: `64b689e`; test-harness cleanup checkpoint: `c7a1b47`.
Build manifest: `artifacts/package-build/20260922-154859-3119/report.json`.
Tested candidate: `generated/desktop/p3-candidate-r6`.

| File | SHA-256 |
|---|---|
| Facets.exe | `6a0266cb7571aa4d437a32094acd353f020c77dcf7ff5a3305ae45d0609e5c20` |
| Facets.pck | `4eb8cf5e6c88968e8dceeffa9996a4e01ec768954791a4b6bb47b52e5c2da304` |
| gem-assets.pck | `78c87eb8fafa5e844e219c2f0f138b08821ef77ba139c2e3975818110938f284` |

P3 has its own profile, simulation/content/replay/save identities and state
schema 4. Original P0/P1/P2 and merge-control identities remain separate.
The user-confirmed opening extraction is in `commission-opening.fac`; the old
commission reference is retained and explicitly rejected. Deep-seam reference
bytes are unchanged. The fixture README records these compatibility decisions.

## Completed behavioral exits

Evidence paths below are under `artifacts/game/p3/` unless otherwise stated.

- `final-integrated-closure.json`: all 39 registered requirements closed. The
  source-stable `final-integrated-r6` run completed 39 stages: 38 passed, while
  the legacy intervention playback passed its 40 assertions but failed shutdown.
  Its half-second drain timer could expire in 8–9 microseconds using the prior
  40× frame delta. `final-cleanup-r6` uses a monotonic 500ms drain, retains all
  assertions, adds an elapsed-time assertion, and passes source checks and clean
  shutdown. Five corrected verbose diagnostics also pass. Only this test changed;
  the independent closure audit proves all runtime and other test inputs match.
  The original failed run remains unchanged.
- P3 integrated counts: families 101, settings 39, entry 72, extraction 39,
  complete flow 279, save 99, replay 89, delivered headless view 4. These include
  pure rejection, unpublished rollback, deterministic replay and restore.
  Save coverage exercises all eleven declared phases and six write interruption
  points, >2^53 integers, accepted reservations exactly once, corrupt/incompatible
  input, backup recovery and terminal-boundary normalization.
- `native-ui-720-r6` and `native-ui-900-r6`: 283 assertions each on the actual
  executable, using routed keyboard/mouse board, toolbar and menu input. Both
  three-room reference wins, every reachable reward pair, 0/1/2 carry, complete
  checkpoint replay, parked and choice Continue, failed-load preservation/retry,
  overlapping board/preview ownership, and restart/menu/loading teardown pass.
  Assisted diagnostic playback is kept separate from timing acceptance.
- `legacy-release-r6/release/release.json`: all ten actual-executable stages
  pass, including lifecycle, both display sizes, 2,000 P1 and 1,194 P2 frozen
  state/event pairs, trial equivalence at 30/60/120 FPS, and isolated missing and
  corrupt asset packs. No gameplay fallback is used for delivery failure.
- `tuning-r6` and `tuning-r6-audit.json`: every seed 1–100 under both immutable
  policies completes, 401 assertions pass, and all 200 full FAC1 replays are
  saved and re-executed. Independent population/hash admission passes. Named
  inputs are `p3-production-v1` and `p3-seeds-1-100-v1`. First-v1 loses 100/100;
  mixed-v1 wins 13/100 and loses 87/100. All losses are Work exhaustion and remain
  in the corpus. These characterize automated policies, not human difficulty.

## Performance and delivery scope

Measured on Windows, Intel Core i9-14900HX, NVIDIA RTX 4060 Laptop GPU (index 0),
Godot 4.6.1, Balanced power profile, mailbox presentation and 120 FPS cap.
The scoped awake/window observer acquired and released its request for release
runs. No power-plan or driver settings were changed.

`cpu-full-r5` contains 1,500 rooms / 64,542 batches, with identical mechanical
outcomes across three repetitions and zero deadline/reserve failures. Normal
command readiness p95/max is 22.160/64.572ms; main scheduling p95/max is
2.614/9.884ms. These timings remain attributed to r5 executable bytes.
`final-source-scope.json` proves the r6 CPU methods, simulation, worker, content
and project inputs are identical. Changes concern expedition UI/save/lifecycle
and native terminal-owner observation. `cpu-smoke-r6` independently verifies the
final assembly on 15 rooms / 658 batches. `cpu-full-2x-r6` passes all 1,500 rooms
and 64,542 batches with zero deadline failures. Independent raw-data audit matches
every seed/policy/repetition digest, batch count and terminal phase to the normal
corpus. It took 2,754.266 seconds; command readiness p95/max is 53.685/110.046ms
(ratio 0.3579/0.73364), and main scheduling p95/max is 3.636/12.510ms. Stress
passes its zero-deadline-failure gate; its readiness ratios do not meet the
separate normal-load reserve margins and are not presented as doing so.

| Actual r6 native workload | Frame p95 | Main p95 / max | Feedback p95 | Handoff p95 | Readiness ratio p95 / max |
|---|---:|---:|---:|---:|---:|
| 1280×720 | 15.625ms | 0.293 / 16.374ms | 9.195ms | 15.376ms | 0.173173 / 0.24604 |
| 1600×900 | 14.391ms | 0.308 / 15.586ms | 8.889ms | 13.139ms | 0.180853 / 0.227007 |
| 1280×720, modeled 2× | 10.504ms | 0.302 / 14.808ms | 8.775ms | 11.578ms | 0.249273 / 0.377667 |
| 1600×900, modeled 2× | 15.380ms | 0.323 / 14.788ms | 8.873ms | 15.253ms | 0.250433 / 0.49542 |

Both normal and corresponding 2× native profiles pass unchanged computation
deadlines, with zero starvation, no warmed asset reload and 40 retained release
cases each. Normal frame p99/max is 17.323/33.765ms at 720 and 16.915/28.207ms
at 900. The main-frame measurements include publication of terminal expedition
outcomes. Independent audits recompute raw populations, quantiles and deadlines.
The 2× gate requires zero deadline misses/starvation; its input and main-thread
metrics are reported separately above. Its 1600×900 readiness p95 slightly
exceeds the normal profile's 0.25 reserve criterion. Modeled stress adds delay
equal to measured computation service time without sleeping the renderer; it is
a scheduling sensitivity check, not certification of a particular slower CPU.

The full CPU content-load corpus covers four authored room definitions, all
eight settings combinations and 0/1/2 incoming T4/T5 gems. Native timing uses
seeds 1, 6, 11, 20 and 31 across its five policies. These are synthetic workload
fixtures, distinct from the complete expedition route witnesses. No animation
duration or frozen threshold was changed to obtain a pass.

P3 native gem payload is 3,140,736 bytes; non-gem RGBA payload is 280,576 bytes;
decoded audio is 328,320 bytes. Whole-process memory reports separately include
renderer, snapshots, worker and retained diagnostic measurements; they are not
isolated worker allocation counts. The full normal CPU probe peaked at
511,463,424 working-set bytes / 404,140,032 sampled private bytes while retaining
64,542 raw measurement records. The full 2× run peaked at 460,734,464 working-set
bytes / 403,140,608 sampled private bytes. Native timing peaked at 517,386,240
working-set bytes / 641,888,256 sampled private bytes; the larger UI/lifecycle
matrix peaked at 550,027,264 / 671,047,680 bytes. These are whole-process bounds
for the measured runs, not promises about all workloads or isolated worker use.

`editor-package-r6` checks the exact packaged PCK using the separate editor
asset harness: 64 views and all delivered bindings load; burst/rest p95 is
14.201/8.380ms, with max 17.399/30.896ms. It passes the 16.7ms p95 budget. This
does not erase historical rare approximately 0.5-second editor-harness intervals
or establish a driver defect. Historical second-long stalls coincided with
Modern Standby; actual release evidence is reported separately.

## Preservation and review delivery

`final-preservation.json` verifies 2,303 archived historical evidence files,
14 successor archive entries, 58 baseline-tracked fixture/golden/audio/content
files and game JSON expectations selected by the audit, plus all three P3
reference hashes. Frozen expectations and thresholds were not rewritten.
`final-completion-audit.json` verifies all 279 packaged source inputs against
the current runtime and checks the identities and completion of every required
release profile. Reproducible audit scripts and raw evidence remain beside it.

The review bundle is [facets-p3-20260922.zip](../../generated/desktop/facets-p3-20260922.zip).
Its [optional review form](../../generated/desktop/facets-p3-20260922/REVIEW.md)
asks four short questions without requiring a session. The bundle contains the
exact tested executable/PCK/asset pack, startup notes, form, build identity and
this report. `artifacts/game/p3/final-delivery.json` records ZIP identity and
per-entry checksum verification. No runtime rebuild occurs during bundling.

## Limitations

The original whole-action 5ms target still fails: the fresh retained P1/P2
release controls measure p95 38.229/42.136ms. It is not the successor's incremental
main-frame or computation-deadline metric. Normal native p95 acceptance does not
promise every frame is below 16.7ms or that every machine meets this profile.

Save durability is verified flush/close, same-directory rename and recovery
under the six injected file failures; this is not a guarantee against arbitrary
hardware power loss. Continue is manual and timed restores are paused/assisted.
Broader human testing remains deferred, potentially until after P5. No balance,
learning, feel or listening acceptance is fabricated from automated checks.
