# Lapidary Evaluation Notes

Generated 2026-08-18T10:15:58 on NVIDIA GeForce RTX 4060 Laptop GPU by `tools/eval_sheets.gd` (windowed CLI).

Sheets: `contact_sheet.png`, `grade_sheet.png`, `lighting_sheet.png`, `rung_sheet.png`.

## Timings

```
single stone by rung - ruby maker - median chunk dispatch scaled to full spp
rung           res   spp  chunk     chunk ms     frame ms
interact       128     4      1        0.473         1.89
preview        256    32      8        8.612        34.45
board_live     112     8      8        1.557         1.56
clip_bake      224   160     32       26.151       130.76
hero           768   512      8       66.939      4284.10

batched BOARD_LIVE - 112px cells - 4 maker stones cycled - median of 5
gems       ms/frame     ms/gem
1              2.44      2.445
16            13.73      0.858
64            60.02      0.938
```

## Summary

- Contact sheet: 12 stones (8 authored .tres + 4 in-code makers) all render non-empty with distinct silhouettes and body color under the gameplay rig; the print row darkens mids and reins in chroma relative to raw.
- Grade sheet (corundum ruby, stops 0.15-1.00): low cut shows windowing streaks and outline jitter, low surface shows scratch glints, low crystal shows body haze; clarity silk is the subtlest axis at 176 px.
- Lighting sheet: gameplay rig reads warm with dark-field facet contrast; reference daylight is neutral and flatter; raw-vs-print deltas are visible but small at 64 spp; diamond fire barely reads at 224 px.
- Rung frame cost (ruby maker): interact 1.89 ms, preview 34.45 ms, board_live 1.56 ms, clip_bake 130.76 ms, hero 4284.10 ms at 512 spp; low-grade quartz scatter noise only clears at clip_bake and above.
- BOARD_LIVE batch scales sublinearly: 1 gem 2.44 ms/frame, 16 gems 13.73 ms, 64 gems 60.02 ms (0.938 ms/gem at 64).
