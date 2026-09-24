# P2 closeout execution journal

Execution started 2026-09-21 at `43ab9c9`. The governing plan is
[P2 finalization and P3 preparation](P2_FINALIZATION_AND_P3_PREPARATION.md).

## User-directed scope amendment

The user is the sole reviewer currently and requested one build/form, with human
review/testing deferred until much later, potentially after P5. C3 and T3 now
prepare reproducible review material; they do not require invented sessions or
block engineering P3 readiness. Human feel/difficulty/intervention preference
remain unmeasured. Retain atomic default pending actual later adoption review.
Engineering trial coverage and the CPU target remain required.

## Evidence roots

- `artifacts/game/p2-closeout/20260921-implementation/baseline-manifest.json`:
  1,028 tracked-file hashes and 2,303 copied, checksum-verified historical
  evidence/document files captured before implementation edits.
- `s0-import/`: initial sandboxed import failed on Godot cache/user-directory and
  certificate access. Correctly classified as failed despite exit zero.
- `s0-baseline/`: 18 completed passing registered stages, source stable. P1 2,000 checkpoints and P2 1,194 gameplay actions (+100 Begin), 77 complete / 23 failed. Debug p95: P1 47.6 ms, P2 53.71 ms. CPU gate fails.

## Work status

| Step | Status |
|---|---|
| S0.1 | Complete: checkpoint 6899716, protected evidence and frozen P2 corpus |
| S0.2 | Complete: current docs reconciled; historical bytes preserved |
| S0.3–S0.4 | Complete: 63 fields / 23 cases and source extension audit |
| C1 | Complete: 6ece4a9, 19 integrated passing stages |
| C2 | Complete release matrix in r3; 5 ms CPU target fails; measured decision package awaits user disposition |
| C3 | Complete amended deliverable: one r3 build/form and three reproducible policy witnesses; human findings deferred |
| T0–T2 | Complete: e7069cf plus 2defe1a; native 30/60/120 FPS equivalence, actual expiry/stall and lifecycle pass |
| T3 | Complete amended deliverable: optional paired comparison in the same build/form; human findings deferred |
| T4 | Decline production adoption for this milestone; retain isolated trial; no human preference claim |
| R0 | e0bf129: tracked contract, four layouts, 14 acceptance specifications, 112 passing structural assertions; activation awaits CPU disposition |

Each verified checkpoint will record its commit, exact checks and remaining gates
here and in the tracked closeout ledger. Checkpoints and their evidence follow.


## Checkpoint 6899716 — evidence and current-status reconciliation

S0.1 and S0.2 complete. Baseline 18-stage run and subsequent three-stage frozen
P2 comparison both passed with source stability. The P2 reference contains 1,294
state/event pairs including Begin, with the original corpus report checksum.
Runner result-classification tests (10 cases) and occupied-output preservation
passed. Historical P0/P1 references and reports were not rewritten.

The cumulative audit accounts for 63 expected fields across 23 frozen cases;
see P2_CLOSEOUT_AUDIT.md and the audit-fields artifact. C1 closes the identified
edge coverage and RoomProbe quantile discrepancy. ActionProbe already used
nearest rank; only RoomProbe had the lower-index ten-sample p95 issue.


## Checkpoints 6ece4a9, 3e0d8b2, e7069cf

- 6ece4a9: inherited source/field audit and meaningful edge regressions; all 19
  integrated stages passed. Corrected small-sample room p95 convention.
- 3e0d8b2: bounded short-string wire cache/native ID validation; original codec
  vectors and all P1/P2 checkpoint pairs pass. Full admission/hashing retained.
- e7069cf: real pre-gravity continuation and versioned paused/24/48-tick trial,
  complete in-memory replay admission, transactional failure, shared accounting
  and comparison UI. Trial simulation 304 assertions; playback 26 assertions.
  The first view test exposed a real cancellation resource leak despite passing
  assertions. Explicit wake/disconnect at the draw boundary fixed it; the rerun
  passed without leaked-resource errors. Earlier failed logs are retained.

Release r1: package audit/runtime probe passed, then all 10 actual-executable
stages passed, including 2,000 P1 and 1,194 P2 gameplay checkpoint pairs and
30/60/120-FPS trial equivalence. Native 1600x900 / 1280x720 frame p95 is
15.726 / 15.702 ms; maxima 50.025 / 44.723 ms. No warmed-burst page loads.
Gem payload 3,133,568 bytes, non-gem RGBA estimate 280,576, audio 328,320.
Human feel/learning/preference remain unmeasured.

CPU remains failed: exact release P1 p50/p95/max 14.207/33.263/72.945 ms;
P2 17.171/37.218/78.334 ms. A milestone decision is still required; no technical
waiver follows from the human-review amendment. Final r2 adds explicit result
sound-tail cancellation, actual recovery view/restore, real timed expiry and a
visible-stall witness. This is new coverage, not an unmotivated repeated run.

## Final engineering checkpoints and iteration

The 22-stage integrated run passed with stable source hashes, including 947
closeout assertions and all original P1/P2 checkpoints. Actual r2 then exposed
an empty-tween error despite correct final-state assertions. The added real-clock
sequence revealed that the trial published readiness before a queued board
rebuild completed. Restart could recycle views during the opening animation.
Failed logs, focused reproductions and ordered diagnostics remain preserved.

`2defe1a` makes synchronous snapshots supersede queued rebuilds and only enables
trial Start after constructing its initial views. Five affected registered stages
pass; trial playback now has 37 assertions, including actual prefix visibility and
expiry playback. No simulation identity changed. `e0bf129` checkpoints the P3
contract and structural specification. `f36ef46` checkpoints the review entry,
asset preflight and complete release verifier.

Final r3: build audit `artifacts/package-build/20260921-174540-5320/` passes;
`release-r3/release.json` records all 10 actual-executable witnesses passing.
P1 2,000 and P2 1,194 action pairs match frozen references. Trial admitted streams
match at 30/60/120 FPS and reduced motion; actual expiry, visible-stall pause,
missing/corrupt assets and all release lifecycle assertions pass without engine
errors. Native 1280×720 room and timed-trial screenshots were visually inspected.

CPU p50/p95/max: P1 14.162/32.637/73.181 ms; P2 17.308/37.640/77.164 ms.
Frame p95/max: 1600×900 15.803/69.633 ms; 1280×720 15.827/67.968 ms.
Memory payload budgets pass and no warmed-burst gem page loads occur. The CPU
target remains failed, with options and a bounded follow-up in
[P2_CPU_DECISION.md](P2_CPU_DECISION.md). No human or CPU waiver is inferred.

Preservation recheck: all 2,303 archived files, 25 frozen source/audio files and
20 P0 evidence files match their captured hashes. Accepted audio is unchanged.
The one review delivery is `generated/reviews/Facets-P2-Review-20260921.zip`, with
launcher, three-file r3 package, exact hashes, instructions and optional form.
Copied package hashes match the verified release. Human review is not required
now; broader learning, difficulty, dense-audio/feel and preference remain deferred.

## Completion audit supplement

The current worktree matches all 231 source files in the r3 build manifest.
Both copies of the three-file package and the delivered review ZIP match their
recorded hashes. The final legacy GPU control, explicitly listed in the plan,
also completes its 20-action playback/lifecycle witness with stable source hashes
and no engine errors (`final-legacy-gpu/`). The completion-classifier's ten cases
and the timeout/child-termination/success process-control checks pass in fresh
logs. This supplements the final release evidence; it does not turn an editor
GPU measurement into a release CPU result. The sole remaining P3 activation gate
is the requested explicit CPU milestone decision, which remains pending.
