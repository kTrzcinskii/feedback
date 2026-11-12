class_name PlayerCharacter
extends CharacterBody2D

signal parry_started(direction: Vector2, active_duration: float)
signal parry_window_ended(was_successful: bool)
signal parry_cooldown_ended()
signal player_damaged(source: Object, remaining_hp: int)
signal player_died(source: Object)

enum ParryState {
	IDLE,
	ACTIVE,
	COOLDOWN,
}

# --- Section 4: Initial tunable parameters ---
@export_group("Units")
## 1.0 Character Height (CH) in pixels
@export var character_height: float = 64.0

@export_group("Parry Parameters")
## Active window duration in seconds (Proposed: 0.20 s).
@export var parry_active_duration: float = 0.20
## Cooldown duration in seconds after active window ends (Proposed: 0.20 s).
@export var parry_cooldown: float = 0.20
## Hitbox range in Character Heights (Proposed: 1.0 CH).
@export var parry_hitbox_range_ch: float = 1.0
## Angular coverage in degrees from the locked direction (Proposed: ±22.5°).
@export var parry_angular_coverage_deg: float = 22.5
## Section 2.4: A successful parry against an enemy attack resets the parry cooldown,
## allowing the player to initiate another parry immediately after the current active window ends.
@export var reset_cooldown_on_attack_parry: bool = true
## Section 2.4: A successful environmental surface parry does not reset the cooldown by default
## (TODO: change after gameplay tests).
@export var reset_cooldown_on_surface_parry: bool = false

@export_group("Movement Parameters")
## Ordinary horizontal movement speed (in CH/s) [br]
## [b]applied immediately without acceleration[/b]
@export var ground_movement_speed_ch: float = 5.0
## Upward jump impulse velocity (in CH/s)
@export var jump_velocity_ch: float = 8.5
## Downward gravity acceleration (in CH/s²)
@export var gravity_ch: float = 22.0
## Airborne horizontal control acceleration (in CH/s²)
@export var air_control_acceleration_ch: float = 18.0

@export_group("Health & Collision")
@export var max_hp: int = 3
## Temporary invulnerability duration after receiving non-lethal damage (in seconds)
@export var invulnerability_duration: float = 0.75
@export var hurtbox_radius: float = 22.0
@export var parry_origin_offset: Vector2 = Vector2(0.0, -32.0)

var hp: int = 3
var is_dead: bool = false
var invulnerability_timer: float = 0.0
var facing_direction: int = 1

var parry_state: ParryState = ParryState.IDLE
var parry_timer: float = 0.0
var parry_direction: Vector2 = Vector2.RIGHT
var has_parry_momentum: bool = false
var visual_motion: String = ""

var _parry_requires_release: bool = false
var _parry_succeeded_in_current_window: bool = false
var _cooldown_reset_earned_in_current_window: bool = false
var _impulse_applied_this_tick: bool = false
var _prev_animation: StringName = PlayerAnimatedSprite.IDLE
var _land_visual_timer: float = 0.0
var _airborne_time: float = 0.0
var _hurt_visual_active: bool = false

# Optional simulated input overrides for deterministic testing
var use_simulated_input: bool = false
var sim_move_dir: Vector2 = Vector2.ZERO
var sim_parry_dir: Vector2 = Vector2.INF
var sim_jump_just_pressed: bool = false
var sim_parry_pressed: bool = false

@onready var player_visual: Node2D = get_node_or_null("PlayerVisual") as Node2D
@onready var animation_tree: PlayerAnimationTree = get_node_or_null("PlayerVisual/AnimationTree") as PlayerAnimationTree
@onready var animated_sprite: PlayerAnimatedSprite = get_node_or_null("AnimatedSprite2D") as PlayerAnimatedSprite
var _parry_hitbox: Area2D = null
var _parry_polygon: CollisionPolygon2D = null


func _ready() -> void:
	process_physics_priority = -10
	hp = max_hp
	_setup_parry_nodes()
	if animation_tree != null:
		animation_tree.active = true
	set_visual_motion(PlayerAnimationTree.Motion.IDLE)
	if animated_sprite != null:
		if not animated_sprite.animation_finished.is_connected(_on_animation_finished):
			animated_sprite.animation_finished.connect(_on_animation_finished)
		animated_sprite.visible = (player_visual == null)
		animated_sprite.play_idle()


func set_visual_motion(next: PlayerAnimationTree.Motion) -> void:
	var next_name: StringName = PlayerAnimationTree.motion_to_name(next)
	if next_name != visual_motion:
		if animation_tree != null:
			animation_tree.set_motion(next)
		visual_motion = next_name


func set_visual_motion_by_name(next_name: StringName) -> void:
	set_visual_motion(PlayerAnimationTree.name_to_motion(next_name))


func show_parry() -> void:
	if animation_tree != null:
		animation_tree.fire_parry()


func interrupt_parry() -> void:
	if animation_tree != null:
		animation_tree.abort_parry()


func _set_locomotion_scale(scale_val: float) -> void:
	if animation_tree != null:
		animation_tree.set_locomotion_scale(scale_val)


func set_facing(left: bool) -> void:
	if player_visual != null:
		player_visual.scale.x = -absf(player_visual.scale.x) if left else absf(player_visual.scale.x)
	if animated_sprite != null:
		animated_sprite.flip_h = left


func _setup_parry_nodes() -> void:
	_parry_hitbox = get_node_or_null("ParryHitbox") as Area2D
	if _parry_hitbox == null:
		_parry_hitbox = Area2D.new()
		_parry_hitbox.name = "ParryHitbox"
		_parry_hitbox.position = parry_origin_offset
		add_child(_parry_hitbox)

	_parry_polygon = _parry_hitbox.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if _parry_polygon == null:
		_parry_polygon = CollisionPolygon2D.new()
		_parry_polygon.name = "CollisionPolygon2D"
		_parry_hitbox.add_child(_parry_polygon)

	_rebuild_parry_sector_polygon()
	_set_parry_hitbox_enabled(false)


func _rebuild_parry_sector_polygon() -> void:
	if _parry_polygon == null:
		return
	var r: float = get_parry_range_px()
	var half_rad: float = get_parry_half_angle_rad()
	var steps: int = 8
	var pts := PackedVector2Array()
	pts.append(Vector2.ZERO)
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var ang: float = lerpf(-half_rad, half_rad, t)
		pts.append(Vector2.from_angle(ang) * r)
	_parry_polygon.polygon = pts


func _set_parry_hitbox_enabled(enabled: bool) -> void:
	if _parry_polygon != null:
		_parry_polygon.disabled = not enabled
	if _parry_hitbox != null:
		_parry_hitbox.monitoring = enabled
		_parry_hitbox.monitorable = enabled
		_parry_hitbox.rotation = parry_direction.angle()


func get_parry_origin_global() -> Vector2:
	return global_position + parry_origin_offset


func get_parry_range_px() -> float:
	return parry_hitbox_range_ch * character_height


func get_parry_half_angle_rad() -> float:
	return deg_to_rad(parry_angular_coverage_deg)


func get_hurtbox_radius() -> float:
	return hurtbox_radius


func is_invulnerable() -> bool:
	return invulnerability_timer > 0.0


func is_parry_active() -> bool:
	return parry_state == ParryState.ACTIVE


func is_parry_on_cooldown() -> bool:
	return parry_state == ParryState.COOLDOWN


func get_parry_state_name() -> String:
	match parry_state:
		ParryState.IDLE:
			return "READY"
		ParryState.ACTIVE:
			return "ACTIVE"
		ParryState.COOLDOWN:
			return "COOLDOWN"
	return "UNKNOWN"


## Samples 8-directional input once when parry starts (Section 2.1).
## Defaults to facing_direction when no directional input is held.
## Diagonal directions are normalized.
func sample_parry_direction(raw_input: Vector2) -> Vector2:
	var dx: float = 0.0
	var dy: float = 0.0
	if absf(raw_input.x) > 0.1:
		dx = signf(raw_input.x)
	if absf(raw_input.y) > 0.1:
		dy = signf(raw_input.y)

	if dx == 0.0 and dy == 0.0:
		return Vector2(float(facing_direction), 0.0)

	return Vector2(dx, dy).normalized()


func _read_movement_input() -> float:
	if use_simulated_input:
		return sim_move_dir.x
	var left: bool = Input.is_action_pressed("MoveLeft") if InputMap.has_action("MoveLeft") else false
	var right: bool = Input.is_action_pressed("MoveRight") if InputMap.has_action("MoveRight") else false
	return (1.0 if right else 0.0) - (1.0 if left else 0.0)


func _read_parry_direction_input() -> Vector2:
	if use_simulated_input:
		return sim_parry_dir if sim_parry_dir.is_finite() else sim_move_dir
	var left: bool = Input.is_action_pressed("ParryLeft") if InputMap.has_action("ParryLeft") else Input.is_action_pressed("MoveLeft")
	var right: bool = Input.is_action_pressed("ParryRight") if InputMap.has_action("ParryRight") else Input.is_action_pressed("MoveRight")
	var up: bool = Input.is_action_pressed("ParryUp") if InputMap.has_action("ParryUp") else false
	var down: bool = Input.is_action_pressed("ParryDown") if InputMap.has_action("ParryDown") else Input.is_action_pressed("Crouch")
	var x_axis: float = (1.0 if right else 0.0) - (1.0 if left else 0.0)
	var y_axis: float = (1.0 if down else 0.0) - (1.0 if up else 0.0)
	return Vector2(x_axis, y_axis)


func get_aim_direction_preview() -> Vector2:
	return sample_parry_direction(_read_parry_direction_input())


func _read_jump_just_pressed() -> bool:
	if use_simulated_input:
		return sim_jump_just_pressed
	return Input.is_action_just_pressed("Jump") if InputMap.has_action("Jump") else false


func _read_parry_pressed() -> bool:
	if use_simulated_input:
		return sim_parry_pressed
	return Input.is_action_pressed("Parry") if InputMap.has_action("Parry") else false


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_impulse_applied_this_tick = false
	if invulnerability_timer > 0.0:
		invulnerability_timer = maxf(0.0, invulnerability_timer - delta)

	var move_x: float = _read_movement_input()
	var parry_dir_input: Vector2 = _read_parry_direction_input()
	var jump_just_pressed: bool = _read_jump_just_pressed()
	var parry_pressed: bool = _read_parry_pressed()

	# Update facing direction from horizontal movement input when not locked in an active parry
	if absf(move_x) > 0.1 and parry_state != ParryState.ACTIVE:
		facing_direction = 1 if move_x > 0.0 else -1

	_update_parry_cycle(delta, parry_dir_input, parry_pressed)

	_update_movement_and_gravity(delta, move_x, jump_just_pressed)

	_resolve_unparried_attacks_and_hazards()

	_move_character_body_2D(delta)
	_resolve_unparried_attacks_and_hazards()

	_update_animations_and_visuals(delta, move_x)


func _update_movement_and_gravity(delta: float, input_x: float, jump_just_pressed: bool) -> void:
	var max_ground_movement_speed: float = ground_movement_speed_ch * character_height
	var air_acceleration: float = air_control_acceleration_ch * character_height
	var jump_velocity: float = jump_velocity_ch * character_height
	var gravity: float = gravity_ch * character_height

	var grounded: bool = (func() -> bool:
		if not is_on_floor():
			velocity.y += gravity * delta
			return false
		if jump_just_pressed:
			velocity.y = -jump_velocity
			return false
		if not _impulse_applied_this_tick:
			velocity.y += gravity * delta
		return true
	).call()

	# Horizontal movement and air control
	var has_h_input: bool = absf(input_x) > 0.1
	var move_sign: float = signf(input_x) if has_h_input else 0.0

	if grounded and not _impulse_applied_this_tick and not has_parry_momentum:
		# ordinary horizontal movement
		velocity.x = move_sign * max_ground_movement_speed
	else:
		# Airborne movement or parry-generated momentum preservation & adjustment
		if has_h_input:
			var target_vx: float = move_sign * max_ground_movement_speed
			if signf(velocity.x) == move_sign and absf(velocity.x) > max_ground_movement_speed:
				# Already at max speed in the desired direction
				pass
			else:
				velocity.x = move_toward(velocity.x, target_vx, air_acceleration * delta)
				# Reset parry momentum
				if grounded and has_parry_momentum and is_equal_approx(velocity.x, target_vx):
					has_parry_momentum = false
		elif not has_parry_momentum and grounded:
			velocity.x = 0.0


func _move_character_body_2D(delta: float) -> void:
	var was_on_floor: bool = is_on_floor()
	move_and_slide()

	if not is_on_floor():
		_airborne_time += delta
	else:
		if not was_on_floor and not _impulse_applied_this_tick:
			has_parry_momentum = false
		if _airborne_time >= 0.10:
			_land_visual_timer = 0.31
		_airborne_time = 0.0


func _update_parry_cycle(delta: float, dir_input: Vector2, parry_pressed: bool) -> void:
	# Advance active window / cooldown timers first
	if parry_state == ParryState.ACTIVE:
		parry_timer -= delta
		if parry_timer <= 1e-6:
			var overflow: float = maxf(0.0, -parry_timer)
			_end_active_parry_window(overflow)
	elif parry_state == ParryState.COOLDOWN:
		parry_timer -= delta
		if parry_timer <= 1e-6:
			parry_timer = 0.0
			parry_state = ParryState.IDLE
			parry_cooldown_ended.emit()

	# Releasing the parry button clears the release requirement (Section 2.3)
	if not parry_pressed:
		_parry_requires_release = false

	# Activate parry only if IDLE, button is pressed, and button was released since last press
	if parry_state == ParryState.IDLE and parry_pressed and not _parry_requires_release:
		_start_parry(dir_input)

	# Any press while in IDLE/ACTIVE/COOLDOWN latches _parry_requires_release until released
	if parry_pressed:
		_parry_requires_release = true


func _start_parry(dir_input: Vector2) -> void:
	parry_direction = sample_parry_direction(dir_input)
	parry_state = ParryState.ACTIVE
	parry_timer = parry_active_duration
	_parry_requires_release = true
	_parry_succeeded_in_current_window = false
	_cooldown_reset_earned_in_current_window = false

	_rebuild_parry_sector_polygon()
	_set_parry_hitbox_enabled(true)
	show_parry()

	if animated_sprite != null:
		if animated_sprite.animation != PlayerAnimatedSprite.PARRY:
			_prev_animation = animated_sprite.animation
		animated_sprite.play(PlayerAnimatedSprite.PARRY)

	parry_started.emit(parry_direction, parry_active_duration)


func _end_active_parry_window(overflow: float = 0.0) -> void:
	var was_successful: bool = _parry_succeeded_in_current_window
	_set_parry_hitbox_enabled(false)
	parry_window_ended.emit(was_successful)

	# Section 2.4: A successful parry that resets cooldown allows initiating another parry
	# immediately after the current active window ends without waiting for cooldown.
	if _cooldown_reset_earned_in_current_window or parry_cooldown <= 1e-6:
		parry_state = ParryState.IDLE
		parry_timer = 0.0
		parry_cooldown_ended.emit()
	else:
		parry_state = ParryState.COOLDOWN
		parry_timer = maxf(0.0, parry_cooldown - overflow)
		if parry_timer <= 1e-6:
			parry_timer = 0.0
			parry_state = ParryState.IDLE
			parry_cooldown_ended.emit()



func _resolve_unparried_attacks_and_hazards() -> void:
	if is_dead or get_tree() == null:
		return

	var origin: Vector2 = get_parry_origin_global()

	# Instant-death and ordinary hazards
	for node in get_tree().get_nodes_in_group("lethal_hazards"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var hazard := node as Node2D
		var h_center: Vector2 = hazard.call("get_hazard_center_global") if hazard.has_method(
				"get_hazard_center_global") else hazard.global_position
		var h_radius: float = float(hazard.call("get_hit_radius")) if hazard.has_method("get_hit_radius") else 22.0
		if origin.distance_to(h_center) <= (hurtbox_radius + h_radius):
			var instant: bool = bool(hazard.get("is_instant_death")) if ("is_instant_death" in hazard) else true
			if instant:
				instant_kill(hazard)
			else:
				var dmg: int = int(hazard.get("damage")) if ("damage" in hazard) else 1
				take_damage(maxi(1, dmg), hazard, false)
			if is_dead:
				return

	# Damage from un-parried enemy attacks and projectiles
	for node in get_tree().get_nodes_in_group("parryable_attacks"):
		if not is_instance_valid(node) or not (node is Node2D) or node.is_queued_for_deletion():
			continue
		var attack := node as Node2D
		if attack.has_method("can_damage_player") and not bool(attack.call("can_damage_player", self)):
			continue

		var hit_radius: float = float(attack.call("get_hit_radius")) if attack.has_method("get_hit_radius") else 12.0
		var start_pos: Vector2 = attack.get(
				"prev_global_position") if ("prev_global_position" in attack) else attack.global_position
		var end_pos: Vector2 = attack.global_position
		var dist: float = Geometry2D.get_closest_point_to_segment(origin, start_pos, end_pos).distance_to(origin)

		if dist <= (hurtbox_radius + hit_radius):
			if attack is ParryableProjectile:
				attack.queue_free()
			take_damage(1, attack, false)
			if is_dead:
				return

	# Damage from contact with an enemy body
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if node.has_method("is_defeated") and bool(node.call("is_defeated")):
			continue
		var enemy := node as Node2D
		var e_center: Vector2 = enemy.call("get_center_global") if enemy.has_method(
				"get_center_global") else (enemy.global_position + Vector2(0, -32))
		var e_radius: float = float(enemy.call("get_hit_radius")) if enemy.has_method("get_hit_radius") else 26.0
		if origin.distance_to(e_center) <= (hurtbox_radius + e_radius):
			take_damage(1, enemy, false)
			if is_dead:
				return


## Checks whether a point or swept segment [seg_start, seg_end] with radius target_radius
## intersects the directional parry sector (origin, parry_direction, range, ±half_angle).
func is_segment_in_parry_sector(seg_start: Vector2, seg_end: Vector2, target_radius: float = 0.0) -> bool:
	var origin: Vector2 = get_parry_origin_global()
	var range_px: float = get_parry_range_px()
	var max_dist: float = range_px + target_radius
	var half_angle: float = get_parry_half_angle_rad()
	var dir_norm: Vector2 = parry_direction.normalized() if parry_direction.length_squared() > 1e-6 else Vector2.RIGHT

	var closest_to_origin: Vector2 = Geometry2D.get_closest_point_to_segment(origin, seg_start, seg_end)
	var samples: Array[Vector2] = [
		seg_start,
		seg_start.lerp(seg_end, 0.25),
		seg_start.lerp(seg_end, 0.50),
		seg_start.lerp(seg_end, 0.75),
		seg_end,
		closest_to_origin,
	]

	for pt in samples:
		var rel: Vector2 = pt - origin
		var dist: float = rel.length()
		if dist > max_dist:
			continue
		if dist <= 1e-4:
			return true
		var angle_diff: float = absf(dir_norm.angle_to(rel))
		if angle_diff <= half_angle + 1e-4:
			return true

	# If the target has a positive radius, also check intersection against the two radial boundary edges
	if target_radius > 0.0:
		var base_angle: float = dir_norm.angle()
		var edge_a_end: Vector2 = origin + Vector2.from_angle(base_angle - half_angle) * range_px
		var edge_b_end: Vector2 = origin + Vector2.from_angle(base_angle + half_angle) * range_px
		var pts_a: PackedVector2Array = Geometry2D.get_closest_points_between_segments(seg_start, seg_end, origin, edge_a_end)
		if pts_a.size() >= 2 and pts_a[0].distance_to(pts_a[1]) <= target_radius + 1e-4:
			return true
		var pts_b: PackedVector2Array = Geometry2D.get_closest_points_between_segments(seg_start, seg_end, origin, edge_b_end)
		if pts_b.size() >= 2 and pts_b[0].distance_to(pts_b[1]) <= target_radius + 1e-4:
			return true

	return false


func instant_kill(source: Object = null) -> void:
	if is_dead:
		return
	take_damage(maxi(hp, max_hp), source, true)


func take_damage(amount: int, source: Object=null, ignore_invulnerability: bool=false) -> void:
	if is_dead or amount <= 0:
		return
	if not ignore_invulnerability and is_invulnerable():
		return
	hp = maxi(0, hp - amount)
	interrupt_parry()
	_hurt_visual_active = true
	if player_visual != null and animated_sprite != null:
		player_visual.visible = false
		animated_sprite.visible = true
	player_damaged.emit(source, hp)
	if hp <= 0:
		is_dead = true
		invulnerability_timer = 0.0
		_set_parry_hitbox_enabled(false)
		if animated_sprite != null:
			animated_sprite.play_hurt()
		player_died.emit(source)
	else:
		# Temporary invulnerability
		invulnerability_timer = invulnerability_duration
		if animated_sprite != null and parry_state != ParryState.ACTIVE:
			if animated_sprite.animation != PlayerAnimatedSprite.HURT:
				_prev_animation = animated_sprite.animation
			animated_sprite.play_hurt()


func reset_player_state(spawn_global_position: Vector2) -> void:
	global_position = spawn_global_position
	velocity = Vector2.ZERO
	hp = max_hp
	is_dead = false
	invulnerability_timer = 0.0
	facing_direction = 1
	parry_state = ParryState.IDLE
	parry_timer = 0.0
	parry_direction = Vector2.RIGHT
	has_parry_momentum = false
	_parry_requires_release = false
	_parry_succeeded_in_current_window = false
	_cooldown_reset_earned_in_current_window = false
	_impulse_applied_this_tick = false
	_land_visual_timer = 0.0
	_airborne_time = 0.0
	_hurt_visual_active = false
	sim_move_dir = Vector2.ZERO
	sim_parry_dir = Vector2.INF
	sim_jump_just_pressed = false
	sim_parry_pressed = false
	_set_parry_hitbox_enabled(false)
	interrupt_parry()
	set_facing(false)
	_set_locomotion_scale(1.0)
	visual_motion = ""
	set_visual_motion(PlayerAnimationTree.Motion.IDLE)
	if player_visual != null:
		player_visual.visible = true
		player_visual.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if animated_sprite != null:
		animated_sprite.visible = (player_visual == null)
		animated_sprite.flip_h = false
		animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
		animated_sprite.play_idle()


func _on_animation_finished() -> void:
	if animated_sprite == null or is_dead:
		return
	var current_anim: StringName = animated_sprite.animation
	if current_anim == PlayerAnimatedSprite.HURT:
		_hurt_visual_active = false
		if player_visual != null:
			player_visual.visible = true
			animated_sprite.visible = false
		animated_sprite.play(_prev_animation)
	elif current_anim == PlayerAnimatedSprite.PARRY or current_anim == PlayerAnimatedSprite.JUMP:
		animated_sprite.play(_prev_animation)


func _update_animations_and_visuals(delta: float, input_x: float) -> void:
	if is_dead:
		return

	set_facing(facing_direction < 0)
	var tint := Color(1.0, 1.0, 1.0, 1.0)
	if is_invulnerable():
		var flash: float = 0.55 if int(invulnerability_timer * 20.0) % 2 == 0 else 0.90
		tint = Color(1.0, 0.75, 0.75, flash)

	if player_visual != null:
		player_visual.modulate = tint
		if animated_sprite != null:
			player_visual.visible = not _hurt_visual_active
			animated_sprite.visible = _hurt_visual_active

	if not is_on_floor():
		_land_visual_timer = 0.0
		_set_locomotion_scale(1.0)
		if absf(velocity.y) <= 120.0 and absf(velocity.x) > 80.0:
			set_visual_motion(PlayerAnimationTree.Motion.AIR_MOVE)
		elif velocity.y < 0.0:
			set_visual_motion(PlayerAnimationTree.Motion.RISE)
		else:
			set_visual_motion(PlayerAnimationTree.Motion.FALL)
	elif absf(input_x) > 0.1 or absf(velocity.x) > 5.0:
		_land_visual_timer = 0.0
		var base_speed: float = maxf(1.0, ground_movement_speed_ch * character_height)
		var speed_scale: float = clampf(absf(velocity.x) / base_speed, 0.5, 2.0)
		_set_locomotion_scale(speed_scale)
		set_visual_motion(PlayerAnimationTree.Motion.RUN)
	else:
		_set_locomotion_scale(1.0)
		if _land_visual_timer > 0.0:
			_land_visual_timer = maxf(0.0, _land_visual_timer - delta)
			set_visual_motion(PlayerAnimationTree.Motion.LAND)
		else:
			set_visual_motion(PlayerAnimationTree.Motion.IDLE)

	if animated_sprite == null:
		return

	animated_sprite.modulate = tint
	if parry_state == ParryState.ACTIVE:
		if animated_sprite.animation != PlayerAnimatedSprite.PARRY:
			animated_sprite.play(PlayerAnimatedSprite.PARRY)
		return

	if not is_on_floor():
		if animated_sprite.animation != PlayerAnimatedSprite.JUMP and animated_sprite.animation != PlayerAnimatedSprite.PARRY and animated_sprite.animation != PlayerAnimatedSprite.HURT:
			animated_sprite.play(PlayerAnimatedSprite.JUMP)
	elif absf(input_x) > 0.1 or absf(velocity.x) > 5.0:
		if animated_sprite.animation != PlayerAnimatedSprite.MOVE and animated_sprite.animation != PlayerAnimatedSprite.PARRY and animated_sprite.animation != PlayerAnimatedSprite.HURT:
			animated_sprite.play(PlayerAnimatedSprite.MOVE)
	else:
		if animated_sprite.animation != PlayerAnimatedSprite.IDLE and animated_sprite.animation != PlayerAnimatedSprite.PARRY and animated_sprite.animation != PlayerAnimatedSprite.HURT:
			animated_sprite.play(PlayerAnimatedSprite.IDLE)
