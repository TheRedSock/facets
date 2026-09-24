# Remaining prototype: direction, proof, production, acceptance

Status: active continuation plan, 2026-09-24. Game P3 engineering is complete on
its recorded profile. P4/P5 experience and final-content work remain. This plan
replaces the superseded P4/P5 execution instructions; it does not change runtime
behavior, frozen baselines or historical test results.

## Start here

Read [current state](../../docs/current/STATE.md) and
[game vision](../../docs/design/VISION.md). The next task is
[EXPLORATION.md](EXPLORATION.md). [User anchors](../../docs/design/USER_ANCHORS.md)
can be filled in now or through concrete design comparisons; unanswered fields
do not block research and reversible studies.

**Objective:** demonstrate a coherent, satisfying gemstone game at the current
three-room scope, using the existing engine deliberately and retaining dependable
simulation/delivery guarantees. Prove the design before expanding its production.

## Sequence and current status

| Stage | Deliverable and exit | Status |
|---|---|---|
| P4.0 — establish the target | Concise semantic/capability brief, 2–3 distinct visual/interaction directions, feasibility studies, recommended target and migration outline; choose a direction from concrete artifacts | Ready to start; no studies or direction selection completed |
| P4.1 — prove it in play | One representative room and one between-room choice, with actual new gem content, intended non-gem treatment, motion and sound; review ordinary and demanding sequences against the chosen target | Planned; depends on target selection |
| P4.2 — complete necessary foundations | Resolve architecture/production obstructions found by the study, establish reusable boundaries and an integrated regression checkpoint | Planned; required pieces may be brought into P4.1 |
| P4.3 — expand the proven treatment | Complete the expedition's required screen/state/asset coverage, accessibility and alternate-profile proof; selected sources, manifests and package coverage | Planned; depends on a convincing study and usable foundations |
| P5 — accept or revise the prototype | Exact packaged build, relevant engineering checks and final-content performance, perceptual evidence and an honest disposition of remaining user-dependent judgments | Planned; broader testing remains deferred |

P4.2 is not permission to postpone architecture required by the playable study.
Do the enabling work first where necessary, then use the study to avoid designing
an oversized framework. A failed study returns to the responsible design or
production decision before full asset production begins.

## What changes from the old plan

| Previous planning assumption | Current treatment |
|---|---|
| Finish prescribed workshop UI, vector rubble, procedural environment and audio recipes | Reopen the direction and production methods; keep functional coverage and provenance responsibilities |
| Asset/icon/cue counts primarily describe progress | Derive an inventory from the chosen experience and cover every required semantic state; counts alone do not establish quality |
| Small pose study, then broad UI/asset implementation | Compare target compositions, prove one integrated playable study, then expand |
| Broad presentation/learning review appears late in P5 | Inspect native visuals, interaction and sound from the first study onward; retain final P5 review |
| Older atomic timing or stable-only save assumptions mixed with successor notes | Use current P3/merge-window contracts; preserve controls under their own identities |
| Historical unfamiliar-tester session quotas | User remains sole reviewer; no new session-count gate or invented population evidence |

The old numeric recognition and session-duration goals remain historical
hypotheses. Current acceptance requires explicit observations and uncertainty;
future broader testing can adopt a fresh protocol. Technical thresholds are not
relaxed by aesthetic redesign; [acceptance](ACCEPTANCE.md) distinguishes current
P3 gates, proposed content budgets and retained legacy failures.

## Architectural and creative treatment

Follow [engineering boundaries](../../docs/engineering/BOUNDARIES.md): preserve
simulation/identity/replay guarantees, offline production and validated delivery
ownership; reopen presentation and critique its APIs against the target.

For each major subsystem proposed for change, select KEEP, ADAPT, REFACTOR or
REPLACE, with a concrete experience need and evidence. Delete obsolete code only
after its consumers and required diagnostic controls are accounted for. Existing
code is evidence; it is not a mandatory composition or class hierarchy.

Do not trade away the live post-merge input opportunity for cinematic polish.
Mechanic, protocol and scope changes need an explicit decision, compatibility
analysis and their own checks. Propose them when warranted rather than hiding
them inside a presentation change.

## Working method

- Keep a single integration owner for artistic cohesion, shared APIs and final
  acceptance. Work in bounded milestones with reviewable artifacts.
- For creative alternatives, use fresh contexts containing the semantic brief,
  necessary capabilities and user anchors. Avoid giving every designer the old
  scene source, screenshots, abandoned attempts and entire archive.
- If using subagents, make exploration independent and implementation ownership
  explicit. Parallelize production only when the direction and interfaces exist.
  Do not have several agents concurrently redesign shared scene/session owners.
- Judge quality through rendered output, interaction and audition. An independent
  critic should see the target and result before implementation rationales.
- Spend iteration on the most consequential discrepancy. There is no token,
  elapsed-time or arbitrary revision quota that proves sufficient effort.
- If a capability, listening surface or tool is unavailable, state the limitation,
  demonstrate alternatives, and retain the affected judgment as open.

## Decision points and handoffs

Before selecting a direction, present concrete alternatives and tradeoffs. The
user may select or explicitly delegate that choice. Do not ask for permission on
routine reversible work already within the task. Do not make new spending,
mechanics changes or expansion implicit in an artistic recommendation.

Each milestone handoff identifies the target/artifacts, selected sources and
build identity, changes and their reasons, evidence with scope, remaining material
discrepancies, and the next bounded action. Update the status table only from
actual results. Document **engineering passed**, **perceptually reviewed**,
**user accepted**, and **unverified** separately.

The next action in this repository is P4.0, not another P3 implementation batch
and not production of the complete old presentation inventory. This documentation
task prepares that work; it does not claim to have executed it.
