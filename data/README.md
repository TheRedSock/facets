# Authored data

`tiles/` holds 16 logical tile definitions in two eight-gem merge ladders.
`spawn_tables/` holds optional simulation spawn tables with integer weights.
Board layouts use `BoardLayoutResource`.

`lapidary/` holds optical species/index curves, absorber spectra, materials,
conditions, shapes/cuts, stones, recipes, clips, rigs, print/style and explicit
asset batches. Add a physical gem through these resources and a `GemAssetRequest`;
changing a material does not automatically change gameplay tiers or merge rules.
`GemGrade` is metadata. Optical evidence is stored with the physical inputs.

The [factory contract](../core/lapidary/factory/CONTRACT.md) defines realization,
identity and delivery. The [tools guide](../tools/README.md) defines build commands.
Generated worker stores and delivery packages live outside this authored data
directory. There is no GemVisualResource or runtime optical registry.
