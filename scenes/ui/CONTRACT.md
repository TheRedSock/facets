# Room presentation

RoomHudModel produces recursively immutable values from a committed RunState.
It shares RoomActionLegality for costs and disabled reasons; labels never encode
mechanics. RoomPanel owns controls and emits intents. RunScene owns selection,
command submission and generation gates, while ActionPlayer owns animation.
The normal Main scene opts into Open seam; direct RunScene remains the explicit
legacy diagnostic fixture used by the existing motion/probe checks.
