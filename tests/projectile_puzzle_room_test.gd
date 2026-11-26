extends SceneTree

const ROOM := preload("res://scenes/levels/projectile_puzzle_room.tscn")

var failures := 0


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
	var completion_label: Label = room.get_node("Exit/CompletionLabel")
	player.use_simulated_input = true
	emitter.stop_firing()

	await _wait_physics_frames(5)
	emitter.fire_once()
	await _wait_physics_frames(95)
	_check(player.hp < player.max_hp, "Incoming shot passes the switch and hits the player")
	_check(not puzzle_switch.is_activated and not door.is_open, "Incoming shot leaves the door closed")
	_check(not completion_label.visible, "Room starts incomplete")

	player.sim_move_dir = Vector2.RIGHT
	await _wait_physics_frames(90)
	player.sim_jump_just_pressed = true
	await _wait_physics_frames(1)
	player.sim_jump_just_pressed = false
	await _wait_physics_frames(50)
	_check(player.global_position.x < door.global_position.x, "Walking and jumping cannot bypass the closed door")

	room.reset_room()
	await _wait_physics_frames(5)
	for frame in range(150):
		var projectiles := get_nodes_in_group("projectiles")
		if not projectiles.is_empty():
			var shot := projectiles[0] as ParryableProjectile
			if shot.global_position.x - player.global_position.x <= 65.0:
				break
		await physics_frame
	player.sim_parry_dir = Vector2.RIGHT
	player.sim_parry_pressed = true
	await _wait_physics_frames(1)
	player.sim_parry_pressed = false
	await _wait_physics_frames(75)
	_check(player.hp == player.max_hp, "Parry protects the player from the reflected shot")
	_check(puzzle_switch.is_activated and door.is_open, "Reflected shot opens the door")

	player.sim_move_dir = Vector2.RIGHT
	await _wait_physics_frames(150)
	_check(completion_label.visible, "Walking to the exit shows completion")

	Input.action_press("Restart")
	await _wait_physics_frames(2)
	Input.action_release("Restart")
	_check(not completion_label.visible, "Restart clears completion")
	_check(not puzzle_switch.is_activated and not door.is_open, "Restart closes the door and resets the switch")
	_check(is_equal_approx(player.global_position.x, room.spawn_point.global_position.x),
			"Restart returns the player to spawn")
	_check(emitter.is_firing() and get_nodes_in_group("projectiles").is_empty(),
			"Restart clears projectiles and starts the emission cycle again")

	room.queue_free()
	await process_frame
	print("projectile_puzzle_room_test: %s (%d failure(s))" % ["FAIL" if failures else "OK", failures])
	quit(1 if failures else 0)


func _wait_physics_frames(count: int) -> void:
	for frame in range(count):
		await physics_frame


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
	print(("  ok    " if condition else "  FAIL  ") + description)
