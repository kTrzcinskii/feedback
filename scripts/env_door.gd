class_name EnvDoor
extends StaticBody2D

## Visible slab widths in the sliding-gate animation, from closed to open.
const SLAB_WIDTHS := [32.0, 24.0, 16.0, 8.0, 0.0]

var is_open: bool = false

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _slab: RectangleShape2D = _collision.shape as RectangleShape2D


func _ready() -> void:
	add_to_group("resettable")
	_sprite.frame_changed.connect(_sync_collision_to_frame)


func open_door() -> void:
	if is_open or _sprite.is_playing():
		return

	_sprite.play()


func reset_state() -> void:
	_sprite.stop()


func _sync_collision_to_frame() -> void:
	var width: float = SLAB_WIDTHS[_sprite.frame]
	is_open = width == 0.0
	
	_sprite.z_index = 0 if is_open else 1
	_sprite.self_modulate.a = 0.45 if is_open else 1.0
	_collision.set_deferred("disabled", is_open)
	if not is_open:
		_slab.set_deferred("size", Vector2(width, _slab.size.y))
		_collision.set_deferred("position", Vector2((SLAB_WIDTHS[0] - width) * 0.5, _collision.position.y))
