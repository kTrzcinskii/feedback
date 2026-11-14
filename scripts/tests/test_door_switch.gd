extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/levels/the_proving_hall.tscn") as PackedScene
	var level := packed.instantiate() as TestLevel
	root.add_child(level)
	await process_frame
	await physics_frame
	var sw := level.get_node("PuzzleSwitch") as EnvSwitch
	var door := level.get_node("PuzzleDoor") as EnvDoor
	var projectile := ParryableProjectile.new()
	level.add_child(projectile)
	assert(not sw.is_activated and not door.is_open)
	sw.on_hit_by_projectile(projectile)
	assert(not sw.is_activated and not door.is_open)
	projectile.is_reflected = true
	sw.on_hit_by_projectile(projectile)
	assert(sw.is_activated and door.is_open)
	await process_frame
	assert(door.get_node("CollisionShape2D").disabled)
	sw.reset_state()
	assert(not sw.is_activated and not door.is_open)
	assert(not door.get_node("CollisionShape2D").disabled)
	print("Feature checks passed: door-switch")
	quit()
