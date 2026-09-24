# Prototype non-gem presentation — production specification

**Delivered subset, 2026-09-21:** the P2 workshop UI, rubble, icons, effects and ten v3 material-resonance cues are generated and packaged. `art_source/game/manifest.json`, its audio recipes and the P2 handoff own accepted hashes. The earlier sine/chord recipe table below is historical rejected candidate direction, not a regeneration specification. Future family/extraction cues should use the accepted sharp mineral/friction/resonance palette and receive separate audition. Dense in-game human listening remains deferred.

Status: planned production work, 2026-09-14. Defines what an implementation agent should create and wire for P2–P4. Assets described here have **not** been generated. The [architecture audit](ARCHITECTURE_HARDENING.md) owns identity/theme separation; the [integration plan](GAME_ENGINE_INTEGRATION.md) owns delivered gems.

## 1. Art direction and required tools

Create a restrained dark work surface, quiet slate panels, warm ivory text and small brass accents. Gems remain the brightest and most detailed objects. Default palette tokens: surface `#141A22`, panel `#202A35`, raised `#2B3846`, text `#F2EADB`, muted text `#B8B6AC`, accent `#D9B978`, focus `#EAF6FF`, danger `#E87F79`. These are starting tokens; verify contrast and gem recognition in the actual game. Never identify an action or hazard only by color.

The required prototype pack can be made entirely with tools already available: repository edits for SVG/Godot scenes/themes; Godot 4.6.1 for import, rendering and playback; Python's standard `wave`, `math`, `struct` and `random` modules for offline synthesized SFX. `C:/Python314/python.exe` is available on this workstation; otherwise discover a configured Python runtime. No purchased asset pack, external audio generator, image-generation subscription or unverified font download is required.

Use native vector/code geometry for UI and simple VFX. Use the image-generation tool only if an optional illustrated bitmap background is deliberately chosen later; follow the imagegen skill then. The initial pack has no dependency on that choice. There is no installed specialist music/SFX generation tool being assumed by this plan. No music or voice-over is required for the three-room prototype.

## 2. Files, profiles and reproducibility

Create these assets under the workspace paths in the architecture document:

| Item | Source / accepted output | Production method |
|---|---|---|
| UI style | `assets/ui/themes/workshop.tres`; neutral alternative theme | Shared Godot Theme, StyleBoxFlat, font/spacing tokens |
| Icons | `art_source/game/icons/*.svg` → accepted `assets/ui/icons/*.svg` | Edit vector paths directly; one coherent style |
| Tier glyphs | `assets/ui/tiers/tier_01.svg` through `tier_08.svg` | Clean contour of the approved tier shape, separate from gem body |
| Rubble | `assets/ui/board/rubble_intact.svg`, `rubble_cracked.svg` | Layered vector shards with stable outline and contrasting cracks |
| Background | `scenes/ui/work_surface.tscn` plus presentation palette | Code/native gradient, edge vignette and sparse line texture; no semantic bitmap text |
| VFX | `scenes/effects/*.tscn` with shared motion profile | Tween/Line2D/Polygon2D/simple sprite transforms and pooling |
| SFX source | `art_source/game/audio/prototype_sfx.json` and `tools/game/build_prototype_sfx.py` | Offline recipes, fixed per-cue seed and waveform parameters |
| SFX output | `assets/audio/sfx/<cue_id>.wav` | 48 kHz, mono, signed 16-bit PCM WAV |
| Vocabulary | `data/localization/en.csv` plus generated expanded-text test catalog | Stable keys and named placeholders; no rules encoded in labels |
| Presentation | `data/presentation/workshop.tres`, `neutral.tres`, cue definitions | Map mechanical/event IDs to text/icon/audio/VFX without changing simulation |
| Provenance | `art_source/game/manifest.json` | Source, generator version/recipe/seed, license or authorship, output SHA-256, acceptance record |

P2 implements `python tools/game/build_prototype_sfx.py --recipes art_source/game/audio/prototype_sfx.json --output generated/game/sfx-new-candidates` and `godot --headless --path . --script tools/game/check_presentation_content.gd`. Write candidates to generated output first, audition/inspect, then promote only selected outputs into `assets/`. Do not overwrite accepted assets during unattended recipe experiments. Version accepted recipes with their outputs. The user accepted ten v3 resonant material cues on 2026-09-14; exact output hashes, feedback and reference-only provenance are in `art_source/game/manifest.json`. The remaining four cues belong to later content stages.

Use Godot's embedded default font initially, avoiding an external font dependency. If a later custom font is selected, add its actual license and coverage tests before acceptance. Use theme font sizes rather than rasterized text or hardcoded per-label overrides. Accepted runtime assets live in the game PCK; only gemstone deliveries belong in `gem-assets.pck`.

## 3. UI and graphic inventory

Create 19 semantic icons: `action_budget`, `tactic_charge`, `exchange`, `clear_target`, `promote_target`, `family_quartz`, `family_beryl`, `family_corundum`, `first_clear_discount`, `neighbor_range`, `objective_clear`, `objective_deliver`, `objective_flagship`, `back`, `confirm`, `pause`, `restart`, `audio`, `inspect`. Add eight tier glyphs and the two rubble states. Navigation arrows can be drawn by reusable controls; do not create dozens of nearly identical files.

Icon specification: SVG `viewBox="0 0 64 64"`, transparent background, 6px safe inset, 3px main stroke, rounded line joins, maximum three filled shapes plus simple detail. Use a monochrome light asset with UI tint tokens where appropriate; these are UI symbols, never recolored gem bodies. Check at 24, 32 and 48px. Resource icons must remain distinct by geometry: action budget uses three horizontal ticks, tactic charge a small open radial motif. Tool silhouettes: two opposing arrows, wedge/chisel, upward faceted arrow. Family emblems: Quartz three short columns, Beryl hexagonal ring, Corundum paired chevrons. These emblems are game symbols, not crystallographic diagrams.

Tier glyphs use the same orientation/envelope as the active gem grammar, with a fixed numeral badge outside the stone. Rubble uses 112×112 logical canvas, three broad gray chunks; the cracked variant adds two obvious dark cracks and lighter exposed edges. Durability pips are live UI controls, not baked into the image. Broken rubble uses the VFX and then an empty cell, not a persistent third sprite. Outlets are drawn as an inset bracket and directional notch with visible threshold text; inactive/active states change pattern as well as color.

Build reusable panel/button/card components with normal, hover, pressed, focus, disabled and selected states. Focus is an ivory double border; selection uses corners/ring; disabled controls retain readable labels and explain unavailable costs/targets. Never rely on yellow tinting of a gem for selection. All decorative board/tile children remain `MOUSE_FILTER_IGNORE`.

At 1920×1080, use the existing approximately 960px board region and 112px gem canvases. Theme spacing scale 4/8/12/16/24/32px; initial body text 20px, secondary 16px, major counters 28px and screen heading 32px. Treat these as a starting layout profile, not pixel constants in core. Verify the current 1600×900 window and 1280×720 stress layout with approximately 80px cells. Reserve enough room for longer labels and wrap descriptions rather than covering the board.

Required UX screens/components: main menu; room briefing; objective/resource/tool HUD; collection strip and selected-piece inspector; pause/accessibility options; carry selection; reward cards; two-card route selection; room/run results; save incompatibility and asset-load failure panels. Early P2 can use plain panels; by P4 they share the same theme and vocabulary. HUD updates from view-model changes, not per-frame state polling. Modals own focus and return it on close; keyboard actions share command validation with mouse input.

## 4. Background and motion assets

Use one reusable procedural background for all three room types. Draw a dark vertical gradient, low-opacity edge vignette and sparse broad seam lines outside the board's central area. The board itself is a uniform dark inset with visible active-cell boundaries; holes show the surrounding surface. Room identity comes from title/objective/thumbnail and a small accent palette change, not three noisy paintings. Generate thumbnails from authored room geometry, not hand-painted images that can become inaccurate.

An optional bitmap brief, only after the procedural version is accepted: “Top-down restrained jeweler's dark slate work surface, broad soft texture, low contrast, cool charcoal and muted warm edges, empty central 65 percent for a game board, no gemstones, tools, letters, symbols, UI, people or sharp bright highlights; evenly lit, seamless-feeling composition.” Generate one 16:9 source with the available image tool, inspect it, and derive an accepted 1920×1080 background using normal asset tooling. Record the actual tool output size and provenance; do not assume the generator returns the requested dimensions. It is decoration only; missing optional decoration uses the explicitly authored procedural profile.

Required VFX use lightweight reusable nodes:

| Effect | Trigger and construction | Timing / bound |
|---|---|---|
| Selection/focus | Ring/corners around selected cell | Static; no pulse required |
| Invalid action | Small position nudge of the selected view | 100 ms; ≤3px; zero motion in reduced mode |
| Match commitment | Thin outline over source component, then merge convergence | 80–120 ms; shared component cue |
| Promotion | Scene scale 1→1.08→1 plus delivered upgrade clip | 160–220 ms transform; clip duration remains its delivered metadata |
| Obstacle hit/break | Crack flash, then at most six triangular chips on break | 80/180 ms; no chips over HUD |
| Family reaction | Emblem pulse and a short line/ring from source to actual targets | 120–180 ms; show cause before target outcome |
| Extraction | Translate piece toward actual outlet, fade, update contract | 180–250 ms; count once from committed event |
| Room result | Quiet panel fade and objective mark | 180 ms; no fullscreen flash |

All timings live in a motion profile. Reduced motion replaces travel/chips/nudge with still outlines and brief fades; identical rule results. Do not repaint facet geometry or claim a UI sparkle is simulated optical behavior. Pool transient effects; initial caps: 24 live transient nodes, 12 chips, one family cue per committed activation. Collapse repeated cosmetic flashes at high speed while preserving causal explanation and final view.

## 5. Sound generation brief

Build 14 original synthetic cues. The recipes below are a complete starting direction, not assertions that uncreated sounds are pleasant. Audition and tune them together. Use short envelopes with at least 3 ms attack and 8 ms release to avoid hard truncation. Keep generated signal peaks at or below 0.5 full scale initially; never normalize every sound to maximum amplitude. Do not use simulation RNG for noise or pitch.

| Cue ID | Recipe at 48 kHz | Duration |
|---|---|---:|
| `ui_nav` | Soft sine at 660 Hz, rapid decay | 45 ms |
| `ui_accept` | Quiet 660 then 880 Hz sine taps | 90 ms |
| `ui_reject` | Two muted descending 330/247 Hz taps | 120 ms |
| `tile_swap` | Low-level seeded noise burst with smoothed amplitude, slight stereo positioning by cell handled in playback | 70 ms |
| `match_commit` | Decaying partials 740/1110/1850 Hz at weights 1/.35/.15 | 110 ms |
| `tile_promoted` | Three soft sine attacks at 523/659/784 Hz, spaced 45 ms | 190 ms |
| `obstacle_hit` | Short low-pass-smoothed noise plus 150 Hz damped sine | 80 ms |
| `obstacle_broken` | Three decreasing noise taps, 35 ms apart, quieter 220 Hz tail | 160 ms |
| `family_quartz` | Two clear but quiet partials 880/1320 Hz | 120 ms |
| `family_beryl` | Two rising tones 587/784 Hz with soft overlap | 160 ms |
| `family_corundum` | Two compact low taps 196/294 Hz | 110 ms |
| `tile_extracted` | Soft rising 659/880 Hz pair with longer release | 230 ms |
| `room_complete` | Quiet 523/659/784 Hz chord revealed sequentially | 350 ms |
| `run_failed` | Gentle 392/330 Hz descent; no loud alarm | 240 ms |

Implementation recipe: sum weighted sinusoids with sample-time envelopes; generate bounded noise with a fixed local Python seed derived from cue ID; smooth noise with a documented one-pole coefficient stored in the recipe. Apply gain/envelope, check finite samples, clamp only as a final guard, quantize to signed 16-bit PCM and write WAV through `wave`. Any clamping during normal generation is a failed candidate: lower gain and regenerate. Source parameters, generator version and file hash go into the manifest. Identical outputs require the same recorded generator/runtime environment; this offline synthesis is not part of cross-platform game determinism.

No extra tool-activation sound is necessary: tool UI uses `ui_accept`, followed by the relevant swap/hit/promotion event sound. Avoid playing `match_commit` once per removed gem. Play one per component and aggregate simultaneous identical hits. Family cues sound only on a committed effect, not a skipped target. A terminal recovery can reuse `tile_extracted` under a distinct event mapping without becoming a delivery in simulation.

Create buses `Master`, `UI`, `GameSFX`, and an unused-by-default `Music` bus for later content. Configure volume/mute through user settings, independent of saved rules. Use a limiter on the master bus and conservative source levels; control polyphony before relying on the limiter. Godot supports routed buses/effects for this separation. [Godot audio buses](https://docs.godotengine.org/en/4.6/tutorials/audio/audio_buses.html).

Initial playback cap: eight voices total, at most four game-impact voices, reserve a voice for UI and results; drop/coalesce low-priority duplicate hits before results/family/extraction cues. Same cue cooldown 50 ms except explicitly sequenced UI events. If speed mode skips a burst, summarize it with one cue; never replay all missed sounds afterward. No sound communicates required information without a visible counterpart.

## 6. Wiring and ownership

### Foundational motion acceptance

Basic fluidity is P1-A work using existing gem assets. Animate independent
unsupported stacks concurrently, with coherent acceleration and full journeys;
short falls land before long falls, and ordinary cell crossings do not restart
motion. Keep stable instances, spawn spacing, support and complete bent/portal
paths. Decorative landing tails are cancelable and need not block unrelated
movement. Use a whole-wave barrier before the next match where independence is
unproven. Preserve visible upgrade chains before gravity.

The normal player must not await every one-cell movement in global sequence.
Retain that player as a reference, not the intended final feel. Test actual
accepted actions and inspect recorded motion; a gem-clip burst or final snapshot
cannot establish concurrent falling. See the
[P1-A plan](../plans/P1_FLUIDITY_AMENDMENT.md) for release/skew/path, cancellation
and CPU/frame acceptance. Art production, cue tuning and HUD decomposition stay
in their named later stages.

The original profiles' speed/reduced-motion settings change presentation only.
The implemented [merge-window successor](../core/run/MERGE_WINDOW_PREPARATION.md)
has an explicit mechanical timing/accessibility policy: input uses the published
post-merge board on its first drawn frame, live promoted identities remain
selectable during decoration, and consumed ghosts are noninteractive. Reduced
motion preserves the same window duration. Practice, focus loss and visible
stall pauses are explicitly assisted records. Cosmetic delays cannot secretly
create extra reaction time or matches. Native performance remains an open
successor release gate, separate from functional playback evidence.

### Media and view ownership

Add a game `PresentationCatalog` separate from GemDeliveryCatalog. It maps semantic event/action/resource IDs to optional VFX/audio/icon/text entries. A `GamePresenter` consumes immutable view models and ordered committed events. A `CuePlayer` handles media pools, and `TimelinePlayer` handles ordering/transforms. Neither writes Work, Craft, hazards or objectives. GemForge remains the only gem-page owner.

UI hover/focus sounds are local presentation events. Gameplay sounds/VFX follow timeline playback, not simulation emission time, so a solved turn does not play every effect before its animation. Track presentation generation/action IDs to avoid double playback after resume or repeated acknowledgments. On navigation/restart cancel tweens, stop queued sounds and release pooled references belonging to the old generation. Fast-forward snaps to the authoritative snapshot without repeating payouts or notifications.

Preload the active game's small UI/SFX set at session start. Validate required cue/profile references and optional omissions explicitly. A muted channel is intentional; a missing required file is an admission failure with an error message. Do not route sound/video through the optical asset factory or add fake gem clip roles for button hover and rubble.

## 7. Delivery stages and verification

| Stage | What to make and wire | Exit evidence |
|---|---|---|
| P1-A — restore fundamental motion | Concurrent complete journeys using existing gem assets; coherent fall curves, stable path identity and safe cancellation | Actual-action motion review, rule checkpoint equivalence, measured input/CPU/frame/playback timing; keep unmet gates open |
| P2 — functional presentation kit | One shared theme/vocabulary, procedural background, resources/tools/clear-objective icons, rubble states/outlet primitive, basic focus/error/merge/hit cues | One room plays with correct costs/terms, readable target states, keyboard focus and mute; no hidden simulation access |
| P3 — expedition coverage | Carry/reward/route/briefing/results panels, remaining family/settings/objective icons, family/extraction/result cues | Every three-room state has a mapped icon/text/cue and useful empty/error state |
| P4c — complete presentation pack | Finish all 19 icons + 8 glyphs + 2 rubble states, 14 WAV cues, listed VFX, workshop and neutral profiles, asset provenance and package coverage | Art/audio gallery, two-profile pivot test, reduced motion, expanded text, lifecycle tests and release audit |
| P5 — accept in game | Test actual desktop executable with the gem pack and all UI/audio assets | Human visual/audio review and measured loading/frame/voice/memory evidence |

Required review tools to implement with P4c: a Godot presentation gallery showing all icons/control states/board overlays and triggering every cue; a headless reference/dimension/audio-header checker; an asset manifest with selected outputs and hashes. Render native 1080p and 720p screenshots for inspection. Review SFX through actual playback at normal listening volume; file headers or waveform plots cannot establish sound quality. Also audition a dense cascade, simultaneous obstacle hits, volume/mute and menu restart.

Acceptance: no icon clipping or illegible badge, no text overflow in expanded English, grayscale distinctions, correct focus order, no high-contrast fullscreen flashing, no audible clicks/clipping/fatiguing cue stacking, no late voices after navigation, no cold asset loads during a declared cascade, and no missing export references. Proposed budgets: ≤16 MiB live non-gem texture payload for the active procedural prototype profile and ≤2 MiB decoded SFX, tracked separately from the ≤16 MiB gem target; measure fonts, scene overhead and temporary decode memory separately. No claim of meeting these budgets until measured.

The implementation handoff is executable with repository code tools, the installed Godot and Python. If optional raster illustration is selected, use the available image-generation tool with the brief above and retain source/provenance. Music, licensed font procurement, voice acting and extensive painted biome backgrounds remain outside prototype scope.
