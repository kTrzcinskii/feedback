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
	print("=== Running Feedback Base Groundwork Test Suite ===")
	var packed_level: PackedScene = load("res://scenes/TestLevel.tscn") as PackedScene
	var level: TestLevel = packed_level.instantiate() as TestLevel
	root.add_child(level)
	await process_frame
	await physics_frame

	var player: PlayerCharacter = level.player
	player.use_simulated_input = true

	await _test_movement_and_jump_rules(player, level)
	await _test_damage_invulnerability_and_instant_death(player, level)
	await _test_layered_player_visual_assets(player, level)

	print("=== Test Summary: %d passed, %d failed ===" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _test_movement_and_jump_rules(player: PlayerCharacter, level: TestLevel) -> void:
	print("-- Test 1: Ordinary Movement (No Acceleration), Reversal & Jump Rules (Sections 3.1 - 3.3)")
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
	print("-- Test 2: Ordinary Damage, 0.75s Invulnerability & Instant-Death Hazards (Section 3.6)")
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
	print("-- Test 3: Layered SVG Pipeline Player Visuals & Locomotion States")
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
