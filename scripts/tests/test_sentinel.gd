extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/levels/the_proving_hall.tscn") as PackedScene
	var level := packed.instantiate() as TestLevel
	root.add_child(level)
	await process_frame
	await physics_frame
	var emitter := level.get_node("SentinelEmitter") as ProjectileEmitter
	emitter.auto_fire = false
	var projectile := emitter.fire_projectile()
	assert(projectile != null and projectile.source_emitter == emitter)
	assert(projectile.velocity.length() > 0.0)
	emitter.on_hit_by_reflected_projectile(projectile)
	assert(emitter.is_defeated())
	emitter.reset_state()
	assert(not emitter.is_defeated())
	print("Feature checks passed: sentinel")
	quit()
