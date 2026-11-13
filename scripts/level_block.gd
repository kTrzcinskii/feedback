@tool
extends ParryableSurface

## Resize here rather than scaling the body. The origin is the block center.
@export var size: Vector2 = Vector2(160, 32):
	set(value):
		size = Vector2(maxf(40.0, value.x), maxf(16.0, value.y))
		_update_geometry()


func _ready() -> void:
	_update_geometry()


func _update_geometry() -> void:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var visual := get_node_or_null("SurfaceVisual") as NinePatchRect
	if collision == null or visual == null:
		return
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	collision.one_way_collision = one_way
	visual.position = -size * 0.5
	visual.size = size
