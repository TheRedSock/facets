# P4.0 task: establish and demonstrate the target experience

Status: ready task brief, not yet executed. Use this file as the next agent's
assignment. The outcome is a concrete design package and a playable-study plan;
a broad production migration is outside this task.

## Assignment

Develop the strongest feasible expression of gemstone collection and run build
identity through roguelike, match-3 and merge play. Gemology and lapidary practice
are thematic anchors; the existing room, tier, family, carry and intervention
systems are candidate implementations open to critique. Preserve engineering
guarantees and the playable baseline while exploring alternatives.

Design final gem style and surroundings together using the physical renderer,
lighting, animation and print/style controls. Prefer a direction available
AI-assisted production can sustain. Photorealism, a particular workshop aesthetic
and the present screen/mechanic inventory are not fixed destinations.

Do not start by editing the existing UI. Extract the problem, explore solutions,
then compare the target to the implementation. Similarity, novelty, minimum diff
and maximal reuse are neutral until they serve the player experience.

The name “Facets” is a placeholder codename. Do not use it to preselect a theme,
story or faceted visual language. A final title can follow the strongest direction;
naming exploration is optional and must not displace the playable/artistic proof.

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

Classify relevant characteristics as user anchor, engineering invariant, current
game rule, preference, implementation accident, suspected debt or unknown. Do not
promote tested game rules into permanent design invariants. Preserve consistent
state/input authority within each proposed rule set, with explicit version and
migration consequences when it differs from P3.

State how collecting/appreciating a gem connects to choosing a build and making
a match/merge decision. Test whether the existing tier/family approach expresses
that relationship well enough. Critique actual player benefits, not just labels.

Separate “supported by engine,” “implemented in current game,” “previously
measured,” and “desired but unverified.” Include enough capability information
to avoid designing an imaginary runtime optical system.

### 2. Explore alternatives

Develop two or three structurally distinct directions. Include a credible use of
the current mechanical baseline and an alternative developed from the user's
anchors without assuming the current presentation or secondary mechanics exist.
A mechanical change is not mandatory if the comparison favors the baseline.
Vary composition, collection/build interaction, spatial metaphor and hierarchy,
not just colors. Identify proposed rules separately from visual changes.

For each direction provide a composed board/HUD study, one meaningful collection/
build choice, one collection/showroom treatment and a meaningful action storyboard.
Explain the role of factual gem/cut information, fictional abilities, material
relationships, typography, core controls and sound. Follow the same representative
gem from appreciation to choice to play. Use actual samples at plausible size;
label illustrative mockups and unbuilt behavior. A showroom study does not commit
to a full catalog, permanent unlock economy or new game mode.

Reference images/audio may establish specific qualities to investigate, not a
license to copy a whole product or invent tool capabilities. Give reference
sources and state what is being borrowed. Check available production tools before
making one indispensable to the direction.

### 3. Investigate the important feasibility questions

For shortlisted directions, test real gem pose/light/print/style/clip candidates
together with representative environment/board art, effects and sound. Repeat a
workflow on a contrasting asset or state and demonstrate a controlled revision.
Record consistency, manual cleanup, generation/render cost and integration effort.
One attractive mockup or an unexecuted generation recipe is insufficient evidence
of repeatable production quality.

Use a small Godot interaction experiment where mechanics or runtime feasibility
is uncertain. Keep candidates isolated and reversible; preserve accepted assets
and baseline behavior. Do not produce the full roster or every screen here.

Use native 112px/80px baseline contexts and representative window compositions,
plus one explicitly authored larger gem sample if proposing a high-resolution
showroom. Assess style coherence across sizes and motion. Identify renderer/style
limitations honestly and propose a focused extension only for a demonstrated need.

Identify runtime risks for the rough future older-phone 60 fps goal: simulation
work, effects/overdraw, texture residency/bandwidth and showroom loading. Separate
estimates from measurements; desktop headroom or synthetic slowdown is not mobile
validation. Device nomination/measurement can remain future work without blocking
concept studies. Do not turn this task into a port or broad accessibility project.
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

Specify the first playable study: one representative playable segment, one build
choice and one gem's board/showroom treatment. For a retained P3 direction include
ordinary play, a dense promotion/family/rubble/intervention sequence and an
extraction fixture if the room does not exercise it. For a revised rule set,
specify equivalent decision/causality stress cases and the smallest versioned
prototype needed. Reuse existing runtime/production capabilities where suitable;
identify the necessary replacements rather than forcing the target through old APIs.

## Deliverable and stopping point

Create a compact `plans/prototype/TARGET_PROPOSAL.md` only when the investigation
has produced it. Link studies under a new `artifacts/game/p4/` directory with
source/candidate identities and instructions to view/listen/run. Do not create a
placeholder target spec and report the exploration complete.

The proposal, production recipes and a compact evidence manifest belong in Git.
Raw study media under `artifacts/` does not travel with a clone: record where to
retrieve selected review artifacts, their hashes and source revision, or preserve
appropriately sized accepted assets in the repository. Follow the
[handoff/recovery boundary](../../docs/BUILDING.md#what-travels-with-git) so the
chosen direction can be reviewed and continued from another machine.

The proposal includes the semantic/capability brief, alternatives, recommended
direction, critique and revisions, repeatable-production evidence, uncertain
judgments, scope/mechanics changes, architecture disposition, performance risks
and the first playable implementation task. Explain why the recommendation
expresses gemstone collection/build identity better and can be produced reliably.
Identify consequential choices needed from the user; do not invent their answers.

Stop at the reviewable choice of direction unless the user has already delegated
selection and continued implementation. Under such delegation, record the
provisional/selected status and proceed only within the authorized scope. This
task does not independently authorize a broad game rewrite or additional content.

Missing optional user anchors do not justify stopping at a questionnaire. Continue
useful research and alternatives; show concrete artifacts before asking the user
to commit to an artistic direction.
