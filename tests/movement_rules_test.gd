## Headless check of ruleset §3.1–3.3 and §3.5 (ordinary collision) in the collision test room.
## Run: godot --headless --path . --import && godot --headless --path . -s res://tests/movement_rules_test.gd
## Player origin is at the feet; its collision circle spans y in [-52, -8] relative to it.
extends SceneTree

const ROOM := preload("res://scenes/levels/collision_test_room.tscn")

var player: PlayerCharacter
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var room := ROOM.instantiate()
	root.add_child(room)
	player = room.get_node("CharacterBody2D") as PlayerCharacter
	player.use_simulated_input = true
	var ch := player.character_height
	var speed := player.ground_movement_speed_ch * ch

	# Horizontal: immediate start, stop and reversal (§3.1)
	await _settle(Vector2(120, 0))
	_check(player.is_on_floor(), "starts grounded")
	await _hold(Vector2.RIGHT, 1)
	_check(is_equal_approx(player.velocity.x, speed), "right press sets full speed in one tick")
	await _hold(Vector2.ZERO, 1)
	_check(player.velocity.x == 0.0, "release stops immediately")
	await _hold(Vector2.RIGHT, 3)
	await _hold(Vector2.LEFT, 1)
	_check(is_equal_approx(player.velocity.x, -speed), "reversal is immediate")

	# Side wall stops the player (§3.5)
	await _hold(Vector2.LEFT, 120)
	_check(player.global_position.x >= 20.0 and player.velocity.x <= 0.0, "left wall blocks, no bounce")

	# Jump: one impulse from the floor, midair jump rejected, landing restores (§3.2)
	await _settle(Vector2(120, 0))
	await _jump()
	_check(not player.is_on_floor() and player.velocity.y < 0.0, "grounded jump leaves floor")
	var vy_before := player.velocity.y
	await _jump()
	_check(player.velocity.y > vy_before, "midair jump rejected")
	await _until_grounded()
	_check(player.is_on_floor(), "lands")
	await _jump()
	_check(player.velocity.y < 0.0, "landing restores jump")

	# Running jump keeps full ground speed on the takeoff tick
	await _settle(Vector2(120, 0))
	player.sim_jump_just_pressed = true
	await _hold(Vector2.RIGHT, 1)
	player.sim_jump_just_pressed = false
	_check(is_equal_approx(player.velocity.x, speed), "running jump starts at full speed")

	# Air control accelerates instead of overwriting velocity (§3.3)
	await _settle(Vector2(120, 0))
	await _jump()
	await _hold(Vector2.RIGHT, 1)
	_check(player.velocity.x > 0.0 and player.velocity.x < speed, "air control is gradual")

	# Low ceiling stops upward motion (bottom edge at y = -130)
	await _settle(Vector2(360, 0))
	await _jump()
	var min_top := INF
	for i in 30:
		await _hold(Vector2.ZERO, 1)
		min_top = minf(min_top, player.global_position.y - 52.0)
	_check(min_top >= -132.0, "ceiling blocks the head (top reached %.1f)" % min_top)

	# High-speed impacts: floor and right wall hold at well above jump speeds
	await _settle(Vector2(960, -700))
	player.velocity = Vector2(0, 3000)
	await _until_grounded()
	_check(player.is_on_floor() and player.global_position.y <= 9.0, "fast fall lands on floor")
	await _settle(Vector2(1800, -400))
	player.velocity = Vector2(2500, 0)
	await _hold(Vector2.ZERO, 20)
	_check(player.global_position.x <= 1900.0, "fast horizontal hit stops at right wall")

	print("movement_rules_test: %s (%d failure(s))" % ["FAIL" if failures else "OK", failures])
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
	print(("  ok    " if ok else "  FAIL  ") + what)


func _hold(dir: Vector2, ticks: int) -> void:
	player.sim_move_dir = dir
	for i in ticks:
		await physics_frame


func _jump() -> void:
	player.sim_jump_just_pressed = true
	await _hold(Vector2.ZERO, 1)
	player.sim_jump_just_pressed = false


func _settle(pos: Vector2) -> void:
	player.reset_player_state(pos)
	await _hold(Vector2.ZERO, 30)


func _until_grounded() -> void:
	for i in 240:
		await _hold(Vector2.ZERO, 1)
		if player.is_on_floor():
			return
