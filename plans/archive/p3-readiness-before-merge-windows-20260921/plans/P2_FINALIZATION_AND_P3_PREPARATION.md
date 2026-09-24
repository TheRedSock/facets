# P2 finalization and P3 preparation

Status: **engineering deliverables complete, 2026-09-21; P3 activation awaits explicit CPU disposition.**

Current results are in [the execution journal](P2_CLOSEOUT_JOURNAL.md), the
tracked `tests/game/closeout-status.json`, and the source-adjacent
[P3 preparation contract](../core/run/P3_PREPARATION.md). The dated starting
assessment and original gate wording below remain historical. The user amendment
immediately below supersedes their human-session requirements. T4 now declines
production adoption for this milestone and retains the isolated trial; P3 is
specified around whole atomic actions. The one build/form is delivered under
`generated/reviews/Facets-P2-Review-20260921.zip`. All 22 integrated stages,
five corrected-playback stages and ten final executable witnesses pass. P3
activation still needs [the CPU decision](P2_CPU_DECISION.md), because measured
P2 p95 is 37.640 ms against 5 ms.

**Execution amendment, user direction 2026-09-21:** the user is the sole reviewer
at this stage and does not expect human review, trialing or focus testing until
much later, potentially after P5. Deliver one verified build and review form.
The participant/session requirements below are deferred human acceptance work,
not blockers to engineering P3 preparedness. Do not fabricate findings or treat
one reviewer as representative or omniscient. Execute the engineering trial and
record its results, retain atomic production as the conservative default, and
leave player-feel claims and any production intervention adoption for later review.
P3 readiness now means the engineering gates and contract package are complete,
with human-evaluation debt explicitly carried forward. The CPU target remains
unchanged; this amendment does not waive technical correctness or verification.

Finish the existing tactical room, reconcile its inherited foundation and evidence,
complete the required intervention experiment, then freeze P3's contracts. Do not
restart P2's completed batches or implement the expedition against an undecided
continuation model. P3 preparation can begin now; production integration follows
the gates below.

This review read the seven active plans, the twelve active system/design documents
in `docs/` plus its index, relevant gameplay/presentation/delivery contracts,
test/runner guidance, and selected implementation and evidence files. Historical
archives were used through their active references, not re-audited in full. No
runtime changes, Godot test reruns, new release measurements, player sessions or
optical review are claimed by this planning task.

## 1. Authority and verified starting point

Use [P0](../docs/P0_BASELINE.md) for frozen decisions; the
[phase plan](../docs/PROTOTYPE_BUILD_PLAN.md), [game design](../docs/GAME_DESIGN.md)
and [content systems](../docs/CONTENT_SYSTEMS.md) for intended scope; current
source-adjacent contracts for implemented behavior; and phase handoffs for dated
evidence. A discrepancy needs an explicit disposition, not an automatic choice
of whichever document is newest. Engine-readiness P0–P5 is a separate workstream
from prototype P0–P6.

The reviewed tracked tree was clean at `43ab9c9` (accepted P2 audio). The checkpoint
sequence is `95a02f7` P1/P1-A → `5e71dcb` policy → `a35452f` room simulation →
`e46ecc3` playback/UI → `f746c05` presentation/package → `43ab9c9` accepted audio.

Fresh read-only identity evidence is in
[inventory.json](../artifacts/game/p2-p3-planning-20260921/inventory.json), generated
by [verify_inventory.ps1](../artifacts/game/p2-p3-planning-20260921/verify_inventory.ps1):

- All 19 frozen P0 files and the tracked fixture case file match the baseline.
- All 223 sources listed by the latest P2 package report match the current files;
  all three release files match their recorded hashes.
- The P1 checkpoint ledger contains 2,000 pairs; its preserved source report
  matches the ledger's source hash. This does not re-execute those checkpoints.
- Stored P2 simulation/playback/audio/teardown reports contain respectively
  16/7/7/2 completed, passing stage records. These are historical results.

| Workstream | Current status | What still prevents acceptance |
|---|---|---|
| P0 | Frozen decisions, fixtures and delivery baseline exist | Preserve their bytes and resolve remaining fixture ownership cumulatively |
| P1 | Deterministic action/state/replay foundation implemented | Revalidate retained invariants when shared code changes |
| P1-A | Concurrent ordinary motion and lifecycle checks delivered | Complete-action CPU p95 target and human feel review remain open; cross-wave overlap is explicitly deferred |
| P2 B0–B6 | Open seam, rubble, tools, Craft, recovery, functional UI and accepted audio implemented | Fresh coverage audit; release gaps; human seed/teaching/dense-audio evaluation |
| P2 B7 | Automated room evidence recorded | 3–5 short player sessions and resulting corrections |
| Trial T0–T4 | Required, unimplemented at this checkpoint | Real continuation, paused/timed comparison, player evaluation, decision |
| P3 | Design exists; expedition systems are not implemented | Trial decision and reviewed reaction/transition/save contracts |

Historical latency remains a material gap: P1-A release corpus p95 **39.907 ms**;
P2's ten-action release witness p95 **33.350 / 33.784 ms** at 1600×900 / 1280×720.
The corresponding P2 frame p95 is **8.426 / 8.507 ms**. Different workloads cannot
establish a speedup; neither frame timing nor the small winning witness meets the
**5 ms complete-action p95** target. The P2 automated corpus's 77 wins / 23 losses
over 100 seeds is a policy result, not human difficulty acceptance.

## 2. Execution order and completion gates

```text
S0 evidence preservation + reconciliation + source/test audit
  → C1 minimal corrections + fresh functional baseline
  → C2 latency investigation/remediation + release candidate
  → C3 room player sessions + targeted iteration → ROOM GATE
  → T0 → T1 paused → T2 timed → T3 paired sessions → T4 decision → TRIAL GATE
  → R0 P3 contracts/fixtures/version freeze → P3 IMPLEMENTATION READY
```

P3 content inventories, fixture sketches, asset coverage and save-state field
inventories can be prepared alongside closeout. Do not freeze production episode,
reaction-cap or persistence behavior before T4. A test harness used to review the
trial is not permission to ship its mechanic.

| Gate | Required exit | Failure disposition |
|---|---|---|
| S0 audit | Each inherited requirement has an owner, source/test anchor, evidence class and disposition; blockers have reproductions | Fix correctness/evidence blockers in C1 before relying on their results |
| Room | Functional/release matrix passes; teaching seeds and 3–5 player sessions support survivor/rubble understanding and at least two purposeful tool choices; dense audio and feel reviewed | Revise the smallest responsible room, teaching or interaction issue and retest |
| CPU | Complete-action p95 ≤5 ms on the declared ordinary 8×8 workload; maxima and stress cases reported separately | Keep open. If remediation needs a larger change, present measured options for an explicit milestone decision; do not quietly move it to P5 |
| Trial | T0–T4 evidence and explicit adopt / optional challenge / decline outcome | Revise-and-retest remains open until a follow-up disposition; missing participants also leaves it open |
| P3 ready | Room/trial exits, audited contracts/fixtures, versions and remaining-risk ownership agreed | Preparatory work may continue, but do not call the phase implementation-ready with unowned blockers |

The room acceptance and trial are distinct records. Full closeout must also state
the inherited CPU result. If an explicit decision permits progression with the
latency gate open, retain the failed target and bounded follow-up in the handoff;
such a decision is not a performance pass. No waiver is made by this plan.

## 3. Step 0 — reconcile before extending (S0)

### S0.1 Preserve a reproducible review baseline

Create a new run directory under `artifacts/game/p2-closeout/<run-id>/`. Record
HEAD, working-tree status/diff, relevant source/content hashes, Godot and export
template versions, package/catalog hashes, machine, test policy and seed inputs.
Snapshot the current P0/P1/P2 evidence index before any new test invocation.

**Fix the report destination hazard first.** `tools/check_engine.ps1` writes
`artifacts/checks`; `tests/game/replay_corpus.gd` writes the original P1 report path;
`test_game_room_replay.gd` overwrites the P2 summary; the registered action probe
also has a fixed path. Add an optional output root, propagated through the runner
and report-producing checks, with distinct new-run outputs. Alternatively use a
verified isolated workspace for the first rerun. Merely copying logs afterward
does not protect a historical file already overwritten. Preserve original reports
and checksums, including failed attempts.

Record a full P2 command/checkpoint corpus before semantic changes: the current
room replay test repeats and restores its own execution, but its saved summary
contains counts rather than independently frozen per-action expectations. Reuse
the explicit seeds 1–100 and current arithmetic command-selection policy, name
that policy, and capture accepted commands, state/event pairs and initial snapshot
identity. Independently review small semantic cases before approving new P2
reference vectors. Never regenerate P0/P1 goldens to make corrections pass.

Deliver: baseline manifest, evidence index, safe output routing, candidate P2
checkpoint corpus and a reviewed reference disposition. A changed P2 outcome is
a rule/protocol decision or a documented defect correction, not an optimization.

### S0.2 Reconcile document and status drift

| Finding confirmed in this review | Required reconciliation |
|---|---|
| Root README still describes an early board demo; phase-plan header emphasizes P1-A despite its later P2 section | Update current navigation/status to the playable atomic P2 room with explicit open gates; avoid implementation inventories in root guides |
| P2 implementation plan mixes completed batches with “proposed checks” / “not runnable today” and old pre-implementation source findings | Add a clear historical-planning boundary and current command/status route; retain original review evidence |
| Presentation spec says assets have not been generated, while later text records accepted v3 sounds | Mark the delivered P2 subset and identify the manifest/recipes as its current authority |
| Presentation sound table still describes melodic sine/chord recipes rejected during P2 | Preserve as historical candidate direction; future family/extraction cues should follow the accepted sharp mineral/friction/resonance palette and be auditioned separately |
| Integration/rewrite prose recommends sequential playback; later P1-A/P2 contracts deliver concurrent ordinary motion | State that sequential playback is the diagnostic reference and conservative fallback, not the normal-room default; retain source-review date context |
| P0 baseline and fluidity assessment contain old “unstarted” / optional-trial prose | Do not rewrite frozen/historical evidence. Route current execution to handoffs and the required trial; the fluidity assessment already has a superseding addendum |
| `fixture-disposition.json` is a P1 coverage ledger; `p2-checkpoints.json` separately records later inherited fields | Create a cumulative requirement/field coverage view; preserve the historical ledger's meaning and the frozen fixture bytes |
| Prototype milestone prose can suggest save/resume is only vertical-slice work | Make clear that implemented P3 state needs complete stable-boundary disk persistence and Continue; broader accessibility/polish remains P4/P5 |

Use additive status notes for active historical reviews. If replacing a document
wholesale, archive its original bytes and verify a checksum manifest before
updating links. This new plan supplements the existing detailed P2/trial plans;
it does not replace their semantics or report milestones complete.

### S0.3 Audit earlier phases by invariant, not pass count

Create `audit-matrix` with one row per requirement/frozen field: phase/decision ID,
current source function, test/assertion, recorded evidence, fresh evidence,
severity, correction owner and closure condition. Classify rows as confirmed,
regression, incomplete coverage, historical wording, or deliberately deferred.
The following is the minimum review scope, not a claim these are newly found bugs.

| Area and source owners | Review and required witnesses |
|---|---|
| P0 baseline / fixture adapters | All 23 cases and every expected field accounted for. Match-4/5 Craft, first/last-Work win and recovery now have P2 witnesses. `outlet_delivery` transfers to P3; `seal_removed_before_merge` remains P6. Keep the 113 historical smoke dispositions and intentional changes explicit |
| P1 legality / topology — `core/board`, `action_legality.gd` | Pure rejection, directed survivor choice, connected intersections, portals excluded from matching, spawn-entry policy, zero-gravity fallback, nine topology cases and bounded 16×16 support |
| P1 identity / replay — `run_state.gd`, `canonical_codec.gd`, `replay_record.gd`, stream bank | Every mechanical field, exact integers, all stream positions, IDs/counters, immutable content, malformed-version rejection, clone isolation; original codec/action bytes and 2,000 P1 state/event pairs |
| P1/P2 transactions — `action_transaction.gd`, `room_transaction.gd`, `resolution_budget.gd` | Rejection versus technical failure versus gameplay loss; complete rollback after costs, target effect, promotion/spawn, obstacle break, Craft and before publication; no side effects from repeated ack/skip |
| P1-A motion — `motion_plan.gd`, `action_player.gd` | Same-wave concurrent journeys and spacing, shorter falls, pre-gravity chain visibility, retained custom paths, cancellation during every new await; include P2 wave-local rubble pockets |
| P2 room/admission — `room_definition.gd`, `room_state.gd`, `state_admission.gd` | Raw obstacle collisions/IDs/durability, marked/unmarked rubble, source-footprint hit deduplication, two components hitting one target, stable-boundary victory, terminal restore, no post-completion recovery |
| P2 tools/economy — `room_action_legality.gd`, `tool_resolver.gd`, `craft_policy.gd` | Costs and allowance sequence; stale IDs; explicit target layers; T3/T4 Chisel and T4/T5 Refine boundaries; direct and cascade wins; strongest-match/cap/clipping; all tool descendants suppressed |
| P2 recovery — `recovery_resolver.gd`, `room_boundary_resolver.gd` | Tool-only ready state; high-tier/locked identity preservation; exact dedicated-stream shuffle; zero-draw shortfall, final-candidate success/exhaustion, cap rollback and restore without recovery rerun |
| P2 presentation — RunScene, RoomHudModel, RoomPanel, RoomAudio | Current costs/disabled reasons, immutable projections, focus and target preview, independent input gates, cue cancellation/mute/voice limits, no state mutation from views |
| Delivery / packaging | Exact inventory/import remaps, resource hashes, no source-art/Atelier leakage, actual executable lifecycle evidence, all live page owners rather than cache count only |

Inspect missing edge coverage before adding tests. Add tests for a demonstrated
gap or changed behavior; do not duplicate existing assertions merely to increase
counts. Do not expand optical verification when the change is gameplay-only.

### S0.4 Review the actual P3 extension points

These source findings constrain the implementation plan:

| Current implementation | Consequence for P3 / trial |
|---|---|
| `TurnController.execute_turn` runs the full loop; `prepare_turn` precomputes it and `step_cascade` reads presentation steps | T1 requires a real resumable resolver and admitted pending state. A paused animation is insufficient |
| `ActionContext.match_step` records source snapshots and directly applies fixed one-point obstacle damage; `CraftPolicy` has `bonus_candidate: 0` | Add bounded family dispatch at the causal match boundary. Corundum replaces the base damage amount; never add an accidental second hit. Separate best base, raw bonus, capped award and actual gain |
| `ActionContext` has a cause and reward restriction but no implemented family-use/continuation state | Define action/episode scopes and inherited suppression explicitly; extraction cannot erase legitimate earlier earnings or restore eligibility to descendants |
| `RoomDefinition` admits only clear-marked-rubble; the boundary resolver knows only that objective | Add typed outlet/demand admission and stable extraction in the resolver; do not implement delivery counting in scenes |
| `start_room` bootstraps a fresh starter catalog/streams/session and `_publish_session` clears the command record | It is a standalone room API, not an expedition transition. Add a run-owned transition that preserves roster/settings/RNG/replay and uses a distinct room snapshot notification |
| New boards start with namespace `piece` and allocator 1; opening generation only copies initial obstacles | Carry needs explicit staging and run-wide noncolliding identity. Reusing `start_room` would risk resetting identity/history; opening retries must preserve carried records |
| Runtime tile resources currently supply no family tags; bootstrap reads them into mechanical catalog identity | Introduce curated P3 metadata with explicit content identity; prevent new defaults from silently changing P1/P2 controls or old replay expectations |
| `autoloads/save_service.gd` writes arbitrary JSON directly to the final path | Replace/adapt it for bounded, versioned, exact-integer, atomic admitted saves. Its existence does not establish Continue support |
| GemForge prepares one upcoming set; RunScene currently preflights the active roster | Review reward/carry/old-board overlap and cancellation. Extend ownership only if tests show the current API cannot support the needed transition |

Deliver a focused source review with code anchors and reproductions, including
“no correction needed” dispositions. Do not turn this audit into a framework
rewrite or implement P3 just to repair documentation.

## 4. Finalize the atomic room

### C1 — correct demonstrated gaps and establish a fresh baseline

Dependency: S0 preservation and audit. Relative size: bounded, findings-dependent.

Fix correctness, invalid admission, evidence overwrite, stale presentation and
misleading player text before new content. Every mechanical correction updates
its owning contract, regression expectation and compatibility decision. Preserve
the existing P1 mode and byte vectors. A new observation is not permission to
rewrite an old baseline. Record deferred low-impact cleanup separately.

Run the affected registered suites, then one integrated foundation/room run after
the corrections converge. Keep stage completion markers, full failed-process
classification, source stability and report provenance. The runner's source hash
selection does not cover all shipped media/project/export inputs; supplement it
with the package/presentation manifest hashes.

Exit: no unresolved correctness/identity/rollback/lifecycle blocker; the cumulative
fixture matrix and fresh checks agree; P2 cross-revision reference evidence is
preserved and its intended changes explained.

### C2 — latency and complete release coverage

Dependency: C1. Relative size: uncertain; profile before estimating optimization.

Measure complete accepted actions, pure legality/enumeration, startup and playback
separately. Use the retained P1 100-seed control plus the explicitly identified P2
mixed-command corpus; report tool, recovery and near-cap/stress cases separately.
Record p50/p95/max, sample counts, work/facts/segments and allocations if measurable.
Timing must include cloning, resolution, boundary/recovery, candidate validation,
fact projection, hashes and publication. Measure debug and actual release apart;
do not time movie capture as performance.

Profile canonical encoding, immutable catalog copying, final re-admission, scans
and availability enumeration first. Introduce caching or an internal validator
only with explicit immutability/invalidation rules and equivalent invariant tests.
Do not weaken external admission, identity, fact ordering or rollback to reach
the target. Avoid speculative threading or a different gravity scheduler.

Build a fresh isolated package after corrections, preserve its three-file bundle,
and exercise the actual executable. Audit existing probes before extending them:
the current room probe covers seed-7 completion/replay/restart and separate tool
fixtures, not the entire B7 release matrix.

Required release witnesses: Begin; each tool through preview/confirm/cancel;
invalid/stale input; a natural Work-exhaustion loss; final-Work victory; board-lock
diagnostic fixture; restart/skip during travel, direct effects and result tails;
menu/navigation cancellation; keyboard/focus; mute/volume; missing/corrupt pack;
required UI/SFX load error; explicit simulation failure and recovery controls.
Clearly label authored diagnostic fixtures versus ordinary player play.

Capture native 1600×900 and 1280×720 UI/motion, input-to-first-visible-response,
commit-frame stalls, full frame distribution and forced waiting. Require no
additional cold gem loads in the declared warmed burst. Measure gem payload,
non-gem textures and decoded audio separately (targets 16 MiB / 16 MiB / 2 MiB),
and state unmeasured font/scene/decode overhead. Retain accepted audio hashes;
do not reopen sound generation without a demonstrated problem.

Exit: a reproducible release candidate and completed lifecycle matrix, plus a
CPU pass or a concrete measured open-gate decision package. P5 later repeats these
checks under expedition load; it does not retroactively supply P2 evidence.

### C3 — seed vetting, room sessions and closeout

Dependency: usable corrected release candidate. Relative size: participant and
iteration dependent; reserve this as actual human work.

Select a small named teaching set including the seed-7 winning control, at least
one different tactical opening and a reproducible failure sequence. Save their
complete command witnesses and content hashes. Seed 7's ten-action win with
7 Work remaining is only a winning witness; it does not prove intentional tool
teaching or appropriate difficulty. Expose vetted selection in a development
entry/launcher without turning debug actions into the player flow.

Run 3–5 short sessions. For each record build/seed, familiarity, instruction given,
survivor predictions, rubble-rule explanation, at least two purposeful tool
decisions, mistakes/rejections, Craft earned/wasted/spent, outcome, decision time,
forced waiting, stalls and sound comments. Across sessions exercise all three
tools; do not script a player's supposed preference. Include dense cascades,
volume/mute and restart listening. Allow individual failed runs; evaluate whether
the cause was understandable and decisions were meaningful.

If tool use merely bypasses matching, Craft opportunities are opaque, or waiting
dominates, adjust teaching/layout/feedback first. A required economy change uses
a reviewed successor rules profile and fresh evidence. Recheck affected cases
and repeat relevant sessions after changes. Missing participants remains an open
gate; bot outcomes, agent inspection and accepted audio audition cannot replace it.

Deliver an updated [P2 handoff](P2_HANDOFF.md), checkpoint ledger and phase status
with independent statuses for mechanics, presentation/package, player learning,
dense audio/feel, inherited CPU, and trial. Record the room gate separately from
the downstream experiment. Retain unsuccessful observations.

## 5. Required intervention trial — execute T0–T4

The [trial plan](P2_INTERVENTION_TRIAL.md) remains authoritative. C3's room gate
precedes player evaluation of this experiment. Freeze/correct resolver seams first;
do not let trial work obscure the baseline room's remaining issues.

| Batch | Concrete deliverable and exit |
|---|---|
| T0 | Separate experimental rules/command/replay IDs and hand-explained fixtures: surviving promoted instance `(2,3)`, intended `(1,3)/(1,4)/(1,5)` line; automatic-chain-consumed opportunity; no legal opportunity; occupied/ineligible/stale targets; zero/one remaining Work; near-cap continuation. Define selection among multiple eligible survivors and exact offer boundary deterministically before code |
| T1 | Park a real resolver after automatic chains and before gravity. Snapshot/restore board, RNG, allocators, phase, pending work, causal counters, limits, earnings, scoped uses and window identity. Commit validated prefix; each decision/continuation segment is atomic. Failure retains prefix in a diagnostic state with restart. Pass matches control semantics/RNG after explicitly removing mode-only identity |
| T2 | Paused plus 60-Hz logical-clock profiles with 24/48-tick deadlines. Start clock at zero only after boundary presentation; tick `< deadline` may accept, tie/late expires. Record start/input sequence/decision/pass/expiry/pause/focus changes. Same admitted stream under 30/60/120 render FPS, stalls and reduced motion gives identical results |
| T3 | 3–5 counterbalanced qualitative sessions on matched opportunities across atomic, paused, 400 ms and 800 ms profiles; include planning-preferring players. Record frequency, chosen benefit, mistakes, Work/Craft consequences, waiting and preference. Test both timed profiles even if paused wins the first comparison |
| T4 | Build/profile/fixture identities, determinism/lifecycle results, recordings, findings and explicit adoption disposition. A revise outcome includes a concrete retest and remains open |

One accepted intervention costs one additional Work; no offer at zero Work.
Pass/invalid costs nothing. At most one intervention per normal-swap episode,
involving an eligible surviving promoted instance and stationary orthogonal gem,
creating a match involving a swapped piece. Share Craft/family budgets, technical
caps and one normal-turn hazard boundary. No tool allowance refresh, early Craft
spending or tools during resolution. Suppression is inherited. Speculation cannot
consume authoritative RNG or publish state.

Test pause/focus, expiry ties, queued/stale commands, restart/navigation at a
window, failed continuation and reduced motion. Do not repeatedly reset a budget
per segment. Clock behavior under render stalls must not make the visible window
misleading; revise before evaluating players if it does. Save to disk only at
stable episode boundaries unless a separately reviewed production policy expands
that support; complete in-memory trial continuation restore is still required.

| T4 decision | P3 consequence |
|---|---|
| Decline | Keep atomic production actions and stable-only saves; retain useful tested resolver seams without shipping window UI |
| Optional challenge | Keep the expedition atomic unless separately approved; isolate challenge protocols and persistence. Supporting a second production mode needs its own scope/acceptance decision |
| Adopt in main mode | Freeze production episode/subcommand, cost/reward, failure and save-boundary contracts before families/rewards; retain atomic control |
| Revise/retest | Continue the bounded experiment; no P3 contract freeze yet |

This plan does not select the outcome in advance. Unrestricted moves while falling,
transient matches, multiple windows and transport interception remain out of scope.

## 6. P3 preparation and implementation handoff

### R0 — produce the contract/fixture package

Preparation can start during C1–C3, with T4-dependent fields explicitly provisional.
Final freeze follows the room/trial gates and any recorded latency disposition.
Deliver `plans/P3_IMPLEMENTATION_PLAN.md` then, with these resolved contracts:

1. **Run identity and phases.** Define expedition state versus current room state;
   monotonic instance/action/event/removal allocation across rooms; recorded carry,
   reward, route and next-room commands; phase/revision rejection and explicit
   room-start snapshot publication. Never clear the expedition replay at a room
   transition. Specify restart-room versus restart-expedition controls explicitly.
2. **Protocol compatibility.** Reserve a new P3 profile/state/replay identity before
   reference capture; retain codec/stream/settling versions only if unchanged.
   Name supported old P1/P2 paths and explicit unsupported-version errors. Make
   family metadata/profile loading compatible with preserved control snapshots.
3. **Reaction ordering and budgets.** Pre-upgrade source identity, frozen component
   footprint, base outcome then bounded ordered intents, live-target revalidation,
   applied/skipped reasons and one shared budget. Specify terminal T8 eligibility:
   source-family effects must follow admitted content, while Beryl has no survivor
   target. No duplicate generic removal/subtype awards.
4. **Transition economy/content.** Carry up to two remaining T4+ IDs; no extracted
   pieces; preserve tier and clear temporary statuses. Convert T5 carried Sapphire
   to Aquamarine after reward with the same ID/tier and no triggers. Entry Craft is
   `max(1,min(3,carried Craft))`, then the one-time bonus, capped at 6; new Work and
   tool allowance reset. Steady Hand use resets per room.
5. **Opening and staging.** Admit staging cells/carry order/capacity; preserve
   carried pieces unchanged while retrying surrounding population. No free setup
   matches, at least one legal swap, bounded attempts and explicit invalid content
   on exhaustion. Reserve carry IDs before allocating new pieces; prior run state
   survives failed preparation. Select an explicit run-owned board-stream policy.
6. **Extraction/terminal boundary.** Typed outlet/minimum-tier/lock conditions,
   qualifying gems in `(y,x)` order, one removal identity per extracted gem, one
   demand unit each; stop when demand completes. Incomplete extraction resumes
   settling under suppression, within the same action/episode and budget.
   Completion beats final-Work failure and stops further refill/hazard/recovery.
   Keep dust/seal production rooms deferred; only admit concrete capability rules.
7. **Offers and routes.** Three distinct legal offers, no duplicated fallback:
   Aquamarine, unowned Steady Hand, unowned Beryl Bridge, one +1 next-room Craft
   fallback. Check every first-choice combination leaves a valid second offer
   screen. Define deterministic roll order and persisted offer IDs/selections;
   rewards/routes use their own streams. Reopen/reload never rerolls. Define
   Beryl Bridge's eligibility with starter Emerald access explicitly.
8. **Saves and presentation preparation.** Enumerate every stable run phase that
   can save/restore, including unresolved offers and carry/route selections. Save
   catalog/rules/content identity, board and carry, counters/settings, one-time
   bonus, offers/routes, replay position and complete stream/allocator states.
   Separate user presentation preferences. Preflight all displayed reward/roster/
   carry roles before finalizing a choice; failed/retried loads preserve displayed
   offers and the last committed run without spending RNG.

The run flow stays: Open seam → carry → reward → two-card route → selected
six-rubble seam or three-T3+ commission → carry → reward → Vault T5+ → results.
All four room definitions serve a three-room run. No extra reward follows the
finale. Existing art/bindings for starter eight plus Aquamarine are the baseline;
new optical studies are not a P3 prerequisite.

### P3 batches to prepare, then execute after R0

These are implementation destinations, not already existing classes or runnable
new tests. Each batch lands its focused contracts/tests and minimal usable
presentation; the last UI batch integrates coverage rather than postponing it all.

| Batch / dependency | Owners and concrete work | Exit evidence |
|---|---|---|
| P3.1 — R0 | `core/game`, `core/rules`, `data/tiles` / family data: curated Quartz/Corundum/Beryl; one bounded dispatcher/typed intents; eligibility and bonus settlement | Quartz +1 once within cap; Corundum replaces adjacent damage with 2; Beryl lowest T1–3 neighbor with `(y,x)` tie, no-target does not consume use, induced chain cannot reactivate it; source-family promotion, suppression, stale-target/conflict and cap rollback fixtures |
| P3.2 — 1 | Catalog/roster and settings: Sapphire→Aquamarine; Steady Hand; Beryl Bridge; explicit preview/effective cost/range | Complete before/after ladder and family access; conversion identity preserved; discounts spent only on accepted Chisel, once per room; no duplicate settings or hidden supply changes |
| P3.3 — 2 | Run lifecycle/opening: carry selection, staging, fresh room population, entry economy and retained run allocators/streams | Zero/one/two carries, stale/duplicate selections, conversion, staging failure/retry, ID collision prevention, no setup rewards, exact new-room replay |
| P3.4 — 1, 3 | Objective admission/resolution: commission and Vault, outlets and rubble gates, unique extraction removal and suppressed continuation | Frozen `outlet_delivery` fields; threshold/blocked outlet, ordered simultaneous candidates, last-Work delivery, no double delivery/carry/T8 payout, no work after completion; a scripted witness per objective |
| P3.5 — 2–4 | Expedition orchestration: four definitions, three-room run, two rewards and one route; once-only offers, compatibility filtering | Every route and reachable reward sequence admitted; no empty/duplicated offers, no RNG consumption on reopen/rejection; successful and failed full-run replays, persistent command history |
| P3.6 — state evolves in 1–5 | Save boundary / SaveService: canonical payload or exact-integer envelope, schema/content admission, safe slot names, temp-write/verify/replace and last-known-good file; Continue UI only once supported | Restore each stable gameplay/selection phase; injected interrupted write, corrupt/truncated/incompatible file, >2^53 RNG values, no silent fresh run, no offer reroll; active state preserved on failure |
| P3.7 — alongside each feature, integrate after 5–6 | RunScene/app panels, immutable view models, ActionPlayer/cue mappings, GemForge preflight, explicit export inventories; headless tuning runner under `tools/game` | Full keyboard/mouse expedition, carry/reward/route/family/extraction explanations; remaining four cues auditioned against accepted palette; native release/lifecycle/asset-overlap checks; named rules+seeds+policy produces exact digests/outcomes |

Persistence schema and in-memory replay evolve with each batch; P3.6 is disk I/O
and fault/lifecycle integration, not a late discovery of missing mechanical state.
If intervention is adopted, integrate its versioned episode model in R0/P3.1
before attaching family caps; never bolt it on after reward/save implementation.

P3 verification should add focused family, settings/roster, carry/opening,
extraction, expedition-choice, disk-save and presentation suites to the maintained
registry. Register their actual names/markers/timeouts when created. Retain P1/P2
controls and a ≥100-seed manifest per declared expedition policy/build, with no
failed seed discarded. Paired authored fixtures must demonstrate at least two
useful build lines: Quartz funding a tool, Corundum improving clearance, Beryl
through Aquamarine changing a planned cascade. Bot success does not prove choice
quality; a universally mandatory reward is a tuning defect.

The tuning runner must accept immutable profile/seed/policy inputs and report
outcomes/reasons, Work/Craft, highest created/extracted tier, carry, reactions,
tool use, recovery/caps, timing and exact state/event identity. Keep policy RNG
independent from rule streams; no live tuning of an existing run.

## 7. Verification commands and evidence protocol

The following stage names are registered now. **Run them only after S0 report
preservation/output routing is in place**, with outputs directed to a fresh run.
The current runner has no output-root parameter; do not pretend one exists.

```powershell
& ./tools/check_engine.ps1 -Only import,source_check,test_smoke,test_rng_cross_platform,test_board_consumer,test_run_delivery,test_game_rules,test_game_state,test_game_transaction,test_game_replay,test_game_playback,test_game_motion,test_game_room,test_game_tools,test_game_recovery,test_game_room_replay,check_presentation_content,test_game_room_playback
& ./tests/test_check_result.ps1
& ./tests/test_check_process.ps1
& ./tools/check_engine.ps1 -Gpu -Only game_action_probe
& ./tools/build_game_package.ps1 -AssetPack generated/gem-assets.pck -Probe -FrameBudgetMs 16.7
```

Runner/process tests are especially relevant if S0 changes output orchestration.
The legacy GPU action probe remains a separate control. The current room probe
is an executable opt-in, not a registered `game_room_probe` stage. Against the
freshly built executable, use an absolute, new report path:

```text
Facets.exe --resolution 1600x900 -- --room-probe=<absolute-new-report.json> --room-screenshots
Facets.exe --resolution 1280x720 -- --room-probe=<another-absolute-new-report.json> --room-screenshots
```

Check process exit, expected completion marker, Godot errors/cleanup, source/build
identity and required observations, not only report `status`. Record environmental
failures separately. Headless/dummy-audio checks establish functional behavior;
native release recordings and human listening/playing establish their respective
claims. Preserve exact canonical replay files alongside readable JSON summaries.

## 8. Handoff requirements and first action

The closeout handoff must link baseline/integrity evidence, audit matrix and
correction dispositions; protocol decisions; fresh complete checks and package
hashes; witness commands; player findings and iterations; CPU/frame/waiting/memory
results; trial profiles/decision; and the reviewed P3 contract/fixture package.
Every open item needs an owner, prerequisite and measurable exit. Do not label
all of P2 “done” because B7's automated subset passes.

**First execution task: S0.1–S0.4, then C1 only.** Produce the preserved evidence
bundle, reconcile current status, audit the actual invariant coverage, and fix
demonstrated foundation/room defects. Keep latency remediation, room playtests,
trial implementation and P3 implementation as separately reviewable checkpoints.

Scope exclusions remain: new families beyond three, extra settings beyond two,
shops/currency, dynamic grade/cut techniques, seals/dust gameplay, transport rooms,
map-editor UI, unrestricted realtime input, broad scene/framework rewrites and
optical rebakes without a specific accepted art requirement. P4 owns broader art,
theme pivot, gallery and accessibility polish; P5 owns full-prototype acceptance;
P6 owns the expanded six-room content.
