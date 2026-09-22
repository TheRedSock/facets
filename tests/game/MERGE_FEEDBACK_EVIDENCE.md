# Input feedback and stall investigation — 2026-09-22

Later [observer/boundary correction evidence](MERGE_HEADROOM_EVIDENCE.md) records
a passing full normal CPU corpus. The measurements below remain scoped to the
feedback builds; final r6 stress/native/control and delivery checks are pending.

The requested tool/sound fixes and one pending swap are implemented and verified.
The second-long stall is strongly associated with the overnight screen-off power
state; its exact internal blocking operation is not proven. Full P3 readiness
is still not declared: a fresh CPU-only headroom check missed its margin even
though all current native profiles completed without missed deadlines.

## Implementation and regression

`d6a5ef7` fixes unavailable tool selection, Escape/button/toggle cancellation and
rejected-target recovery. Committed promotion/rubble sounds now accompany the
successor merge; reduced-motion playback in the older trial summarizes committed
cues rather than suppressing them. No accepted audio files were regenerated.

`5a9e3d8` adds one presentation-only buffered swap during swap/gravity motion.
It follows the selected live gem IDs, replaces an older pending pair on a new
gesture, and shows cyan outlines/link plus status feedback. The next eligible
phase admits it once with normal legality, price, context and full animation.
Invalid/disappeared/nonadjacent targets cancel without spending. Focus/pause,
restart/menu, failure/terminal and restore discard unadmitted intent. Mechanical
protocols/goldens are unchanged; accepted moves use ordinary replay records.

The immediate restart/navigation witness exposed abandoned loading coroutines.
GemForge now owns callback-based loading; a freed room receives no callback and
an older generation cannot replace a new room. This corrected the strict leak
failure instead of ignoring it. Accelerated audio tests also allow 0.5 real
seconds for the mixer to drain stopped voices before engine shutdown.

Fresh reports under `artifacts/game/merge-readiness/`:

- `feedback-fixes-r1/r2`: new tool/audio assertions, source/import, merge, trial
  and original room playback. The first retained trial report had mixer resources
  at shutdown; its corrected repeat passed strict checks.
- `buffer-r5`: all six source/delivery/headless-input/native-input/native-playback/
  replay stages passed. Input suites each passed 95 assertions.
- `buffer-final`: native input plus both older audio/playback controls passed.
  The 1280×720 buffer screenshot was inspected using synthetic test gems.
- The new actual release passed all 40 fixed cases on every native run below,
  including actual mouse buffering during normal/reduced gravity.

## Power-state evidence and controlled comparison

`stall-power-timeline.json` records Kernel-Power entry into Modern Standby at
00:40:44 and exit at 06:59:21 (local time, UTC+02). The previous r5 long-stall
reports at 02:12–02:38 fall inside that interval. Windows also records an earlier
idle entry at 23:45. No matching Security lock events were available; absence of
those events is not proof the machine was unlocked.

Microsoft describes Modern Standby as encompassing screen-off power states, and
documents desktop application suspension/throttling during those states:
[standby states](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby-states),
[desktop activity moderation](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/integrating-apps-with-modern-standby).
These explain why the old measurements cannot cleanly isolate a gameplay or
driver defect. They do not identify the exact cause of each individual frame.

The new diagnostic wrapper uses a temporary
[execution-state request](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate)
and records idle/default-desktop/screensaver observations. All requested guards
acquired and released successfully. No global power/driver/security setting was
changed and no user input was synthesized. The observer did not identify Facets
as the OS foreground window; its near-zero idle readings must not be presented
as proof of real player activity or physical display latency. Godot's actual
rendered-frame and functional measurements remain the evidence below.

| NVIDIA, feedback r1 build | Frame p95 / max (ms) | Result |
|---|---:|---|
| 1280×720, 1×, awake request | 11.080 / 33.017 | Passed |
| 1600×900, 1×, awake request | 16.321 / 29.471 | Passed |
| 1280×720, 2×, awake request | 16.237 / 31.248 | Passed |
| 1600×900, 2×, awake request | 16.310 / 37.300 | Passed |

Reports: `stall-awake-nvidia-r1`, `feedback-native-900`,
`feedback-native-720-2x`, `feedback-native-900-2x`, each under `release/`.
All five policies completed, with zero starvation/deadline misses and no
unexpected assisted pause. Normal input/main-thread/headroom gates passed;
2× stress requires zero misses, with its tighter headroom figures reported only.

Crucially, the **unchanged old r5 executable** also completed all policies while
awake with frame p95/max 16.332/32.097 ms (`stall-awake-old-build-r1`). Its strict
run still failed on readiness p95 ratio 0.251187 versus 0.25, a distinct marginal
headroom failure. It did not exhibit a long pause. This separates disappearance
of the stalls from the new gameplay changes. `feedback-active-no-request` is an
additional passing updated-build run without any keep-awake request; it does
not deliberately induce idle or prove behavior after the display turns off.

An external PresentMon/ETW attempt (`stall-etw-nvidia-r1`) was unavailable:
Windows denied starting the trace because this account lacks the required
administrator/Performance Log Users permission. This was an OS permission error,
not an automatic approval rejection. No permission or group change was attempted.

## Remaining margin and practical next step

The updated 15-room CPU smoke completed all 578 batches with exact outcomes and
no deadline misses, but command readiness p95 was 40.454 ms against 37.5 ms
(ratio 0.269693 against 0.25). The same fresh workload in unchanged r5 also failed,
at 40.016 ms (ratio 0.266773). All 15 final mechanical digests matched exactly
(`feedback-cpu-reference.json`). Preserve both failures. This is additional
evidence about current scheduling/headroom, not a recurrence of a 1.2-second
freeze or proof of a buffer regression. The simulation, worker, hash/admission
and CPU-probe source hashes are unchanged between these builds.

The reasonable path for unattended testing is awake/power-aware captures with
interruption metadata, rather than speculative simulation optimization. Keep
the game's protective focus/stall pause. If a long stall recurs in a verified
active environment, capture thread/presentation ETW evidence before choosing
a driver/engine or game-code correction. For full readiness, separately resolve
the current CPU margin miss and repeat its affected measurements; no target has
been relaxed and no old failure erased.

## Delivery

Final build: `generated/desktop/merge-feedback-r2`, checkpoint `4cf3aff`.
This final correction leaves ordinary gravity's cues with ActionPlayer, avoiding
duplicate tool cues from the streaming owner. Reduced gravity still emits its
otherwise absent cue summary. `feedback-final-source` passed all five focused
source/input/native-input/trial/original-room checks. The r1 performance table
above remains explicitly that build's measurements; final r2 native reports are
`feedback-final-720` and `feedback-final-900`.
Both final runs passed all native gates and all 40 fixed cases. Frame p95/max
were 15.252/20.212 ms at 720p and 10.672/24.397 ms at 900p. Main-frame p95/max
were 0.255/4.689 and 0.342/7.661 ms; readiness p95/max ratios were
0.149353/0.205613 and 0.164693/0.291087. No long pause or deadline miss occurred.
Build/audit manifest: `artifacts/package-build/20260922-100800-5622/report.json`.
All 259 exported source hashes match (`feedback-source-identity.json`).
PCK SHA-256: `b1f2ed8afe01eb4fb7a126d67e93c12bb2818c4e87bb0dca8010746c4b48f3f8`.
The single updated review ZIP is
`generated/desktop/facets-feedback-review-20260922.zip`, with optional notes,
default-graphics launcher, source/package hashes and this report. The delivery
record `feedback-delivery.json` verifies every copied game file and ZIP entry.
