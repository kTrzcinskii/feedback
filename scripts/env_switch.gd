## Code first implementation of an environmental switch
## The switch instance can be used as usual with scenes but also
## supports creation purely in code i.e., [code]EnvSwitch.new()[/code]
## creates a fully functional instance with [AnimatedSprite2D].
class_name EnvSwitch
extends Area2D

signal switch_activated(switch_node: EnvSwitch)
signal switch_reset(switch_node: EnvSwitch)

const SWITCH_FRAMES: SpriteFrames = preload("res://assets/godot/env-switch.tres")
static var SWITCHED_FRAME: int = _resolve_switched_frame()

@export var linked_door: NodePath
@export var hit_radius: float = 28.0

var is_activated: bool = false
var _sprite: AnimatedSprite2D = null


func _ready() -> void:
	add_to_group("switches")
	add_to_group("resettable")
	_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _sprite == null:
		_sprite = AnimatedSprite2D.new()
		_sprite.name = "AnimatedSprite2D"
		_sprite.sprite_frames = SWITCH_FRAMES
		_sprite.centered = false
		_sprite.offset = Vector2(-48, -48)
		_sprite.animation = &"switch"
		add_child(_sprite)
	_update_visual()


func get_hit_radius() -> float:
	return hit_radius

## Only reflected projectiles activate the switch, and only once until
## reset
func on_hit_by_projectile(projectile: ParryProjectile) -> void:
	if projectile == null or not projectile.is_reflected:
		return
	if is_activated:
		return
	is_activated = true
	_update_visual()
	switch_activated.emit(self)
	if not linked_door.is_empty():
		var door_node: Node = get_node_or_null(linked_door)
		if door_node != null and door_node.has_method("open_door"):
			door_node.call("open_door")


func reset_state() -> void:
	is_activated = false
	_update_visual()
	switch_reset.emit(self)
	if not linked_door.is_empty():
		var door_node: Node = get_node_or_null(linked_door)
		if door_node != null and door_node.has_method("reset_state"):
			door_node.call("reset_state")


func _update_visual() -> void:
	if _sprite == null:
		return
	_sprite.stop()
	_sprite.frame = SWITCHED_FRAME if is_activated else 0
	_sprite.modulate = Color(0.76, 0.96, 0.72, 1.0) if is_activated else Color(1.0, 1.0, 1.0, 1.0)

static func _resolve_switched_frame() -> int:
	if SWITCH_FRAMES != null and SWITCH_FRAMES.has_animation(&"switch"):
		return max(0, SWITCH_FRAMES.get_frame_count(&"switch") - 1)
	return 0