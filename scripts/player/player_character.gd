class_name PlayerCharacter
extends CharacterBody2D

signal parry_started(direction: Vector2, active_duration: float)
signal parry_succeeded(target: Object, category: StringName, direction: Vector2, resulting_velocity: Vector2)
signal parry_failed(projectile: ParryableProjectile)
signal parry_window_ended(was_successful: bool)
signal parry_cooldown_ended()
signal player_damaged(source: Object, remaining_hp: int)
signal player_died(source: Object)

enum ParryState {
	IDLE,
	ACTIVE,
	COOLDOWN,
}

@export_group("Units")
## 1.0 Character Height (CH) in pixels
@export var character_height: float = 64.0

## (TODO: adjust as needed after gameplay tests).
@export_group("Parry Parameters")
## Active window duration in seconds
@export var parry_active_duration: float = 0.20
## Cooldown duration in seconds after active window ends
@export var parry_cooldown: float = 0.20
## Seconds after the active parry ends during which a projectile hit can trigger the failure cue
@export var parry_failure_cue_grace_duration: float = 0.4
## Hitbox range in Character Heights
@export var parry_hitbox_range_ch: float = 1.0
## Angular coverage in degrees from the locked direction
@export var parry_angular_coverage_deg: float = 22.5
## Successful parry against an attack resets the cooldown
@export var reset_cooldown_on_attack_parry: bool = true
## A successful environmental surface parry does not reset the cooldown
@export var reset_cooldown_on_surface_parry: bool = false
## Impulse magnitude granted by parrying a physical attack, in CH/s (Section 2.5.B & Section 4).
@export var physical_attack_impulse_ch: float = 10.0
## Default impulse magnitude 'J' granted by parrying a solid environmental surface, in CH/s (Section 3.5 & Section 4).
@export var surface_parry_impulse_ch: float = 9.5
## Default coefficient of restitution 'e' for surface parry reflection (Section 3.5).
@export var default_surface_restitution: float = 0.35

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
var _parry_failure_cue_grace_remaining: float = 0.0
var _parry_succeeded_in_current_window: bool = false
var _cooldown_reset_earned_in_current_window: bool = false
var _surface_parried_in_current_window: bool = false
var _parried_targets_in_current_window: Array[int] = []
var _parried_targets_this_tick: Array[int] = []
var _impulse_applied_this_tick: bool = false
var _pre_slide_velocity: Vector2 = Vector2.ZERO
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
@onready var _parry_feedback: ParryFeedback = get_node_or_null("ParryFeedback") as ParryFeedback
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
		_parry_polygon.set_deferred("disabled", not enabled)
	if _parry_hitbox != null:
		_parry_hitbox.set_deferred("monitoring", enabled)
		_parry_hitbox.set_deferred("monitorable", enabled)
		_parry_hitbox.rotation = parry_direction.angle()
	if _parry_feedback != null:
		_parry_feedback.position = _parry_hitbox.position
		_parry_feedback.show_active_sector(enabled, _parry_polygon.polygon, _parry_hitbox.rotation)


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


## Samples 8-directional input once when parry starts.
## Defaults to facing_direction when no directional input is held.
## Diagonal directions are normalized
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
	var left: bool = Input.is_action_pressed("ParryLeft") if InputMap.has_action(
			"ParryLeft") else Input.is_action_pressed("MoveLeft")
	var right: bool = Input.is_action_pressed("ParryRight") if InputMap.has_action(
			"ParryRight") else Input.is_action_pressed("MoveRight")
	var up: bool = Input.is_action_pressed("ParryUp") if InputMap.has_action("ParryUp") else false
	var down: bool = Input.is_action_pressed("ParryDown") if InputMap.has_action(
			"ParryDown") else Input.is_action_pressed("Crouch")
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

	_parried_targets_this_tick.clear()
	_impulse_applied_this_tick = false
	if invulnerability_timer > 0.0:
		invulnerability_timer = maxf(0.0, invulnerability_timer - delta)

	var move_x: float = _read_movement_input()
	var parry_dir_input: Vector2 = _read_parry_direction_input()
	var jump_just_pressed: bool = _read_jump_just_pressed()
	var parry_pressed: bool = _read_parry_pressed()

	# Update facing direction from horizontal movement when not locked in an active parry
	if absf(move_x) > 0.1 and parry_state != ParryState.ACTIVE:
		facing_direction = 1 if move_x > 0.0 else -1

	_update_parry_cycle(delta, parry_dir_input, parry_pressed)

	_update_movement_and_gravity(delta, move_x, jump_just_pressed)

	# 3. Resolve same-tick parry priority before damage (Sections 2.5 & 2.6)
	_pre_slide_velocity = velocity
	_resolve_combat_and_parry_tick()

	_move_character_body_2D(delta)
	_resolve_combat_and_parry_tick()

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

	# is_on_floor(), not `grounded`: on the takeoff tick ground rules still apply, so running jumps start at full speed
	if is_on_floor() and not _impulse_applied_this_tick and not has_parry_momentum:
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
	_pre_slide_velocity = velocity
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
	_parry_failure_cue_grace_remaining = maxf(0.0, _parry_failure_cue_grace_remaining - delta)

	# Advance active window / cooldown timers
	if parry_state == ParryState.ACTIVE:
		parry_timer -= delta
		if parry_timer <= 1e-6:
			# Next physics frame overflow
			var overflow: float = maxf(0.0, -parry_timer)
			_end_active_parry_window(overflow)
	elif parry_state == ParryState.COOLDOWN:
		parry_timer -= delta
		if parry_timer <= 1e-6:
			parry_timer = 0.0
			parry_state = ParryState.IDLE
			parry_cooldown_ended.emit()

	if not parry_pressed:
		_parry_requires_release = false

	if parry_state == ParryState.IDLE and parry_pressed and not _parry_requires_release:
		_start_parry(dir_input)

	if parry_pressed:
		_parry_requires_release = true


func _start_parry(dir_input: Vector2) -> void:
	parry_direction = sample_parry_direction(dir_input)
	parry_state = ParryState.ACTIVE
	parry_timer = parry_active_duration
	_parry_requires_release = true
	_parry_succeeded_in_current_window = false
	_cooldown_reset_earned_in_current_window = false
	_surface_parried_in_current_window = false
	_parried_targets_in_current_window.clear()

	_rebuild_parry_sector_polygon()
	_set_parry_hitbox_enabled(true)
	show_parry()

	if animated_sprite != null:
		if animated_sprite.animation != PlayerAnimatedSprite.PARRY:
			_prev_animation = animated_sprite.animation
		animated_sprite.play(PlayerAnimatedSprite.PARRY)

	parry_started.emit(parry_direction, parry_active_duration)


func _end_active_parry_window(overflow: float=0.0) -> void:
	var was_successful: bool = _parry_succeeded_in_current_window
	_parry_failure_cue_grace_remaining = maxf(0.0, parry_failure_cue_grace_duration - overflow)
	_set_parry_hitbox_enabled(false)
	parry_window_ended.emit(was_successful)

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


## Same-tick parry and death priority
## 1. Check whether parry is active
## 2. Check whether incoming attack intersects the directional hitbox
## 3. If successful, neutralize or redirect the attack
## 4. Apply the corresponding momentum effect, if applicable
## 5. Resolve any remaining collisions and damage
func _resolve_combat_and_parry_tick() -> void:
	if is_dead:
		return

	if parry_state == ParryState.ACTIVE:
		_resolve_active_parry_against_attacks()
		if parry_state == ParryState.ACTIVE:
			_resolve_active_parry_against_surfaces()

	_resolve_unparried_attacks_and_hazards()


func _resolve_active_parry_against_attacks() -> void:
	if get_tree() == null:
		return
	var attacks: Array[Node] = get_tree().get_nodes_in_group("parryable_attacks")
	for node in attacks:
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var attack := node as Node2D
		var inst_id: int = attack.get_instance_id()
		if _parried_targets_in_current_window.has(inst_id):
			continue

		if attack.has_method("is_attack_active") and not bool(attack.call("is_attack_active")):
			continue

		var hit_radius: float = float(attack.call("get_hit_radius")) if attack.has_method("get_hit_radius") else 12.0
		var start_pos: Vector2 = attack.get(
				"prev_global_position") if ("prev_global_position" in attack) else attack.global_position
		var end_pos: Vector2 = attack.global_position

		if is_segment_in_parry_sector(start_pos, end_pos, hit_radius):
			var parried_ok: bool = true
			if attack.has_method("on_parried"):
				parried_ok = bool(attack.call("on_parried", self, parry_direction))
			if not parried_ok:
				continue

			_parried_targets_in_current_window.append(inst_id)
			_parried_targets_this_tick.append(inst_id)

			var category: StringName = attack.call("get_attack_category") if attack.has_method(
					"get_attack_category") else &"attack"
			if category == &"physical":
				var imp_dir: Vector2 = attack.call("get_impulse_direction") if attack.has_method(
						"get_impulse_direction") else (-parry_direction)
				var imp_ch: float = physical_attack_impulse_ch
				if "impulse_override_ch" in attack and float(attack.get("impulse_override_ch")) > 0.0:
					imp_ch = float(attack.get("impulse_override_ch"))
				apply_parry_impulse(imp_dir.normalized() * (imp_ch * character_height))

			_on_parry_success(attack, category, end_pos)
			if parry_state != ParryState.ACTIVE:
				break


func _resolve_active_parry_against_surfaces() -> void:
	if _surface_parried_in_current_window:
		return
	var world_2d: World2D = get_world_2d()
	if world_2d == null:
		return
	var space_state: PhysicsDirectSpaceState2D = world_2d.direct_space_state
	if space_state == null:
		return

	var origin: Vector2 = get_parry_origin_global()
	var range_px: float = get_parry_range_px()
	var half_rad: float = get_parry_half_angle_rad()
	var base_angle: float = parry_direction.angle()

	var ray_angles: Array[float] = [
		base_angle,
		base_angle - half_rad * 0.25,
		base_angle + half_rad * 0.25,
		base_angle - half_rad * 0.50,
		base_angle + half_rad * 0.50,
		base_angle - half_rad * 0.75,
		base_angle + half_rad * 0.75,
		base_angle - half_rad * 0.95,
		base_angle + half_rad * 0.95,
	]

	var best_hit: Dictionary = {}
	var best_dist_sq: float = INF

	for ang in ray_angles:
		var ray_dir: Vector2 = Vector2.from_angle(ang)
		var query := PhysicsRayQueryParameters2D.create(origin, origin + ray_dir * range_px, collision_mask,
				[get_rid()])
		query.collide_with_bodies = true
		query.collide_with_areas = false
		var result: Dictionary = space_state.intersect_ray(query)
		if not result.is_empty():
			var normal: Vector2 = result.get("normal", Vector2.ZERO)
			if normal.length_squared() > 1e-6 and parry_direction.dot(normal) < -0.1:
				var hit_pos: Vector2 = result.get("position", origin)
				var d_sq: float = origin.distance_squared_to(hit_pos)
				if d_sq < best_dist_sq:
					best_dist_sq = d_sq
					best_hit = result

	if best_hit.is_empty():
		return

	_surface_parried_in_current_window = true
	var surface_normal: Vector2 = (best_hit["normal"] as Vector2).normalized()
	var collider: Object = best_hit.get("collider", null)
	var hit_point: Vector2 = best_hit.get("position", origin)

	var restitution: float = default_surface_restitution
	var impulse_mult: float = 1.0
	var custom_impulse_ch: float = -1.0
	if collider is ParryableSurface:
		var ps := collider as ParryableSurface
		restitution = ps.restitution
		impulse_mult = ps.impulse_multiplier
		custom_impulse_ch = ps.surface_impulse_ch

	# If move_and_slide already cancelled velocity into the surface on
	# this tick, restore the pre-slide normal component
	if _pre_slide_velocity.dot(surface_normal) < velocity.dot(surface_normal):
		velocity = _pre_slide_velocity

	apply_surface_parry_bounce(surface_normal, restitution, impulse_mult, custom_impulse_ch)
	_on_parry_success(collider, &"surface", hit_point)


## Momentum and impulse application (v_new = v_old + delta_v)
func apply_parry_impulse(delta_v: Vector2) -> void:
	velocity += delta_v
	has_parry_momentum = true
	_impulse_applied_this_tick = true


## Environmental surface parry reflection & impulse
## v_reflected = v - (1 + e) * dot(v, n) * n if dot(v, n) < 0, else v
## v_new = v_reflected + J * n
func apply_surface_parry_bounce(
		surface_normal: Vector2,
		restitution: float=-1.0,
		impulse_multiplier: float=1.0,
		custom_impulse_ch: float=-1.0
) -> void:
	var n: Vector2 = surface_normal.normalized()
	if n.length_squared() <= 1e-6:
		return
	var e: float = restitution if restitution >= 0.0 else default_surface_restitution
	var v_dot_n: float = velocity.dot(n)
	var v_reflected: Vector2 = (velocity - (1.0 + e) * v_dot_n * n) if v_dot_n < 0.0 else velocity
	var base_impulse_ch: float = custom_impulse_ch if custom_impulse_ch >= 0.0 else surface_parry_impulse_ch
	var j_impulse: float = base_impulse_ch * character_height * impulse_multiplier

	velocity = v_reflected + j_impulse * n
	has_parry_momentum = true
	_impulse_applied_this_tick = true


func _on_parry_success(target: Object, category: StringName, _fx_global_pos: Vector2) -> void:
	_parry_succeeded_in_current_window = true
	if category == &"surface":
		if reset_cooldown_on_surface_parry:
			_cooldown_reset_earned_in_current_window = true
	else:
		if reset_cooldown_on_attack_parry:
			_cooldown_reset_earned_in_current_window = true

	parry_succeeded.emit(target, category, parry_direction, velocity)


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
		var inst_id: int = attack.get_instance_id()
		# A successfully parried attack doesn't decrease player hp
		if _parried_targets_this_tick.has(inst_id):
			continue
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
				if parry_state == ParryState.ACTIVE or _parry_failure_cue_grace_remaining > 0.0:
					parry_failed.emit(attack)
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


## Checks whether a point or swept segment [seg_start, seg_end] with
## radius target_radius intersects the directional parry sector (origin,
## parry_direction, range, ±half_angle).
func is_segment_in_parry_sector(seg_start: Vector2, seg_end: Vector2, target_radius: float=0.0) -> bool:
	var origin: Vector2 = get_parry_origin_global()
	var range_px: float = get_parry_range_px()
	var max_dist: float = range_px + target_radius
	var half_angle: float = get_parry_half_angle_rad()
	var dir_norm: Vector2 = parry_direction.normalized() if parry_direction.length_squared() > 1e-6 else Vector2.RIGHT

	var closest_to_origin: Vector2 = Geometry2D.get_closest_point_to_segment(origin, seg_start, seg_end)
	# TODO: update this to be more elaborate
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
		var pts_a: PackedVector2Array = Geometry2D.get_closest_points_between_segments(seg_start, seg_end, origin,
				edge_a_end)
		if pts_a.size() >= 2 and pts_a[0].distance_to(pts_a[1]) <= target_radius + 1e-4:
			return true
		var pts_b: PackedVector2Array = Geometry2D.get_closest_points_between_segments(seg_start, seg_end, origin,
				edge_b_end)
		if pts_b.size() >= 2 and pts_b[0].distance_to(pts_b[1]) <= target_radius + 1e-4:
			return true

	return false


func instant_kill(source: Object=null) -> void:
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
	_parry_failure_cue_grace_remaining = 0.0
	parry_direction = Vector2.RIGHT
	has_parry_momentum = false
	_parry_requires_release = false
	_parry_succeeded_in_current_window = false
	_cooldown_reset_earned_in_current_window = false
	_surface_parried_in_current_window = false
	_parried_targets_in_current_window.clear()
	_parried_targets_this_tick.clear()
	_impulse_applied_this_tick = false
	_pre_slide_velocity = Vector2.ZERO
	_land_visual_timer = 0.0
	_airborne_time = 0.0
	_hurt_visual_active = false
	sim_move_dir = Vector2.ZERO
	sim_parry_dir = Vector2.INF
	sim_jump_just_pressed = false
	sim_parry_pressed = false
	_set_parry_hitbox_enabled(false)
	if _parry_feedback != null:
		_parry_feedback.clear_outcomes()
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
		animated_sprite.play_parry()
		return

	animated_sprite.play_locomotion(is_on_floor(), absf(input_x) > 0.1 or absf(velocity.x) > 5.0)
