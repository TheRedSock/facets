class_name GemCutModelModifier
extends Resource

## Post-compile hook applied to GemCutModelResource before mesh assembly.
## Subclass and override apply_to_model() in tool or game code.


func apply_to_model(model) -> void:
	if model == null:
		return
