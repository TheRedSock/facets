# CPU completion observer and readiness boundaries — 2026-09-22

This correction is implemented and focused checks pass; full release acceptance
is pending. No thresholds, simulation rules, animations or historical results
have been changed.

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
