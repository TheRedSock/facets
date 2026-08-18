# Clip delivery layer — tracer needs

Written by the clips workstream against `gem_tracer.gd` kernel v1 (the
`configure_stone` / `set_clip_sample` / `finalize_print` host). That API
covers almost everything the baker needs — rung feature flags, full
StoneInstance upload (inclusions/wear/media/zoning), in-shader rig yaw,
per-role power multipliers, GPU print with exposure. Remaining gaps, none
blocking v1:

1. **Seed ingestion**: `configure_stone()` receives the StoneInstance (which
   carries `seed`) but does not apply it; the caller must remember a separate
   `set_seed(instance["seed"])` or every stone renders with seed 1. Footgun —
   suggest `configure_stone` read the instance seed itself. Baker and GemForge
   currently call `set_seed` explicitly as the workaround.

2. **Background ownership**: same shape as seed — `set_background()` must be
   called separately after `configure_stone()` (only the spike-compat
   `configure()` reads it from params). Worked around identically.

3. **Synchronous dispatch only**: `accumulate()` does `submit()` + `sync()`,
   so every batch blocks the calling thread for the full GPU time. Fine for
   the CLI; for the in-game launcher a split submit-now/collect-later (or a
   fence query) would let the background baker overlap GPU work with the
   frame instead of stalling ~5–15 ms per `_process` tick at CLIP_BAKE res.

4. **Premultiplied output**: `gem_print.glsl` stores `rgb * coverage` with
   coverage alpha. Standard CanvasItem straight-alpha blending slightly
   darkens AA edges unless the material uses premultiplied blend. Cosmetic at
   112 px; flagging so the print/board workstreams pick one convention.

5. **bloom_gain envelope**: the clip schema names a `bloom_gain` effect
   envelope, but the print pass has no bloom stage yet (arch doc lists
   micro-bloom as a print feature). The baker samples and forwards
   `exposure_pulse`, `key_boost`, `rim_boost` today; `bloom_gain` is parked
   until the print pass grows the knob.

6. **Batched grid readback**: `configure_stones(..., grid)` + `set_instances`
   exist, but there is no per-cell readback/finalize helper — packaging all 8
   idles as one 4x2 grid dispatch would cut cold-start dispatch overhead.
   Nice-to-have for `ensure_required` bursts, not needed at current timings.
