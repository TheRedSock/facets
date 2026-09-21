class_name MergeModifiers
extends RefCounted
## Typed, bounded diagnostic seam; no new authored gems or settings are shipped.
const DEFAULTS := {"schema":1,"discount_charges":0,"reward_bonus":0,"reward_trigger":"direct",
	"reward_scope":"move","reward_context":"intervention","reward_family":""}

static func admit(value: Variant) -> Dictionary:
	if not value is Dictionary: return StateAdmission.fail("modifier_schema")
	for key in value:
		if not DEFAULTS.has(key): return StateAdmission.fail("modifier_schema")
	for key in ["schema","discount_charges","reward_bonus","reward_trigger"]:
		if not value.has(key): return StateAdmission.fail("modifier_schema")
	value = DEFAULTS.merged(value,true)
	if not value.schema is int or value.schema != 1: return StateAdmission.fail("modifier_version")
	if not value.discount_charges is int or value.discount_charges < 0 or value.discount_charges > 16: return StateAdmission.fail("modifier_charges")
	if not value.reward_bonus is int or value.reward_bonus < 0 or value.reward_bonus > 3: return StateAdmission.fail("modifier_reward")
	if value.reward_trigger not in ["direct","automatic","any"]: return StateAdmission.fail("modifier_trigger")
	if value.reward_scope not in ["move","room","run"] or value.reward_context not in ["intervention","any"]: return StateAdmission.fail("modifier_scope")
	if not value.reward_family is String or (not value.reward_family.is_empty() and not GameValue.valid_id(value.reward_family)): return StateAdmission.fail("modifier_family")
	return {"ok":true,"value":GameValue.freeze(value)}

static func price(classification: String, charges: int) -> int:
	return 0 if classification == "intervention" and charges > 0 else 1

static func matches(classification: String, direct: bool, trigger: String) -> bool:
	return classification == "intervention" and (trigger == "any" or (trigger == "direct" and direct) or (trigger == "automatic" and not direct))
