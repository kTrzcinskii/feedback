## Code first implementation of a door
## The door instance can be used as usual with scenes but also supports
## creation purely in code i.e., [code]EnvDoor.new()[/code] creates a
## fully functional instance with [CollisionShape2D] and
## [AnimatedSprite2D].
class_name EnvDoor
extends StaticBody2D

const DOOR_FRAMES: SpriteFrames = preload("res://assets/godot/env-door.tres")
static var OPEN_FRAME: int = _resolve_open_frame()

var is_open: bool = false
var _sprite: AnimatedSprite2D = null
var _collision: CollisionShape2D = null


func _ready() -> void:
	add_to_group("resettable")
	_collision = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _collision == null:
		_collision = CollisionShape2D.new()
		_collision.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		rect.size = Vector2(36, 96)
		_collision.shape = rect
		add_child(_collision)

	_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _sprite == null:
		_sprite = AnimatedSprite2D.new()
		_sprite.name = "AnimatedSprite2D"
		_sprite.sprite_frames = DOOR_FRAMES
		_sprite.centered = false
		_sprite.offset = Vector2(-48, -48)
		_sprite.animation = &"door"
		add_child(_sprite)
	_apply_state()


func open_door() -> void:
	if is_open:
		return
	is_open = true
	if _collision != null:
		_collision.set_deferred("disabled", true)
	if _sprite != null:
		_sprite.play(&"door")


func reset_state() -> void:
	is_open = false
	_apply_state()


func _apply_state() -> void:
	if _collision != null:
		_collision.disabled = is_open
	if _sprite != null:
		_sprite.stop()
		_sprite.frame = OPEN_FRAME if is_open else 0

static func _resolve_open_frame() -> int:
	if DOOR_FRAMES != null and DOOR_FRAMES.has_animation(&"door"):
		return max(0, DOOR_FRAMES.get_frame_count(&"door") - 1)
	return 0
