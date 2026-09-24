# Current repository state

As of 2026-09-24. This is an orientation, not a new verification run.

## What exists

Facets is a Godot gemstone match-3 merge roguelike. Two separate foundations exist:

| Workstream | Implemented state | What this does not establish |
|---|---|---|
| Offline gemstone engine | Authoring, cut compilation, material/lighting requests, optical rendering, clips, printing, delivery and desktop packaging; engine P0–P5 accepted in the dated report | Final game art direction, every mineral phenomenon, or acceptance of new content |
| Game prototype | P3 engineering batches complete: repeated paid merge-window interventions, three family reactions, three-room expedition across four authored room definitions, rewards, carry, route choice and disk Continue | Human learning, balance, listening quality, reaction comfort or a finished presentation |

The P3 engineering checkpoint is `31ce6bfb4fe3faa4805538339c860d2d4206f90f`.
The dated report identifies runtime checkpoint `64b689e`, harness correction
`c7a1b47`, exact r6 package identity and the scope of earlier measurements.
These are evidence references, not a claim that an arbitrary later checkout is
byte-identical. Recheck identity before reusing a result.

The current game uses the merge-window successor. Original atomic P1/P2 and the
earlier intervention trial remain diagnostic controls with their own identities.
Do not apply their resolution, save or timing assumptions to P3.

## Where to inspect or run it

- [Project overview](../../README.md) and `project.godot` for development.
- [Fresh-machine setup](../BUILDING.md) for installations and missing generated assets.
- [P3 verification and tested bundle](../../tests/game/P3_FINAL_VERIFICATION.md)
  for the exact reviewed engineering build, download path and optional user form.
- [Current mechanics](../design/MECHANICS.md) for a compact gameplay explanation.
- [Engineering boundaries](../engineering/BOUNDARIES.md) for owner/source routes.

## Presentation state

P2/P3 provide functional controls, workshop assets, cues and baseline gemstone
deliveries. They do not constitute the target aesthetic for the remaining work.
The user reports dissatisfaction with UI, sound, rubble and the limited use of
the gemstone engine. That is current product feedback; this documentation task
has not independently played, visually reviewed or listened to the build.

The existing ten material-resonance cues were accepted as P2 assets. Their
provenance remains valid; that historical acceptance does not prevent a new sound
direction. The earlier rejected sine/chord recipe proposal is archived and must
not be mistaken for a current regeneration instruction.

P4 design exploration and presentation production remain ahead. The
[remaining plan](../../plans/prototype/README.md) now begins by demonstrating a
target experience before expanding its asset and screen coverage. No new art
direction, asset set, API redesign or gameplay change is selected by this cleanup.

The user's subsequent [anchors](../design/USER_ANCHORS.md) clarify gemology-led
collection/build identity, physically grounded but stylizable output, repeatable
AI-assisted asset production and future phone-class performance. Current mechanics
are open to design critique. These clarify the next investigation; they do not
change the implemented P3 behavior or its recorded evidence.

## Evidence and limits

| Need | Authoritative starting point |
|---|---|
| P3 implementation and engineering exits | [Final verification](../../tests/game/P3_FINAL_VERIFICATION.md), [checkpoint map](../../tests/game/P3_IMPLEMENTATION_STATUS.md) |
| P3 behavior and compatibility | [P3 contract](../../core/run/P3_PREPARATION.md), [merge-window contract](../../core/run/MERGE_WINDOW_PREPARATION.md) |
| Successor foundation evidence | [Merge readiness](../../tests/game/MERGE_FINAL_READINESS.md); historical foundation, before completed P3 content |
| Engine capability and measured limits | [Engine readiness report](../ENGINE_READINESS_REPORT.md); engine P0–P5, dated 2026-09-13 |
| Runtime delivery guarantees | [Delivery contract](../../core/delivery/CONTRACT.md) |
| Original mechanics reference | [Frozen P0 baseline](../P0_BASELINE.md); original profile, not current P3 authority |
| Asset provenance | [Game media manifest](../../art_source/game/manifest.json), [runtime manifest](../../data/presentation/workshop_manifest.json), authored lapidary resources |

The measured P3 Windows profiles passed their declared engineering gates.
Automated policy results establish reproducibility and characterize those
policies; they are not human difficulty measurements. Normal p95 frame targets
are not maximum-frame or all-machine guarantees. See the report for exact CPU,
GPU, workload, stress, latency and memory attribution.

The original atomic whole-action 5 ms target still fails. It is separate from
the successor's passing incremental computation/animation contract. Keep that
failure visible without treating it as an unmeasured P3 failure or silently
closing it using a different metric.

The user is the sole reviewer at this stage. Broader testing is deferred,
potentially until after P5. A playable build and automated checks do not establish
learning, aesthetic, listening or balance acceptance. Optional user feedback must
not become an invented session-count requirement.
