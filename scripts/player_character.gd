class_name PlayerCharacter
extends CharacterBody2D

signal player_damaged(source: Object, remaining_hp: int)
signal player_died(source: Object)

@export_group("Units")
## 1.0 Character Height (CH) in pixels
@export var character_height: float = 64.0

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
var has_parry_momentum: bool = false
var visual_motion: String = ""

var _impulse_applied_this_tick: bool = false
var _prev_animation: StringName = PlayerAnimatedSprite.IDLE
var _land_visual_timer: float = 0.0
var _airborne_time: float = 0.0
var _hurt_visual_active: bool = false

# Optional simulated input overrides for deterministic testing
var use_simulated_input: bool = false
var sim_move_dir: Vector2 = Vector2.ZERO
var sim_jump_just_pressed: bool = false

@onready var player_visual: Node2D = get_node_or_null("PlayerVisual") as Node2D
@onready var animation_tree: PlayerAnimationTree = get_node_or_null("PlayerVisual/AnimationTree") as PlayerAnimationTree
@onready var animated_sprite: PlayerAnimatedSprite = get_node_or_null("AnimatedSprite2D") as PlayerAnimatedSprite


func _ready() -> void:
	process_physics_priority = -10
	hp = max_hp
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


func get_parry_origin_global() -> Vector2:
	return global_position + parry_origin_offset


func get_hurtbox_radius() -> float:
	return hurtbox_radius


func is_invulnerable() -> bool:
	return invulnerability_timer > 0.0


func _read_movement_input() -> float:
	if use_simulated_input:
		return sim_move_dir.x
	var left: bool = Input.is_action_pressed("MoveLeft") if InputMap.has_action("MoveLeft") else false
	var right: bool = Input.is_action_pressed("MoveRight") if InputMap.has_action("MoveRight") else false
	return (1.0 if right else 0.0) - (1.0 if left else 0.0)


func _read_jump_just_pressed() -> bool:
	if use_simulated_input:
		return sim_jump_just_pressed
	return Input.is_action_just_pressed("Jump") if InputMap.has_action("Jump") else false


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_impulse_applied_this_tick = false
	if invulnerability_timer > 0.0:
		invulnerability_timer = maxf(0.0, invulnerability_timer - delta)

	var move_x: float = _read_movement_input()
	var jump_just_pressed: bool = _read_jump_just_pressed()

	if absf(move_x) > 0.1:
		facing_direction = 1 if move_x > 0.0 else -1

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
		if animated_sprite != null:
			animated_sprite.play_hurt()
		player_died.emit(source)
	else:
		# Temporary invulnerability
		invulnerability_timer = invulnerability_duration
		if animated_sprite != null:
			if not animated_sprite.is_hurt():
				_prev_animation = animated_sprite.animation
			animated_sprite.play_hurt()


func reset_player_state(spawn_global_position: Vector2) -> void:
	global_position = spawn_global_position
	velocity = Vector2.ZERO
	hp = max_hp
	is_dead = false
	invulnerability_timer = 0.0
	facing_direction = 1
	has_parry_momentum = false
	_impulse_applied_this_tick = false
	_land_visual_timer = 0.0
	_airborne_time = 0.0
	_hurt_visual_active = false
	sim_move_dir = Vector2.ZERO
	sim_jump_just_pressed = false
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
	elif current_anim == PlayerAnimatedSprite.JUMP:
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
	if not is_on_floor():
		if animated_sprite.animation != PlayerAnimatedSprite.JUMP and animated_sprite.animation != PlayerAnimatedSprite.HURT:
			animated_sprite.play(PlayerAnimatedSprite.JUMP)
	elif absf(input_x) > 0.1 or absf(velocity.x) > 5.0:
		if animated_sprite.animation != PlayerAnimatedSprite.MOVE and animated_sprite.animation != PlayerAnimatedSprite.HURT:
			animated_sprite.play(PlayerAnimatedSprite.MOVE)
	else:
		if animated_sprite.animation != PlayerAnimatedSprite.IDLE and animated_sprite.animation != PlayerAnimatedSprite.HURT:
			animated_sprite.play_idle()
