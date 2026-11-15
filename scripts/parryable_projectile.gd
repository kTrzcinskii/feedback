class_name ParryableProjectile
extends Area2D

const PROJECTILE_FRAMES: SpriteFrames = preload("res://assets/godot/projectile-fly.tres")

@export var speed: float = 340.0
@export var direction: Vector2 = Vector2.LEFT
@export var collision_radius: float = 12.0
@export var max_lifetime: float = 8.0

var velocity: Vector2 = Vector2.ZERO
var is_reflected: bool = false
var prev_global_position: Vector2 = Vector2.ZERO
var ignore_player_until_exit: bool = false
var source_emitter: Node2D = null

var _ignored_player: Node2D = null
var _lifetime: float = 0.0
var _sprite: AnimatedSprite2D = null
var _collision_shape: CollisionShape2D = null


func _ready() -> void:
	add_to_group("parryable_attacks")
	add_to_group("projectiles")
	prev_global_position = global_position
	if velocity.length_squared() <= 1e-6:
		velocity = (direction.normalized() if direction.length_squared() > 1e-6 else Vector2.LEFT) * speed
	else:
		speed = velocity.length()
		direction = velocity.normalized()

	_setup_nodes()
	_update_visual_orientation()


func _setup_nodes() -> void:
	_collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _collision_shape == null:
		_collision_shape = CollisionShape2D.new()
		_collision_shape.name = "CollisionShape2D"
		var circle := CircleShape2D.new()
		circle.radius = collision_radius
		_collision_shape.shape = circle
		add_child(_collision_shape)

	_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _sprite == null:
		_sprite = AnimatedSprite2D.new()
		_sprite.name = "AnimatedSprite2D"
		_sprite.sprite_frames = PROJECTILE_FRAMES
		_sprite.centered = false
		_sprite.offset = Vector2(-48, -48)
		_sprite.animation = &"fly"
		add_child(_sprite)
		_sprite.play(&"fly")


func configure(p_origin: Vector2, p_direction: Vector2, p_speed: float, p_emitter: Node2D = null) -> void:
	global_position = p_origin
	prev_global_position = p_origin
	direction = p_direction.normalized() if p_direction.length_squared() > 1e-6 else Vector2.LEFT
	speed = p_speed
	velocity = direction * speed
	source_emitter = p_emitter
	_update_visual_orientation()


func get_attack_category() -> StringName:
	return &"projectile"


func get_hit_radius() -> float:
	return collision_radius


func can_damage_player(player: Node2D) -> bool:
	if not is_inside_tree() or is_queued_for_deletion():
		return false
	if ignore_player_until_exit and _ignored_player == player:
		return false
	return true


func on_parried(player: Node2D, _parry_dir: Vector2) -> bool:
	# Reverse velocity by 180 degrees, preserving original speed (Section 2.5.A)
	velocity = -velocity
	direction = -direction
	is_reflected = true
	ignore_player_until_exit = true
	_ignored_player = player
	prev_global_position = global_position
	_update_visual_orientation()
	return true


func _update_visual_orientation() -> void:
	if _sprite != null:
		_sprite.rotation = direction.angle()
		_sprite.modulate = Color(0.76, 0.63, 1.0, 1.0) if is_reflected else Color(1.0, 1.0, 1.0, 1.0)


func _physics_process(delta: float) -> void:
	prev_global_position = global_position
	global_position += velocity * delta
	_lifetime += delta

	if _lifetime >= max_lifetime:
		queue_free()
		return

	if ignore_player_until_exit and is_instance_valid(_ignored_player):
		var player_origin: Vector2 = _ignored_player.call("get_parry_origin_global") if _ignored_player.has_method("get_parry_origin_global") else _ignored_player.global_position
		var player_radius: float = float(_ignored_player.call("get_hurtbox_radius")) if _ignored_player.has_method("get_hurtbox_radius") else 22.0
		if global_position.distance_to(player_origin) > (player_radius + collision_radius + 8.0):
			ignore_player_until_exit = false
			_ignored_player = null

	_check_target_interactions()


func _check_target_interactions() -> void:
	if is_queued_for_deletion():
		return

	# Check switches
	for sw in get_tree().get_nodes_in_group("switches"):
		if not is_instance_valid(sw) or not (sw is Node2D):
			continue
		var sw_node := sw as Node2D
		var sw_radius: float = float(sw_node.call("get_hit_radius")) if sw_node.has_method("get_hit_radius") else 28.0
		if _segment_distance_to_point(prev_global_position, global_position, sw_node.global_position) <= (collision_radius + sw_radius):
			if sw_node.has_method("on_hit_by_projectile"):
				sw_node.call("on_hit_by_projectile", self)
			queue_free()
			return

	# Check enemies/emitters
	if is_reflected:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or not (enemy is Node2D):
				continue
			if enemy.has_method("is_defeated") and bool(enemy.call("is_defeated")):
				continue
			var enemy_node := enemy as Node2D
			var enemy_center: Vector2 = enemy_node.call("get_center_global") if enemy_node.has_method("get_center_global") else (enemy_node.global_position + Vector2(0, -32))
			var enemy_radius: float = float(enemy_node.call("get_hit_radius")) if enemy_node.has_method("get_hit_radius") else 28.0
			if _segment_distance_to_point(prev_global_position, global_position, enemy_center) <= (collision_radius + enemy_radius):
				if enemy_node.has_method("on_hit_by_reflected_projectile"):
					enemy_node.call("on_hit_by_reflected_projectile", self)
				queue_free()
				return


static func _segment_distance_to_point(a: Vector2, b: Vector2, p: Vector2) -> float:
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
	return p.distance_to(closest)
