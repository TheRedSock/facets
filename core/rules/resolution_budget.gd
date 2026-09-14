class_name ResolutionBudget
extends RefCounted
var rules: RuleSet
var work := 0
var facts := 0
var error := ""

func _init(profile: RuleSet = null) -> void:
	rules = profile if profile != null else RuleSet.new()

func spend(visits: int, segments: int = 0) -> bool:
	work += visits
	facts += segments
	if work > int(rules.value("max_work")): error = "work_cap"
	if facts > int(rules.value("max_facts")): error = "fact_cap"
	return error.is_empty()
