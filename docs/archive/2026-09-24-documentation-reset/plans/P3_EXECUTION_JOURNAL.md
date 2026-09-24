# P3 execution journal

## 2026-09-22 — source reconciliation

Baseline: `codex/physical-gem-engine`, clean at `2d3102a`. No user changes.
Preparation checks are structural evidence only; preserve frozen fixtures and
historical reports. The prepared merge-window contract supersedes older atomic
proposals and the obsolete intervention paragraph in the prototype plan.

Reusable: MergeSession/Kernel/Executor provide detached transactions, one default
successor, complete replay, Craft entitlement and diagnostic move/room/run scopes.
Catalog/rules are immutable; BoardState owns allocation and obstacle topology.
MergeRoomView owns animation, identity buffering, tool cancellation and lifecycle.

Missing: authored families/profile/settings, expedition owner, carry-aware opening,
typed extraction, rewards/routes, disk persistence and expedition release probes.
Preserve original schema-2/rubble admission. OpeningGenerator currently discards
initial instances and resets allocation. Completion can leave holes; restore must
admit committed sessions rather than require equilibrium. Diagnostic reaction
helpers do not establish production families. Preserve all legacy wire identities.

## Execution checklist / owners and exit evidence

- [x] P3.1: P3Content/RuleSet, FamilyDispatcher, MergeMoveContext/Kernel.
  Source snapshots, simultaneous components, Quartz cap/clipping, Corundum
  replacement/dedup, Beryl ordering/revalidation, T8/suppression, intervention,
  unpublished rollback; kernel/seams/replay/P2 controls; playable family entry.
- [x] P3.2: replacement/previews, settings/effective prices. Ladder, carry ID,
  exact Bridge range, accepted-only Steady Hand, unchanged supply/legacy controls.
- [x] P3.3: ExpeditionState, carry opening transaction and selection view.
  Zero/one/two carry, rejection purity, load/preparation failure, RNG retries,
  monotonic allocators, complete streams/history.
- [x] P3.4: typed RoomDefinition/RoomState/extraction boundary. Frozen outlet
  fields, locks/threshold/order/demand, final Work, suppression, unique removal,
  objective witnesses.
- [x] P3.5: four rooms, rewards/routes/choice views. Every reward pair and route,
  persisted rolls, complete win/loss replays.
- [x] P3.6: canonical save/file store/Continue. All declared phases, exactly-once
  reservations, assisted resume, >2^53, corruption/version and file fault injection.
- [x] P3.7: input/delivery/lifecycle, deterministic tuning, actual release CPU/
  deadline/frame/memory at both sizes, source/package identity, optional review.
  Required engineering gates pass; see tests/game/P3_FINAL_VERIFICATION.md.
  Human review remains deferred.

Baseline `artifacts/game/p3/baseline`: 697 kernel, 45 seams, 138 preparation
assertions passed with markers; runner failed on sandbox certificate-store access.
Native rerun is separate evidence.

P3.1: native baseline passes all three stages. `b1-r1` passes import, legacy
tools, kernel, replay and seams; initial new test failed parsing, corrected in
`b1-r2`. `b1-r3` passes expanded family, merge commands and identity-buffer input
tests. `b1-final` passes final family assertions including multi-contact rubble
and Beryl-induced pending match. No thresholds/goldens changed. The reaction
queue has a 256-intent per-paid-move limit, reducible for diagnostics, in addition
to existing work/fact limits; exhaustion rejects the unpublished batch. UI has
a separate P3 family-room entry and explanations. Full expedition release
presentation/performance remains P3.7 work.

P3.1 checkpoint: `5711ed2`.
P3.2 evidence: `b2-r1` passes import, legacy tools/input/replay and families.
The metadata test initially compared typed StringName arrays with String arrays;
canonical comparison fixes that test without changing metadata. `b2-final`
passes all 39 settings assertions and retained input checks. Full ladder/reward
preview and effective tool labels are available in the P3 view.

P3.2 checkpoint: `efa731e`.
P3.3: `b3-r1` passes entry, settings, families and merge replay. `b3-final`
passes import/source check, entry/view, legacy room and merge input. Entry tests
use explicitly synthetic completion to isolate transitions; they do not claim
a full expedition winning replay. That witness belongs to P3.5. Runtime view
now offers briefing, normal family play, carry selection and failure results.

P3.3 checkpoint: `0bf5f15`.
P3.4 evidence: `b4-r1` passes extraction, entry, merge kernel and legacy room/
closeout checks. `b4-final` passes extraction, view and merge input. Tests read
the frozen P0 outlet fields directly; no fixture or historical expectation edits.
Extraction has a single removal ID shared with its subtype and suppresses
subsequent automatic earnings. Cyan outlet labels and committed delivery notice
provide functional presentation; native final-package checks remain pending.

P3.4 checkpoint: `ffefb4e`.
P3.5: `b5-flow-r1` failed a policy parse and numeric-JSON assertion, then stopped
without a completion marker. Automatic approval initially rejected terminating
both Godot processes; complete command lines proved both were the headless test
and its console wrapper. Only the verified test child was stopped. No editor was
touched. `b5-flow-r2` passes 279 assertions with actual deep-seam (82 steps) and
commission (81 steps) three-room wins. Both full canonical replays are frozen
under tests/fixtures/p3_expedition_v1. `b5-final` passes 88 replay assertions,
including a real first-swap seed-1 loss, plus entry/view and legacy merge replay.
No failures/seeds were discarded. The greedy policy demonstrates reachability,
not difficulty or optimal play. Reward/entry asset failure preserves choices.

P3.5 checkpoint: `931784c`.
P3.6 evidence: `b6-r1` stopped on a test type-inference error before dependent
tests. `b6-r2` is source-stable and passes source parse, all 89 save assertions,
frozen expedition replay, view and retained input checks. Every declared phase
is witnessed, including a live worker resuming a saved accepted ticket once.
All six write interruption points preserve a valid prior slot/recovery, and
retry publishes the new slot. Corruption and unsupported versions are explicit.
File durability is flush/close plus same-directory rename/recovery; this does
not claim resistance to arbitrary hardware loss beyond the tested fault model.

P3.6 checkpoint: `4af1757`.
Confirmed correction: user requested qualifying opening extraction on Begin,
before first paid input. `opening-confirmed-r1` passes source, import, extraction
and both complete expedition flows; `opening-confirmed-r2` passes P3 replay/save
and legacy merge replay. Original commission reference is retained and explicitly
rejected, corrected reference is separately named; deep route is byte-identical.
This fixes the unreleased P3 behavior without changing frozen legacy expectations.

Opening correction checkpoint: `b40f31b`.
P3.7 functional evidence: `b7-ui-r1` caught premature test exit during prefetch;
`b7-ui-r2` waits for owned previews and exits cleanly. `native-ui-r1` exposed
incorrect probe mouse coordinate scaling; `native-ui-r2` exposed canceled preview
callbacks retaining freed rows and layout changes before click completion.
WeakRef ownership and focus-follow scrolling fix the runtime issue. `r3` import
caught a missing explicit WeakRef type before export. All failed evidence retained.
`native-ui-r4` passes complete actual-release routes. `native-ui-r5` expands to
262 passing assertions including all reward pairs, carry counts, parked-window
Save/Continue, real controls, full replay, retry and loading/menu/restart cleanup.
The package is `generated/desktop/p3-candidate-r5`, inventory/source manifest
`artifacts/package-build/20260922-151821-9655/report.json`. Performance, full
integrated controls, tuning and second display verification remain open.

P3.7 functional checkpoint: `437e46c`. The full normal CPU corpus is running
against immutable r5 package bytes. A subsequent source audit found terminal
expedition publication still waited for presentation; correction is pending
verification: publish outcome with the terminal batch, normalize detached saves
at terminal capture, retain the visual tail, test both win/loss save mappings.
Additional pending verification: explicit paired Sapphire/Aquamarine utility,
current-versus-replacement ladder labels, carry coordinates/staging order,
initial keyboard focus, and native board gestures through normal Input routing.
Tuning now accepts immutable named production/seed-list IDs and records resources,
family/tool counts, rubble damage, ranks and complete replay files.
Normal r5 CPU evidence remains attributed to r5; changes above do not alter the
CPU probe, P3Workload, simulation or worker. Final source/package scope must be
verified explicitly, with final-package smoke and full 2x stress; do not silently
attribute r5 raw timings to another executable.

`b7-audit-r1` passes six source-stable stages: strict parse, retained input,
101 family assertions including paired build utility, 99 save assertions including
terminal success/failure normalization, and delivered view ownership.
`native-timing-720-r6` passes complete owner-inclusive native timing: frame p95
15.625ms, feedback p95 9.195ms, main p95/max 0.293/16.374ms, zero starvation.
`native-ui-720-r6` passes routed board/toolbar/menu input and lifecycle, including
failed Continue retaining current board/RNG/resources and outcomes before visual
tails. Candidate manifest: artifacts/package-build/20260922-154859-3119/report.json.
`cpu-full-r5` passes 1500 rooms / 64542 batches, all repetitions identical,
zero deadline/headroom failures; command p95/max 22.160/64.572ms, main p95/max
2.614/9.884ms. Exact r5 bytes retained. Final scope audit remains required.

Runtime checkpoint: `64b689e`. `native-ui-720-r6` and `native-ui-900-r6`
each pass 283 assertions with actual routed keyboard/mouse input. All four
native timing profiles (720/900, normal/2x) pass; independent raw-population
audits verify the gates and zero starvation. `final-source-scope.json` proves
the r5 normal CPU execution path is unchanged in r6, while preserving attribution.
`tuning-r6` completes all 200 fixed seed/policy runs and 401 assertions, with
complete re-executed FAC1 saves. Independent hash/population audit passes.
First-v1 loses 100/100; mixed-v1 wins 13/100. These are automated policy results,
not human balance acceptance; every loss remains in evidence.

`final-integrated-r6` completed all 39 stages with stable source: 38 passed;
the retained intervention-playback control passed its 40 assertions but failed
shutdown on audio resource leaks. Verbose diagnostics reproduced it. Measuring
the existing 0.5-second SceneTreeTimer showed 8-9 microsecond waits after resetting
40x time_scale: the current frame still carried the accelerated delta. A monotonic
500ms drain retains the intended duration and all original assertions, adding
an elapsed-time assertion. Five independent corrected diagnostics pass cleanly;
`final-cleanup-r6` passes registered source and 41-assertion playback checks.
Only the test harness changed; packaged runtime/audio bytes are unchanged.
The failed integrated run and diagnostic variants are retained, never relabeled.

`legacy-release-r6` passes all ten actual-executable stages, both native sizes,
2,000 P1 + 1,194 P2 complete state/event pairs, trial 30/60/120 equivalence and
isolated missing/corrupt packs. Original whole-action p95 is 38.229/42.136ms,
still failing its separate 5ms target. `editor-package-r6` passes exact-PCK
64-view/all-binding checks; burst/rest p95 14.201/8.380ms. This fresh short
editor result does not erase the retained historical editor-stall observations.
`cpu-smoke-r6` passes 15 rooms / 658 batches with independent raw audit.
`cpu-full-2x-r6` started at 16:28 local, using all 100 seeds, five policies and
three repetitions. It runs alone; no other engine tests or benchmarks are active.
Final source-stable registered closure is `final-integrated-closure.json` (39
requirements, 38 original passes plus the corrected harness rerun). The registered
P3 replay count is 89 after the opening-extraction compatibility correction.
Review README/form are prepared under generated/desktop/facets-p3-20260922;
final archive and engineering completion remain pending the full stress exit.

Final engineering closure, 2026-09-22 17:14 local: `cpu-full-2x-r6` passes
1,500 rooms / 64,542 batches, all three repetitions, zero deadline failures.
Independent raw audit matches every normal-run digest, batch count and terminal
phase. Command p95/max 53.685/110.046ms (ratios 0.3579/0.73364); main scheduling
p95/max 3.636/12.510ms. Stress satisfies its zero-deadline-failure gate; normal
reserve margins are not claimed for stress. Whole-process working/private peaks
are 460,734,464 / 403,140,608 bytes. Scoped awake request acquired and released.
`final-preservation.json` verifies 2,303 historical archive files, 14 successor
archive entries, 58 frozen fixture/content/audio/JSON files and all P3 references.
`final-completion-audit.json` passes all required engineering exits, validates
279 current packaged source inputs, exact package hashes and completed reports.
Human-dependent acceptance and the old whole-action 5ms target remain deferred
and failed respectively, exactly as described in the final tracked report.

One review archive: generated/desktop/facets-p3-20260922.zip (39,137,996 bytes),
SHA256 174f476132da300dc6dbd5041d9f1745193dc56f19f91610393e292b780c9249.
`final-delivery.json` verifies all seven ZIP entries by CRC and SHA-256, including
exact tested r6 runtime bytes. README, optional four-question form, BUILD.json
and verification report accompany the three portable runtime files. No rebuild
or source change was made during bundling. All P3 engineering batches are complete
on the measured profile; no human acceptance is invented.

Final engineering/documentation checkpoint: 31ce6bfb4fe3faa4805538339c860d2d4206f90f. Tracked worktree checked clean after commit; runtime source remains byte-identical to the r6 package manifest.
