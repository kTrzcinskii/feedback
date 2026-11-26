## Ensure the ranged enemy lab loads with one example of every movement mode.
## Run: godot --headless --path . -s res://tests/ranged_enemy_level_test.gd
extends SceneTree

const LEVEL := preload("res://scenes/levels/ranged_enemy_test.tscn")

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := LEVEL.instantiate() as TestLevel
	root.add_child(level)
	await process_frame

	var modes: Dictionary = {}
	var enemy_count := 0
	for node in get_nodes_in_group("enemies"):
		if node is RangedEnemy:
			enemy_count += 1
			modes[(node as RangedEnemy).movement_type] = true
	_check(enemy_count == 3, "level: loads three Sentinel examples")
	_check(modes.has(RangedEnemy.MovementType.PATROL), "level: includes a patrol")
	_check(modes.has(RangedEnemy.MovementType.CHASE), "level: includes a chaser")
	_check(modes.has(RangedEnemy.MovementType.STATIONARY), "level: includes a stationary turret")
	_check(level.get_node_or_null("CharacterBody2D") is PlayerCharacter, "level: includes the player")
	var sentinel_sprite := level.get_node_or_null("Enemies/PatrolSentinel/AnimatedSprite2D") as AnimatedSprite2D
	_check(sentinel_sprite != null and sentinel_sprite.sprite_frames != null
			and sentinel_sprite.sprite_frames.has_animation(&"idle")
			and sentinel_sprite.sprite_frames.has_animation(&"move")
			and sentinel_sprite.sprite_frames.has_animation(&"shoot")
			and sentinel_sprite.sprite_frames.has_animation(&"hurt"),
			"animations: scene assigns all Sentinel SpriteFrames")

	var patrol := level.get_node_or_null("Enemies/PatrolSentinel") as RangedEnemy
	_check(patrol != null, "reset: finds the patrol to defeat")
	if patrol != null:
		var patrol_spawn := Vector2(520.0, -80.0)
		patrol.take_damage(patrol.hp)
		_check(patrol.is_defeated() and not patrol.visible, "reset: defeated enemy is hidden")
		level.reset_room()
		var is_restored: bool = (
				not patrol.is_defeated()
				and patrol.visible
				and patrol.hp == patrol.max_hp
				and patrol.global_position.distance_to(patrol_spawn) < 0.001
		)
		var state := "defeated=%s visible=%s HP=%d/%d position=%s spawn=%s resettable=%s" % [
			str(patrol.is_defeated()), str(patrol.visible), patrol.hp, patrol.max_hp,
			str(patrol.global_position), str(patrol_spawn), str(get_nodes_in_group("resettable").has(patrol)),
		]
		_check(is_restored, "reset: room reset restores defeated enemies to spawn (%s)" % state)

	level.queue_free()
	await process_frame
	print("ranged_enemy_level_test: %s (%d failure(s))" % ["FAIL" if failures else "OK", failures])
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
	print(("  ok    " if ok else "  FAIL  ") + what)
