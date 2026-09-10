class_name GemCondition
extends Resource
## Explicit specimen condition. Grade is a recipe/selection label; these fields
## describe realized physical features and remain stable under lighting/pose.
@export var defects: Array[GemDefect] = []
@export var finish: GemSurface = GemSurface.new()
