## Verify room exits load the configured scene, spawn, and carry only player HP.
## Run: godot --headless --path . -s res://tests/level_transition_test.gd
extends SceneTree

const FIRST_ROOM := preload("res://scenes/levels/progression_room_01.tscn")
const SECOND_ROOM_NAME := "ProgressionRoom02"
const SECOND_SPAWN := Vector2(96, 8)

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var transition_service := LevelTransitionService.new()
	transition_service.name = "LevelTransition"
	root.add_child(transition_service)

	var result: Error = change_scene_to_packed(FIRST_ROOM)
	_check(result == OK, "loads first progression room")
	await process_frame
	await process_frame

	var first_room := current_scene as TestLevel
	_check(first_room != null, "first room uses the shared level controller")
	if first_room == null:
		_finish()
		return

	var player := first_room.player
	var exit := first_room.get_node("ExitToRoom02") as LevelExit
	_check(player != null and exit != null, "first room has player and configured exit")
	if player == null or exit == null:
		_finish()
		return

	player.hp = 2
	player.velocity = Vector2(120, -80)
	player.parry_state = PlayerCharacter.ParryState.COOLDOWN
	player.parry_timer = 0.12
	player.invulnerability_timer = 0.3
	player.global_position = exit.global_position
	var physics_frames := 0
	while current_scene == first_room and physics_frames < 60:
		await physics_frame
		physics_frames += 1
	await process_frame
	await process_frame

	var second_room := current_scene as TestLevel
	_check(second_room != null and second_room.name == SECOND_ROOM_NAME,
			"exit loads its configured destination room")
	if second_room != null:
		var destination_player := second_room.player
		_check(destination_player != null, "destination room loads its player")
		if destination_player != null:
			_check(destination_player.global_position.distance_to(SECOND_SPAWN) < 0.01,
					"destination player starts at the configured marker (%s)" % destination_player.global_position)
			_check(destination_player.hp == 2, "player HP carries into the destination")
			_check(destination_player.velocity == Vector2.ZERO
					and destination_player.parry_state == PlayerCharacter.ParryState.IDLE
					and is_zero_approx(destination_player.parry_timer)
					and is_zero_approx(destination_player.invulnerability_timer),
					"movement, parry, and temporary effects reset at the destination")

	_finish()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
	print(("  ok    " if ok else "  FAIL  ") + what)


func _finish() -> void:
	print("level_transition_test: %s (%d failure(s))" % ["FAIL" if failures else "OK", failures])
	quit(1 if failures else 0)
