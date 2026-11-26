class_name EnvDoor
extends StaticBody2D

var is_open: bool = false

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("resettable")


func open_door() -> void:
	if is_open:
		return

	is_open = true
	_collision.set_deferred("disabled", true)
	_sprite.play(&"door")


func reset_state() -> void:
	is_open = false
	_collision.set_deferred("disabled", false)
	_sprite.stop()
	_sprite.frame = 0
