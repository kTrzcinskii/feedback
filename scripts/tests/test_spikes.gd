extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/levels/the_proving_hall.tscn") as PackedScene
	var level := packed.instantiate() as TestLevel
	root.add_child(level)
	await process_frame
	await physics_frame
	var spikes := level.get_node("Hazards/SpikesHazard0") as LethalSpikesHazard
	level.player.invulnerability_timer = 0.75
	level.player.global_position = spikes.get_hazard_center_global() - level.player.parry_origin_offset
	level.player._physics_process(0.016)
	assert(level.player.is_dead and level.player.hp == 0)
	print("Feature checks passed: spikes")
	quit()
