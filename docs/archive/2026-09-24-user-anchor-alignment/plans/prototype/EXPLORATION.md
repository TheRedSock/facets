# P4.0 task: establish and demonstrate the target experience

Status: ready task brief, not yet executed. Use this file as the next agent's
assignment. The outcome is a concrete design package and a playable-study plan;
a broad production migration is outside this task.

## Assignment

Develop the strongest feasible presentation of Facets' core concept. Preserve
dependable behavior and production capabilities. Treat current presentation as
a functional baseline whose composition, interaction, media and implementation
choices may be reconsidered.

Do not start by editing the existing UI. Extract the problem, explore solutions,
then compare the target to the implementation. Similarity, novelty, minimum diff
and maximal reuse are neutral until they serve the player experience.

## Context packet

Coordinator reads:

1. [Current state](../../docs/current/STATE.md), [vision](../../docs/design/VISION.md)
   and [user anchors](../../docs/design/USER_ANCHORS.md).
2. [Mechanics map](../../docs/design/MECHANICS.md) and
   [presentation brief](../../docs/design/PRESENTATION.md).
3. [Engineering boundaries](../../docs/engineering/BOUNDARIES.md),
   [production capabilities](../../docs/production/README.md) and
   [acceptance](ACCEPTANCE.md), then only the necessary owners.

The coordinator must inspect current P3/merge-window authority before proposing
input or motion changes. Inspect the current build when possible and label all
observations by build and method. Separate the user's dissatisfaction, historical
reviews and newly observed defects.

Fresh designers initially receive only the extracted brief, actual capability
limits, relevant user anchors and neutral gem samples. They do not need repository
history or old UI/source. If the baseline is later shown, identify which aspects
are functional evidence rather than design constraints. A role name alone does
not create independent context.

## Required work

### 1. Extract a compact brief

Classify relevant characteristics as invariant, preference, implementation
accident, suspected debt or unknown. Preserve the player decisions, semantic
identity, timing/input authority and genuinely necessary constraints.

Separate “supported by engine,” “implemented in current game,” “previously
measured,” and “desired but unverified.” Include enough capability information
to avoid designing an imaginary runtime optical system.

### 2. Explore alternatives

Develop two or three structurally distinct directions. At least one should be
credible under the assumption that the current presentation layer does not exist.
Vary composition, spatial metaphor, hierarchy and interaction, not just colors.

For each direction provide a composed board/HUD study, a reward or carry decision,
and a storyboard or motion study of a meaningful action. Explain gem/environment
material relationships, text hierarchy, accessibility and audio intent. Use actual
gem samples at plausible size; label illustrative mockups and unbuilt behavior.

Reference images/audio may establish specific qualities to investigate, not a
license to copy a whole product or invent tool capabilities. Give reference
sources and state what is being borrowed. Check available production tools before
making one indispensable to the direction.

### 3. Investigate the important feasibility questions

Create bounded candidate studies where needed: real gem pose/lighting/short clips,
rubble material and damage states, a representative sound/mix, or a small Godot
interaction experiment. Keep them isolated and reversible; preserve accepted
assets. Do not spend this stage producing the full roster or every screen.

Use native 112px/80px gem contexts and representative window compositions.
Feasibility may require code, but a temporary mock interaction is not evidence
that the P3 runtime preserves its rules or performance. Mark that distinction.

### 4. Select and map the route to implementation

Compare the directions using the acceptance rubric. Recommend one coherent
direction; avoid averaging incompatible concepts. Ask a fresh critic to identify
specific mismatches between artifacts and intent, not provide an unsupported score.

Only now compare the recommended target with current APIs/scenes. Produce a
KEEP/ADAPT/REFACTOR/REPLACE disposition with experience requirement, obstruction,
owner, compatibility implications, effort/risk and proof for consequential changes.
Include at least one considered alternative where a replacement is proposed.

Specify the first playable study: one representative room, ordinary play, a dense
sequence covering promotion/family/rubble/intervention, and one between-room
choice. Include an extraction fixture if the room itself does not exercise it.
Use the existing runtime and real production path for that subsequent milestone.

## Deliverable and stopping point

Create a compact `plans/prototype/TARGET_PROPOSAL.md` only when the investigation
has produced it. Link studies under a new `artifacts/game/p4/` directory with
source/candidate identities and instructions to view/listen/run. Do not create a
placeholder target spec and report the exploration complete.

The proposal includes the semantic/capability brief, alternatives, recommended
direction, critique and revisions, feasibility evidence, uncertain judgments,
architecture disposition, and the first playable implementation task. Clearly
identify any decisions needed from the user.

Stop at the reviewable choice of direction unless the user has already delegated
selection and continued implementation. Under such delegation, record the
provisional/selected status and proceed only within the authorized scope. This
task does not independently authorize a broad game rewrite or additional content.

Missing optional user anchors do not justify stopping at a questionnaire. Continue
useful research and alternatives; show concrete artifacts before asking the user
to commit to an artistic direction.
