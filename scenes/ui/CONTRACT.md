# Room presentation

RoomHudModel produces recursively immutable values from a committed RunState.
It shares RoomActionLegality for costs and disabled reasons; labels never encode
mechanics. RoomPanel owns controls and emits intents. RunScene owns selection,
command submission and generation gates, while ActionPlayer owns animation.
The normal Main scene opts into Open seam; direct RunScene remains the explicit
legacy diagnostic fixture used by the existing motion/probe checks.

Workshop assets are explicitly listed with source hashes in
data/presentation/workshop_manifest.json. The text Translation is compiled from
the source CSV by tools/game/build_vocabulary.gd and registered after engine
resource loaders initialize. Native 1600×900 and 1280×720 screenshots and exact
release probe results belong in artifacts/game/p2/presentation.

RoomAudio owns two UI and six GameSFX voices, persistent in-process mute/volume,
and generation-based cancellation. Full voice pools drop decorative cues instead
of queuing stale sounds. It loads only the manifest's selected audio resources.
While the revised material-sound candidates await listening review, that list is
empty and audio controls are disabled. Candidate recipes/synthesis stay offline.
Restart, skip, delivery failure and destruction cancel owned sound/effect work.
