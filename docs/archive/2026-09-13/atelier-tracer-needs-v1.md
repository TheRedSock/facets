# Atelier — tracer needs

Written by the atelier workstream against `gem_tracer.gd` kernel v1 while
building the interactive designer preview (`scenes/design/gem_atelier.gd`).
The host API covers the whole v1 feature set; nothing below blocks.

1. **Seed / background ingestion**: `configure_stone()` receives the
   StoneInstance (which carries `seed`) and the caller has the rig in hand,
   but the tracer applies neither — every reconfigure must be followed by
   `set_seed(instance["seed"])` + `set_background(GemRigCompiler.background(rig))`
   or the render silently uses seed 1 and a stale background. Suggest
   `configure_stone` read the seed itself and grow an optional background
   argument.

2. **Synchronous dispatch blocks the UI frame**: `accumulate()` submits and
   syncs, so the atelier's frame stalls for the full GPU time of each batch.
   At 512x512 / PREVIEW policy this measured ~21 ms for the 4 spp first batch
   and ~44 ms per 12 spp batch on an included t2 amethyst (RTX 4060) — the
   panel drops to ~20 fps while converging. Fine for a design tool; a
   submit-now/collect-later split (or fence query) would keep interactive
   consumers at 60 fps.

3. **Per-batch readback for display**: the only way to show progress is
   `finalize_print()` → `Image` → `ImageTexture.update()`, a GPU print pass
   plus a ~1 MB CPU readback and re-upload per batch at 512px. The contract
   already names `texture_rd(slot) -> Texture2DRD` for the live path; landing
   it would let progressive previews draw the print texture directly with
   zero copies.

4. **Fixed tracer size**: width/height are frozen at `create()`; rung `res`
   values are advisory. The atelier holds one 512x512 tracer and always pays
   512x512 dispatch cost even for INTERACT-grade first batches. A cheap
   resize (or per-dispatch viewport) would let one tracer serve
   INTERACT-through-HERO without rebuilding pipelines and buffers.
