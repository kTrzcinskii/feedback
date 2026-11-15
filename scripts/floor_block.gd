@tool
extends ParryableSurface

const GROUND: SpriteFrames = preload("res://assets/godot/platform-ground.tres")
const FOUNDATION: Texture2D = preload("res://assets/environment/foundation.svg")

## Top-left origin. Size changes both artwork and collision.
@export var size: Vector2 = Vector2(192, 96):
	set(value):
		size = Vector2(maxf(16, value.x), maxf(32, value.y))
		_update_geometry()


func _ready() -> void:
	_update_geometry()


func _update_geometry() -> void:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null:
		var rectangle := RectangleShape2D.new()
		rectangle.size = size
		collision.shape = rectangle
		collision.position = size * 0.5
		collision.one_way_collision = one_way
	queue_redraw()


func _draw() -> void:
	draw_texture_rect(FOUNDATION, Rect2(Vector2(0, 20), size - Vector2(0, 20)), true)
	for i in range(ceili(size.x / 96.0)):
		var texture := GROUND.get_frame_texture(&"ground", i % 4)
		var tile_size := Vector2(minf(96, size.x - i * 96), minf(texture.get_height(), size.y))
		draw_texture_rect_region(texture, Rect2(Vector2(i * 96, 0), tile_size), Rect2(Vector2.ZERO, tile_size))
