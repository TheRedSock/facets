class_name MergeModifiers
extends RefCounted
## Typed, bounded diagnostic seam; no new authored gems or settings are shipped.
const DEFAULTS := {"schema":1,"discount_charges":0,"reward_bonus":0,"reward_trigger":"direct"}

static func admit(value: Variant) -> Dictionary:
	if not StateAdmission.exact(value,DEFAULTS.keys()): return StateAdmission.fail("modifier_schema")
	if not value.schema is int or value.schema != 1: return StateAdmission.fail("modifier_version")
	if not value.discount_charges is int or value.discount_charges < 0 or value.discount_charges > 16: return StateAdmission.fail("modifier_charges")
	if not value.reward_bonus is int or value.reward_bonus < 0 or value.reward_bonus > 3: return StateAdmission.fail("modifier_reward")
	if value.reward_trigger not in ["direct","automatic","any"]: return StateAdmission.fail("modifier_trigger")
	return {"ok":true,"value":GameValue.freeze(value)}

static func price(classification: String, charges: int) -> int:
	return 0 if classification == "intervention" and charges > 0 else 1

static func matches(classification: String, direct: bool, trigger: String) -> bool:
	return classification == "intervention" and (trigger == "any" or (trigger == "direct" and direct) or (trigger == "automatic" and not direct))
