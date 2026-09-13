# Authoring and admission

`GemAuthoringDocument` is the durable editing owner. Open a supported resource or
create from a resource, edit stored property paths, inspect `validation_error()`
and `changes()`, then save or freeze. `snapshot()` is detached. Editing never
mutates a loaded catalog resource or external dependency. Arrays can be replaced
as a whole; existing Array elements can be addressed by integer path components.
Packed numerical arrays are replaced as values. Script/editor metadata is not an
editable physical property.

Invalid drafts remain undoable but cannot be saved or frozen. History holds 64
states; the comparison baseline remains the last save even when history is
trimmed. Save As refuses an existing destination without explicit `replace`.
Saving the current file checks its disk checksum, preventing silent overwrites
after external edits. A validated sibling temporary file is renamed into place.
Text save adopts the reloaded values, including Godot text precision. Binary
`.res` freeze verifies exact stored values and preserves document path/dirty
state. Frozen filenames also require explicit replacement.

`GemAuthoringAdmission` calls production job, planner, specimen and resource
validators. Context-dependent terms/conditions must be edited inside a specimen
or request. A syntactically valid cut resource still requires specimen admission
to validate its actual geometry. All specimens now compile their host geometry
during CPU admission, including plain faceted stones without defects.

Capabilities reuse the admission functions for scalar, isotropic Mueller and
uniaxial crystal policies. The report distinguishes CPU admission from untested
device requirements; `shaderFloat64` is required for crystal transport. Numerical
admission does not certify the model or its appearance. `GemAppearanceAcceptance`
binds explicit review decisions/checks to exact request, source pipeline and
provenance. A changed request makes its review stale.

`GemContentIdentity` remains the full evidence/admission identity.
`GemPhysicalIdentity` excludes audited labels, notes and optical evidence from
master/geometry inputs. New fields participate conservatively. Cut labels do not
seed manufacture; stable group/index identities own its independent channels. Material
amounts/scattering, optical curves, geometry and physical condition changes still
invalidate their participating outputs. Print changes reuse masters; style
changes reuse prints. Full renderer-source identities remain versioned.

Editing measured/published coefficients creates authored derivative evidence,
retaining the source descriptor and its digest. Concentration has evidence
separate from the absorption spectrum, so changing amount does not invalidate
the spectrum's measurement. Repeated edits keep one source parent; document
history holds intermediate drafts. Specimen variation uses the same derivation.

`generate_lapidary_data.gd` writes a fresh candidate directory and property diff
under `generated/catalog-candidates/`; it never writes canonical catalog data.
Adopt desired candidates through explicit document save/replace after review.
The generator remains a reproducible transcription/fit tool, not an owner of
subsequent authored material/stone/cut edits.

Gates: `test_authoring_document`, `test_render_dependencies`,
`test_job_validation`, `test_asset_planner`, `generate_lapidary_data` (CPU);
`authoring_workflow_check`, `atelier_admission_check`, `asset_batch_check` (GPU).
The current Atelier clears pending/invalid images and uses shared admission.
Its synchronous execution and transient controls are replaced in readiness P4.
