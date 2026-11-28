extends SceneTree

const ROOM := preload("res://scenes/levels/projectile_puzzle_room.tscn")
const EMITTER_LAB_PATH := "res://scenes/levels/emitter_test.tscn"

var failures := 0
var _departure_x := INF


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var room := ROOM.instantiate() as TestLevel
	root.add_child(room)
	current_scene = room

	var player := room.player
	var door: EnvDoor = room.get_node("Door")
	var puzzle_switch: EnvSwitch = room.get_node("Switch")
	var emitter: ProjectileEmitter = room.get_node("ProjectileEmitter")
	var gate_sprite: AnimatedSprite2D = door.get_node("AnimatedSprite2D")
	var portal: LevelExit = room.get_node("ExitToEmitterLab")
	var portal_sprite: AnimatedSprite2D = portal.get_node("PortalSprite")
	_check(gate_sprite.animation == &"sliding-gate"
			and gate_sprite.sprite_frames.get_frame_count(&"sliding-gate") > 1,
			"Gate uses the sideways-opening animation")
	_check(portal_sprite.animation == &"portal" and portal_sprite.is_playing()
			and not portal.get_node("Portal").visible,
			"Exit plays the ornate portal animation in place of the default graphic")
	player.use_simulated_input = true
	emitter.stop_firing()

	await _wait_physics_frames(5)
	emitter.fire_once()
	await _wait_physics_frames(95)
	_check(player.hp < player.max_hp, "Incoming shot passes the switch and hits the player")
	_check(not puzzle_switch.is_activated and not door.is_open, "Incoming shot leaves the door closed")

	player.sim_move_dir = Vector2.RIGHT
	await _wait_physics_frames(90)
	var player_collision: CollisionShape2D = player.get_node("CollisionShape2D")
	var player_radius := (player_collision.shape as CircleShape2D).radius
	var slab_front_x := door.global_position.x - 16.0
	_check(absf(player_collision.global_position.x + player_radius - slab_front_x) < 1.0,
			"Walking stops at the visible front of the closed slab")
	player.sim_jump_just_pressed = true
	await _wait_physics_frames(1)
	player.sim_jump_just_pressed = false
	await _wait_physics_frames(50)
	_check(player.global_position.x < door.global_position.x, "Walking and jumping cannot bypass the closed door")

	room.reset_room()
	await _parry_next_shot(player, emitter)
	_check(player.hp == player.max_hp, "Parry protects the player from the reflected shot")
	_check(puzzle_switch.is_activated and door.is_open, "Reflected shot opens the door")

	Input.action_press("Restart")
	await _wait_physics_frames(2)
	Input.action_release("Restart")
	_check(not puzzle_switch.is_activated and not door.is_open, "Restart closes the door and resets the switch")
	_check(is_equal_approx(player.global_position.x, room.spawn_point.global_position.x),
			"Restart returns the player to spawn")
	_check(emitter.is_firing() and get_nodes_in_group("projectiles").is_empty(),
			"Restart clears projectiles and starts the emission cycle again")

	await _parry_next_shot(player, emitter)
	_check(puzzle_switch.is_activated and door.is_open, "The gate can be reopened after restart")
	player.hp = player.max_hp - 1
	var expected_hp := player.hp
	var portal_x := portal_sprite.global_position.x
	player.tree_exiting.connect(func() -> void: _departure_x = player.global_position.x)
	player.global_position.x = portal_x - 36.0
	await _wait_physics_frames(3)
	var stayed_at_jamb := is_instance_valid(room) and current_scene == room
	_check(stayed_at_jamb, "Standing against the stone jamb does not teleport the player")
	if stayed_at_jamb:
		player.sim_move_dir = Vector2.RIGHT

	for frame in range(150):
		await physics_frame
		if current_scene != null and current_scene.scene_file_path == EMITTER_LAB_PATH:
			break
	var destination := current_scene as TestLevel
	var reached_lab := destination != null and destination.scene_file_path == EMITTER_LAB_PATH
	_check(reached_lab, "Walking into the portal loads the emitter lab")
	if reached_lab:
		_check(absf(_departure_x - portal_x) <= 28.0, "Teleport starts when the player reaches the glowing opening")
		_check(destination.player.global_position.distance_to(destination.spawn_point.global_position) < 1.0,
				"Portal places the player at the lab entry")
		_check(destination.player.hp == expected_hp, "Portal carries HP into the lab (expected %d, got %d)"
				% [expected_hp, destination.player.hp])

	print("projectile_puzzle_room_test: %s (%d failure(s))" % ["FAIL" if failures else "OK", failures])
	quit(1 if failures else 0)


func _parry_next_shot(player: PlayerCharacter, emitter: ProjectileEmitter) -> void:
	for frame in range(150):
		var projectiles := get_nodes_in_group("projectiles")
		if not projectiles.is_empty():
			var shot := projectiles[0] as ParryableProjectile
			if shot.global_position.x - player.global_position.x <= 65.0:
				break
		await physics_frame
	emitter.stop_firing()
	player.sim_parry_dir = Vector2.RIGHT
	player.sim_parry_pressed = true
	await physics_frame
	player.sim_parry_pressed = false
	await _wait_physics_frames(65)


func _wait_physics_frames(count: int) -> void:
	for frame in range(count):
		await physics_frame


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
	print(("  ok    " if condition else "  FAIL  ") + description)
