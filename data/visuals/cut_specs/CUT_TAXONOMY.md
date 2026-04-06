# Cut Taxonomy

This file maps the authored cut specs to the eight face-up silhouette buckets used by the realism pass:

- `round`: 8 or more visible outline edges
- `square`
- `triangle`
- `diamond`: rhombus / lozenge / kite-family
- `hexagon`
- `rectangle`
- `oval`: includes marquise-family variants
- `special`: pear, heart, shield, pentagon, and other non-core fancy outlines

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
| `trillion` | `triangle` | `textbook` | Curved-side trillion / trilliant family. |
| `straight_trillion` | `triangle` | `modified_standard` | Straight-sided trillion variant. |
| `lozenge` | `diamond` | `textbook` | Standard lozenge cut with step-cut tiers. |
| `lozenge_radiant` | `diamond` | `modified_standard` | Radiant-style modified lozenge retained as an alternate rhombus cut. |
| `kite_brilliant` | `diamond` | `modified_standard` | Offset kite brilliant that still reads inside the diamond family. |
| `hex_brilliant` | `hexagon` | `modified_standard` | Alternate brilliant-style hexagon cut. |
| `hexagon_step` | `hexagon` | `textbook` | Standard hexagon step cut. |
| `half_dutch_rose_hex` | `hexagon` | `fantasy_designer` | Custom hex rose, retained as a fantasy/designer cut. |
| `baguette_step` | `rectangle` | `textbook` | Narrow rectangular step cut. |
| `tapered_baguette_step` | `rectangle` | `textbook` | Tapered baguette side-stone family. |
| `emerald_step` | `rectangle` | `textbook` | Classic emerald-cut step family. |
| `opal_cushion` | `rectangle` | `fantasy_designer` | Soft rectangular cushion reserved for opal-led patterned studies. |
| `patterned_cushion` | `rectangle` | `fantasy_designer` | Neutral patterned cushion used by non-opal material studies. |
| `oval_brilliant` | `oval` | `textbook` | Standard oval brilliant. |
| `antique_oval` | `oval` | `modified_standard` | Vintage oval with a smaller table and taller crown. |
| `marquise_brilliant` | `oval` | `textbook` | Marquise / navette treated as an oval-family fancy variant. |
| `pear_brilliant` | `special` | `textbook` | Standard pear brilliant. |
| `heart_brilliant` | `special` | `textbook` | Standard heart brilliant. |
| `shield_brilliant` | `special` | `fantasy_designer` | Designer shield cut with a broader crown and tapered lower flanks. |
| `pentagon_brilliant` | `special` | `fantasy_designer` | Designer pentagon brilliant. |
| `octagon_step` | `square` | `modified_standard` | Step-cut octagon that reads as a clipped-corner square. |
| `radiant_octagon` | `square` | `modified_standard` | Radiant-style octagon that reads as a clipped-corner square. |
