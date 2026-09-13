class_name GemCutExpression
extends RefCounted
## Bounded scalar arithmetic, without object access, side effects or RNG.
## Godot Expression performs arithmetic; this lexer restricts the language.
const FUNCTIONS := ["sin", "cos", "tan", "atan", "sqrt", "abs", "min", "max", "pow", "deg_to_rad", "rad_to_deg"]
const INPUTS := ["p", "s", "meet"]
static var _cache := {}

static func syntax_error(source: String) -> String:
	return _prepare(source).get("error", "")

static func evaluate(source: String, parameters: Dictionary, measures: Dictionary, meet := NAN) -> Dictionary:
	var prepared := _prepare(source)
	if prepared.has("error"): return prepared
	var expression: Expression = prepared.expression
	var value: Variant = expression.execute([parameters, measures, meet], null, false, true)
	if expression.has_execute_failed(): return {"error": expression.get_error_text()}
	if not (value is int or value is float) or not is_finite(float(value)): return {"error": "Expression must produce a finite scalar: " + source}
	if absf(value) > 1e6: return {"error": "Expression exceeds normalized authoring bounds"}
	return {"value": float(value)}

static func _prepare(source: String) -> Dictionary:
	if _cache.has(source): return _cache[source]
	if source.is_empty() or source.length() > 512: return {"error": "Scalar expression needs 1..512 characters"}
	var token := RegEx.new()
	token.compile("[0-9]+(?:\\.[0-9]*)?(?:[eE][+-]?[0-9]+)?|\\.[0-9]+(?:[eE][+-]?[0-9]+)?|[A-Za-z_][A-Za-z_0-9]*|[+*/%(),.\\-]")
	var compact := source.replace(" ", "").replace("\t", "")
	var parts := token.search_all(compact)
	var normalized := ""
	var cursor := 0
	for i in parts.size():
		var part: RegExMatch = parts[i]
		if part.get_start() != cursor: return {"error": "Unsupported scalar expression syntax"}
		cursor = part.get_end()
		var text := part.get_string()
		if text.is_valid_float():
			# Mathematical division must not become integer division.
			normalized += text + ".0" if text.is_valid_int() else text
		elif text.is_valid_identifier():
			var property := i > 0 and parts[i - 1].get_string() == "."
			var call := i + 1 < parts.size() and parts[i + 1].get_string() == "("
			if call and (property or text not in FUNCTIONS): return {"error": "Only declared scalar math functions may be called"}
			if not property and not call and text not in INPUTS: return {"error": "Unknown scalar input: " + text}
			normalized += text
		else: normalized += text
	if cursor != compact.length(): return {"error": "Unsupported scalar expression syntax"}
	var expression := Expression.new()
	if expression.parse(normalized, PackedStringArray(INPUTS)) != OK: return {"error": expression.get_error_text()}
	var result := {"expression": expression}
	if _cache.size() >= 512: _cache.clear()
	_cache[source] = result
	return result
