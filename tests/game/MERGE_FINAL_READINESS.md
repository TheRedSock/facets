# Final P3-readiness verification — 2026-09-22

The successor's engineering checks pass on the declared current-machine profile.
Final bundle identity and requirement closure are recorded separately in
`artifacts/game/merge-readiness/r8-delivery-final.json` and `r8-completion-audit.json`.
The [ledger](merge-readiness-status.json) owns final gate status. This establishes
the foundation for P3 implementation, not implemented P3 families, expedition,
disk Continue, player learning, balance or reaction comfort.

## Exact candidate and scope

Runtime/probe checkpoint: `b0b943748a14fd7af2910bee71b958ce10a50950`.
Build: `artifacts/package-build/20260922-115724-0176/report.json`;
candidate: `generated/desktop/merge-readiness-r8-observer`.
All 259 packaged source inputs match the current runtime. PCK SHA-256:
`5e4a658c4377a6f181142da55457b8dcb5a74936ed305013ae6f7774ce93cd1a`.
Later evidence/tooling commits do not change these executable bytes.

The final candidate differs from r6 only in native probe observation: explicit
gesture admission/rejection and complete main-frame sample retention. The CPU
probe execution prefix and all simulation, worker, data, presentation, project
and asset inputs are identical (`r8-cpu-evidence-scope.json`). Full CPU results
remain attributed to r6 bytes; fresh r8 CPU smoke verifies the assembled candidate.

## Verified exits

- `r8-final-integrated/run.json`: all 31 registered stages completed, passed and
  were source-stable. Covers inherited invariants/frozen replays, kernel, repeated
  paid interventions, accounting, executor isolation/cancellation, native motion,
  restore/replay, P3 seams and preparation. Input tests pass 98 assertions each
  headless/native; P3 preparation passes 138 structural assertions.
- `r6-cpu-full` and `r6-cpu-stress2x`: 1,500 rooms and 51,873 batches each,
  zero deadline misses. Independent audits recompute all raw intervals/quantiles
  and match every historical final mechanical outcome. Normal command readiness
  p95/max is 20.803/54.628 ms (13.9%/36.4% of the 150 ms interval).
- `r8-native-720-visible`, `r8-native-visible-900`, both corresponding `-2x`
  profiles, and `r8-native-visible-720-repeat`: all pass, with zero starvation
  and 40 fixed cases each. Independent audits verify complete frame populations,
  deadlines, quantiles, admission counts and exact package identities.
- Normal native frame p95 is 13.861–15.134 ms; handoff p95 13.755–15.196 ms;
  readiness ratio p95 0.1452–0.19082. Maximum normal frame interval is 22.928 ms.
  Maximum main-frame work is 7.898 ms; main p95 is 0.267–0.298 ms.
- `r8-closeout-visible/release/release.json`: all ten actual-executable stages
  pass on NVIDIA: lifecycle, both room sizes, 2,000 P1 and 1,194 P2 checkpoint
  pairs, old trial equivalence at 30/60/120 FPS, and isolated missing/corrupt packs.
  Original-room frame targets pass. Original whole-action CPU still fails 5 ms
  (fresh P1/P2 p95 32.348/36.965 ms); it is not the successor's per-frame metric.
- `r8-cpu-smoke`: 15 rooms/578 batches pass with command p95/max
  21.376/31.090 ms. `r8-characterization`: 32 special-case/near-cap records pass.
  Separate fourfold-delay characterization completes 15 rooms/578 batches with
  no deadline misses; its command ratio p95/max 0.406967/0.635853 exceeds normal
  reserve margins. This is characterization, not a full fourfold-load guarantee.
- Active-wave characterization executes 56/224/448 effects on 8x8 and
  226/904/1808 on 16x16 boards. Largest synthetic service time is 928.370 ms.
  This repeats complete admission/hashing per wave and demonstrates why future
  content must remeasure individual batches; it is not current authored gameplay.
- Native payload accounting: gem pages 3,133,568 bytes, non-gem RGBA 280,576 bytes,
  decoded audio 328,320 bytes; all are below their declared payload budgets.
  Whole-process reports separately include worker/snapshots/renderer overhead.
- Fresh preservation audit verifies 2,303 archived evidence files, 27 frozen
  source/audio files, 21 current P0 evidence/baseline files and 14 successor
  archive hashes. Original goldens are unchanged; only the separate successor
  redirection golden was added. All three earlier teaching replay hashes match.
- The original plan's separate controls also pass: presentation content, the
  20-action legacy GPU probe (`r8-explicit-plan-controls`), all 11 completion
  classifier cases, and timeout/child-termination/success process-runner cases.
  The external editor's exact-packaged-PCK view probe passes its 16.7 ms p95
  budget: burst/rest p95 8.381/8.404 ms, all 64 views loaded, no source leakage.
  Its p99/max are approximately 488/494 ms. These rare editor-harness intervals
  remain a diagnostic limitation, not actual release-gameplay timing evidence.
  Presentation/tooling owns any editor-versus-release reproduction needed before
  making a stronger maximum-latency claim. No such claim or max-frame gate is
  introduced here; the required actual-release input/deadline gates pass.

## Environment and retained failures

Measured native profile: i9-14900HX / RTX 4060 Laptop, Godot 4.6.1, Mobile Vulkan,
1280x720 and 1600x900, original mailbox VSync and 120 FPS cap. Tests explicitly
keep their window visible with a temporary always-on-top flag and a scoped awake
request; every request released successfully. Expanded observations confirm
visible, non-minimized windows. OS foreground interaction and physical display
scanout latency are not established. The delivered launcher changes no global
setting and does not force always-on-top.

The historical second-long stalls occurred inside a recorded Windows Modern
Standby interval. Awake unchanged-build tests support environmental interference;
they do not identify each exact blocked operation. Later r6 margin failures,
standard-VSync and 240-FPS experiments remain preserved. Neither rendering change
was adopted. Windows occlusion/timer behavior is a supported hypothesis, not a
claim of a proven driver defect. See [the detailed investigation](MERGE_HEADROOM_EVIDENCE.md)
and [feedback evidence](MERGE_FEEDBACK_EVIDENCE.md). No threshold was relaxed.

The user is the sole optional reviewer. One build and one form are the amended
deliverable; broader human testing is deferred, potentially until after P5.
P3 must remeasure family/expedition loads and implement the seven prepared batches
with their own exits. Existing readiness does not certify future stacked modifiers.
