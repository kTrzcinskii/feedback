## Headless checks for projectile cleanup (FB020): projectiles are removed on
## static world contact and when leaving the level bounds, and a sustained
## firing sequence leaves no accumulating projectiles.
## Run: godot --headless --path . --import && godot --headless --path . -s res://tests/projectile_cleanup_test.gd
extends SceneTree

const TICKS_PER_SECOND: int = 60

var failures: int = 0
var _last_projectile: ParryableProjectile = null


class FakeLevel extends Node2D:
	var rect := Rect2(Vector2(-200, -200), Vector2(400, 400))

	func _ready() -> void:
		add_to_group("level")

	func get_projectile_bounds() -> Rect2:
		return rect


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_world_contact()
	await _test_character_body_ignored()
	await _test_out_of_bounds()
	await _test_sustained_sequence()
	await _test_reflected_cleanup()
	await _test_level_bounds_from_terrain()
	print("projectile_cleanup_test: %s (%d failure(s))" % ["FAIL" if failures else "OK", failures])
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
	print(("  ok    " if ok else "  FAIL  ") + what)


func _on_launch(projectile: ParryableProjectile) -> void:
	_last_projectile = projectile


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


func _cleanup(world: Node) -> void:
	world.queue_free()
	await process_frame
	await process_frame


func _make_world() -> Node2D:
	var world := Node2D.new()
	root.add_child(world)
	return world


func _make_wall(parent: Node2D, pos: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = pos
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	col.shape = rect
	body.add_child(col)
	parent.add_child(body)
	return body


func _make_character_block(parent: Node2D, pos: Vector2, radius: float) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.position = pos
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	col.shape = circle
	body.add_child(col)
	parent.add_child(body)
	return body


func _make_emitter(world: Node2D) -> ProjectileEmitter:
	var emitter := ProjectileEmitter.new()
	emitter.auto_start = false
	world.add_child(emitter)
	emitter.projectile_launched.connect(_on_launch)
	return emitter


## A projectile sweeping into a static wall is freed on that tick.
func _test_world_contact() -> void:
	var world := _make_world()
	_make_wall(world, Vector2(600, 0), Vector2(40, 400))
	var emitter := _make_emitter(world)
	emitter.launch_angle_deg = 0.0
	emitter.projectile_speed = 900.0
	emitter.fire_once()
	await _ticks(20)
	_check(is_instance_valid(_last_projectile), "contact: still flying before the wall")
	await _ticks(30)
	_check(not is_instance_valid(_last_projectile), "contact: freed on hitting a static wall")
	await _cleanup(world)


## Non-static bodies (e.g. characters) are not world contact: the existing
## player/enemy contact rules stay authoritative.
func _test_character_body_ignored() -> void:
	var world := _make_world()
	_make_character_block(world, Vector2(300, 0), 60.0)
	var emitter := _make_emitter(world)
	emitter.launch_angle_deg = 0.0
	emitter.projectile_speed = 900.0
	emitter.fire_once()
	await _ticks(40)
	_check(is_instance_valid(_last_projectile), "contact: flies through a non-static body")
	await _cleanup(world)


## Leaving the level-provided rect frees the projectile.
func _test_out_of_bounds() -> void:
	var world := _make_world()
	var level := FakeLevel.new()
	world.add_child(level)
	var emitter := _make_emitter(world)
	emitter.launch_angle_deg = 0.0
	emitter.projectile_speed = 900.0
	emitter.fire_once()
	await _ticks(5)
	_check(is_instance_valid(_last_projectile), "bounds: alive inside the level rect")
	await _ticks(40)
	_check(not is_instance_valid(_last_projectile), "bounds: freed once outside the level rect")
	await _cleanup(world)


## Rapid sustained firing against a wall never accumulates projectiles.
func _test_sustained_sequence() -> void:
	var world := _make_world()
	_make_wall(world, Vector2(300, 0), Vector2(40, 2000))
	var emitter := _make_emitter(world)
	emitter.launch_angle_deg = 0.0
	emitter.projectile_speed = 900.0
	emitter.initial_delay = 0.0
	emitter.attack_interval = 0.1
	emitter.start_firing()
	var max_live := 0
	for i in 220:
		await physics_frame
		max_live = maxi(max_live, get_nodes_in_group("projectiles").size())
	_check(max_live <= 6, "sustained: live projectiles stay bounded (max %d)" % max_live)
	emitter.stop_firing()
	for i in 120:
		if get_nodes_in_group("projectiles").is_empty():
			break
		await physics_frame
	_check(get_nodes_in_group("projectiles").is_empty(), "sustained: everything drains to zero after firing stops")
	await _cleanup(world)


## Reflected projectiles are cleaned up on world contact too.
func _test_reflected_cleanup() -> void:
	var world := _make_world()
	_make_wall(world, Vector2(300, 0), Vector2(40, 2000))
	_make_wall(world, Vector2(-400, 0), Vector2(40, 2000))
	var emitter := _make_emitter(world)
	emitter.launch_angle_deg = 0.0
	emitter.projectile_speed = 900.0
	emitter.fire_once()
	await _ticks(5)
	_last_projectile.on_parried(null, Vector2.ZERO)
	await _ticks(10)
	_check(is_instance_valid(_last_projectile), "reflected: still flying after the parry")
	await _ticks(45)
	_check(not is_instance_valid(_last_projectile), "reflected: freed on the wall behind the emitter")
	await _cleanup(world)


## The real level derives bounds from its terrain: contains the room and
## frees a contact-disabled projectile once it leaves the grown rect.
func _test_level_bounds_from_terrain() -> void:
	var level := (load("res://scenes/levels/emitter_test.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	var bounds: Rect2 = (level as TestLevel).get_projectile_bounds()
	_check(bounds.has_point(Vector2(960, -200)), "level bounds: terrain rect contains the room centre")
	_check(bounds.size.x > 2000.0, "level bounds: margin applied (width %.0f px)" % bounds.size.x)
	var proj := ParryableProjectile.new()
	proj.die_on_world_contact = false
	level.add_child(proj)
	proj.configure(Vector2(1000, -200), Vector2.RIGHT, 900.0, null)
	await _ticks(5)
	_check(is_instance_valid(proj), "level bounds: alive inside the terrain rect")
	for i in 200:
		await physics_frame
		if not is_instance_valid(proj):
			break
	_check(not is_instance_valid(proj), "level bounds: freed beyond the terrain rect")
	await _cleanup(level)
