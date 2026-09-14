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

RoomAudio owns two UI, four impact and two reserved result voices, persistent in-process mute/volume,
and generation-based cancellation. Full voice pools drop decorative cues instead
of queuing stale sounds. It loads only the manifest's selected audio resources.
Ten original resonant material cues were accepted by the user on 2026-09-14 and
promoted with their exact candidate hashes. WAV import preserves 48 kHz mono PCM16;
sample data totals 328,320 bytes. Candidate recipes/synthesis stay offline.
GameSFX routes impacts and results; Music remains unused. A master limiter and
50 ms non-UI same-cue cooldown bound dense effects. UI sequences bypass cooldown.
Required resource failures gate loading; Sound mute/volume remain independent of rules.
Restart, skip, delivery failure and destruction cancel owned sound/effect work.
