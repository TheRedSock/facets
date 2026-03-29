# Spawn Tables

`SpawnTableResource` `.tres` files defining which tiers can spawn and with what probability.

## Default Table

The default spawn table is created in code by `RunController._create_default_spawn_table()`:

```
allowed_tiers: [1, 2, 3, 4]
weights:       [4, 3, 2, 1]    # T1 is 4x more likely than T4
```

Place `.tres` files here to create alternative tables for different floors, modifiers, or challenge modes. Pass them via the run config dictionary.

## Integer-Only Weights

**Weights must be `Array[int]`, not `Array[float]`.** The spawn system uses integer-only weighted selection (`randi_range`) to ensure cross-platform deterministic replay. Float weights will cause type errors.
