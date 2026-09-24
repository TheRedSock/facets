# Isolated intervention trial

`InterventionTrial` owns the separately versioned
`facets-intervention-trial-v1` state/replay envelope and the rules profiles
`trial-paused-v1`, `trial-24-v1`, `trial-48-v1`. Its embedded P2 RuleSet supplies
unchanged match/settle/tool primitives; the outer profile owns episode cost,
window selection and clock rules. The embedded pending state is not a P2 save.
Normal RunController remains atomic; no trial mode is enabled implicitly.

TurnController's cursor parks after every automatic promotion chain and before
gravity. It retains phase/cascade/initial survivor priority. ActionContext keeps
the episode's RNG-backed state, allocators, causal facts, ancestry, journeys,
best Craft and technical budgets. It does not precompute a future branch.

At a parked boundary with remaining Work, enumerate live movable promoted IDs
in board `(y,x)` order. Offer the first survivor with a legal matching orthogonal
swap, with targets ordered `(y,x)`. Consumed instances are absent; an ID that
survives another promotion remains eligible. At most one window is offered.
Automatic chains have priority. Empty, locked, ineligible or stale targets reject.

Root swap costs one Work and advances normal turns once. An accepted intervention
costs one additional Work without refreshing tools or advancing turns. All
matches share Craft eligibility and the episode budget. Pass/expiry preserve
the exact atomic state/facts/RNG. The trial envelope accounts for additional
Work explicitly rather than weakening P2 external admission.

Each decision/continuation runs on a detached candidate. Technical failure retains
the committed prefix in diagnostic state, including its board, RNG and facts;
restart is available. Transcripts record diagnostic injection separately when
used by tests. No hidden truncation or budget reset occurs at a segment boundary.

Commands have exact fields, window/revision, strictly next sequence and integer
tick. `presented` starts once at zero after the boundary is shown. `advance`
updates the 60-Hz logical clock; deadlines are 24/48 ticks and expiry wins ties.
`pause` records manual/focus/stall suspension; no tick advance is accepted while
paused. `decide` supplies an exact offered command or null for pass. Invalid input
does not advance sequence/time or charge Work. Cosmetic rendering cannot change
an admitted stream's result. A visible stall may be recorded as an assisted pause;
it is excluded from unassisted timing interpretation.

Snapshot identity includes initial state/root command, profile, bounded transcript,
current state, complete context/cursor, offers, clock and diagnostic status.
Admission reconstructs the transcript in a detached session and requires exact
canonical equality of the entire snapshot. Forged pending fields reject. The
transcript allows at most 512 entries, reserving its last slot for a decision.
Production disk persistence remains stable-only; this API is in-memory trial
continuation/replay, not a Continue implementation.

`InterventionFixture` is explicitly authored diagnostic content. It is never a
fallback for normal room generation. Its main move is `(3,3)->(2,3)` (zero-based):
the vertical T1 line promotes at `(2,3)`. Swapping that T2 left makes the intended
line at `(1,3),(1,4),(1,5)`. Separate fixtures cover an automatic chain and no
opportunity. Registered tests distinguish unit/semantic evidence from actual
release playback and human preference. Human sessions are deferred by the user;
atomic production remains the default pending any later adoption review.

Closeout disposition (2026-09-21): decline adoption into P3 production for this
milestone; retain this isolated implementation and review entry for later
evaluation. This is an engineering scope decision under the user's deferred
human-review policy, not a finding that players prefer atomic actions. P3
reactions and persistence therefore target whole atomic actions. Reopening
adoption requires an explicit decision and new compatibility review.
