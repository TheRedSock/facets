# Merge-window readiness execution journal

User resumed execution on 2026-09-21 under the successor G0-G7 plan. This explicit
amendment replaces the earlier human-session and whole-action CPU activation
requirements for future readiness; it does not rewrite their historical results.
The app API still reports the old goal blocked and exposes no resume/objective
edit operation. Execution proceeds under the user's instruction and this ledger.

## G0 — verified foundation and frozen profile

Source baseline: `d5e0445`; clean tracked working tree before implementation.
Frozen executable acceptance values: `tests/game/merge-profile-v1.json`.
All 30 MW cases have exact assertions and ownership in the tracked readiness
ledger. Future cases remain pending; a design specification is not test evidence.

Baseline r1 stopped on sandbox-denied Godot editor/cache access. Retained report:
`artifacts/game/merge-readiness/g0-baseline/run.json`. It did not execute dependent
gameplay stages. Unchanged r2 ran with normal cache access: all seven requested
stages completed and passed, with stable source inventory in
`artifacts/game/merge-readiness/g0-baseline-r2/run.json` and `source-before.txt`.
Coverage: import, full source load, existing P3 specification checks, intervention
trial, rules, state and transactions. Full frozen corpora remain final legacy
regressions; this focused baseline is not a new performance claim.

Reference performance remains the exact prior r3 release: P2 complete-action
p95 37.640 ms, native frame p95 15.803/15.827 ms. Those metrics are historical,
not successor batch latency. G6 must collect new release results.

Ownership audit: board, RNG, ActionContext, physics, spawner and projection are
detached RefCounted services. GameCatalog/RuleSet/RoomDefinition data are deeply
read-only; supply resources are newly allocated. Resource loading in bootstrap
and room setup stays on the main thread. CanonicalCodec's mutable static string
cache and GameValue's shared RegEx need explicit synchronization or isolated
replacement before G3. Scene callbacks, pooled views and audio stay main-thread
owned. ActionContext journey facts must not be extended after a batch publishes;
batch freezing and clearing journey indices are required at the new boundary.

Reconciled source assumptions: existing RunState is embedded P2 data, not a
successor envelope; outer session owns batch/move/window identity and admission.
Its structural counters need explicit normalization for bounded diagnostic Work
discounts. No legacy external admission or golden expectation is weakened.
One-batch successor orchestration reuses matching, effects, gravity and resources;
the legacy TurnController remains the exact full-action control. Tests use
the existing fresh-output/completion-marker runner as soon as they exist.

G0 passes its reconciliation/profile/ownership/focused-baseline exits. G1-G7
remain pending. The tracked readiness ledger is the current acceptance inventory.

## G1 — incremental reference kernel

Added successor MergeSession, MergeMoveContext and MergeKernel. Matching/effect
and gravity services are reused; no legacy rule execution was edited. Each
candidate is detached and readmitted before publication. One merge parks before
newly formed matches and gravity; gravity publishes exact facts separately.
Costs, fresh move identity, incremental Craft and terminal checks have their
initial reference implementation; repeated-input acceptance belongs to G2.

G1 r1/r2 caught errors in the new disjoint fixture: surrounding tiles accidentally
extended the two intended three-gem lines. Corrected those neighbors and retained
the exact expected survivors. The runner rejected a script error despite a
zero-failures assertion summary. Registry ordering now initializes source before
kernel execution. The G0 ledger's nested future-gate array was also flattened.

G1 r3 passed import/source/kernel. G1 r4 added work/fact/cascade cap witnesses
and passed 689 assertions. The 50-action all-pass corpus compares board, Work,
Craft and RNG with the legacy control; early-terminal differences are explicitly
classified and a fixed terminal fixture proves stop-before-refill behavior.
The r2 run separately passed unchanged transaction/trial checks. Published facts
remain unchanged across continuation. Full release and broader frozen corpora
remain G6/G7 requirements. G1's focused implementation exits are complete.

## G2 — repeated commands and accounting

Typed bounded modifier admission now owns diagnostic intervention discounts and
direct/automatic reward predicates. Fresh paid scopes preserve ordinary Work,
turn and tool allowance behavior; automatic descendants retain intervention
classification with an explicit direct-batch flag. No authored gems were added.

The fixed redirection board makes a four-match in column 1 instead of the
automatic three-match in column 2; its two denied-match gems remain in place.
Equilibrium/intervention references on the same occupied neighborhood agree on
base effects and Craft. Seed 1 yields five consecutive paid commands (four
interventions), including a remote match, recorded with exact IDs in the report.
Tests cover stale/invalid input purity, finite discount consumption, clipped
entitlement, reward scope and tool-to-paid-swap suppression handoff.

G2 r1 stopped on a missing explicit Array type in a test. R2 passed kernel
regression and found an incorrect test assumption about initial clock sequence;
replaced it with exact pre/post clock equality. R3 passed all command assertions.
Reports are preserved under `artifacts/game/merge-readiness/g2-r1` through `g2-r3`.
G2 reference exits pass; concurrency, native presentation and final integrated
coverage remain separately pending.

## G3 — worker, reservation and isolated default

Added one persistent worker with protected pending/completion mailboxes, priority
generation cancellation and bounded shutdown. Input reserves its exact command,
cost, revision and receipt tick; delayed completion cannot expire admitted input.
One private default candidate may be prepared. Expiry is required to publish it;
intervention discards its state, RNG, IDs, rewards and any private failure.
Publication binds current clock/transcript metadata rather than stale worker time.

The codec's shared short-string cache is sealed read-only before worker startup;
new strings use per-codec storage. Shared RegEx access is mutex protected.
Resolution budgets have a scheduling-only cancellation callback, checked during
bounded rule work and excluded from serialization. Worker results transfer
ownership; workers never access scenes or continue mutating published candidates.

G3 r1 caught an inferred-type parse issue. R2 passed source, kernel, commands,
executor, existing state and transaction checks. R3 adds chosen/default failure
and duplicate-queue witnesses and passes. Tests include two genuinely running
default cancellations, input at tick 19, private speculative failure, selected
failure, exact synchronous comparison and eight cancel/teardown cycles. The
executor mailbox is bounded; presentation queue/underflow behavior remains G4.
No release deadline claim is inferred from these functional checks.

## G4 — playable streaming room

Added the opt-in merge-intervention room, streaming live/ghost ownership, fixed
swap feedback, worker overlap, first-drawn-frame window handoff, explicit clock
adapter, reduced-motion fades, tools at equilibrium, pause/pass and lifecycle
cleanup. Menus retain the original atomic entry. Input uses post-merge IDs; the
promoted view is transferable while decoration and independent ghosts continue.
Closing a window cancels unfinished gestures to prevent retargeting a new board.

G4 initial runs caught a native Control signal-name collision and a test type
annotation. The first playback run passed assertions but exposed asynchronous
audio teardown at process exit; a bounded mixer quiescence interval in the test
now establishes resource release instead of ignoring engine leak errors.

G4 r4/r5 passed source, headless and native streaming playback plus both inherited
atomic/trial player suites. Native fixture image was inspected for layout and
actionable promoted identity; these are synthetic delivery assets, not art claims.
R6 passes 68 assertions in each render mode. It includes real keyboard and mouse
drag adapters, four repeated interventions with a remote match, pointer-down
expiry, resize, focus/stall assistance, explicit pass, automatic no-input merge,
and injected late computation with a full subsequent window. 30/60/120 FPS and
reduced-motion runs have identical admitted mechanical checkpoints.

This completes G4 functional exits. Actual packaged content, unassisted latency,
headroom thresholds and final resource measurements remain G6/G7 work.

## G5 — complete restoration and P3 reconciliation

MergeReplay admits the full session by replaying initial state, typed modifiers
and ordered committed commands, checking every state/event/decision-chain digest
and the final complete snapshot. Pending reservations reconstruct from their
immutable accepted ticket and charge once. Private defaults are never saved.
Timed restoration pauses and marks assistance; native room restoration shows the
exact committed board. Clock polls no longer increment transcript sequence, so
frame rate does not manufacture mechanical decisions. Diagnostic failures retain
the committed prefix and replay their explicit injection/cap outcome.

Added diagnostic source-family and once-per-move/room/run reaction seams, with
live-target revalidation and suppression. These are exercised hooks, not shipped
Quartz/Corundum/Beryl content. Reconciled P3 identities (new expedition schema 4),
incremental entitlement, extraction/equilibrium precedence, terminal carry,
eleven save phases, reservations and unpublished-batch failure semantics.
The prior contract/spec/test/plan were archived and all four hashes verified.
P0 expectations and old runtime golden files are unchanged.

G5 r3 passed nine integrated stages including native restoration. R4 passed
strict clock-note schema, reviewed new automatic-versus-redirection vector,
89 replay assertions, 45 seam assertions, native playback and 138 structural P3
assertions. New frozen vector SHA-256:
`f7b3693f8778d563d3f135379eb7205fa8b322f0535036b88d848c9a601f6be2`.
The hand-explained three-match/four-match outcomes were reviewed before capturing
these successor-only checkpoints. G5 exits pass; G6/G7 remain open.

## G6 — initial measurement and corrections (in progress)

Instrumented worker copy/root/resolution/admission/projection-hash and publication,
with accelerated-clock CPU corpus and separate native presentation measurements.
G6 instrument r2: 15 editor rooms, 578 batches, no deadline misses; command p95
28.817 ms, main scheduling p95 1.778 ms. This preliminary default scheduling metric
omitted its initial queue copy; corrected before acceptance runs.

First exported build: generated/desktop/merge-g6-r1; build evidence
artifacts/package-build/20260922-002835-9289. Native-small failed with half-second
draw stalls and an actual replay clock bug. A private default copied before the
first drawn merge could overwrite the live expiry clock during publication.
Publication now preserves live decision state and only resets the new window.
Focused source/commands/executor/replay checks pass in g6-clock-r1; added a direct
pre-presentation-default → gravity → exact-replay regression.

Empty-window controls reproduce periodic ~0.5-second draw stalls on the NVIDIA
Vulkan path and on OpenGL; Direct3D reduces but does not eliminate them. The same
empty-window control on GPU index 1 (Intel integrated) completed 1,200 frames in
10 seconds without a >50 ms gap. This is diagnostic environment evidence, not
permission to omit failed native runs or claim the discrete-GPU gate passed.
Actual Intel room measurements and complete CPU/release exits remain in progress.

### G6 audit corrections and retained evidence

The pre-draw default clock regression now passes, including exact replay of
gravity after expiry. Additional corrections reject empty complete candidate
hashes without changing authority, preserve focus loss across an in-flight
swap/gravity into the next window, and derive terminal sound cues from committed
room results. Main-thread telemetry includes input, default-copy, publication
and presentation callbacks per frame. Review mode includes an explicitly
assisted, untimed redirection practice board. Normal timings remain unchanged.

`g6-audit-r1/r2`, `g6-probe-r4`, `g6-freeze-r1` and `g6-load-r1` contain passing
focused source, kernel, commands, executor, replay, headless/native playback,
P3 seams and load checks. Runner tests pass 11 result-classification cases,
including ObjectDB leaks, and bounded process success/timeout behavior.

The first full release corpus (`g6-cpu-r1`, r2 package) passed 1,500 rooms and
51,873 batches with exact repetition digests. Command ready latency p95 was
20.049 ms, maximum 40.650 ms; total main scheduling per operation p95 1.624 ms,
maximum 8.784 ms. This is accelerated-decision CPU evidence, not 1,500 animated
native rooms. A fresh complete corpus is running against final candidate r4.

Native r4 Intel 1280×720 (`g6-native-720-r2`) passed all five policies and 18
release witnesses. Feedback p95/max: 8.365/8.666 ms; default handoff:
12.222/13.091 ms; main-frame work: 0.334/5.444 ms; frame p95/p99/max:
9.066/12.185/18.437 ms. Demand readiness ratio p95/max: 0.1398/0.163473.
However, 1600×900 (`g6-native-900-r1`) failed due to rare ~0.8–1.2 s pauses
that correctly marked an assisted attempt. Removing process-memory polling
(`g6-native-900-no-memory`) and changing Dummy to Windows audio
(`g6-native-900-wasapi`) did not remove them. A prior 720 run also recorded a
1.24 s frame. The clean 720 repeat does not erase those observations.

The editor script-profile control (`g6-profile-native`) captured a 908 ms frame
with about 19 ms measured script time, before a sub-millisecond draw. This
narrows the location but does not establish an engine/driver root cause.
The attempted OpenGL Intel override (`g6-native-900-intel-gl`) actually selected
NVIDIA according to the engine log and failed; it is not Intel evidence.
No driver, global power or OS graphics preference was changed. G6/G7 remain open.

`g6-load-r1/test_merge_load/active-waves.json` passed correctness for six
editor-only characterization cases. Applied effects scale exactly 56/224/448
on 8×8 and 226/904/1808 on 16×16. Service times were 28.588/112.495/224.614 ms
and 113.713/456.726/916.779 ms respectively. Each independent wave repeats
copy/admission/hashing, so these are conservative synthetic costs, not ordinary
release gates or future authored-family measurements. The 8×8 eight-wave case
and larger cases demonstrate where the current 150 ms allowance can be exceeded.

Final r4 CPU corpus `g6-cpu-final-r1` passed: 1,500 rooms, 51,873 batches,
three exact deterministic repetitions, zero failures, 971.738 s elapsed.
Command readiness p95/max 19.666/46.695 ms (ratio 0.131107/0.3113);
gravity 21.835/54.630 ms (ratio 0.057704/0.156309); default 22.920/58.183 ms.
Main scheduling per operation p95/max 1.640/9.729 ms. Native per-frame totals
remain a separate measurement. Whole-process peak working set 389,197,824 bytes,
sampled peak private memory 282,857,472 bytes, including worker and snapshots;
these are not isolated worker allocation counts. Package bytes remained exact.

The final acceptance audit strengthened MW08 with a complete hand-authored
early-terminal board/ID/allocator expectation and an explicit legacy-settling
comparison with equal Work/Craft. The new assertion passes in the ongoing
`g7-final-controls-r1` matrix (697 kernel assertions). All 257 exported source
files were rehashed against the r4 build manifest with no mismatch. Subsequent
edits are tests and documentation, not runtime changes.

`g7-final-controls-r1` completed all 29 registered stages with stable source and
zero failed checks. This includes both original replay corpora, 697 successor
kernel assertions, native playback, complete replay/restore and future P3
structural checks. Commit `f315041` checkpoints the verified corrections and
measurement harness; it does not mark the still-open G6/G7 gates complete.

Longer Intel empty-window control `g6-empty-intel-65s` completed 7,761 measured
frames at 1600×900, p95 8.581 ms and maximum 9.613 ms. The first external-observer
attempt `g6-pipeline-native` was not executed by the release binary; that run
still completed the ordinary packaged probe successfully, with a retained
69.875 ms maximum frame. It establishes no pipeline-counter finding and does
not erase prior intermittent failures. The actual editor observer
`g6-pipeline-editor` reproduced an active ~1.047 s pause with unchanged pipeline
compilation counters (four canvas compilations throughout). Shader-pipeline
warm-up is therefore not supported as a remedy by this trace. Some other long
observer frames occurred during explicitly excluded initialization/replay work;
only the native probe's active intervals are performance samples.

### Post-checkpoint late-gravity audit

The deadline audit found that a late gravity follower held input correctly but
did not increment starvation: the adapter's check required a paid reservation,
which gravity continuations do not have. Added a gravity/busy branch and a
forced-late-gravity witness shared by headless/native playback and actual release
cases. It checks one recorded late interval, closed input without a reservation,
unchanged committed board/RNG/cost while waiting, recovery and a full subsequent
window when applicable. Verification/build are pending after the isolated 2×
CPU run. This correction changes presentation deadline reporting and its fault
witness; kernel, worker, content and CPU probe sources remain unchanged from r4.

The first 2× run completed 500 rooms / 17,291 batches without deadlines, but
strict `run.json` correctly failed on 181 negative-microsecond sleep errors.
The delay loop read the clock twice and could cross its deadline between reads.
Clamped the diagnostic sleep to 0–500 µs without changing the intended deadline
or normal zero-injection path. The release runner now includes engine errors
and the report path in its failure message instead of printing an empty reason.

`g6-gravity-r1` passed five source-stable stages: source, worker, headless/native
playback (82 assertions each) and replay. The adapter also records a late
completion when a long frame crosses the deadline and receives the result in
one poll. Fresh package r5 is `generated/desktop/merge-g6-r5`, build manifest
`artifacts/package-build/20260922-021057-0440/report.json`. Its 257-file manifest
differs from r4 only in the worker's diagnostic sleep, the adapter's deadline
reporting and the fixed release witnesses.

R5's 26 fixed release witnesses passed at both sizes. Its normal Intel 720 run
failed on an assisted pause (maximum frame 1.236188 s); its 900 run passed with
p95/max frame 8.982/16.552 ms. This is still intermittent, not a graphics fix.
Normal smoke and packaged mandatory/near-cap characterization passed. The
corrected `g6-cpu-stress2x-r2` passed all 500 rooms / 17,291 batches with zero
deadline misses and zero engine errors, in 553.639 s. Command p95/max:
32.641/57.591 ms; gravity: 41.487/78.953 ms; default: 43.191/78.719 ms; main
scheduling per operation: 1.874/11.700 ms. All 515 final r5 smoke/stress mechanical
states match their normal-corpus references (`g6-r5-cpu-reference.json`).

### Final measured handoff

Runtime corrections are checkpointed at `71bdf36`. Both r5 native 2× profiles
completed their fixed 26-case matrix. 720 failed on assisted pauses/nonterminal
all-pass and survivor policies; 900 passed its checks but retained a 1.233055 s
maximum frame. Neither result establishes a fix. The 4× delay characterization
passed 15 rooms in 38.951 s with no engine errors (`g6-cpu-characterization4x-r5`).

The default-GPU legacy release matrix `g7-release-r5` failed its real trial
expiry witness. Added an explicit per-invocation GPU selector, then
`g7-release-r5-intel` passed all ten stages, 2,000 P1 / 1,194 P2 pairs and
trial equivalence at 30/60/120 FPS. No global graphics preferences changed.
Fresh legacy P1/P2 p95 32.627/36.343 ms still fail their old 5 ms metric.

All 257 r5 source hashes match the build manifest. The review folder/ZIP contains
the identical three tested package files, optional form, launchers, evidence
and manifest; `g7-delivery-r5.json` verifies copied bytes and ZIP entries.
The final source screenshot was inspected: practice instructions, board and
controls are legible at 1600×900. Earlier 720 visual inspection remains valid
because the final reporting fixes did not change layout.

G6 is not passed. G7 functional verification/delivery is complete but readiness
depends on G6. MW28/MW29 retain native failures. Engine/native thread and graphics
tracing across the pause is the remaining correction checkpoint; cause is not
proven and isolated passing repeats do not close it. The tracked evidence gives
a concrete conditional P3-development amendment for review, not an adopted waiver.
No human evaluation or adoption decision blocks engineering. All background
verification processes have completed.

Final evidence/tooling checkpoint: e461a50. Tracked working tree is clean. Final metadata validation resolved 46 links across seven edited/delivered documents, all 30 acceptance IDs and every gate evidence path. Delivered ZIP SHA-256: bc6352b1a68767370df669ae998f8c5181558abd59c6d575441656aa200613f7. Runtime remains the tested 71bdf36 build; the later commit changes only tooling/evidence.


### User feedback: tool selection and audio, 2026-09-22
Fixed unavailable-tool selection, explicit cancel/Escape/toggle paths and rejected-target recovery in the successor. Restored promotion/rubble cues and older trial reduced-motion cue summaries. feedback-fixes-r1 passed source/import, new input cases and merge playback; trial assertions passed but strict teardown caught retained audio resources. The accelerated test now permits 0.5 real seconds for the mixer to drain; feedback-fixes-r2 passed both trial and original room playback, including zero engine errors. No game timings or acceptance limits changed.


Tool/audio checkpoint d6a5ef7. Buffer final verification: buffer-r5 passed source, delivery, headless/native input (95 assertions each), existing native merge playback and replay. buffer-final passed native input plus old trial/original-room audio controls. Earlier buffer-r3/r4 strict teardown failures were preserved and corrected: asset loading is now owned by persistent GemForge with generation-checked callbacks, avoiding abandoned room coroutine states on immediate navigation. The 1280x720 synthetic-fixture screenshot was inspected for cyan pending-pair feedback and legible controls; production assets are separately packaged. Simulation/replay protocol and all frozen goldens remain unchanged.


### Power-aware stall investigation and feedback handoff
Windows Kernel-Power logs place the r5 failures at 02:12–02:38 inside Modern Standby (00:40:44–06:59:21). The unchanged r5 build completed all native policies awake with max frame 32.097ms, failing only p95 headroom 0.251187 vs 0.25. Feedback r1 passed both sizes at 1x/2x on NVIDIA; maxima 29–37ms. A normal awake run without keep-awake also passed (max20.262ms). This strongly supports environmental interference, not proof of every exact wait. ETW capture was unavailable due OS privileges; no account/settings changes attempted. The observer did not establish OS foreground status or real user activity. Temporary display/system requests acquired/released correctly.

The r1 CPU smoke failed only command headroom: p95 40.454ms vs37.5ms. Same workload in unchanged r5 also failed at40.016ms; all15 final digests match, no deadlines missed. Do not confuse this reserve-margin failure with the former second-long freezes. Final runtime4cf3aff only corrects audio ownership for gravity; final source/delivery hashes and native reports are retained. G6 remains open on CPU headroom, with no target waiver. See tracked MERGE_FEEDBACK_EVIDENCE.md for complete scope and final ZIP identity.


Final evidence/tooling checkpoint: 4b42571; runtime checkpoint: 4cf3aff. Working tree clean after commit. Delivery verifies 259 source hashes, all three game files and all ten ZIP entries. ZIP SHA-256 be4b6c23c1f092bfcb2a64894c9ed59e9f8cc4ac050e37b0551c20b069869fbc. Final metadata check resolved 45 local Markdown links, all 30 acceptance IDs and referenced gate/delivery evidence. No Facets/Godot processes remain. User confirmed preference for simultaneous board-wide clearing; recorded in successor plan without changing already-correct runtime behavior.


### Resumed G6: CPU observer and boundary audit, 2026-09-22
Prior goal turn made concrete progress: input/audio/buffer corrections, package and power-state evidence were checkpointed. Remaining failure was current CPU reserve margin, not a human gate. Re-read current plan/acceptance/owners before resuming.

Instrumented old polling release headroom-polling-r1 passed 15 rooms, with actual 100us-request sleeps at p95 2.441ms and command readiness p95 20.589ms. Prior failed raw records had completion-to-publication p95 15.117ms; OS scheduling affects observer overhead, with no exact historical timer-cause proof. Source editor delay experiment had sandbox startup/certificate errors and is not acceptance. A release script override was ignored; that diagnostic process was stopped.

Checkpoint 7156cc9 adds optional worker completion notification solely for accelerated CPU observation, retains -CpuPolling control, and corrects readiness start to include command reservation and gravity animation setup. Native never blocks on this notification. Focused 4-stage observer, 6-stage boundary and explicit gravity-boundary executor runs passed. All hash/admission work and frozen limits remain intact. r6 immutable package: artifacts/package-build/20260922-104131-9366/report.json. r6 CPU smoke passed (command p95 24.154ms); same-build polling control also passed (22.262ms). Do not infer a speedup from this noisy pair. Full 1,500-room run r6-cpu-full started with temporary awake guard; its completion remains pending.

r6-cpu-full completed all 1,500 rooms / 51,873 batches at 11:01:52 with zero deadline misses/errors. Independent raw/count/nearest-rank audit matched every prior full reference digest/phase/batch/intervention count. Command p95/max20.803/54.628ms; gravity23.916/54.766; default25.121/56.193; main per-operation2.057/5.571. Awake request acquired/released, peak working/private412200960/305123328bytes. An outer shell check mistakenly tested unset LASTEXITCODE after the PowerShell audit; its completed structured audit was re-read and confirmed passed. This was a wrapper check error, not a failed corpus criterion.

Full r6 2x stress is now live: exec session14108, report artifacts/game/merge-readiness/r6-cpu-stress2x/release. Do not restart it on observation timeout; poll the live handle or authoritative process/report state. No parallel game benchmarks. Current normal CPU margin is passed; pending work is full stress, final native1x/2x both sizes, integrated affected controls, final source/package delivery identity and complete readiness reconciliation.

Normal-corpus evidence/tooling checkpoint968af09; runtime remains7156cc9, tested package r6 unchanged. Working tree clean. Goal remains active; stress process session14108 was re-polled and is live. Independent corpus auditor is artifacts/game/merge-readiness/audit_r6_corpus.ps1; use r6-cpu-stress2x/release/probe.json as Report once it finishes, g6-cpu-final-r1/probe.json as Reference, and a fresh output path. Do not use LASTEXITCODE for the PowerShell-only audit; its structured passed flag and exceptions are authoritative.


Continuation verified live stress session14108; previous turn classified progress (7156cc9/968af09 and full normal CPU audit). Prepared, syntax-checked but not launched: artifacts/game/merge-readiness/run_r6_native_matrix.ps1 (four NVIDIA profiles, stops on failed strict gate; requires completed stress) and run_r6_integrated.ps1 (prior29 stages plus headless/native buffer tests=31). Run sequentially after stress to avoid simultaneous game benchmarks. After those, final actual-executable legacy/trial/missing-corrupt-pack matrix still required on r6, plus fresh characterization as applicable, final metadata/requirements audit and delivery. No readiness claim.


Full r6 2x stress finished 11:33:55: all1,500rooms/51,873batches pass with zero deadline misses/errors. Independent raw audit r6-cpu-stress2x-audit.json checks all counts/deadlines/quantiles and matches all historical final digests/phase/batch/intervention counts. Command p95/max38.037/82.074ms; gravity47.522/112.350; default50.560/130.204; command ratios.253580/.547160 reported, not normal-profile headroom passes. Main per-operation2.394/7.026ms. Awake request acquired/released;17,032samples. Memory working/private407764992/302997504bytes. Native four-profile matrix now live, session73796; reports r6-native-720, r6-native-900, r6-native-720-2x, r6-native-900-2x. Do not restart on observation timeout; sequential runner stops on strict failure. Remaining final integrated31, legacy executable10, characterization scope, delivery and complete audit.

### Native pacing correction investigation
Previous user-question turn was a source verification, not readiness completion; resumed concrete G6 work. Re-read terminal r6 reports: native720 failed handoff p9517.932ms and readiness ratio.258487, while all policies/40cases and frame/feedback/main gates passed. The sequential matrix stopped; session73796 is terminal. Same r6 bytes with MaxFps0 passed handoff8.328ms/readiness.181187 but rendered >1000FPS; not adopted as a power-appropriate default. Session81879 is terminal. Preserved both reports and added diagnostic tooling override.

Configuration-only candidate r7-vsync changes project.godot max_fps120->0 and VSync mailbox3->enabled1. Export259-source comparison confirms project.godot is the sole changed runtime input. First sandbox import failed on normal Godot cache/certificate access (artifacts/package-build/20260922-115007-5157); unsandboxed normal-access build passed import/export/inventory, report20260922-115026-7659. Native720 experiment launched session69939 with scoped awake guard; no threshold changes and no other game benchmark running. Final adoption requires measured pacing/frame count and full affected checks.

r7 VSync experiment failed frame p9518.187ms/handoff31.578ms; reverted both project.godot changes. r6 cap240 diagnostic failed handoff18.069ms, also not adopted. r7 feedback400ms outliers exposed a probe defect: rejected expired gestures were attributed to later gravity. b0b9437 corrects explicit gesture admission and drains all main-frame records; source+headless/native input passed98assertions each in receipt-attribution-r1. r8 package20260922-115724-0176 differs from r6 only in merge_probe.gd; CPU worker/corpus path unchanged.

r8-native-720-visible passed all gates/40cases with original120FPS/mailbox and per-test AlwaysOnTop. Frame p95/max15.066/19.217ms; handoff15.196/16.306; readinessratio.1452/.182953; feedback8.839/11.186; main.267/4.015. All80gestureattempts accepted; full7197framepopulation retained. OSforeground unavailable from existing observer (zero matches); Microsoft timer-resolution occlusion behavior is a hypothesis, not proven from a clean repeat. Expanded observer records visible/topmost/minimized Facets window counts, without other-app titles/input synthesis. Remaining visible900/720-2x/900-2x/720repeat matrix now live session85800, stops on failure. No readiness claim or threshold change.

### Current measured candidate, 2026-09-22 12:07
Runtime/probe checkpoint b0b9437, candidate generated/desktop/merge-readiness-r8-observer. Rendering remains original mailbox/120FPS; VSync1 and cap240 experiments were rejected and reverted. Full normal and modeled2x CPU corpora each passed1500rooms/51873batches on r6; r8 changes only native probe admission/frame-drain observation, leaving the entire CPU execution path and game runtime identical. r8 visible native720/900 at1x/2x and normal720repeat all passed; independent raw audits verify quantiles, deadlines, all frame samples, gesture attribution and40cases perprofile. Scoped test visibility is explicit and not a shipped always-on-top setting. No system preferences changed; foreground interaction/physical scanout not established. Historical failed runs retained. Remaining integrated31-stage verification running session40218; actual-executable legacy/trial/delivery matrix, final r8 CPU smoke/characterization, final byte-verified one-build/form delivery and requirement audit still pending.

### Final candidate regressions and characterization
All31integrated stages completed source-stable, including98inputassertions per headless/native mode and138P3 preparation assertions. r8-closeout-visible completed10actual-executable stages on NVIDIA:2,000P1/1,194P2pairs, both native sizes, trial30/60/120FPS and missing/corrupt packs. Original whole-action5ms remains failed (P1/P2p9532.348/36.965ms). Allawake requests acquired/released. r8cpu-smoke15rooms/578batches passes (commandp95/max21.376/31.090ms); characterization32records passes; 4x characterization15rooms/578batches passes zero deadlines with ratio.406967/.635853 (not normal reserve passes). Independent small-corpus audits match all historic outcomes. r8-cpu-evidence-scope verifies r6/r8 CPU execution prefix and all other258runtime inputs unchanged. No active game processes remain after session88635 completion.

Fresh preservation:2,303original evidence files,27frozen source/audio,21P0 evidence/baseline files,14successor archive hashes all match. Three teaching replays match saved hashes. Visual inspection of current release720p ready/900p result and successor redirection confirms fitted, legible controls; synthetic-asset buffer capture confirms cyan pair/link feedback (not production-art proof). All original goldens unchanged, separate successor redirection golden only. Remaining work: exact-byte one-build/form delivery, final requirement/links/ledger reconciliation and checkpoint.

### Final engineering handoff
Completion audit r8-completion-audit.json proves14requirement groups plus every MW01-MW30 acceptance case. It includes all separately named original-plan commands: fresh presentation-content/20-action legacy GPU controls,11completion-classifier cases, bounded process-control checks, and the exact-PCK external asset-view probe at16.7ms p95. That editor harness passes p95(8.381/8.404ms) but retains rare p99/max~0.49s intervals. This remains a qualified presentation/tooling diagnostic follow-up before any stronger maximum-latency claim; actual release gameplay deadlines/input gates pass and no blanket stall-elimination claim is made.

An initial audit assembly referenced the small-corpus count as intervals instead of raw_intervals, then exposed PowerShell array-concatenation precedence in evidence paths. Both audit-construction errors were corrected without changing a test or expectation. Metadata validation also replaced one historical prose-combined evidence reference with exact current report paths and corrected MW08's owner mapping to test_merge_kernel. Final metadata resolves116local links across16documents and194ledger evidence paths. Original threshold profile unchanged.

Final deliverable: generated/desktop/facets-p3-ready-20260922.zip;9entries and259runtime-source hashes independently match. SHA25678b8731f60822120c890dd2462d863787a634c70011b6cba6d7f248d766d1793. The earlier candidate ZIP remains preserved; the final bundle includes the supplemental editor-harness limitation. Runtime/probe checkpoint remainsb0b9437, PCK5e4a658c4377a6f181142da55457b8dcb5a74936ed305013ae6f7774ce93cd1a. All amended engineering exits now pass on the declared current-machine visible/awake profile. Original atomic5ms failure and deferred human findings remain explicit; P3 gameplay itself remains future work. Final evidence/tooling commit follows; no live game benchmarks remain.

Final checkpoint:2d3102a (evidence/tooling/docs); measured runtime/probe:b0b9437. Tracked working tree clean. Final package/evidence remain as audited; exact final ZIP SHA25678b8731f60822120c890dd2462d863787a634c70011b6cba6d7f248d766d1793. Completion audit and metadata validation rerun after commit. All authorized P3 preparedness work is complete under the amended engineering goal; future P3 implementation and human evaluation remain explicitly separate.
