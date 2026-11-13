class_name LethalHazard
extends Area2D

const HAZARD_FRAMES: SpriteFrames = preload("res://assets/godot/env-hazard.tres")

@export var hit_radius: float = 22.0
@export var damage: int = 1
## Section 3.6: Instant-death hazards (such as spikes and bottomless pits) kill the player
## immediately, regardless of remaining HP or active invulnerability.
@export var is_instant_death: bool = true

var _sprite: AnimatedSprite2D = null


func _ready() -> void:
	add_to_group("lethal_hazards")
	_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _sprite == null:
		_sprite = AnimatedSprite2D.new()
		_sprite.name = "AnimatedSprite2D"
		_sprite.sprite_frames = HAZARD_FRAMES
		_sprite.centered = false
		_sprite.offset = Vector2(-48, -48)
		_sprite.animation = &"hazard"
		add_child(_sprite)
		_sprite.play(&"hazard")


func get_hazard_center_global() -> Vector2:
	return global_position + Vector2(0, 20)


func get_hit_radius() -> float:
	return hit_radius
