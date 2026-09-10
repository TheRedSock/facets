class_name GemManifest
extends RefCounted
## Build catalog: the exact stone x clip x rung list with priority classes.
## REQUIRED_NOW = idles for the run's tile set (block-ish: placeholder covers
## the gap), SOON = upgrade spin (turn), LATER = flash (not the merge beat).
## Data lives in data/lapidary/manifest.json; this class owns the ordering and
## filtering logic the launcher and the packaging CLI share.

const PRIORITY_REQUIRED_NOW := 0
const PRIORITY_SOON := 1
const PRIORITY_LATER := 2

const DEFAULT_PATH := "res://data/lapidary/manifest.json"

const _PRIORITY_NAMES := {
	"required_now": PRIORITY_REQUIRED_NOW,
	"soon": PRIORITY_SOON,
	"later": PRIORITY_LATER,
}
const _RUNG_NAMES := {
	"interact": GemRung.INTERACT,
	"preview": GemRung.PREVIEW,
	"board_live": GemRung.BOARD_LIVE,
	"clip_bake": GemRung.CLIP_BAKE,
	"hero": GemRung.HERO,
}

## Entries sorted by (priority, file order). Each:
## {stone_id: StringName, clip_id: StringName, rung: int, priority: int}
var _entries: Array[Dictionary] = []


static func load_default() -> GemManifest:
	var text := FileAccess.get_file_as_string(DEFAULT_PATH)
	if text.is_empty():
		push_warning("GemManifest: missing %s — empty catalog" % DEFAULT_PATH)
		return GemManifest.new()
	return from_json_text(text)


static func from_json_text(text: String) -> GemManifest:
	var manifest := GemManifest.new()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_warning("GemManifest: unparsable manifest JSON")
		return manifest
	var raw: Array = (parsed as Dictionary).get("entries", [])
	var order := 0
	for item in raw:
		if not (item is Dictionary):
			continue
		var e: Dictionary = item
		if not (e.has("stone_id") and e.has("clip_id")):
			push_warning("GemManifest: entry missing stone_id/clip_id — skipped")
			continue
		manifest._entries.append({
			"stone_id": StringName(String(e["stone_id"])),
			"clip_id": StringName(String(e["clip_id"])),
			"rung": rung_from_name(String(e.get("rung", "clip_bake"))),
			"priority": priority_from_name(String(e.get("priority", "later"))),
			"_order": order,
		})
		order += 1
	manifest._entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["priority"] != b["priority"]:
			return a["priority"] < b["priority"]
		return a["_order"] < b["_order"])
	for e in manifest._entries:
		e.erase("_order")
	return manifest


## All entries in priority order (copy).
func entries() -> Array[Dictionary]:
	return _entries.duplicate()


## Entries whose stone is in the run's active tile set, priority order.
func entries_for_tiles(tile_ids: Array) -> Array[Dictionary]:
	var wanted := {}
	for id in tile_ids:
		wanted[StringName(String(id))] = true
	var out: Array[Dictionary] = []
	for e in _entries:
		if wanted.has(e["stone_id"]):
			out.append(e)
	return out


## REQUIRED_NOW entries for the run's active tile set.
func required_now(tile_ids: Array) -> Array:
	var out: Array[Dictionary] = []
	for e in entries_for_tiles(tile_ids):
		if e["priority"] == PRIORITY_REQUIRED_NOW:
			out.append(e)
	return out


## Rung the catalog demands for one stone x clip (fallback when uncatalogued).
func rung_for(stone_id: StringName, clip_id: StringName, fallback := GemRung.CLIP_BAKE) -> int:
	for e in _entries:
		if e["stone_id"] == stone_id and e["clip_id"] == clip_id:
			return e["rung"]
	return fallback


func size() -> int:
	return _entries.size()


static func rung_from_name(name: String) -> int:
	return _RUNG_NAMES.get(name.to_lower(), GemRung.CLIP_BAKE)


static func priority_from_name(name: String) -> int:
	return _PRIORITY_NAMES.get(name.to_lower(), PRIORITY_LATER)


static func priority_name(priority: int) -> String:
	for key: String in _PRIORITY_NAMES:
		if _PRIORITY_NAMES[key] == priority:
			return key
	return "later"
