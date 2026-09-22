# P3 expedition references

These canonical FAC1 snapshots were captured by `test_p3_flow` from real admitted
commands, seed 7, in `artifacts/game/p3/b5-flow-r2`. Both three-room routes reach
Vault completion. The deterministic one-batch greedy policy is a diagnostic
witness, not evidence of player difficulty or preference. Each reference retains
all room decisions and every merge-session checkpoint, plus selection history.

`test_p3_replay` re-executes every checkpoint. Do not refresh these files merely
to fit changed behavior. The older P0/P1/P2 and merge-readiness controls remain
independent. These are runtime regression references, not independent rules
oracles; behavioral family/entry/extraction assertions remain required.
