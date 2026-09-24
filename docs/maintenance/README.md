# Documentation maintenance

The 2026-09-24 cleanup separates active state, design intent, engineering/production
guidance and future work. It does not change runtime code, assets, contracts,
fixtures or historical results. [The index](../README.md) owns reading routes.

## Updating the package

- Keep current state in `docs/current/STATE.md`; link dated evidence rather than
  duplicating measurements and journals.
- Keep intent and user-confirmed choices under `docs/design/`. Mark proposals,
  assumptions and unanswered fields explicitly.
- Keep next work/status in `plans/prototype/README.md`; create detailed execution
  tasks when needed, with bounded outputs and evidence requirements.
- Keep behavior beside its owner in tracked contracts/source/tests. Current
  guides explain boundaries and route readers there.
- Archive superseded narratives with exact bytes, original path and SHA-256.
  Replace them with a redirect where historical/external links need that path.
  Do not rewrite frozen reports to make their links or old claims look current.

Docs/plans are versioned, including preserved archives. Keep generated media, raw
review output and tool installations under ignored `generated/` or `artifacts/`.
See [setup and recovery](../BUILDING.md) for the source-control boundary. Commit
compact decisions and reproducible recipes with links to evidence; transfer the
evidence separately when a future task needs the original observations. Archive
attributes preserve original bytes across Git checkout on different machines.

## Reorganization verification

Run from the repository root, choosing a new report path:

```powershell
python docs/maintenance/check_documentation.py --report artifacts/documentation/2026-09-24-reorganization/check-new.json
```

This checks local links and heading anchors in active guides/redirects and the
all historical archive manifest hashes. Missing links under ignored
`artifacts/` or `generated/` are reported as unavailable local evidence, not broken
source dependencies; a fresh checkout can therefore pass without historical caches. It inventories the two unchanged historical reports
separately. External URLs and links inside frozen archive bodies are not rewritten
or treated as current-documentation dependencies.

To verify the original cleanup also left all protected content unchanged:

```powershell
python docs/maintenance/check_documentation.py --preservation artifacts/documentation/2026-09-24-reorganization/preservation.json --report artifacts/documentation/2026-09-24-reorganization/preservation-check-new.json
```

The preservation snapshot covers 1,240 existing files: tracked files other than
the two root routing guides, existing local archives, and the retained authoring/
baseline/engine guides. It is dated migration evidence. Legitimate later source
changes will differ from it; do not update that baseline to manufacture a pass.

The checker validates documentation structure/preservation only. It does not
rerun game, optical, performance, visual or listening acceptance. The archive
manifest and the cleanup report record what was checked.
