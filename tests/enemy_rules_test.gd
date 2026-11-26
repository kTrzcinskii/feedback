## Headless checks for ranged enemy movement, range-gated firing, and reflected hits.
## Run: godot --headless --path . --import && godot --headless --path . -s res://tests/enemy_rules_test.gd
extends SceneTree

const ENEMY_SCENE := preload("res://scenes/enemies/ranged_enemy.tscn")

var failures: int = 0
var _launched: int = 0
var _last_projectile: ParryableProjectile = null
var _last_enemy_hp: int = -1
var _enemy_defeated: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_patrol()
	await _test_chase()
	await _test_stationary()
	await _test_range_gated_firing()
	await _test_reflected_projectile_damage()
	print("enemy_rules_test: %s (%d failure(s))" % ["FAIL" if failures else "OK", failures])
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
	print(("  ok    " if ok else "  FAIL  ") + what)


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


func _make_enemy(world: Node2D, movement: int) -> RangedEnemy:
	var enemy := ENEMY_SCENE.instantiate() as RangedEnemy
	enemy.movement_type = movement
	enemy.gravity = 0.0
	enemy.attack_range = 0.0
	world.add_child(enemy)
	return enemy


func _make_player(world: Node2D, pos: Vector2) -> Node2D:
	var player := Node2D.new()
	player.position = pos
	player.add_to_group("player")
	world.add_child(player)
	return player


func _make_world() -> Node2D:
	var world := Node2D.new()
	root.add_child(world)
	return world


func _cleanup(world: Node) -> void:
	world.queue_free()
	await process_frame
	await process_frame


func _test_patrol() -> void:
	var world := _make_world()
	var enemy := _make_enemy(world, RangedEnemy.MovementType.PATROL)
	enemy.patrol_left_offset = -40.0
	enemy.patrol_right_offset = 40.0
	await _ticks(60)
	_check(enemy.global_position.x >= -41.0 and enemy.global_position.x <= 41.0
			and not is_zero_approx(enemy.global_position.x),
			"patrol: walks back and forth within configured bounds")
	await _cleanup(world)


func _test_chase() -> void:
	var world := _make_world()
	_make_player(world, Vector2(300.0, 0.0))
	var enemy := _make_enemy(world, RangedEnemy.MovementType.CHASE)
	await _ticks(30)
	_check(enemy.global_position.x > 0.0, "chase: moves toward the player's horizontal position")
	await _cleanup(world)


func _test_stationary() -> void:
	var world := _make_world()
	_make_player(world, Vector2(300.0, 0.0))
	var enemy := _make_enemy(world, RangedEnemy.MovementType.STATIONARY)
	var start_x: float = enemy.global_position.x
	await _ticks(30)
	_check(is_equal_approx(enemy.global_position.x, start_x), "stationary: does not move toward the player")
	await _cleanup(world)


func _test_range_gated_firing() -> void:
	var world := _make_world()
	var player := _make_player(world, Vector2(900.0, 0.0))
	var enemy := ENEMY_SCENE.instantiate() as RangedEnemy
	enemy.movement_type = RangedEnemy.MovementType.STATIONARY
	enemy.gravity = 0.0
	enemy.attack_range = 200.0
	enemy.attack_interval = 0.2
	enemy.initial_shot_delay = 0.0
	enemy.projectile_speed = 300.0
	world.add_child(enemy)
	enemy.projectile_emitter.projectile_launched.connect(_on_projectile_launched)
	_launched = 0
	_last_projectile = null
	await _ticks(20)
	_check(_launched == 0, "firing: stays idle while the player is outside attack range")

	player.position = Vector2(100.0, -32.0)
	await _ticks(40)
	_check(_launched >= 3, "firing: launches repeatedly at the configured interval in range")
	var aim_direction: Vector2 = (ParryableProjectile.target_center(player)
			- enemy.projectile_emitter.global_position).normalized()
	_check(_last_projectile != null and _last_projectile.direction.distance_to(aim_direction) < 1e-3,
			"firing: aims each straight shot at the player's current position")
	player.position = Vector2(900.0, 0.0)
	var launches_at_exit: int = _launched
	await _ticks(30)
	_check(_launched == launches_at_exit, "firing: stops after the player leaves attack range")
	await _cleanup(world)


func _test_reflected_projectile_damage() -> void:
	var world := _make_world()
	var enemy := ENEMY_SCENE.instantiate() as RangedEnemy
	enemy.movement_type = RangedEnemy.MovementType.STATIONARY
	enemy.gravity = 0.0
	enemy.attack_range = 0.0
	enemy.max_hp = 3
	enemy.reflected_projectile_damage = 2
	enemy.enemy_damaged.connect(_on_enemy_damaged)
	enemy.enemy_defeated.connect(_on_enemy_defeated)
	world.add_child(enemy)
	_last_enemy_hp = -1
	_enemy_defeated = false
	_check(enemy.hp == 3, "damage: initializes from configurable maximum HP")
	var projectile := ParryableProjectile.new()
	world.add_child(projectile)
	projectile.configure(enemy.get_center_global(), Vector2.RIGHT, 100.0)
	await physics_frame
	_check(enemy.hp == 3, "damage: ignores an unreflected projectile")
	projectile.queue_free()

	projectile = ParryableProjectile.new()
	world.add_child(projectile)
	projectile.configure(enemy.get_center_global(), Vector2.RIGHT, 100.0)
	projectile.is_reflected = true
	await physics_frame
	_check(_last_enemy_hp == 1 and not _enemy_defeated,
			"damage: reflected hit subtracts configured damage")
	projectile = ParryableProjectile.new()
	world.add_child(projectile)
	projectile.configure(enemy.get_center_global(), Vector2.RIGHT, 100.0)
	projectile.is_reflected = true
	await physics_frame
	_check(_last_enemy_hp == 0 and _enemy_defeated, "damage: enemy is defeated when HP reaches zero")
	await _cleanup(world)


func _on_projectile_launched(_projectile: ParryableProjectile) -> void:
	_launched += 1
	_last_projectile = _projectile


func _on_enemy_damaged(_source: Object, remaining_hp: int) -> void:
	_last_enemy_hp = remaining_hp


func _on_enemy_defeated(_source: Object) -> void:
	_enemy_defeated = true
