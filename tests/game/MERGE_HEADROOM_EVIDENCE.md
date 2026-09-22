# CPU completion observer and readiness boundaries — 2026-09-22

The full normal and 2x CPU corpora, final r8 native/control checks and delivery
verification pass. See [final readiness](MERGE_FINAL_READINESS.md) for combined
evidence and scope. The chronology below preserves earlier pending/failed states.
No thresholds, simulation rules, animations or historical results were changed.

## Evidence and correction

The prior feedback CPU smoke failed command readiness p95 at 40.454 ms against
37.5 ms. Its raw records show command completion-to-publication p95 of 15.117 ms.
That interval includes publication but also the CPU driver's requested 100 µs
polling sleep. It is not all worker calculation. The unchanged older build failed
similarly; these reports remain intact.

`headroom-polling-r1` is a fresh instrumented release of unchanged gameplay. The
15-room run passed: command readiness p95 20.589 ms, service p95 17.000 ms,
completion-to-publication p95 2.325 ms. Requested 100 µs sleeps actually reached
p95 2.441 ms. These observations demonstrate variable observer overhead; they do
not prove the exact OS mechanism behind each older slow sample. The earlier
standalone editor sleep experiment is only diagnostic (and encountered sandbox
startup/certificate errors); it is not release acceptance. A release-template
script override was ignored, and that process was stopped without claiming a
result. Relevant raw evidence is under `artifacts/game/merge-readiness/`.

The default accelerated CPU observer now waits for a semaphore posted only after
a current-generation completion mailbox is filled. It still performs the real
poll/publication and measures through their completion; no measured time is
subtracted. A stale wake cannot publish a superseded default. Every job drains
previously consumed mailbox notifications before scheduling the next work. The
external process watchdog bounds a broken worker. `-CpuPolling` retains the old
observer for controlled comparison. Native gameplay uses its existing nonblocking
frame polling and has independent frame/input/deadline acceptance.

The timing audit also corrected an omission: command latency previously started
after reservation admission. It now starts at receipt. Gravity follower latency
and its deadline now share the recorded presentation boundary, before animation
setup. Tool deadlines likewise start at receipt. These changes make the measured
scope stricter; mechanical/replay identities and animation durations are unchanged.

## Focused verification

- `headroom-observer-source-r1`: four stages passed (source, executor, replay,
  editor CPU smoke), before the additional receipt-boundary correction.
- `headroom-boundaries-source-r1`: all six stages passed with stable source
  (source, executor, replay, native playback, input, editor CPU smoke).
- `headroom-gravity-boundary-r1`: executor regression passed, including explicit
  receipt/gravity timestamps, notification exactly once, private default,
  cancellation, failed demand wake-up and worker teardown.

Full frozen release corpus, stress and final native confirmation remain required
before this correction can establish G6 readiness.

## Full normal release corpus

Runtime checkpoint `7156cc9`; immutable package `generated/desktop/merge-readiness-r6`;
build manifest `artifacts/package-build/20260922-104131-9366/report.json`.
The same-build smoke and former-polling control both passed (command p95
24.154 and 22.262 ms respectively). This pair does not establish a speedup.

`r6-cpu-full/release/run.json` passed all frozen normal targets across three
repetitions × 100 seeds × five policies: **1,500 rooms, 51,873 batches**, with
zero deadline misses or engine errors. `r6-cpu-full-audit.json` independently
recalculates every raw deadline, count and nearest-rank latency percentile and
matches all final mechanical digests, phases, batch and intervention counts to
the preserved full reference in `g6-cpu-final-r1`. Scheduling cancellation counts
are not mechanical identity and are deliberately not compared as gameplay.

| Normal r6 measurement | p95 | Maximum |
|---|---:|---:|
| Command ready latency | 20.803 ms | 54.628 ms |
| Command ready / available interval | 0.138687 | 0.364187 |
| Gravity follower ready latency | 23.916 ms | 54.766 ms |
| Gravity ready / available interval | 0.063575 | 0.164181 |
| Default ready latency | 25.121 ms | 56.193 ms |
| Main scheduling per operation | 2.057 ms | 5.571 ms |
| Command completion to publication | 0.856 ms | 2.303 ms |

Main per-operation figures are not native per-frame totals. Whole-process peak
working set was 412,200,960 bytes; sampled private peak was 305,123,328 bytes,
including retained raw probe records, worker/snapshots and engine allocations.
The temporary awake request acquired and released successfully; 9,454 environment
samples are retained. No global power preference changed.

The fresh normal-profile CPU margin failure is closed on this measured package.
Full r6 2× stress, final native measurements, integrated affected controls and
new delivery verification remain pending. Prior reports and failed gates remain
historical evidence; P3 readiness is not yet declared.

## Full doubled-computation release corpus

`r6-cpu-stress2x/release/run.json` passed all **1,500 rooms / 51,873 batches**
with zero deadline misses and no engine errors. `r6-cpu-stress2x-audit.json`
independently checked every raw interval and matched every reference outcome.
Command ready p95/max was **38.037/82.074 ms**; gravity follower was
47.522/112.350 ms; default was 50.560/130.204 ms. Command readiness ratios were
0.253580/0.547160. Those exceed the stricter normal-profile reserve margins,
but the frozen 2× requirement is zero deadline misses, with margins reported.
No threshold has been changed. Main scheduling per operation was p95 2.394 ms,
max 7.026 ms; native per-frame totals remain a separate gate.

Whole-process peak working set was 407,764,992 bytes; sampled private peak was
302,997,504 bytes. The temporary awake request acquired/released successfully;
17,032 environment observations are retained. Final r6 native/control checks
and delivery remain pending.

## Native frame-pacing investigation

The completed r6 native 1280x720 run (`r6-native-720/release/run.json`)
failed two unchanged normal thresholds: default visible handoff p95 17.932 ms
versus 16.7 ms, and demand readiness p95 ratio 0.258487 versus 0.25.
All five policies and 40 fixed release cases completed without starvation or
deadline misses. Frame p95/max was 16.164/37.026 ms. This is a reserve/pacing
failure, separate from the historical second-long Modern Standby stalls.

An explicit diagnostic override on the identical r6 package, `-MaxFps 0`,
passed (`r6-native-720-uncapped-diagnostic/release/run.json`): handoff p95
8.328 ms, demand readiness ratio p95 0.181187. However, the existing mailbox
VSync mode rendered 70,713 measured frames, with median 0.654 ms intervals.
That excessive frame rate is not an adopted default. Its main-thread series
also reaches the existing 4,096-record per-room limit, so this experiment is
diagnostic evidence, not complete final performance acceptance.

Pinned Godot 4.6.1 sources show that its software FPS limiter uses
[`OS::delay_usec`](https://raw.githubusercontent.com/godotengine/godot/4.6.1-stable/core/os/os.cpp),
whose [Windows implementation](https://raw.githubusercontent.com/godotengine/godot/4.6.1-stable/platform/windows/os_windows.cpp)
uses `Sleep`, including a one-millisecond request for sub-millisecond delays.
The comparison implicates pacing/wait overhead; it does not establish the exact
cause of every historical slow frame. A configuration-only r7 experiment uses
standard VSync (1) and no extra software cap (0). Godot's
[VSync contract](https://docs.godotengine.org/en/4.6/classes/class_displayserver.html#enum-displayserver-vsyncmode)
describes that mode as monitor-refresh limited, unlike mailbox mode (3).
Its actual frame rate and unchanged timing gates must be measured before adoption.
No gameplay, animation duration, deadline, rule cap or simultaneous-match
behavior is changed by this experiment.

The r7 standard-VSync experiment failed: frame p95 18.187 ms, handoff p95
31.578 ms. The rendering change was reverted. A finite 240 FPS override on r6
also failed handoff (18.069 ms), so raising the cap was not adopted either.

The r7 feedback outliers exposed a separate probe attribution defect: an
attempted gesture that arrived after expiry was timed against a gem's later
gravity motion even though no swap had been admitted. Checkpoint `b0b9437`
records explicit admission/rejection and retains all attempted/accepted/expired
counts. Unexpected rejection and lost/superseded accepted feedback fail the
probe. It also drains completed main-frame telemetry before its ordinary-room
retention cap, keeping the entire measured population. `receipt-attribution-r1`
passed source plus 98 assertions each in headless/native input modes, including
a stale tick-19 observation whose actual receipt correctly rejects at expiry.
No game rule or timing target changed.

The r8 package (`artifacts/package-build/20260922-115724-0176/report.json`)
differs from r6 in `scenes/debug/merge_probe.gd` alone among 259 runtime inputs.
Its native test with an explicitly always-on-top test window, original mailbox
VSync and original 120 FPS cap passed at 1280x720 (`r8-native-720-visible`):
frame p95/max 15.066/19.217 ms, handoff 15.196/16.306 ms, feedback
8.839/11.186 ms, readiness ratio 0.1452/0.182953, main 0.267/4.015 ms.
All 40 fixed cases passed; all 80 gestures were accepted, so the correction
did not remove any rejected-input samples from this passing run. All 7,197
active frames have main-thread samples.

The remaining profiles and a repeated normal 720p run also passed. Independent
`r8-native-*-audit.json` reports recompute every raw quantile, demand deadline,
input-attribution count and complete frame population, and verify all 40 fixed
cases and exact package bytes per run.

| r8 visible profile | Frame p95 | Handoff p95 | Readiness ratio p95 |
|---|---:|---:|---:|
| 1280x720 normal | 15.066 ms | 15.196 ms | 0.145200 |
| 1600x900 normal | 15.134 ms | 14.952 ms | 0.147460 |
| 1280x720 modeled 2x | 15.254 ms | 15.230 ms | 0.250207 |
| 1600x900 modeled 2x | 10.608 ms | 11.608 ms | 0.243167 |
| 1280x720 normal repeat | 13.861 ms | 13.755 ms | 0.190820 |

All runs had zero deadline misses/starvation, and all scoped awake requests
acquired/released. The 2x profile is judged against its frozen zero-miss criterion;
its normal reserve ratios are reported, not silently relabelled as normal passes.
The full summaries retain p50/p95/p99/max for all metrics in
`artifacts/game/merge-readiness/r8-native-summary.json`.

The window option is a per-test visibility control, not a shipped game setting.
[Microsoft documents](https://learn.microsoft.com/en-us/windows/win32/api/timeapi/nf-timeapi-timebeginperiod)
that Windows 11 may stop honoring high-resolution timer requests for occluded
applications. Visibility is therefore a testable environmental hypothesis,
not proof of the exact OS mechanism. The expanded observer confirms visible,
non-minimized, topmost test windows; it does not establish foreground interaction
(foreground reads succeeded but identified another process). No global timer, power, driver or security setting
was modified, and no physical-display-latency claim is made.
