# Game vision

Status: working product brief, aligned with the user's anchors on 2026-09-24.
User intent and inherited design hypotheses are distinguished below. Detailed mechanics
live in [the current mechanics map](MECHANICS.md); future ideas live in
[possible routes](POSSIBLE_ROUTES.md).

## Core concept

Make gemstones themselves the subject of a roguelike collection/build game with
match-3 and merge play. Gemology, faceting, lapidary practice, cuts and mineral
identity should inform what the player collects, notices and chooses. Chosen
gems should give a run recognizable build identity, beyond being attractive tokens.

The collection/library is a central concept. A log with detailed specimen/cut
information and high-resolution showroom animations is a promising expression
suggested by the user, not yet a selected screen or a commitment to permanent
unlocks. Explore the connection between appreciating a gem, understanding it and
choosing it for a run. Do not leave this connection as an encyclopedia added later.

The renderer supplies a procedural, physically grounded basis for material and
light interaction. The finished game may be deliberately stylized. Lighting,
animation, print and style should be developed together with the environment;
hyperrealistic final sprites are not a requirement. Scientific precision is a
production ambition supported only to the extent established by actual evidence.

The user leaves the aesthetic open. Select a direction that available AI-assisted
production can reproduce convincingly across gems, environments, effects and
sound. Neither demanding realism nor overly simple cartoon treatment is assumed
to be the answer. Demonstrated cohesion and repeatable quality should decide.

## Working pillars

These are working design tests. Concrete systems such as families, carry,
objectives and intervention windows are the current implementation, not fixed
answers to the collection/build fantasy.

1. **Readable decisions.** Show what can be acted on, what it will cost, where a
   survivor will be, and why a family reaction or objective event occurred.
2. **Collecting has meaning.** A gem has an identity worth appreciating and a
   comprehensible place in a build. Test what makes choosing one consequential.
3. **Build and board reinforce each other.** Collection choices should alter
   useful decisions in match/merge play. Existing family reactions are one approach.
4. **Pacing is intentional.** The current Work/equilibrium/intervention model is
   a tested implementation to assess, not the only possible balance of planning
   and reaction. Preserve its contracts until a different rule is explicitly chosen.
5. **Gemology informs the fiction.** Use accurate material/cut terminology and
   evidence-backed appearances while labeling invented abilities and game value.
   Gemology should influence decisions and presentation, not just label generic perks.
6. **Style is reproducible.** A direction must survive varied specimens, actual
   board sizes, motion and repeated asset production, not just one showcase image.

## Scope to carry into exploration

The current baseline is a desktop, single-player, three-room expedition with
eight active tiers and the Aquamarine replacement, three implemented families,
rubble and delivery objectives, tools, two settings, rewards and selective carry.
Use this as a bounded comparison and implementation baseline. Most of its design
is open to critique: tier/collection structure, families, tools, room objectives,
carry, rewards, extraction and intervention timing may be reconsidered when that
better serves the anchors. Retaining three rooms is a scope default, not a core
fantasy requirement. Recommend a revised prototype scope if needed, with its cost
and smallest proof; do not silently migrate mechanics during a visual edit.

The inherited 10–15 minute run length is a hypothesis, not measured pacing or a
requirement to rush decisions. Windows remains first. The user wants a rough
future target of 60 fps on flagship phones from four to five years before the
2026 brief, without making a port the present project. Architecture should allow
layout/input adaptation and avoid an expensive later optimization effort. Actual
device selection and mobile performance remain unverified; see
[acceptance](../../plans/prototype/ACCEPTANCE.md#future-mobile-performance-intent).

Accessibility breadth and portability are not leading production priorities.
Retain working controls and basic readability while prioritizing the core
experience. New platforms, a broad accessibility campaign or a larger economy/
progression system are not implied by this brief.

## Design freedom

The former jeweler's-workshop palette, panels, layout, vector rubble, procedural
background and synthesis recipes are prior proposals. They are available as one
candidate direction; they are not requirements for every alternative.

Preserve meaning and readability while exploring composition, spatial metaphor,
hierarchy, interaction, material treatment, typography, sound and motion. A
different theme is not automatically better. A familiar element can survive
when it earns its place in the chosen experience.

The physical baseline and final visual treatment are distinct. Test style on
the same underlying specimen before changing physical inputs merely to make it
fit a UI. Preserve meaningful mineral/light cues and describe authored choices
honestly. Do not equate quality with maximal effects, permanent board motion,
more features or a larger asset catalog.

## User authorship

[User anchors](USER_ANCHORS.md) provides space for fantasy, references, constraints
and consequential choices. Unanswered fields remain open. Agents should expose
alternatives and tradeoffs through concrete studies rather than filling the
blanks with invented user preferences.

Ask focused questions when a consequential ambiguity blocks a decision. Continue
independent investigation and reversible studies meanwhile. Record confirmed
choices there, then update the owning brief; do not quietly elevate suggestions
or historical choices into new approvals.
