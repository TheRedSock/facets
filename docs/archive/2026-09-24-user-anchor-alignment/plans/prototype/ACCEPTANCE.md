# Prototype acceptance and evidence

Status: criteria for remaining P4/P5 work, 2026-09-24; not new test results.
Use during exploration and the playable study, not only at the final milestone.

## Perceptual and interaction review

Choose reference artifacts with the target direction. Compare observed output
against them and the player's decisions. Record concrete defects, revisions and
uncertainties; a self-awarded quality score is insufficient.

| Dimension | Evidence needed | Reasons to revise |
|---|---|---|
| Cohesion | Composed board, shell and between-room choice using the intended materials/type/motion/sound | Attractive parts do not form one deliberate experience |
| Decision hierarchy | Actual objective/tool/selection/reward/carry interactions | The player must parse debug prose or cannot see a cost, target or consequence |
| Gem identity | Native 112px/80px stills and motion, silhouettes/grayscale and relevant mixed rosters | Tier/piece identity depends on color/facet noise, clipping or enlarged inspection |
| Gem animation | Real authored optical candidates in runtime choreography | Framing jumps, identity loss, temporal popping, or decoration obscures action |
| Reactive interaction | Real merge-window sequence with input overlay/recording when useful | Publication is delayed, ghosts read as live, feedback lies about admission, or decoration changes timing |
| Non-gem material and layout | Intended background, rubble states, controls and overlays in a busy board | Placeholder treatment carries the identity, readability is lost, or room composition feels accidental |
| Sound | Actual isolated and dense-sequence listening at ordinary volume, repeated over play | Clicks, harsh/fatiguing repetition, masking, stale voices or disconnected timing |
| Accessibility and lifecycle | Keyboard/focus, reduced motion, mute/volume, small window, expanded text, error/retry and navigation | Hidden information, overflow, lost focus, inaccessible action or stale work |

Review 1600×900 and 1280×720, which have P3 evidence, and the intended 1920×1080
composition. Do not call a larger still a native game review. Additional platform
support requires explicit scope and its own evidence. Any new animation-speed
control must honor the current mechanical clock policy.

Capture native screenshots, short action recordings and playable/auditionable
artifacts. Inspect the actual result; source code cannot establish visual quality,
and audio headers/plots cannot establish listening quality. If a review surface
is unavailable, mark that dimension unverified and provide the material needed
for review. Do not fabricate a sensory judgment.

The user is the sole reviewer. Their feedback is optional unless a current task
requests a specific selection. Lack of feedback is neither acceptance nor a
reason to block independent engineering. No external participant quota is imposed.
Learning, difficulty and reaction comfort remain unmeasured until observations
support them; scripted success or bot win rates do not substitute for those.

## Engineering and release proof

Use [tests](../../tests/README.md), [game checks](../../tests/game/README.md),
[tools](../../tools/README.md) and the affected contracts. Run checks appropriate
to actual changes, then required milestone/release coverage. Do not run unrelated
optical suites merely because UI changed; do not omit delivery or rule coverage
when their boundaries changed.

- Preserve deterministic outcomes, canonical ordered events and save/replay
  compatibility for retained mechanics. Cosmetic/profile changes must not alter
  results for the same recorded commands. Keep frozen controls intact.
- Verify current P3 input authority, reservations, window timing, reduced-motion
  policy, interruption, skip, load retry and Continue after affected changes.
- Exercise the complete run, both routes, rewards/carry and success/failure;
  preserve exact-once outcomes, failed-load state and live page ownership through
  transitions. Asset-gallery or editor-only checks are insufficient.
- Demonstrate the remaining presentation pivot requirement: a coherent selected
  profile and a neutral high-contrast alternative, including vocabulary changes
  throughout HUD, descriptions, rewards, dialogs, errors and results, with equal
  mechanical results. This is planned evidence, not claimed existing coverage.
- Validate asset references/provenance, explicit export inclusion, decoded media,
  generation cancellation, pooled voices/effects and no cold gem-page loading
  during declared prefetched sequences.
- Build the clean Windows package, record exact source/asset/executable identity,
  and test that release. Require registered completion markers, not exit code alone.

## Measurements and inherited limits

Preserve the distinction between current successor gates and old atomic metrics.
The [P3 verification report](../../tests/game/P3_FINAL_VERIFICATION.md) and registered
checks own the measured profiles and thresholds; repeat applicable final-content
workloads after changes. Retain the original failed 5 ms whole-action target as
legacy evidence; do not replace successor acceptance with it or declare it fixed.

The inherited desktop frame target is p95 application intervals at most 16.7 ms
on the stated machine/workload. Report p99/max stalls, input/computation/handoff
timings and forced waiting as relevant, with exact measurement scope. A gem-only
burst is not full-expedition performance. Separate capture runs from uncontended
timing runs; do not hide failures by lengthening mechanical windows.

Planning content targets remain at most 16 MiB live gem texture payload, 16 MiB
active non-gem textures and 2 MiB decoded SFX. Include all live owners, not just
cache entries, and report fonts/scene/decode/whole-process overhead separately.
These are inherited targets, not a claim that new final content meets them.
Propose any budget revision explicitly, with measured tradeoffs.

## Completion records

At each stage distinguish engineering passed, agent perceptual review, user
acceptance and unverified judgments. Record the exact artifacts, method and
material remaining discrepancies. Correct significant mismatches before declaring
the target achieved; inventory coverage and test counts cannot compensate for them.

P4.1 exits with an integrated, reviewable study that supports the chosen direction.
P4.3 exits with that treatment covering the complete current expedition, including
empty/error/disabled/focus/transitional states. P5 delivers the exact tested build
and an accept/revise/defer disposition for remaining experience questions. It
must not declare human-dependent goals satisfied when review remains deferred.
