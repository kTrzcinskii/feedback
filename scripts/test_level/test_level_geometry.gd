extends SceneTree

var failures := 0
var checks := 0
var spawn_hits := 0


func _initialize() -> void:
	run_tests.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)


func step_frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func run_tests() -> void:
	var scene_path := "res://scenes/levels/the_proving_hall.tscn" if ResourceLoader.exists(
			"res://scenes/levels/the_proving_hall.tscn") else "res://scenes/TestLevel.tscn"
	var level: TestLevel = load(scene_path).instantiate()
	root.add_child(level)
	var player := level.player
	player.use_simulated_input = true
	player.player_damaged.connect(count_spawn_hit)
	await step_frames(480)
	player.player_damaged.disconnect(count_spawn_hit)
	check(spawn_hits == 0 and player.hp == player.max_hp and not level._reset_pending,
			"Spawn stays safe through eight seconds of live attack cycles")

	await test_downhill_grounding(level, player)
	await test_one_way_platforms(level, player)

	# Walk and jump with the real controller, without teleporting between landings.
	level.reset_room()
	player.position = Vector2(60, 0)
	await step_frames(12)
	for target in [Vector2(200, -72), Vector2(360, -144), Vector2(520, -216),
		Vector2(680, -288), Vector2(864, -216), Vector2(1056, -144), Vector2(1216, -72)]:
		await jump_to(player, target)
	# The same route must work backwards, so the test room cannot strand the player.
	for target in [Vector2(1056, -144), Vector2(864, -216), Vector2(680, -288),
		Vector2(520, -216), Vector2(360, -144), Vector2(200, -72)]:
		await jump_to(player, target)

	level.reset_room()
	player.position = Vector2(864, 0)
	await step_frames(60)
	check(player.position.distance_to(Vector2.ZERO) < 12.0 and player.hp == player.max_hp,
			"Falling into the spike trench resets the player safely")

	# A running jump also provides a short route across the trench at floor level.
	level.reset_room()
	player.position = Vector2(720, 0)
	await step_frames(12)
	player.sim_move_dir = Vector2.RIGHT
	await step_frames(3)
	player.sim_jump_just_pressed = true
	await step_frames(1)
	player.sim_jump_just_pressed = false
	await step_frames(43)
	player.sim_move_dir = Vector2.ZERO
	await step_frames(12)
	check(player.global_position.x > 960 and player.is_on_floor() and player.hp == player.max_hp,
			"The lower trench crossing is reachable with a running jump")

	# The collision floor ends at the visible boundaries, rather than continuing infinitely.
	var space := level.get_world_2d().direct_space_state
	for x in [-700.0, 1900.0]:
		var ray := PhysicsRayQueryParameters2D.create(Vector2(x, -10), Vector2(x, 500))
		check(space.intersect_ray(ray).is_empty(), "No invisible floor outside the room")

	print("Geometry checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)


func count_spawn_hit(_source: Object, _hp: int) -> void:
	spawn_hits += 1


func jump_to(player: PlayerCharacter, target: Vector2) -> void:
	var direction := signf(target.x - player.position.x)
	player.sim_move_dir = Vector2(direction, 0)
	player.sim_jump_just_pressed = true
	await step_frames(1)
	player.sim_jump_just_pressed = false
	var landed := false
	for i in range(90):
		# Brake using the actual air-control acceleration before reaching the target.
		var braking_distance := player.velocity.x * player.velocity.x / (2.0 * player.air_control_acceleration_ch * player.character_height)
		var remaining := (target.x - player.position.x) * direction
		if remaining < braking_distance + 4.0:
			player.sim_move_dir.x = -signf(player.velocity.x) if absf(player.velocity.x) > 20.0 else 0.0
		else:
			player.sim_move_dir.x = direction
		await step_frames(1)
		if i > 4 and player.is_on_floor():
			landed = absf(player.position.y - (target.y + 8.0)) < 4.0 and absf(player.position.x - target.x) < 70.0
			break
	check(landed, "Reach landing %s with an ordinary jump (ended at %s)" % [target, player.position])
	player.sim_move_dir = Vector2.ZERO
	await step_frames(2)


func test_downhill_grounding(level: TestLevel, player: PlayerCharacter) -> void:
	level.reset_room()
	player.position = Vector2(-400, -180)
	await step_frames(30)
	check(player.is_on_floor(), "Player settles on the tilted platform")
	var starting_y := player.position.y
	player.sim_move_dir = Vector2.LEFT
	var airborne_frames := 0
	for i in range(10):
		await step_frames(1)
		if not player.is_on_floor():
			airborne_frames += 1
	check(player.position.y > starting_y + 10.0, "Player actually travels downhill")
	check(airborne_frames == 0,
			"Downhill movement stays grounded on every frame (%d airborne frames)" % airborne_frames)
	player.sim_jump_just_pressed = true
	await step_frames(1)
	player.sim_jump_just_pressed = false
	check(not player.is_on_floor() and player.velocity.y < -400.0,
			"A downhill jump detaches immediately from the slope")


func test_one_way_platforms(level: TestLevel, player: PlayerCharacter) -> void:
	var platform_names := [
		"LowPlatform", "MiddlePlatform", "HighPlatform", "SummitPlatform",
		"TrenchBridge", "LandingPlatform", "ReturnStep", "AngledSurface", "CeilingPlatform"
	]
	for plat_name in platform_names:
		var surface: ParryableSurface = level.get_node_or_null("Platforms/" + plat_name) as ParryableSurface
		check(surface != null, "Platform %s exists in test level" % plat_name)
		if surface != null:
			var col: CollisionShape2D = surface.get_node_or_null("CollisionShape2D") as CollisionShape2D
			check(col != null and col.one_way_collision, "Platform %s has one-way collision enabled" % plat_name)

	# Verify walls are not one-way
	for wall_name in ["BounceWallLeft", "EndWall"]:
		var wall: ParryableSurface = level.get_node_or_null("Walls/" + wall_name) as ParryableSurface
		if wall != null:
			var col: CollisionShape2D = wall.get_node_or_null("CollisionShape2D") as CollisionShape2D
			check(col != null and not col.one_way_collision, "Wall %s remains solid (not one-way)" % wall_name)

	# Test jumping onto LowPlatform directly from below:
	# Floor is at y = 0, LowPlatform top is at y = -72 (landing y = -64).
	# A jump from beneath passes through the underside and lands safely on top.
	level.reset_room()
	player.position = Vector2(200, 0)
	await step_frames(12)
	check(player.is_on_floor(), "Player is grounded beneath LowPlatform")
	player.sim_jump_just_pressed = true
	await step_frames(1)
	player.sim_jump_just_pressed = false

	var passed_through_upwards := false
	var landed_on_platform := false
	for i in range(70):
		await step_frames(1)
		# Ascending through platform height (above platform bottom -44 with upward velocity)
		if player.velocity.y < 0.0 and player.position.y < -70.0:
			passed_through_upwards = true
		if i > 5 and player.is_on_floor():
			landed_on_platform = absf(player.position.y - (-64.0)) < 4.0 and absf(player.position.x - 200.0) < 10.0
			break

	check(passed_through_upwards, "Player jumps through LowPlatform from below without being blocked")
	check(landed_on_platform and player.is_on_floor(),
			"Player lands and stands firmly on top of LowPlatform from below")

	# Test jumping onto ReturnStep directly from below:
	# Floor is at y = 0, ReturnStep top is at y = -72 (landing y = -64).
	level.reset_room()
	player.position = Vector2(1216, 0)
	await step_frames(12)
	check(player.is_on_floor(), "Player is grounded beneath ReturnStep")
	player.sim_jump_just_pressed = true
	await step_frames(1)
	player.sim_jump_just_pressed = false

	passed_through_upwards = false
	landed_on_platform = false
	for i in range(70):
		await step_frames(1)
		if player.velocity.y < 0.0 and player.position.y < -70.0:
			passed_through_upwards = true
		if i > 5 and player.is_on_floor():
			landed_on_platform = absf(player.position.y - (-64.0)) < 4.0 and absf(player.position.x - 1216.0) < 10.0
			break

	check(passed_through_upwards, "Player jumps through ReturnStep from below without being blocked")
	check(landed_on_platform and player.is_on_floor(), "Player lands and stands firmly on top of ReturnStep from below")
