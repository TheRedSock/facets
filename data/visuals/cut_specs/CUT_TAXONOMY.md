# Cut Taxonomy

This file maps the authored cut specs to the face-up silhouette buckets used by the realism pass. Each bucket corresponds to a distinct tier silhouette in the gameplay hierarchy.

## Core Tier Shapes (T1--T8)

These eight buckets define the silhouette progression that players use for instant tier identification:

- `round`: 8 or more visible outline edges (T1)
- `square`: square-family (T2)
- `triangle`: triangle-family (T3)
- `oval`: elliptical outlines (T4)
- `diamond`: rhombus / lozenge / kite-family (T5)
- `rectangle`: rectangle-family (T6)
- `marquise`: pointed-end boat shapes, promoted from oval-family to a distinct core shape (T7)
- `pear`: teardrop / drop shapes, promoted from special to a distinct core shape (T8)

## Reserved Shape Categories

- `polygon`: regular/semi-regular 5--7 sided shapes (pentagon, hexagon, heptagon). Reserved for potential T0 hazard/obstacle gems. The hex step, hex brilliant, hex rose, and pentagon brilliant cuts live here. These shapes are not assigned to any standard-tier gameplay gem.
- `special`: ornate, asymmetric, or organic shapes (star, heart, shield, etc.). Reserved for potential T9 transcendent/artifact gems. No standard-tier gameplay gem uses this bucket.

## Shape Complexity Progression

The tier-shape mapping follows a deliberate complexity curve:

| Tier | Shape | Rationale |
| --- | --- | --- |
| T1 | Round | Simplest scan; high-frequency tile |
| T2 | Square | Compact, easily parsed |
| T3 | Triangle | First non-rectangular; distinguishable from T1--T2 |
| T4 | Oval | Soft curves; distinct from all angular shapes above |
| T5 | Diamond | Rotated-square/rhombus; mid-rarity, visually sharp |
| T6 | Rectangle | Elongated; contrasts with T5's compact diamond |
| T7 | Marquise | Pointed boat-shape; dramatic and rare |
| T8 | Pear | Asymmetric teardrop; the most complex standard silhouette |
| T0 | Polygon | Regular polygons (5--7 sides) signal "not a normal gem" |
| T9 | Special | Ornate one-offs signal legendary status |

`Class` uses three buckets:

- `textbook`: common trade-standard cut family
- `modified_standard`: a real historical/commercial family simplified or stylized for the game
- `fantasy_designer`: custom or designer cut kept for visual variety, not presented as a textbook trade cut

| Spec | Bucket | Class | Notes |
| --- | --- | --- | --- |
| `classic_round` | `round` | `textbook` | Modern round brilliant baseline. |
| `old_european_round` | `round` | `modified_standard` | Historic round style with a smaller table and deeper profile. |
| `simple_octagon_step` | `round` | `modified_standard` | Single-cut round with an octagonal table and simple eight-main crown/pavilion layout. |
| `rose_round` | `round` | `modified_standard` | Simplified historical rose cut. |
| `double_rose` | `round` | `modified_standard` | Layered rose-family variant, simplified for gameplay readability. |
| `cross_rose` | `round` | `fantasy_designer` | Cross-centered rose kept as a custom library cut. |
| `cushion` | `square` | `textbook` | Standard square cushion brilliant / pillow-cut family. |
| `princess_square` | `square` | `textbook` | Sharp square brilliant / princess family. |
| `asscher_step` | `square` | `textbook` | Square emerald-family step cut. |
| `radiant_square` | `square` | `textbook` | Square radiant with clipped corners. |
| `octagon_step` | `rectangle` | `modified_standard` | Elongated step-cut octagon (e.g. alexandrite); reads as a clipped-corner rectangle. |
| `radiant_octagon` | `square` | `modified_standard` | Radiant-style octagon that reads as a clipped-corner square. |
| `trillion` | `triangle` | `textbook` | Curved-side trillion / trilliant family. |
| `straight_trillion` | `triangle` | `modified_standard` | Straight-sided trillion variant. |
| `oval_brilliant` | `oval` | `textbook` | Standard oval brilliant. |
| `antique_oval` | `oval` | `modified_standard` | Vintage oval with a smaller table and taller crown. |
| `lozenge` | `diamond` | `textbook` | Standard lozenge cut with step-cut tiers. |
| `lozenge_radiant` | `diamond` | `modified_standard` | Radiant-style modified lozenge retained as an alternate rhombus cut. |
| `kite_brilliant` | `diamond` | `modified_standard` | Offset kite brilliant that still reads inside the diamond family. |
| `baguette_step` | `rectangle` | `textbook` | Narrow rectangular step cut. |
| `tapered_baguette_step` | `rectangle` | `textbook` | Tapered baguette side-stone family. |
| `emerald_step` | `rectangle` | `textbook` | Classic emerald-cut step family. |
| `opal_cushion` | `rectangle` | `fantasy_designer` | Soft rectangular cushion reserved for opal-led patterned studies. |
| `patterned_cushion` | `rectangle` | `fantasy_designer` | Neutral patterned cushion used by non-opal material studies. |
| `marquise_brilliant` | `marquise` | `textbook` | Standard marquise brilliant, now a core tier shape. |
| `navette` | `marquise` | `modified_standard` | Narrower, sharper-tipped marquise variant with a more elongated profile. |
| `pear_brilliant` | `pear` | `textbook` | Standard pear brilliant. |
| `pendeloque` | `pear` | `modified_standard` | Elongated drop-shaped pear variant with narrower shoulders and a more pronounced point. |
| `hexagon_step` | `polygon` | `textbook` | Standard hexagon step cut. Reserved for T0 polygon shapes. |
| `hex_brilliant` | `polygon` | `modified_standard` | Alternate brilliant-style hexagon cut. Reserved for T0 polygon shapes. |
| `half_dutch_rose_hex` | `polygon` | `fantasy_designer` | Custom hex rose, retained as a fantasy/designer cut. Reserved for T0 polygon shapes. |
| `pentagon_brilliant` | `polygon` | `fantasy_designer` | Designer pentagon brilliant. Reserved for T0 polygon shapes. |
| `heart_brilliant` | `special` | `textbook` | Standard heart brilliant. Reserved for T9 special shapes. |
| `shield_brilliant` | `special` | `fantasy_designer` | Designer shield cut with a broader crown and tapered lower flanks. Reserved for T9 special shapes. |
