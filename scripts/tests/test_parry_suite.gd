extends SceneTree

var _failures: int = 0
var _passes: int = 0


func _initialize() -> void:
	call_deferred("_run_all_tests")


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("FAIL: ", msg)


func _assert_approx(a: float, b: float, eps: float, msg: String) -> void:
	_assert_true(absf(a - b) <= eps, "%s (got %.4f, expected %.4f ± %.4f)" % [msg, a, b, eps])


func _run_all_tests() -> void:
	print("=== Running Feedback FB023 Parry Activation Cycle Test Suite ===")
	var scene_path := "res://scenes/levels/the_proving_hall.tscn" if ResourceLoader.exists("res://scenes/levels/the_proving_hall.tscn") else "res://scenes/TestLevel.tscn"
	var packed_level: PackedScene = load(scene_path) as PackedScene
	var level: TestLevel = packed_level.instantiate() as TestLevel
	root.add_child(level)
	await process_frame
	await physics_frame

	var player: PlayerCharacter = level.player
	player.use_simulated_input = true

	_test_8_directions_and_lock(player, level)
	_test_sector_hitbox_geometry(player, level)
	await _test_activation_cycle_and_hold_rules(player, level)
	await _test_movement_and_jump_rules(player, level)
	await _test_damage_invulnerability_and_instant_death(player, level)
	await _test_layered_player_visual_assets(player, level)

	print("=== Test Summary: %d passed, %d failed ===" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _test_8_directions_and_lock(player: PlayerCharacter, level: TestLevel) -> void:
	print("-- Test 1: 8-Directional Sampling & Direction Lock (Section 2.1)")
	level.reset_room()
	player.use_simulated_input = true

	# Default to facing direction when no input is provided
	player.facing_direction = 1
	_assert_true(player.sample_parry_direction(Vector2.ZERO).is_equal_approx(Vector2.RIGHT), "Default direction when facing right is RIGHT")
	player.facing_direction = -1
	_assert_true(player.sample_parry_direction(Vector2.ZERO).is_equal_approx(Vector2.LEFT), "Default direction when facing left is LEFT")

	# All 8 cardinal and diagonal directions normalized
	var cases: Array[Array] = [
		[Vector2(1, 0), Vector2.RIGHT],
		[Vector2(-1, 0), Vector2.LEFT],
		[Vector2(0, -1), Vector2.UP],
		[Vector2(0, 1), Vector2.DOWN],
		[Vector2(1, -1), Vector2(1, -1).normalized()],
		[Vector2(-1, -1), Vector2(-1, -1).normalized()],
		[Vector2(1, 1), Vector2(1, 1).normalized()],
		[Vector2(-1, 1), Vector2(-1, 1).normalized()],
	]
	for c in cases:
		var sampled: Vector2 = player.sample_parry_direction(c[0])
		_assert_true(sampled.is_equal_approx(c[1]), "Sampled direction for %s matches %s" % [str(c[0]), str(c[1])])
		_assert_approx(sampled.length(), 1.0, 1e-4, "Direction %s is unit-normalized" % str(c[0]))

	# Lock direction during active parry even if input changes
	player.sim_move_dir = Vector2(1, -1)
	player.sim_parry_pressed = true
	player._physics_process(0.016)
	_assert_true(player.is_parry_active(), "Parry active after press")
	_assert_true(player.parry_direction.is_equal_approx(Vector2(1, -1).normalized()), "Initial parry direction is UP-RIGHT")

	# Attempt to change direction mid-parry to DOWN-LEFT
	player.sim_move_dir = Vector2(-1, 1)
	player._physics_process(0.05)
	_assert_true(player.is_parry_active(), "Parry still active at t=0.05s")
	_assert_true(player.parry_direction.is_equal_approx(Vector2(1, -1).normalized()), "Parry direction remains locked during active window")
	player.sim_parry_pressed = false
	player.sim_move_dir = Vector2.ZERO

	# Verify real InputMap actions ParryRight + ParryUp, ParryRight + ParryDown, and independent MoveLeft + ParryRight
	level.reset_room()
	player.use_simulated_input = false
	Input.action_press("MoveLeft")
	Input.action_press("ParryRight")
	Input.action_press("ParryUp")
	Input.action_press("Parry")
	player._physics_process(0.016)
	_assert_true(player.is_parry_active(), "Parry active via InputMap actions")
	_assert_true(player.parry_direction.is_equal_approx(Vector2(1, -1).normalized()), "ParryRight + ParryUp gives UP-RIGHT even while MoveLeft is held")
	_assert_true(player.velocity.x < 0.0, "Player moves LEFT via MoveLeft while parrying UP-RIGHT via ParryRight+ParryUp")
	Input.action_release("MoveLeft")
	Input.action_release("ParryRight")
	Input.action_release("ParryUp")
	Input.action_release("Parry")

	level.reset_room()
	player.use_simulated_input = false
	player.global_position += Vector2(0, -120)
	Input.action_press("ParryRight")
	Input.action_press("ParryDown")
	Input.action_press("Parry")
	player._physics_process(0.016)
	_assert_true(player.is_parry_active(), "Parry active via ParryRight + ParryDown")
	_assert_true(player.parry_direction.is_equal_approx(Vector2(1, 1).normalized()), "ParryRight + ParryDown gives DOWN-RIGHT")
	Input.action_release("ParryRight")
	Input.action_release("ParryDown")
	Input.action_release("Parry")
	player.use_simulated_input = true


func _test_sector_hitbox_geometry(player: PlayerCharacter, level: TestLevel) -> void:
	print("-- Test 2: Angular Sector Hitbox Geometry (Section 2.2)")
	level.reset_room()
	player.use_simulated_input = true
	player.parry_direction = Vector2.RIGHT
	var origin: Vector2 = player.get_parry_origin_global()
	var range_px: float = player.get_parry_range_px()
	_assert_approx(range_px, 64.0, 1e-3, "Hitbox range is 1.0 CH (64 px)")

	# Inside range (0.8 CH) and within ±22.5°
	var p_center: Vector2 = origin + Vector2.from_angle(deg_to_rad(0.0)) * (range_px * 0.8)
	var p_plus20: Vector2 = origin + Vector2.from_angle(deg_to_rad(20.0)) * (range_px * 0.8)
	var p_minus20: Vector2 = origin + Vector2.from_angle(deg_to_rad(-20.0)) * (range_px * 0.8)
	_assert_true(player.is_segment_in_parry_sector(p_center, p_center, 0.0), "0 deg at 0.8 CH is inside sector")
	_assert_true(player.is_segment_in_parry_sector(p_plus20, p_plus20, 0.0), "+20 deg at 0.8 CH is inside sector")
	_assert_true(player.is_segment_in_parry_sector(p_minus20, p_minus20, 0.0), "-20 deg at 0.8 CH is inside sector")

	# Outside ±22.5° angular coverage
	var p_plus26: Vector2 = origin + Vector2.from_angle(deg_to_rad(26.0)) * (range_px * 0.8)
	var p_minus26: Vector2 = origin + Vector2.from_angle(deg_to_rad(-26.0)) * (range_px * 0.8)
	var p_behind: Vector2 = origin + Vector2.LEFT * (range_px * 0.5)
	_assert_true(not player.is_segment_in_parry_sector(p_plus26, p_plus26, 0.0), "+26 deg is outside ±22.5 deg sector")
	_assert_true(not player.is_segment_in_parry_sector(p_minus26, p_minus26, 0.0), "-26 deg is outside ±22.5 deg sector")
	_assert_true(not player.is_segment_in_parry_sector(p_behind, p_behind, 0.0), "180 deg behind player is outside sector")

	# Finite target_radius overlapping radial boundary edge
	_assert_true(player.is_segment_in_parry_sector(p_plus26, p_plus26, 12.0), "+26 deg with 12px radius overlaps ±22.5 deg sector boundary")

	# Outside 1.0 CH range
	var p_far: Vector2 = origin + Vector2.RIGHT * (range_px * 1.2)
	_assert_true(not player.is_segment_in_parry_sector(p_far, p_far, 0.0), "1.2 CH at 0 deg is outside 1.0 CH range")

	# Diagonal normalization check
	player.parry_direction = Vector2(1, -1).normalized()
	var p_diag_norm: Vector2 = origin + Vector2(1, -1).normalized() * (range_px * 0.98)
	var p_diag_unnorm: Vector2 = origin + Vector2(1, -1) * range_px
	_assert_true(player.is_segment_in_parry_sector(p_diag_norm, p_diag_norm, 0.0), "Normalized diagonal at 0.98 CH is inside")
	_assert_true(not player.is_segment_in_parry_sector(p_diag_unnorm, p_diag_unnorm, 0.0), "Unnormalized diagonal (1.414 CH) is outside range")


func _test_activation_cycle_and_hold_rules(player: PlayerCharacter, level: TestLevel) -> void:
	print("-- Test 3: Parry Activation Cycle, Hold & Cooldown Rules (Sections 2.3, 2.4 & 3.6)")
	level.reset_room()
	player.use_simulated_input = true
	player.sim_move_dir = Vector2.UP

	var dt: float = 0.05
	player.sim_parry_pressed = true
	player._physics_process(dt)
	_assert_true(player.parry_state == PlayerCharacter.ParryState.ACTIVE, "Immediate ACTIVE state on button press")
	_assert_approx(player.parry_timer, 0.20, 1e-4, "Initial active timer is 0.20s")

	player._physics_process(dt) # rem 0.15
	player._physics_process(dt) # rem 0.10
	player._physics_process(dt) # rem 0.05
	_assert_true(player.parry_state == PlayerCharacter.ParryState.ACTIVE, "Still ACTIVE before 0.20s expires")

	player._physics_process(dt) # rem 0.00 -> transitions to COOLDOWN (0.20s)
	_assert_true(player.parry_state == PlayerCharacter.ParryState.COOLDOWN, "Transitions to COOLDOWN after 0.20s even when button held")
	_assert_approx(player.parry_timer, 0.20, 1e-4, "Cooldown timer starts at 0.20s")

	for _i in range(4):
		player._physics_process(dt)
	_assert_true(player.parry_state == PlayerCharacter.ParryState.IDLE, "Transitions to IDLE after 0.20s cooldown (total 0.40s)")

	player._physics_process(dt)
	_assert_true(player.parry_state == PlayerCharacter.ParryState.IDLE, "Holding button after cooldown does NOT auto-trigger a new parry")

	player.sim_parry_pressed = false
	player._physics_process(dt)
	player.sim_parry_pressed = true
	player._physics_process(dt)
	_assert_true(player.parry_state == PlayerCharacter.ParryState.ACTIVE, "Releasing and pressing again after cooldown triggers new parry")

	player.sim_parry_pressed = false
	for _i in range(4):
		player._physics_process(dt)
	_assert_true(player.parry_state == PlayerCharacter.ParryState.COOLDOWN, "Now in COOLDOWN")
	player.sim_parry_pressed = true
	player._physics_process(dt)
	_assert_true(player.parry_state == PlayerCharacter.ParryState.COOLDOWN, "Pressing during cooldown has no effect")
	for _i in range(3):
		player._physics_process(dt)
	_assert_true(player.parry_state == PlayerCharacter.ParryState.IDLE, "Cooldown finishes while button still held from mid-cooldown press")
	player._physics_process(dt)
	_assert_true(player.parry_state == PlayerCharacter.ParryState.IDLE, "Press initiated during cooldown does not queue/auto-trigger when cooldown ends")

	# Verify airborne parry availability
	player.sim_parry_pressed = false
	player._physics_process(dt)
	player.global_position += Vector2(0, -120)
	player.velocity = Vector2(0, -50)
	player._physics_process(0.016)
	_assert_true(not player.is_on_floor(), "Player is airborne")
	player.sim_parry_pressed = true
	player._physics_process(0.016)
	_assert_true(player.is_parry_active(), "Parry activates while airborne")

	# Verify parry availability during 0.75s invulnerability (Section 3.6)
	level.reset_room()
	player.use_simulated_input = true
	player.take_damage(1, null)
	_assert_true(player.is_invulnerable(), "Player is invulnerable after taking non-lethal damage")
	player.sim_move_dir = Vector2.UP
	player.sim_parry_pressed = true
	player._physics_process(0.016)
	_assert_true(player.is_parry_active(), "Parrying is still possible during post-damage invulnerability")

	player.sim_parry_pressed = false
	player.sim_move_dir = Vector2.ZERO
	await physics_frame


func _test_movement_and_jump_rules(player: PlayerCharacter, level: TestLevel) -> void:
	print("-- Test 4: Ordinary Movement (No Acceleration), Reversal & Jump Rules (Sections 3.1 - 3.3)")
	level.reset_room()
	player.use_simulated_input = true
	await physics_frame
	for _i in range(5):
		player._physics_process(0.016)
	_assert_true(player.is_on_floor(), "Player is grounded at spawn")

	var expected_speed: float = player.ground_movement_speed_ch * player.character_height

	# Section 3.1: Pressing horizontal key immediately sets velocity to configured movement speed (no acceleration)
	player.sim_move_dir = Vector2.RIGHT
	player._physics_process(0.016)
	_assert_approx(player.velocity.x, expected_speed, 1e-3, "Pressing right immediately sets horizontal velocity to configured movement speed")

	# Section 3.1: Releasing movement key immediately stops ordinary horizontal movement
	player.sim_move_dir = Vector2.ZERO
	player._physics_process(0.016)
	_assert_approx(player.velocity.x, 0.0, 1e-4, "Releasing movement key immediately stops ordinary horizontal movement")

	# Section 3.1: Pressing opposite direction immediately changes direction to full configured speed
	player.sim_move_dir = Vector2.RIGHT
	player._physics_process(0.016)
	_assert_approx(player.velocity.x, expected_speed, 1e-3, "Moving right at full speed before reversal")
	player.sim_move_dir = Vector2.LEFT
	player._physics_process(0.016)
	_assert_approx(player.velocity.x, -expected_speed, 1e-3, "Pressing opposite direction immediately sets velocity to full speed in opposite direction")

	# Section 3.2: Grounded jump vs midair jump rejection
	player.sim_move_dir = Vector2.ZERO
	player._physics_process(0.016)
	player.sim_jump_just_pressed = true
	player._physics_process(0.016)
	var vy_after_jump: float = player.velocity.y
	_assert_true(vy_after_jump < -400.0, "Grounded jump applies upward velocity impulse")
	player.sim_jump_just_pressed = false
	player._physics_process(0.05)
	_assert_true(not player.is_on_floor(), "Player is now airborne")

	# Section 3.3: Air control applies horizontal acceleration rather than immediately overwriting velocity
	player.sim_move_dir = Vector2.RIGHT
	player._physics_process(0.016)
	_assert_true(player.velocity.x > 0.0 and player.velocity.x < expected_speed, "Airborne input accelerates gradually rather than immediately reaching max ground speed")
	player.sim_move_dir = Vector2.ZERO

	var vy_midair_before: float = player.velocity.y
	player.sim_jump_just_pressed = true
	player._physics_process(0.016)
	_assert_true(player.velocity.y > vy_midair_before, "Second midair jump is rejected (gravity continues accelerating downwards)")
	player.sim_jump_just_pressed = false
	await physics_frame


func _test_damage_invulnerability_and_instant_death(player: PlayerCharacter, level: TestLevel) -> void:
	print("-- Test 5: Ordinary Damage, 0.75s Invulnerability & Instant-Death Hazards (Section 3.6)")
	level.reset_room()
	player.use_simulated_input = true
	_assert_true(player.hp == player.max_hp and player.max_hp >= 2, "Player starts at full HP (%d)" % player.max_hp)

	# Non-lethal damage from projectile grants 0.75s invulnerability
	var proj := ParryableProjectile.new()
	level.add_child(proj)
	proj.configure(player.get_parry_origin_global(), Vector2.LEFT, 300.0)
	player._physics_process(0.016)
	_assert_true(player.hp == player.max_hp - 1 and not player.is_dead, "Un-parried projectile decreases player HP by 1 (non-lethal)")
	_assert_true(player.is_invulnerable(), "Player becomes temporarily invulnerable after non-lethal damage")
	_assert_approx(player.invulnerability_timer, 0.75, 1e-3, "Invulnerability duration starts at 0.75s")

	# Ordinary damage (e.g. enemy body contact) is ignored while invulnerable
	var hp_during_invuln: int = player.hp
	var emitter: ProjectileEmitter = level.get_node_or_null("SentinelEmitter") as ProjectileEmitter
	if emitter != null:
		var orig_emitter_pos: Vector2 = emitter.global_position
		emitter.global_position = player.global_position
		player._physics_process(0.016)
		_assert_true(player.hp == hp_during_invuln, "Enemy body contact does not reduce HP during active invulnerability")
		emitter.global_position = orig_emitter_pos

		# Advance past 0.75s invulnerability -> invulnerability expires
		for _i in range(16):
			player._physics_process(0.05)
		_assert_true(not player.is_invulnerable(), "Invulnerability expires after 0.75s")

	# Contact with enemy body when not invulnerable decreases HP and triggers 0.75s invulnerability
	if emitter != null:
		var hp_before_body: int = player.hp
		var orig_emitter_pos: Vector2 = emitter.global_position
		emitter.global_position = player.global_position
		player._physics_process(0.016)
		_assert_true(player.hp == hp_before_body - 1, "Contact with enemy body decreases player HP when not invulnerable")
		_assert_true(player.is_invulnerable(), "Non-lethal enemy body damage activates 0.75s invulnerability")
		emitter.global_position = orig_emitter_pos

	# Instant-death hazard (spikes) kills immediately regardless of remaining HP or active invulnerability
	_assert_true(player.is_invulnerable() and player.hp > 0, "Player has remaining HP and active invulnerability before spikes contact")
	var spikes := LethalSpikesHazard.new()
	level.add_child(spikes)
	spikes.global_position = player.get_parry_origin_global() - Vector2(0, 20)
	player._physics_process(0.016)
	_assert_true(player.is_dead and player.hp == 0, "Instant-death spikes kill player immediately despite remaining HP and active invulnerability")
	spikes.queue_free()
	await physics_frame


func _test_layered_player_visual_assets(player: PlayerCharacter, level: TestLevel) -> void:
	print("-- Test 6: Layered SVG Pipeline Player Visuals & Locomotion States")
	level.reset_room()
	player.use_simulated_input = true
	await physics_frame
	for _i in range(5):
		player._physics_process(0.016)

	_assert_true(player.player_visual != null and player.animation_tree != null, "PlayerCharacter instances PlayerVisual and AnimationTree from player-layered.tscn")
	_assert_true(player.visual_motion == "idle", "Grounded stationary player selects 'idle' locomotion state")

	player.sim_move_dir = Vector2.RIGHT
	player._physics_process(0.016)
	_assert_true(player.visual_motion == "run", "Grounded moving player selects 'run' locomotion state")

	player.sim_move_dir = Vector2.ZERO
	player.sim_jump_just_pressed = true
	player._physics_process(0.016)
	player.sim_jump_just_pressed = false
	player._physics_process(0.05)
	_assert_true(player.visual_motion == "rise", "Ascending airborne player selects 'rise' locomotion state")
	await physics_frame
