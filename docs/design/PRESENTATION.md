# Presentation design brief

Status: target to explore, 2026-09-24. No new direction selected. Read
[vision](VISION.md) and [user anchors](USER_ANCHORS.md), then use the
[exploration task](../../plans/prototype/EXPLORATION.md). This document replaces
the old prescriptive asset recipe with experience requirements.

## What must become convincing

Gems should feel worth observing, collecting, choosing and combining. Gemology and
lapidary practice should inform the visual language, interactions and build
explanations. If generic colored tokens could replace the gems without changing
the experience's meaning, the direction has not yet addressed the user's anchor.

Explore how a collection/library view connects specimen appreciation to a run
choice. A high-resolution animated showroom with material/cut information is a
candidate, not a settled screen design. Demonstrate one gem across collection,
choice and board contexts before producing a full catalog or unlock system.

The UI, surroundings, rubble, motion and audio need one recognizable direction.
Demonstrate their relationship in a composed screen and a playable sequence.
Improving a gem close-up or a menu in isolation does not establish that relationship.

## Physical foundation and authored style

The finished stones may be stylized. Develop their lighting, optical motion,
print/style treatment and surroundings together. Compare the same specimens under
candidate treatments so a promising composition does not depend on replacing all
material inputs or on an isolated photorealistic sprite that clashes with the UI.

Retain meaningful mineral/cut/light behavior while allowing a deliberate visual
interpretation. Check that styling survives varied pale/dark/colored specimens
and changing highlights. Existing style controls have specific limits; see the
[production guide](../production/README.md#style-development). A look requiring
additional controls needs a demonstrated gap and a bounded implementation proposal.

Production feasibility is part of selecting the direction. Pair a composed target
with evidence that its important asset classes can be generated, revised and
integrated consistently. Neither the simplest available tool nor an impressive
one-off mockup should determine the final aesthetic.

## Information and interaction responsibilities

| Moment | What the player must be able to understand |
|---|---|
| Room entry | Objective, pressure, current build and carried-piece staging |
| Deliberation | Match tiers, legal targets, selected piece/next upgrade, Work/Craft and tool availability |
| Merge and intervention | Survivor, newly actionable board, window opportunity/cost, live pieces versus consumed ghosts |
| Family or tool effect | Actual source and target, reason for effect, result and resource change |
| Rubble and extraction | Durability/target state, outlet threshold, qualifying delivery and remaining demand |
| Carry/reward/route | What is retained or exchanged, why the choice matters, and the relevant next-room tradeoff |
| Collection/showroom candidate | What makes this gem/material/cut distinctive, which details are factual, and how choosing it relates to build identity |
| Pause/error/result | Clear recovery or next action, focus ownership, no hidden loss or reroll |

The room/turn rows describe the implemented baseline to explain or critique.
If a selected concept changes those systems, revise the responsibilities and
scope explicitly; do not force the new concept back into the old screen list.

Design hierarchy and progressive disclosure for these responsibilities. Do not
assume they require a fixed sidebar, permanent text dump, card grid or existing
scene hierarchy. Preserve access to necessary information and equivalent mouse/
keyboard actions. Decorative children must not steal board input.

## Gem identity and motion

The working recognition scheme uses tier silhouettes plus visible numerals,
material appearance for gem identity, and separate family/status cues. Color
alone is insufficient. Keep tier numerals available and on by default in baseline
comparisons. The user permits rethinking cut/tier/collection relationships; show
how an alternative preserves match recognition and meaningful lapidary identity.
Proposed symbol changes need an explicit comparison, not an unnoticed asset swap.

Current tier envelopes are round, upright square/cushion, triangle, oval,
lozenge, cropped rectangle, marquise and pear. Their pose, proportion and badge
treatment are study variables. The historical quartz/sapphire concerns and
square/lozenge, round/oval, green-gem and quartz/diamond confusion cases are
useful hypotheses, not fresh findings. Consult the
[dated gem review](../archive/2026-09-24-documentation-reset/docs/GEM_ART_REVIEW.md)
only for those specific observations.

Compare a few representative stones at 112px and 80px in the intended board.
Use actual newly authored pose/light/print/clip candidates. Optical movement
should preserve identity, framing and continuity. Runtime transforms own board
travel and convergence. Quiet rest and a short upgrade tilt are starting
candidates; more motion needs a clear benefit and fatigue review.

For retained P3 mechanics, the intervention opportunity is mechanical. A new cinematic tail must
not delay publication/input or make a consumed ghost selectable. Conversely,
cutting an optical clip must not silently shorten the available window.

## Non-gem art and sound

Explore the intended result and production methods together. Native/vector
geometry, authored textures, image-generated illustrations and appropriate
audio sources can each have a role. A procedural asset is not inherently a
placeholder; a generated bitmap is not inherently better art. Evaluate available
tools, repeatability across variations, revision control, manual cleanup and
integration cost alongside the result. Prefer a strong direction the available
workflow can sustain over a single impressive but unrepeatable sample.

Rubble needs convincing material and clear hit/target states at game size.
Backgrounds need compositional purpose without competing with decision cues.
Room identity may come from staging, light, environment, framing or other
deliberate choices; a palette swap is not a compulsory limit or sufficient proof.

Develop an audio palette through actual audition and repetition. Distinguish
source quality from timing, variation, voice priority and mix. Compare quiet play,
dense cascades, simultaneous hits, family events and results. Respect mute/volume,
cancellation, fatigue and visible equivalents for required information.

## Selection standard

Use [acceptance](../../plans/prototype/ACCEPTANCE.md) to compare alternatives.
Novelty, minimal diffs and inventory size are not quality measures. An attractive
study must lead to a feasible playable result; a functioning build must still
meet the selected perceptual target. Identify unavailable viewing/listening
capabilities and retain those judgments as unverified.
