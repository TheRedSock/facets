# Merge-window readiness evidence

The latest [observer, boundary and environment evidence](MERGE_HEADROOM_EVIDENCE.md)
passes both full CPU corpora and r8 native normal/2x profiles at both sizes,
including a repeat, with explicit test-window visibility. Final integrated,
legacy executable, characterization and delivery verification also pass;
[the final handoff](MERGE_FINAL_READINESS.md) records scope and exact bytes.

Later user-feedback fixes and the power-aware stall investigation are recorded
in [the follow-up evidence](MERGE_FEEDBACK_EVIDENCE.md). That report supersedes
the historical stall diagnosis below. Its then-open CPU headroom margin is
subsequently closed by the evidence linked above. Earlier reports and metrics
are retained; the r5 sections below are historical, not the latest candidate.

Status, 2026-09-22: the successor mechanics and P3 contract reconciliation are
implemented. **G0–G7 engineering readiness passes on the declared profile.** This document records
the scope of measured results, including failures. The executable decision is in
[the 30-case ledger](merge-readiness-status.json); exact requirements remain in
[the acceptance specification](MERGE_WINDOW_ACCEPTANCE.md). Reports and packages
are local, ignored artifacts and may be absent in a fresh checkout.

## Verified foundation

G0–G5 are checkpointed as `6bba782`, `f683e7c`, `52794e7`, `fee1686`, `33b8d9a`
and `748d740`. The system supports repeated paid swaps anywhere during merges,
redirection before pending automatic matches, one isolated default successor,
fresh move accounting, incremental worker execution, stable live/ghost identity,
complete session replay/restoration, and the reconciled P3 extension contracts.
Authored P3 families, expedition, carry/rewards and disk Continue remain future
implementation work.

`f315041` checkpoints the next verified corrections and release harness. A private
default no longer overwrites the live expiry clock; unencodable full candidate
hashes reject; focus loss during motion pauses the following window; terminal
audio follows committed results. The final source matrix at
`artifacts/game/merge-readiness/g7-final-controls-r1/run.json` passed all 29
registered stages with stable source, including the unchanged P1/P2 corpora.
The strengthened kernel has 697 assertions, including a hand-authored complete
early-terminal board/ID expectation and an explicit legacy-settling comparison.

Commit `71bdf36` checkpoints the later deadline audit corrections. Gravity followers correctly held
input but did not record starvation without a paid reservation, and the modeled
delay loop could cross its deadline between two clock reads and request a negative
sleep. The adapter now records waiting gravity and late arrivals; the diagnostic
sleep is clamped to a valid range. Focused worker, replay and headless/native
playback checks passed in `g6-gravity-r1` (82 playback assertions per render mode).
The packaged witness also forces late gravity, retains the committed board/RNG/
cost while waiting, records one late interval and restores a full next window.

## CPU measurements and scope

The full normal corpus was measured on immutable package **r4**, using accelerated
decision clocks and the real worker, copies, admission, hashes and publication.
It does not represent 1,500 fully animated rooms. The normal run excludes one
declared warm-up room and retains every subsequent interval.

| r4 normal corpus | Result |
|---|---|
| Repetitions / seeds / policies | 3 × 100 × 5; 1,500 rooms, 51,873 batches |
| Completion / identity | Zero failures; all repeated final digests identical |
| Command readiness p95 / max | 19.666 / 46.695 ms; interval ratio 0.131107 / 0.3113 |
| Gravity follower readiness p95 / max | 21.835 / 54.630 ms; ratio 0.057704 / 0.156309 |
| Default readiness p95 / max | 22.920 / 58.183 ms |
| Main scheduling per operation p95 / max | 1.640 / 9.729 ms; native per-frame totals are separate |
| Whole-process peak working set / sampled private peak | 389,197,824 / 282,857,472 bytes |

Authority: `g6-cpu-final-r1/run.json`; raw measurements are in its sibling probe
JSON/JSONL files. Process memory includes engine/probe/worker/snapshot allocations;
it is not an isolated worker heap measurement or ordinary-game memory claim.

The first 2× run (`g6-cpu-stress2x-r1`) completed 500 rooms and 17,291 batches
without deadline misses, but **failed** strict acceptance on 181 negative-delay
engine errors. Its internal probe status and zero exit code do not override that
failure. The corrected r5 rerun passed; the failed report remains intact.

| r5 required 2× stress (`g6-cpu-stress2x-r2`) | Result |
|---|---|
| Coverage | 100 seeds × five policies; 500 rooms, 17,291 batches |
| Strict completion | Zero deadline misses, zero engine errors; exact package bytes |
| Command readiness p95 / max | 32.641 / 57.591 ms; ratio 0.217607 / 0.383940 |
| Gravity follower readiness p95 / max | 41.487 / 78.953 ms |
| Default readiness p95 / max | 43.191 / 78.719 ms |
| Main scheduling per operation p95 / max | 1.874 / 11.700 ms |

The r5 normal smoke passed 15 rooms. All 500 stressed final mechanical states and
all 15 smoke states match the corresponding normal-corpus reference
(`g6-r5-cpu-reference.json`). This comparison covers complete final mechanical
state per seed/policy; it does not claim identical native input transcripts or
substitute for the separate full replay/restore tests. Modeled delay tests
scheduling sensitivity, not performance on a specific weaker CPU.

The r5 package changes three exported source files: the diagnostic sleep body,
the room adapter's deadline reporting, and the fixed release witnesses. Normal
mode never enters the changed sleep body. Full 1× figures above remain explicitly
r4 measurements; r5 integration and stress results are recorded separately.

## Native release measurements

Reference machine: i9-14900HX, RTX 4060 Laptop and Intel integrated graphics,
Godot 4.6.1, Windows Balanced power profile. GPU index 1 explicitly selected Intel
in these Vulkan runs. It is machine-specific and is not evidence for the default
NVIDIA path. Original animation/window durations were retained.

| r5 Intel profile | 1280×720 | 1600×900 |
|---|---:|---:|
| Normal timing run | **Failed: assisted pause** | Passed this run |
| Fixed release witnesses | 26 passed | 26 passed |
| Feedback p95 / max, ms | 8.630 / 8.864 | 8.652 / 8.881 |
| Default handoff p95 / max, ms | 12.680 / 15.878 | 12.115 / 13.549 |
| Main-frame work p95 / max, ms | 0.379 / 7.111 | 0.294 / 5.092 |
| Frame p95 / p99 / max, ms | 9.071 / 12.298 / 1,236.188 | 8.982 / 12.250 / 16.552 |
| Demand readiness ratio p95 / max | 0.142373 / 0.193633 | 0.140280 / 0.160573 |

Reports: `g6-native-r5-720/run.json` and `g6-native-r5-900/run.json`. All active
frames are retained, including pauses; fixed assisted/fault cases run separately
after the unassisted measurements. Earlier r4 had a clean 720 run and failing 900
runs. Later clean runs do not establish a fix for this intermittent issue.

Required native 2× reports are `g6-native-r5-stress2x-720` and
`g6-native-r5-stress2x-900`. The 720 run failed on assisted pauses/nonterminal
all-pass and survivor policies; the 900 run passed its checks. All 26 fixed
release witnesses passed in both. Frame p95/max were 9.091/1,265.834 ms and
9.075/1,233.055 ms respectively. Main-frame p95/max were 0.509/8.133 ms and
0.370/7.722 ms; demand readiness ratios were 0.217200/0.277620 and
0.239380/0.400780. A passing aggregate is not proof of a stall-free run: the
900 maximum remains visible. The required native stress exit is still open.

NVIDIA stalls reproduced in an empty window. Intel's 65-second empty control
completed 7,761 measured frames with p95 8.581 ms and max 9.613 ms. An editor
script trace captured a roughly 908 ms frame with about 19 ms measured script
time; a later pipeline-counter trace reproduced an active roughly 1.047 s pause
without new pipeline compilations. Removing memory sampling and changing audio
drivers did not resolve it. The attempted OpenGL GPU override actually selected
NVIDIA, and the release executable did not execute an external observer script;
neither is evidence for the intended diagnostic. All reports are retained under
`artifacts/game/merge-readiness/`. No global driver, graphics or power preference
was changed. The exact owner of the rare Intel pause remains unproven.

## Characterization and deferred evidence

The r5 release characterization passed mandatory last-Work completion/exhaustion,
recovery and all tools at 1×/2×, plus supported-board and bounded candidate-dispatch
cases (`g6-characterization-r5`). Candidate dispatch reports applied and suppressed
counts separately; repeated scope rejection is not 4×/8× active effect execution.

The separate `test_merge_load` executes independent active waves with full copies,
admission and hashes per wave. Its six editor cases apply exactly 56/224/448 effects
on 8×8 and 226/904/1808 on 16×16. The first measured service times were
28.588/112.495/224.614 ms and 113.713/456.726/916.779 ms. These conservative
synthetic costs intentionally repeat admission/hashing; they are not authored P3
content, ordinary release gates or evidence for a particular weaker computer.
They demonstrate that heavy individual batches can still exceed a swap interval.

The r5 4× delay characterization (`g6-cpu-characterization4x-r5`) completed
three seeds × five policies, 15 rooms in 38.951 seconds, with zero recorded
failures or engine errors and unchanged package bytes. This small characterization
does not establish the full normal-corpus headroom at fourfold load.

All 14 preserved archive hashes were verified and remain unchanged. A current
documentation check resolved all 134 local links across 16 guides/plans.
The historical whole-action 5 ms target still failed (retained P2 p95 37.640 ms).
The successor's 5 ms main-thread-per-frame budget is a different measurement.

The user is the sole optional reviewer. No player session, focus group, adoption
vote or completed form is a readiness requirement. Fun, learning, reaction
comfort and balance remain unmeasured; the practice build does not establish them.

## Release handoff and remaining exit

The r5 actual-executable legacy matrix `g7-release-r5-intel/release.json`
completed all ten stages: lifecycle, both native sizes, 2,000 P1 pairs, 1,194
P2 pairs, equivalent trial transcripts at 30/60/120 FPS, and missing/corrupt
asset-pack handling in isolated copies. This is a functional pass on the explicit
Intel profile. It separately reports the old whole-action target as failed
(fresh P1/P2 p95 32.627/36.343 ms). The earlier default-NVIDIA matrix
`g7-release-r5` failed the trial's real 800 ms expiry witness; that failure is
preserved. The GPU selector changes no global settings or test expectations.

The delivered candidate is
`generated/desktop/p3-readiness-review-20260922.zip`, with one executable build,
two explicit launch profiles, an optional form, this evidence, and a byte
manifest. Runtime checkpoint: `71bdf36`; build manifest:
`artifacts/package-build/20260922-021057-0440/report.json`.
`g7-source-identity-r5.json` verifies all 257 source hashes against that build.
`g7-delivery-r5.json` records copied-byte and ZIP-entry verification. The PCK is
`e4a84f96d864391686bcd7ebcbf56fd89396f56e0ed34123dadbcd7a9100c41b`.

G6 is **not passed**; G7 functional checks and delivery are complete, but its
readiness declaration remains dependent on G6. MW28/MW29 remain open on native
timing. No gameplay/accounting/replay contract question or human-review gate is
pending. P3 content implementation has not begun.

The next correction checkpoint must capture an engine/native thread and graphics
trace across the intermittent pause, identify its blocking owner, apply a scoped
fix, and rerun the failing native policies plus both sizes at 1×/2× on the
declared supported profile. Keep all failed runs. A clean repeat alone is not a
fix; the current measurements do not justify further simulation shortcuts.

If the user wants P3 content work to proceed before that diagnosis, the concrete
alternative is an **explicit, unapproved contract amendment**: permit P3 logic
development on the verified simulation foundation while carrying MW28/MW29 and
native timing forward as an open presentation milestone, retaining coherent
holds/assisted-pause behavior and all original thresholds. Call that conditional
development entry, not full P3 readiness. No such waiver has been applied here.
