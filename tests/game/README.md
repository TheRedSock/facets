# P1 game checks

`test_p3_families` executes the separate P3 profile: frozen source families,
Quartz clipping/shared entitlement, Corundum replacement/deduplicated contacts,
Beryl live targeting/ties/no-target/induced chain, T8/suppression, reaction caps,
unpublished rollback, paid interventions and complete family replay/restore.
This is behavioral coverage; `test_p3_preparation` remains structural coverage.

Successor input feedback: `test_merge_input` and `test_merge_input_native` verify
tool cancellation/affordability, committed sound cues, and one identity-following
buffer during swaps/gravity, with normal admission, replay and lifecycle cleanup.
The owning policy is in [the merge contract](../../core/run/MERGE_WINDOW_PREPARATION.md).

Run the registered `test_game_rules`, `test_game_state`, `test_game_transaction`,
`test_game_replay`, `test_game_playback` and `test_game_motion` stages through tools/check_engine.ps1
after import. Every stage has a required completion marker and nonzero failure
exit. These tests use explicit synthetic catalogs/delivery fixtures; production
bootstrap never falls back to them.

fixture-disposition.json assigns every expected field in all 23 immutable P0
cases: 15 full P1 observations, 5 partial and 3 deferred. “Full” concerns the
fixture's named phase, not complete expedition behavior. Craft and recovery
outcomes are P2; outlet/carry are P3; seal lifecycle is P6. Unknown phase/field
names fail the inventory. Locks in matching tests are capability adapters.

smoke-disposition.json accounts for 113 historical assertions, including the
formatted weighted-frequency label. Smoke now runs 114 assertions: it first
rejects the old layout's fill source pointing into a hole, then uses a valid
local source for retained layout observations. The previous cycle termination
assertion now requires explicit physical_cycle failure. Complete atomic rollback
is separately tested for work/fact/settle/cascade/chain caps. Catalog injection
and deterministic survivor ordering intentionally replace legacy fallback rules.

The nine topology scenarios cover irregular supported pockets, sideways-to-down,
upward in-place scanning, directed portal landing, source contention, immovable
occupants above entries, local diagonal fill beside a portal, mixed travel cycles
and no-match lane refill. 16×16 yields exactly 240 movement segments; oversize
layouts reject before allocation. Work and ordinary timing are reported separately.

codec-v1.json contains independent Python reference vectors. action-v1.json is a
reviewed 13-fact match_3 baseline captured after semantic, ancestry and projection
checks: action, swap pair, displaced helper, component, two removal/subtype pairs,
promotion, two spawns and settlement. Its exact bytes and SHA-256 checkpoints are
fixed. tools/game/capture_action_vector.gd writes only a candidate under artifacts;
it never refreshes expected values. JSON-readable facts are diagnostic, while
fact_bytes is the exact wire representation. Protocol changes require review and
an explicit version decision; tests must not rewrite goldens to pass.

seeds.json fixes 100 seeds and an ordered legal-command policy independent of
rule RNG. Each run records every accepted state/event checkpoint, fresh replay
and midpoint snapshot continuation. No failed seed is discarded. The report is
the check runner's new output directory. Same-build equality is the
claim; RNG build mismatches reject. The proposed 5 ms p95 is measured and assessed,
not presumed. test_game_playback uses the real RunScene/BoardScene adapter for
sequential, instant, skip, restart, rejected bounce, delivery error and destruction.
Its accelerated animation clock changes presentation only. Release-executable
interaction is a separate package handoff check.

P1-A adds `p1-checkpoints.json`: all 2,000 state/event pairs captured from the
original completed P1 corpus, with the source report SHA-256. Every replay-corpus
action now compares to this frozen baseline as well as fresh replay/restore.
Do not regenerate it from optimized code. Codec vectors remain independent.

The frozen fixture directory, codec/action goldens and P1 checkpoint file disable
Git newline conversion through .gitattributes. Preserve their exact bytes across
checkouts; do not renormalize them as part of formatting or platform setup.

`test_game_motion` checks L-shaped holes, simultaneous release, unequal landing
times, sampled lane spacing, long entry-only refill, disconnected regions,
direction changes, upward zones, portals, diagonal fill and supported pockets.
It also checks a positive pre-gravity promotion chain and real concurrent/serial
playback, cancellation during travel/landing, restart, error and destruction.

`game_action_probe` is a registered GPU stage using the real delivered pack and
normal RunScene. It measures 20 seed-0 actions, including synchronous commit
frames, input response, planned/observed playback and page loads, plus lifecycle
checks. Functional completion is separate from its reported 5 ms CPU / 16.7 ms
frame targets. Run the same opt-in probe in the actual release executable; the
older delivered-view burst does not substitute for it.
# P2 simulation checks

`test_intervention_trial` covers the isolated real continuation: authored
opportunities, exact atomic pass/expiry, complete pending snapshot admission,
stale/invalid purity, additional Work/shared Craft, deadline ties, focus pause,
failure/prefix recovery and an ordinary-room pass corpus. `test_intervention_playback`
uses the actual comparison view at 30/60/120 frame caps, reduced motion, recorded
stall pauses and destruction during prefix/draw handoff. Leaked resources fail
the registered stage even when assertions pass. These do not establish human
preference; the user's broader evaluation is deferred.

`test_game_closeout` verifies the cumulative 63-field P0 ownership ledger, P2
leaf identity and malformed admission, same-tier Reposition, the Refine T5
boundary, tool-only readiness, integrated shared-target component damage, and
last-candidate recovery inclusion. The latter uses a labelled candidate-order
double; real-RNG stream/replay checks remain separate. High-tier and locked
pieces are preserved. Probe p50/p95 use nearest rank, including small samples.

Registered `test_game_room`, `test_game_tools` and `test_game_recovery` cover
room/obstacle admission, P0 first/last-Work completion, transactional failure
injection, identity-checked tools, suppression, allowance, bounded deterministic
recovery and stream isolation. `test_game_room_replay` runs 100 explicit seeds
with mixed tools/swaps, canonical midpoint restore, stale-command rejection and
complete replay. Its new evidence goes to the runner's unique output directory,
including canonical per-seed replays and every accepted checkpoint. Direct
invocations also choose a fresh directory unless `--report-root=` is supplied.
`p2-reference.json` freezes the 100-seed, 1,194 gameplay-action (+100 Begin)
characterization from unchanged P2 semantics before closeout corrections. Each
run compares all state/event pairs to it. This cross-revision reference supplements
the hand-authored semantic assertions; it is not an independent rules oracle.
These establish simulation behavior; player teaching, pacing, release performance
and the separate intervention trial require their own evidence.

`test_game_tools` additionally witnesses the inherited P0 match-4/match-5 Craft
candidates using the frozen swaps. `test_game_room_playback` exercises typed
effects in concurrent/serial/instant/skip modes, terminal/restart gates, keyboard
target previews, rubble-pocket refill, and bounded audio/mute/cancellation using
the dummy driver. Dense-impact checks cover duplicate coalescing, the four-impact
cap and reserved UI/result voices. Headless teardown allows one mixer interval
after releasing the scene. The third cue set was accepted by the user on
2026-09-14; dense in-game listening remains a separate human observation.
`tools/game/profile_actions.gd` records repeated stage costs separately from complete transactions. It does not turn the sum of microbenchmarks into a complete-action claim. External admission and canonical identity remain mandatory.

`test_p3_preparation` validates the reserved P3 specification against inherited
fixtures, distinct reward pools, authored room/staging cells, protocol versions,
save-field inventory and available delivery bindings. Its 18 acceptance case
specifications are requirements for future executable P3 tests, not passing
implementations. See [the preparation contract](../../core/run/P3_PREPARATION.md).

The actual release matrix is `tools/game/verify_closeout_release.ps1`. It runs
the shipped executable at both native sizes, compares all frozen P1/P2 action
pairs, checks trial replay equivalence at 30/60/120 FPS and exercises isolated
missing/corrupt pack copies. Functional completion, CPU/frame targets and human
evaluation have separate statuses. The tracked `closeout-status.json` preserves
the earlier atomic closeout disposition; the successor ledger below owns current
readiness. Ignored reports retain exact measurements and failures.

## Merge-window successor

The [successor acceptance inventory](MERGE_WINDOW_ACCEPTANCE.md) and
[readiness ledger](merge-readiness-status.json) separate focused correctness from
release performance and final readiness. Registered `test_merge_kernel`,
`test_merge_commands`, `test_merge_executor`, `test_merge_playback`,
`test_merge_native`, `test_merge_replay` and `test_merge_seams` cover their named
owners. `test_merge_native` needs `-Gpu` and uses synthetic delivery fixtures;
it does not substitute for the actual packaged assets.

[Final readiness evidence](MERGE_FINAL_READINESS.md) records the passing
engineering exits, measured scope, retained failures and exact package identity.

`merge_cpu_smoke` runs 15 editor rooms through the worker with accelerated
decision clocks. `merge_characterization` measures bounded diagnostic reaction
dispatch and admitted 8/12/16-cell-wide boards separately from ordinary targets.
`test_merge_load` characterizes independent active promotion waves with linearly
increasing applied-effect counts, including copies, admission and hashes for
each wave. These intentionally heavy cases report misses without relaxing the
ordinary profile or claiming unimplemented P3 content is inexpensive.
The release runner [check_merge_release.ps1](../../tools/check_merge_release.ps1)
checks actual executable identity, completion, every failed interval and exact
repetition digests. Native mode measures rendered view changes after completed
keyboard/mouse gestures, aggregates main-thread callbacks by frame, and then runs
assisted/fault/lifecycle witnesses outside the unassisted measurements.

The frozen successor redirection vector covers deliberate new semantics. Legacy
P0/P1/P2 and trial goldens stay unchanged. Keep every failed report; a renderer
or GPU override is a distinct recorded profile, never evidence for another GPU.

## Implemented P3

[P3 status and behavioral mapping](P3_IMPLEMENTATION_STATUS.md) routes the
registered family/settings/entry/extraction/flow/replay/save/view tests.
`check_p3_release.ps1` executes packaged keyboard/mouse expedition witnesses,
save/Continue, choices and lifecycle cases. Its explicit reference inputs are
copied and hashed in each evidence directory; no source project is loaded.
Native diagnostic playbacks use assisted timing and cannot certify frame gates.
`-Mode tuning` runs immutable `first-v1` and `mixed-v1` policies on every integer
seed 1 through 100, stores every complete replay and verifies every checkpoint.
Policy outcomes are diagnostic measurements, not human difficulty judgments.
