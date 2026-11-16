class_name ParryableProjectile
extends Area2D

enum FlightMode {
	STRAIGHT,
	SPLINE,
	HOMING,
}

const PROJECTILE_FRAMES: SpriteFrames = preload("res://assets/godot/projectile-fly.tres")

@export var speed: float = 340.0
@export var direction: Vector2 = Vector2.LEFT
@export var collision_radius: float = 12.0
@export var max_lifetime: float = 8.0
## Free the projectile when its flight segment hits static world geometry
## (floors, walls, platforms). Bodies such as the player keep their own
## contact rules.
@export var die_on_world_contact: bool = true
## Collision layers checked for world contact (default: layer 1 = terrain).
@export_flags_2d_physics var world_collision_mask: int = 1

var velocity: Vector2 = Vector2.ZERO
var is_reflected: bool = false
var prev_global_position: Vector2 = Vector2.ZERO
var ignore_player_until_exit: bool = false
var source_emitter: Node2D = null

var _flight_mode: int = FlightMode.STRAIGHT
var _path_curve: Curve2D = null
var _path_xform: Transform2D = Transform2D.IDENTITY
var _path_distance: float = 0.0
var _homing_target: Node2D = null
var _homing_turn_rate: float = deg_to_rad(90.0)
var _homing_track_forever: bool = false
var _homing_time_left: float = 0.0

var _ignored_player: Node2D = null
var _lifetime: float = 0.0
var _sprite: AnimatedSprite2D = null
var _collision_shape: CollisionShape2D = null
var _bounds: Rect2 = Rect2()
var _has_bounds: bool = false


func _ready() -> void:
	add_to_group("parryable_attacks")
	add_to_group("projectiles")
	prev_global_position = global_position
	_resolve_level_bounds()
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
	_flight_mode = FlightMode.STRAIGHT
	_path_curve = null
	_homing_target = null
	_update_visual_orientation()


## Ride the curve in p_curve_xform space, then straight along the exit tangent.
func configure_spline_flight(p_origin: Vector2, p_curve: Curve2D, p_curve_xform: Transform2D,
		p_speed: float, p_emitter: Node2D = null, p_start_distance: float = 0.0) -> void:
	global_position = p_origin
	prev_global_position = p_origin
	source_emitter = p_emitter
	speed = p_speed
	_flight_mode = FlightMode.SPLINE
	_path_curve = p_curve
	_path_xform = p_curve_xform
	_path_distance = p_start_distance
	var tangent: Vector2 = transformed_tangent(p_curve, p_start_distance, p_curve_xform)
	direction = tangent.normalized() if tangent.length_squared() > 1e-6 else Vector2.LEFT
	velocity = direction * speed
	_homing_target = null
	_update_visual_orientation()


## Steer toward p_target for p_tracking_duration s (<= 0 = forever).
func configure_homing_flight(p_origin: Vector2, p_direction: Vector2, p_speed: float,
		p_target: Node2D, p_turn_rate_rad: float, p_tracking_duration: float,
		p_emitter: Node2D = null) -> void:
	global_position = p_origin
	prev_global_position = p_origin
	source_emitter = p_emitter
	speed = p_speed
	_flight_mode = FlightMode.HOMING
	_homing_target = p_target
	_homing_turn_rate = maxf(p_turn_rate_rad, 0.0)
	_homing_track_forever = p_tracking_duration <= 0.0
	_homing_time_left = maxf(p_tracking_duration, 0.0)
	direction = p_direction.normalized() if p_direction.length_squared() > 1e-6 else Vector2.LEFT
	velocity = direction * speed
	_path_curve = null
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
	_flight_mode = FlightMode.STRAIGHT
	_path_curve = null
	_homing_target = null
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
	match _flight_mode:
		FlightMode.SPLINE:
			_fly_spline(delta)
		FlightMode.HOMING:
			_fly_homing(delta)
		_:
			global_position += velocity * delta
	_lifetime += delta

	if _lifetime >= max_lifetime:
		queue_free()
		return

	_check_world_contact()
	if is_queued_for_deletion():
		return
	_check_out_of_bounds()
	if is_queued_for_deletion():
		return

	if ignore_player_until_exit and is_instance_valid(_ignored_player):
		var player_origin: Vector2 = _ignored_player.call("get_parry_origin_global") if _ignored_player.has_method("get_parry_origin_global") else _ignored_player.global_position
		var player_radius: float = float(_ignored_player.call("get_hurtbox_radius")) if _ignored_player.has_method("get_hurtbox_radius") else 22.0
		if global_position.distance_to(player_origin) > (player_radius + collision_radius + 8.0):
			ignore_player_until_exit = false
			_ignored_player = null

	_check_target_interactions()


func _fly_spline(delta: float) -> void:
	if _path_curve == null:
		_flight_mode = FlightMode.STRAIGHT
		global_position += velocity * delta
		return
	var length := _path_curve.get_baked_length()
	_path_distance += speed * delta
	if _path_distance >= length:
		var end_point: Vector2 = _path_xform * _path_curve.sample_baked(length)
		var exit_dir := transformed_tangent(_path_curve, length, _path_xform)
		global_position = end_point + exit_dir * (_path_distance - length)
		direction = exit_dir
		velocity = exit_dir * speed
		_flight_mode = FlightMode.STRAIGHT
		_path_curve = null
	else:
		global_position = _path_xform * _path_curve.sample_baked(_path_distance)
		var tangent: Vector2 = transformed_tangent(_path_curve, _path_distance, _path_xform)
		if tangent.length_squared() > 1e-6:
			direction = tangent.normalized()
			velocity = direction * speed
	_update_visual_orientation()


func _fly_homing(delta: float) -> void:
	var tracking := _homing_track_forever or _homing_time_left > 0.0
	if tracking and is_instance_valid(_homing_target):
		var to_target := target_center(_homing_target) - global_position
		if to_target.length_squared() > 1e-6:
			var desired := to_target.normalized()
			var max_turn := _homing_turn_rate * delta
			var turn := clampf(direction.angle_to(desired), -max_turn, max_turn)
			if not is_zero_approx(turn):
				direction = direction.rotated(turn)
	else:
		_flight_mode = FlightMode.STRAIGHT
		_homing_target = null
	if not _homing_track_forever:
		_homing_time_left = maxf(0.0, _homing_time_left - delta)
	velocity = direction * speed
	global_position += velocity * delta
	_update_visual_orientation()


## World contact: free on hitting static geometry. The per-tick segment
## (prev -> current position) is swept through physics space, so tunneling
## is impossible at any speed. Non-static bodies (player, enemies) keep
## their own contact rules (Section 2.5).
func _check_world_contact() -> void:
	if not die_on_world_contact or not is_inside_tree():
		return
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
			prev_global_position, global_position, world_collision_mask, [get_rid()])
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if not hit.is_empty() and hit["collider"] is StaticBody2D:
		queue_free()


## Out of bounds: free once the projectile leaves the level's world rect
## (terrain union + margin, provided by the level node). When no level
## provides bounds, max_lifetime remains the failsafe.
func _check_out_of_bounds() -> void:
	if _has_bounds and not _bounds.has_point(global_position):
		queue_free()


func _resolve_level_bounds() -> void:
	for level in get_tree().get_nodes_in_group("level"):
		if is_instance_valid(level) and level.has_method("get_projectile_bounds"):
			_bounds = level.call("get_projectile_bounds")
			_has_bounds = _bounds.size.x > 0.0 and _bounds.size.y > 0.0
			return
	_has_bounds = false


static func transformed_tangent(curve: Curve2D, distance: float, xform: Transform2D) -> Vector2:
	var length := curve.get_baked_length()
	var a := xform * curve.sample_baked(clampf(distance - 1.0, 0.0, length))
	var b := xform * curve.sample_baked(clampf(distance + 1.0, 0.0, length))
	var t := b - a
	if t.length_squared() <= 1e-10:
		return Vector2.RIGHT
	return t.normalized()


static func target_center(target: Node2D) -> Vector2:
	if target.has_method("get_center_global"):
		return target.call("get_center_global")
	if target.has_method("get_parry_origin_global"):
		return target.call("get_parry_origin_global")
	return target.global_position


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

	# Check enemies
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
