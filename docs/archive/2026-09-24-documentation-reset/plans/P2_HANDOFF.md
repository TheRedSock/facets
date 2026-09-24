# P2 implementation handoff

## Current closeout, 2026-09-21

Engineering deliverables are complete; P3 activation awaits an explicit CPU
milestone decision. See [the execution journal](P2_CLOSEOUT_JOURNAL.md) and
[CPU decision package](P2_CPU_DECISION.md). The dated handoff below remains
historical evidence; its claim of no continuation describes production P2.
An isolated, separately versioned trial now exists without changing P2 identity.

| Acceptance area | Current evidence and disposition |
|---|---|
| Mechanics / identity | 22 integrated stages pass; frozen 2,000 P1 and 1,294 P2 Begin/action pairs retained; 63-field cumulative ownership audited |
| Playback / lifecycle | Five affected stages pass after fixing a reproduced restart/rebuild race; final r3 has ten completed actual-executable stages |
| Presentation / package | Clean runtime-only package; both native sizes, asset failure/recovery, tool controls, result tails, keyboard and cancellation verified; payload budgets pass |
| Player learning / difficulty | Deferred by user; seeds 7/1/8 have complete automated witnesses, not teaching findings |
| Dense sound / feel | Existing accepted audio unchanged; bounded voices/cancellation/mute verified; broader human observation deferred |
| CPU | P1 p95 32.637 ms, P2 37.640 ms; 5 ms target fails. Frame p95 15.803 / 15.827 ms passes the separate frame gate |
| Intervention | Real pending resolver, admitted continuation/replay and paused/400/800 ms comparison verified; decline production adoption for this milestone, retain for later review |
| P3 preparation | e0bf129 contract, four layouts, 14 named acceptance specifications and 112 structural assertions; P3 gameplay remains future work |

One optional sole-reviewer delivery: `generated/reviews/Facets-P2-Review-20260921.zip`.
Extract and run Review.cmd. The included form is not required now. Human testing
may wait until after P5 under the user's amendment. Final tested runtime checkpoint
is `f36ef46`; package/source hashes and failed iterations are preserved in
`artifacts/game/p2-closeout/20260921-implementation/`.

## Historical 2026-09-14 handoff

Status: **playable room implemented; acceptance work remains open**, 2026-09-14.
The normal Play entry opens Open seam. This handoff does not close the inherited
CPU/player-feel gates, human room evaluation or the required intervention trial.

## Checkpoints and behavior

- `95a02f7`: P1 deterministic foundation and P1-A concurrent playback committed.
- `5e71dcb`: B0 P2 policy/ownership freeze.
- `a35452f`: B1–B4 room simulation, obstacle occupancy, Work/Craft, typed tools,
  atomic rollback, deterministic recovery and exact room replay.
- `e46ecc3`: B5 functional room UI and typed concurrent/serial/instant/skip
  playback, including wave-local rubble pockets and keyboard target confirmation.
- `f746c05`: workshop assets, vocabulary, tier badges, bounded effects/audio
  infrastructure and exact package/probe work.
- `43ab9c9`: accepted-audio checkpoint promotes the ten v3 material cues, records user
  approval and exact hashes, and verifies PCM imports, dense voice handling,
  mute/cancellation and a fresh package. Its commit is recorded in the repository
  log and tests/game/p2-checkpoints.json.

Room: 8×8, four marked two-hit rubble, 16 Work, initial Craft 1 / capacity 6,
default starter roster and T1–4 weighted supply. Reposition/Chisel cost 2 Craft,
Refine 3; tools cost no Work, earn no Craft and close the allowance until the next
accepted matching swap. Complete beats final-Work exhaustion. Failed technical
caps roll back the entire action. Recovery preserves eligible instance identity
and uses only its seeded stream with at most 64 candidates.

Protocol: design `facets.prototype.v1`, profile `p2`, simulation `facets-sim-v2`,
RunState schema 2 and `facets-replay-v2`. Legacy schema/replay remains unchanged.
No continuation, intervention clock, families, carry or disk-save UI is claimed.

The shuffle helper required an explicit `self.randi_range` call; its unqualified
call resolved to the global RNG. Tool-triggered recovery exposed this replay bug.
The old game did not call this shuffle helper; its frozen corpus still passes.

## Verified evidence

- `artifacts/game/p2/simulation/checks/results.json`: 16 registered stages passed
  against a stable source tree, including all original 2,000 P1 action checkpoints
  (3,301 assertions), retained playback/motion and new room/tool/recovery checks.
- `artifacts/game/p2/simulation/room-corpus.json`: 100 explicit seeds, 1,194
  accepted gameplay actions, all three tools, canonical midpoint restore and
  exact full replay; 4,355 assertions. Outcomes: 77 complete, 23 failed. These are
  automated policy outcomes, not balance or human acceptance findings.
- `test_game_tools` now also witnesses frozen match-4/match-5 Craft candidates.
  Original P0 files, codec/action vectors and P1 goldens were not rewritten.
- `artifacts/game/p2/playback/checks/`: typed concurrent/serial/instant/skip,
  terminal/restart, keyboard targeting, direct tool and rubble-pocket checks.
- `artifacts/game/p2/presentation/audio-final-checks/`: seven-stage presentation,
  tools and retained motion/playback check run. Voice limits/mute/cancellation
  use the dummy driver; this is functional evidence, not listening acceptance.
  `audio-teardown-checks/` additionally verifies the final probe teardown change.
- `artifacts/package-build/20260914-213143-0379/report.json`: fresh runtime-only
  export, exact inventory and packaged-resource probe all passed. Staging copies
  explicit sources and UID/import metadata; workshop import remaps are admitted
  only for the manifest's named source paths.
- `artifacts/game/p2/presentation/accepted-audio-1600x900.json` and
  `accepted-audio-1280x720.json`: actual Windows executable passed full room completion,
  exact replay, restart, and all three tools through preview/confirm controls.
  Native briefing/ready/progress/result PNGs accompany each report. Agent review
  checked board/rubble, numerals, labels, counters, focus and enlarged sidebar text.
  Both loaded all ten cues, played 86 cues and verified mute/cancellation. The
  process logs also passed cleanup/error checks; a report's status alone is not
  sufficient. Earlier failed import/probe evidence remains preserved separately.

Playable package: `generated/desktop/20260914-213143-0379/Facets.exe`, with adjacent
`Facets.pck` and `gem-assets.pck`. Keep the three files together.

## Measured limits

The ten-action Open seam seed-7 witness clears the room with 7 Work left. Its
complete canonical replay is beside each executable report as `.json.replay`.
This is a reproducible winning witness; purposeful tool teaching remains human
evaluation. The separate instant tool fixtures are excluded from timings.

| Window | CPU action p95 | Frame p95 |
|---|---:|---:|
| 1600×900 | 33.350 ms | 8.426 ms |
| 1280×720 | 33.784 ms | 8.507 ms |

The measured frame target passes on this machine; the inherited 5 ms complete
action target still fails. Ten actions are a small workload, not a broad latency
guarantee. Reports retain maxima, legal-query timings, load time and work counts.
Non-gem source textures account for 280,576 decoded RGBA bytes. Font, scene and
decode overhead are not separately measured. Runtime sound sample data totals
328,320 bytes (48 kHz mono PCM16, no import compression), below the 2 MiB budget.
Loading including scene creation/audio was 117.314 / 121.319 ms respectively.

## Audio review and next work

The user rejected the first candidate set as too melodic and requested rhythmic,
sharp sounds associated with rocks, minerals, grinding, cutting, shearing and
sparkling. The second set was too close to tapping. The user supplied three local
mineral/gem references; only their structure informed the third set. No samples
were copied. The third generator combines filtered impact/granular friction with
inharmonic damped resonance, retaining a short sharp onset and a textured tail.

Accepted sample: `generated/game/sfx-resonant-candidates/audition.wav`.
Recipes: `art_source/game/audio/prototype_sfx.json`; provenance and feedback:
`art_source/game/manifest.json`. **User accepted on 2026-09-14: “Yes, use these”.**
All ten accepted WAVs are now runtime assets with hashes matching the audition
candidates and a fresh regeneration. Generation rejects nonfinite/clipped values;
PCM/header/duration/peak checks pass. Sound controls are enabled. Four impact
voices, two reserved result voices and two UI voices share a master limiter;
non-UI duplicate cues coalesce within 50 ms. Restart/skip/error/destruction stop
owned voices. The headless and executable probes wait for the mixer to consume
stop requests before quitting. Dense in-game listening remains part of player
evaluation; dummy-driver checks establish routing/lifecycle only.

Remaining acceptance:

1. Run 3–5 short player sessions covering survivor placement, rubble damage and
   at least two purposeful tool decisions; record mistakes, waiting and choices.
   Include dense in-game sound, volume/mute and restart listening.
2. Keep the inherited CPU and player-feel targets open until separately met.
3. Execute required T0–T4 in `plans/P2_INTERVENTION_TRIAL.md` after the room gate:
   real resolver continuation, paused/24/48-tick profiles, determinism/lifecycle
   tests, counterbalanced sessions and explicit adoption/revise/decline decision.
   No trial batches are implemented or claimed complete by this checkpoint.

P3 remains gated on the required trial decision. Do not infer human findings from
the automated room corpus or treat committed presentation snapshots as a parked
authoritative resolver.
