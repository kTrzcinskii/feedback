extends SceneTree

const DOOR := preload("res://scenes/fixtures/door.tscn")
const SWITCH := preload("res://scenes/fixtures/switch.tscn")
const PLAYER := preload("res://scenes/character.tscn")
const PROJECTILE := preload("res://scenes/hazards/parryable_projectile.tscn")

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := TestLevel.new()
	level.projectile_bounds_margin = 1000.0
	var player := PLAYER.instantiate() as PlayerCharacter
	player.name = "CharacterBody2D"
	player.position = Vector2(0, -800)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	level.add_child(player)

	var door := DOOR.instantiate() as EnvDoor
	door.position = Vector2(0, 150)
	level.add_child(door)
	var puzzle_switch := SWITCH.instantiate() as EnvSwitch
	puzzle_switch.position = Vector2(0, 32)
	puzzle_switch.linked_door = NodePath("../Door")
	level.add_child(puzzle_switch)
	root.add_child(level)

	var door_collision: CollisionShape2D = door.get_node("CollisionShape2D")
	var slab := door_collision.shape as RectangleShape2D
	var gate_sprite: AnimatedSprite2D = door.get_node("AnimatedSprite2D")
	_check(not door_collision.disabled and slab.size == Vector2(32, 96)
			and door_collision.position == Vector2(0, -48), "closed collider fits a floor-aligned slab")

	var ordinary_shot := _fire_through_switch(level, false)
	await physics_frame
	await physics_frame
	_check(is_instance_valid(ordinary_shot) and ordinary_shot.position.x < 0.0,
			"ordinary shot passes through the switch")
	_check(not puzzle_switch.is_activated and not door.is_open, "ordinary shot leaves door closed")

	var reflected_shot := _fire_through_switch(level, true)
	await physics_frame
	await physics_frame
	_check(not is_instance_valid(reflected_shot), "first reflected shot is consumed")
	_check(puzzle_switch.is_activated and gate_sprite.is_playing() and not door_collision.disabled,
			"reflected shot starts the slide with collision still enabled")

	var next_shot := _fire_through_switch(level, true)
	await physics_frame
	await physics_frame
	_check(is_instance_valid(next_shot) and next_shot.position.x < 0.0,
			"used switch lets later shots through")

	for frame in range(12):
		await physics_frame
		if slab.size.x < 32.0:
			break
	_check(not door_collision.disabled and slab.size.x < 32.0
			and is_equal_approx(door_collision.position.x + slab.size.x * 0.5, 16.0),
			"collider retracts with the slab while its right edge stays fixed")

	level.reset_room()
	await process_frame
	_check(not puzzle_switch.is_activated and not door.is_open and not door_collision.disabled,
			"room restart resets switch and restores door collision")
	_check(not gate_sprite.is_playing() and gate_sprite.frame == 0
			and slab.size == Vector2(32, 96) and door_collision.position == Vector2(0, -48),
			"restart restores the gate's closed pose and full collider")

	_fire_through_switch(level, true)
	await physics_frame
	await physics_frame
	_check(puzzle_switch.is_activated and gate_sprite.is_playing(), "switch can activate again after restart")
	for frame in range(35):
		await physics_frame
		if door_collision.disabled:
			break
	_check(door.is_open and door_collision.disabled and gate_sprite.frame == 4,
			"collision clears once the slab is fully retracted")

	level.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _fire_through_switch(level: TestLevel, reflected: bool) -> ParryableProjectile:
	var shot := PROJECTILE.instantiate() as ParryableProjectile
	level.add_child(shot)
	shot.configure(Vector2(100, 0), Vector2.RIGHT if reflected else Vector2.LEFT, 12000.0)
	if reflected:
		shot.on_parried(null, Vector2.ZERO)
	return shot


func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + description)
