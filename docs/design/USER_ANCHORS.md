# User anchors and design decisions

Status: working worksheet, 2026-09-24. The user may answer in conversation or edit
these fields. Partial answers are useful; this is not a questionnaire that must
be completed before agents can investigate or make reversible studies.

## Already stated

- **Naming clarification (2026-09-24):** “Facets” is a placeholder project
  codename. It may become the game title if appropriate, but must not drive its
  story, design or aesthetics. A stronger direction can use a different title.

- Keep the core Facets concept and solid implementations while permitting
  creative presentation and justified architectural redesign.
- Use the gemstone engine to make realistic-looking gem animations and explore
  its capabilities beyond the initial demonstration outputs.
- Seek a coherent, intentional game experience across UI, sound, gems,
  backgrounds, board elements and interaction.
- Current UI, sound and rubble are unsatisfactory to the user; functional
  completeness is insufficient evidence of the desired design quality.
- The user is the sole reviewer at this stage; broader testing remains deferred.

These anchors record instructions, not a completed visual or audio review.

## Most useful inputs before selecting a direction

### 1. Fantasy and emotional tone

What am I doing in this world, and what should a good sequence feel like?
Possible dimensions to consider: collecting, discovering, excavating, crafting,
curating, solving, improvising. These are prompts, not a proposed answer.

**User input:** _Open._

### 2. References and anti-references

Add links, images, games or short descriptions. For each, name the specific
quality to borrow or avoid: composition, material, sound, pacing, typography,
interaction or atmosphere. An example is not a request to copy the whole work.

**User input:** _Open._

### 3. Relationship between gems and surroundings

How realistic, illustrative, abstract or tactile should the surroundings feel?
Should the board evoke a place/object, or be primarily an elegant game surface?
What should remain visually quiet so the stones and decisions stand out?

**User input:** 
- The general aesthetic and illustrative vision is undecided and open-ended as of now
- The two most important things is: 1) to pick an aesthetic & design direction that has
good asset generation opportunities that AI can work with well and generate good
looking assets, animations, effects and sounds, so something very realistic may be
difficult to get looking good without a lot of careful design work, while something too
cartoony and simple may look too much like a flash game and seem low quality. 2) that 
for the gem renderer output, the lighting, animations & especially stylizer configuration
is set up to align well with the direction, so the generated assets look like a part of 
the aesthetic. The main purpose of the gem renderer is to have a baseline for ensuring 
that there is a procedural way to generate gems based on realistic properties and have
animations produce realistic looking light interaction, but there isn't a need for the
end result gems to have a hyper-realistic look, and the stylizer is intended to provide
the mechanism to tune- or "master" the output to match a given aesthetic.

### 4. Satisfaction and attention

Which moments deserve emphasis: planning, merging, reactive redirection, family
combinations, discovering a reward, carrying a prized gem, or final extraction?
What becomes tiring or distracting after repeated play?

**User input:** _Open._

### 5. Practical boundaries

Which hardware/window sizes matter personally? Are there accessibility or audio
preferences? Is there a preferred limit on offline render time, disk footprint,
new tools, licensing cost or external services? Existing measured profiles remain
the engineering baseline until a change is decided.

**User input:**
- The overall accessibility & portability is not a top priority, but general architecture
should generally consider future ease of adjusting layouts and UI/UX for different devices
- The game should generally have a rough goal such that running the game at 60 fps on say 
flagship phones from 4-5 years ago should not be a problem, although the game is made for 
PC first. That performance target would make a future mobile port not be a large optimization task.

### 6. Non-negotiables and things worth challenging

Beyond the recorded core concept, is any setting, term, mechanic, asset or screen
especially important to keep? Which assumptions would you welcome alternatives
to? Current mechanics remain the starting scope; unanswered fields authorize
exploration, not an unrecorded mechanical change.

**User input:** 
- Most of the core concept is largely open to critique, rethinking & redesign.
- The core concept I want to incorporate in some manner is the idea of different gems
as a primary roguelike collection/library concept, where we could have some collection
log that could display high-res showroom animations of the gems with detailed info,
and giving chosen gems during runs build identity.
- This also ties in with the concept of making the gems themselves, theming around gemology,
lapidarists, faceters and making gemstones themselves the central theme, and not just
being shiny pretty objects, which ties in with the gem renderer being scientifically precise
in the optics, mineral properties, and around cut design, silhouettes & lapidary terminology.
Therefore, the concepts should be pulled from that as an anchor, and how to align that
with the other primary drivers of wanting a roguelike, match-3 & merge style gameplay.

## Confirmed decisions

Only add entries when the user actually confirms a consequential choice. Link
the artifact reviewed; preserve alternatives and rationale in that artifact.

| Date | Decision and scope | Reason / reviewed artifact | Effect on plan or brief |
|---|---|---|---|
| 2026-09-24 | Reorganize documentation and establish a remaining-prototype entry point | Current user request; superseded narratives archived | [Prototype continuation](../../plans/prototype/README.md) becomes the active planning route |

No target art direction or architectural replacement has been selected yet.
Agent working assumptions must be labeled **provisional** in their deliverable,
with alternatives and consequences. Do not fill user-input fields on the user's
behalf or turn an unanswered preference into a permanent constraint.
