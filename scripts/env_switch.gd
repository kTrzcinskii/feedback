class_name EnvSwitch
extends Node2D

@export var linked_door: NodePath
@export var hit_radius: float = 28.0

var is_activated: bool = false

@onready var hit_center: Marker2D = $HitCenter
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _door: EnvDoor = get_node_or_null(linked_door) as EnvDoor


func _ready() -> void:
	add_to_group("switches")
	add_to_group("resettable")


func on_hit_by_projectile(projectile: ParryableProjectile) -> bool:
	if is_activated or not projectile.is_reflected or not is_instance_valid(_door):
		return false

	is_activated = true
	_sprite.frame = _sprite.sprite_frames.get_frame_count(&"switch") - 1
	_door.open_door()
	return true


func reset_state() -> void:
	is_activated = false
	_sprite.frame = 0
