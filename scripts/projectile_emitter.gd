class_name ProjectileEmitter
extends Node2D

const SENTINEL_IDLE: SpriteFrames = preload("res://assets/godot/sentinel-idle.tres")
const SENTINEL_SHOOT: SpriteFrames = preload("res://assets/godot/sentinel-shoot.tres")
const SENTINEL_HURT: SpriteFrames = preload("res://assets/godot/sentinel-hurt.tres")

@export var fire_interval: float = 1.8
@export var initial_delay: float = 0.6
@export var projectile_speed: float = 340.0
@export var fire_direction: Vector2 = Vector2.LEFT
@export var muzzle_offset: Vector2 = Vector2(-28, -36)
@export var can_be_defeated: bool = true
@export var respawn_after_defeat_delay: float = 0.0
@export var auto_fire: bool = true

var _timer: float = 0.0
var _defeated: bool = false
var _respawn_timer: float = 0.0
var _sprite: AnimatedSprite2D = null


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("resettable")
	_timer = initial_delay
	_setup_visuals()


func _setup_visuals() -> void:
	_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _sprite == null:
		_sprite = AnimatedSprite2D.new()
		_sprite.name = "AnimatedSprite2D"
		_sprite.sprite_frames = SENTINEL_IDLE
		_sprite.centered = false
		_sprite.offset = Vector2(-48, -80)
		add_child(_sprite)
	_sprite.flip_h = fire_direction.x < 0.0
	_sprite.sprite_frames = SENTINEL_IDLE
	_sprite.play(&"idle")
	_sprite.animation_finished.connect(_on_animation_finished)


func _on_animation_finished() -> void:
	if _defeated:
		return
	if _sprite != null and _sprite.sprite_frames == SENTINEL_SHOOT:
		_sprite.sprite_frames = SENTINEL_IDLE
		_sprite.play(&"idle")


func _physics_process(delta: float) -> void:
	if _defeated:
		if respawn_after_defeat_delay > 0.0:
			_respawn_timer -= delta
			if _respawn_timer <= 0.0:
				reset_state()
		return

	if not auto_fire:
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer += maxf(0.1, fire_interval)
		fire_projectile()


func fire_projectile() -> ParryableProjectile:
	if _defeated:
		return null
	if _sprite != null:
		_sprite.flip_h = fire_direction.x < 0.0
		_sprite.sprite_frames = SENTINEL_SHOOT
		_sprite.play(&"shoot")

	var proj := ParryableProjectile.new()
	var parent_node: Node = get_parent() if get_parent() != null else self
	parent_node.add_child(proj)
	var dir_norm: Vector2 = fire_direction.normalized() if fire_direction.length_squared() > 1e-6 else Vector2.LEFT
	var spawn_pos: Vector2 = global_position + Vector2(muzzle_offset.x * signf(dir_norm.x if absf(dir_norm.x) > 1e-3 else -1.0), muzzle_offset.y)
	proj.configure(spawn_pos, dir_norm, projectile_speed, self)
	return proj


func get_center_global() -> Vector2:
	return global_position + Vector2(0, -36)


func get_hit_radius() -> float:
	return 26.0


func is_defeated() -> bool:
	return _defeated


func on_hit_by_reflected_projectile(_projectile: ParryableProjectile) -> void:
	if not can_be_defeated or _defeated:
		return
	_defeated = true
	_respawn_timer = respawn_after_defeat_delay
	if _sprite != null:
		_sprite.sprite_frames = SENTINEL_HURT
		_sprite.play(&"hurt")
		_sprite.modulate = Color(1.0, 0.65, 0.65, 0.6)


func reset_state() -> void:
	_defeated = false
	_timer = initial_delay
	_respawn_timer = 0.0
	if _sprite != null:
		_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_sprite.sprite_frames = SENTINEL_IDLE
		_sprite.flip_h = fire_direction.x < 0.0
		_sprite.play(&"idle")
