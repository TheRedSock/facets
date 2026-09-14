# Tactical effects

These concrete P2 handlers operate only on a transaction-owned ActionContext.
RoomTransaction reserves costs before dispatch; TurnController remains the sole
merge/settling resolver. The room protocol is in
[ROOM_CONTRACT.md](../run/ROOM_CONTRACT.md).

ToolResolver applies the admitted root exchange, clearance, lock damage or
promotion. ObstacleResolver applies bounded damage to frozen component targets,
publishes one break and marked-objective progress, and opens the cell to refill.
CraftPolicy settles the strongest eligible component award once after resolution.
No handler reads views, labels, elapsed time or a global random generator.

ActionContext assigns causal event/removal IDs as effects happen, captures source
identity before mutation and carries inherited reward eligibility through every
descendant. Its one ResolutionBudget spans root effects, merge/settling and
recovery. Work accounting is conservative (including resolver scan/segment
estimates); caps protect publication, rather than defining gameplay defeat.

Families, hazard handlers, full seal lifecycle and intervention continuations are
not implemented by this layer. The tool path never invokes future reward handlers.
