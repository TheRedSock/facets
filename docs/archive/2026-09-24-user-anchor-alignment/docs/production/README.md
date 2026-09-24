# Asset production and integration

Status: available workflow and constraints, 2026-09-24. Read this when producing
or integrating content; it does not choose the artistic direction. Use the
[presentation brief](../design/PRESENTATION.md) and selected study for that.

## Gemstones

The existing engine is an offline production system. Follow
[gem authoring](../AUTHORING_WORKFLOW.md) for detached specimen/request editing,
save/reopen, admission, estimates, frozen jobs, rendering and delivery.
[Engine readiness](../ENGINE_READINESS_REPORT.md) records supported tested cases
and measured limits. New content needs its own review.

Useful creative controls already include cut geometry, specimen-specific material
and condition inputs, orientation/framing, lighting, print/style and sampled clips.
Clips can author orientation, orientation time, rig motion, light power and exposure.
Use those capabilities in controlled appearance studies before proposing new
renderer features. More samples cannot add an unsupported physical phenomenon.

Keep material claims tied to evidence. Authored coefficients, grade labels or
an attractive image do not establish mineral calibration. Diagnostic fixtures
demonstrate particular mechanisms; they are not automatically shippable gemstones.

Start with a few contrasting specimens and an actual board context. Compare
rest/light/pose and short motion at 112px and 80px; vary one factor at a time where
the cause matters. Preserve requests, seeds, source provenance, costs and selected
outputs. Expand to the starter eight plus Aquamarine when the treatment is proven.
Larger inspection assets need explicit requests and their own budget.

## Runtime division of work

| Work | Owner |
|---|---|
| Optical changes from pose/light/material | Offline gem requests and clips |
| Swap, fall, convergence, travel, scale and removal | Runtime presentation choreography |
| Tier/family/status, tools, rubble, backgrounds, UI | Game presentation assets/scenes |
| Cue mapping, mixing, voice priority and cancellation | Game presentation/audio |
| Rules, targets, costs and timing authority | Simulation/session contracts |

[GemDeliveryCatalog](../../data/presentation/default.tres) maps logical tile IDs to
asset IDs and semantic roles. `rest` is a still/loop; `upgrade` must complete.
Existing role names do not prescribe the chosen art. Add roles only for a concrete
required view, with admission/playback coverage. Do not use optical clips as a
container for non-gem UI, sound or rubble effects.

The [delivery contract](../../core/delivery/CONTRACT.md) owns preflight, loading,
page lifetimes and cancellation. Include active, reward, carry and transition
owners in live-memory measurement. Missing required assets are errors, not a
reason to silently substitute synthetic gems.

## Non-gem production

Choose methods through representative trials. Code/native/vector geometry can
serve precise UI and effects; raster illustration or textures can serve an
environment when justified; sound can use synthesis, authored recordings or other
available sources. Do not default to a method solely because an old plan made it
easy to generate a complete inventory. Confirm tool availability, authorship and
license needs before depending on a source.

The existing source area is [art_source/game](../../art_source/game/), accepted
assets are under [assets](../../assets/), runtime mappings under
[data/presentation](../../data/presentation/), and generation/check commands are
in [tools](../../tools/README.md). Preserve the accepted manifest and outputs as a
baseline. Write new candidates separately, review them, then promote selected
outputs with source/tool/recipe identity, hashes and acceptance notes.

The existing Python SFX tool and vector sources remain available, but their
use is not an artistic acceptance criterion. Audition both isolated sounds and
the mixed gameplay sequence. Waveform/header checks cannot establish listening
quality. If listening is unavailable, provide playable outputs and mark the
judgment unverified. Do not silently accept an inferior substitute for a missing
production capability; expose the limitation and alternatives.

## Packaging and measurement

Use the explicit runtime export path in the tools guide. Non-gem assets belong
in the game PCK; gemstone delivery belongs in its asset pack. Source recipes,
candidate studies and editor/optical production code remain outside the runtime.

The current 32 MiB LRU and 128 MiB prefetch admission caps are delivery controls,
not accepted content budgets. The inherited prototype planning targets remain
16 MiB live gem texture payload, 16 MiB non-gem texture payload and 2 MiB decoded
SFX, counted separately. Fonts, scene overhead, temporary decode and whole-process
memory must be reported separately. A justified target change is an explicit
decision, not an unreported consequence of a new asset style.

Check the exact packaged build in play. Asset-gallery acceptance, successful
optical rendering and editor probes do not establish release interaction,
perceptual coherence or final-content performance. Follow
[prototype acceptance](../../plans/prototype/ACCEPTANCE.md).
