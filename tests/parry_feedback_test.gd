extends SceneTree

const PLAYER := preload("res://scenes/character.tscn")

var _failures: int = 0
var _misses: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player := PLAYER.instantiate() as PlayerCharacter
	player.use_simulated_input = true
	player.gravity_ch = 0.0
	root.add_child(player)
	player.parry_failed.connect(_on_parry_failed)
	var feedback := player.get_node("ParryFeedback")
	var sector := feedback.get_node("ActiveSector") as Polygon2D
	var burst := feedback.get_node("SuccessBurst") as AnimatedSprite2D
	var failure_mark := feedback.get_node("FailureMark") as Line2D
	var success_sound := feedback.get_node("SuccessSound") as AudioStreamPlayer
	var failure_sound := feedback.get_node("FailureSound") as AudioStreamPlayer
	_check(success_sound.stream.resource_path == "res://assets/audio/parry-success.wav"
			and failure_sound.stream.resource_path == "res://assets/audio/parry-failure.wav",
			"tones are the default cues")

	_launch_at_player(player)
	await _tick()
	_check(_misses == 1 and failure_mark.visible and failure_sound.playing and not success_sound.playing,
			"early hit resolves a failure cue at contact")
	_check(player.hp == player.max_hp - 1 and not burst.visible, "early hit still deals normal damage")

	player.reset_player_state(Vector2.ZERO)
	_check(not sector.visible and not failure_mark.visible and not failure_sound.playing, "reset clears feedback")
	player.sim_parry_pressed = true
	await _tick()
	_check(sector.visible and is_zero_approx(sector.rotation), "active parry shows the locked sector")

	var projectile := _launch_at_player(player)
	await _tick()
	_check(projectile.is_reflected and projectile.velocity.x > 0.0 and player.hp == player.max_hp,
			"successful parry still reverses the shot and protects the player")
	_check(_misses == 1 and burst.visible and not failure_mark.visible
			and success_sound.playing and success_sound.stream != failure_sound.stream,
			"success shows its burst and plays a distinct sound immediately")
	projectile.queue_free()

	player.reset_player_state(Vector2.ZERO)
	player.sim_parry_pressed = true
	await _tick()
	player.sim_parry_pressed = false
	for tick in 20:
		await physics_frame
	_check(not sector.visible and _misses == 1, "empty parry expires without a contact failure")
	player.invulnerability_timer = 1.0
	_launch_at_player(player)
	await _tick()
	_check(_misses == 2 and failure_mark.visible and not burst.visible and failure_sound.playing,
			"late hit resolves failure even during damage immunity")
	_check(player.hp == player.max_hp, "failure feedback respects damage immunity")

	player.reset_player_state(Vector2.ZERO)
	player.sim_parry_pressed = true
	projectile = _launch_at_player(player)
	_launch_at_player(player, Vector2.LEFT)
	await _tick()
	_check(projectile.is_reflected and player.hp == player.max_hp - 1 and _misses == 3,
			"same tick: separate projectiles independently reflect and hit")
	_check(burst.visible and success_sound.playing and failure_mark.visible and failure_sound.playing,
			"same tick: success and failure cues play together")
	projectile.queue_free()
	await create_timer(0.45).timeout
	_check(not burst.visible and not success_sound.playing and not failure_mark.visible and not failure_sound.playing,
			"both cues clear when their animations and sounds finish")

	player.queue_free()
	await process_frame
	await _check_voice_cues()
	print("parry_feedback_test: %s (%d failure(s))" % ["FAIL" if _failures else "OK", _failures])
	quit(1 if _failures else 0)


func _check_voice_cues() -> void:
	var player := PLAYER.instantiate() as PlayerCharacter
	var feedback := player.get_node("ParryFeedback") as ParryFeedback
	feedback.use_voice_cues = true
	root.add_child(player)
	var success_sound := feedback.get_node("SuccessSound") as AudioStreamPlayer
	var failure_sound := feedback.get_node("FailureSound") as AudioStreamPlayer
	_check(success_sound.stream.resource_path == "res://assets/audio/parry-success-voice.wav"
			and failure_sound.stream.resource_path == "res://assets/audio/parry-failure-voice.wav",
			"opting in selects the two voice clips")

	player.parry_succeeded.emit(null, &"projectile", Vector2.RIGHT, Vector2.ZERO)
	player.parry_failed.emit(null)
	await _tick()
	_check(success_sound.playing and failure_sound.playing, "both voice cues can play together")
	player.reset_player_state(Vector2.ZERO)
	_check(not success_sound.playing and not failure_sound.playing, "reset stops both voice cues")

	player.queue_free()
	# Let the audio mixer release stopped streams before the headless process exits.
	await create_timer(0.15).timeout


func _launch_at_player(player: PlayerCharacter, side: Vector2 = Vector2.RIGHT) -> ParryableProjectile:
	var projectile := ParryableProjectile.new()
	projectile.position = player.get_parry_origin_global() + side * 30.0
	projectile.direction = -side
	projectile.die_on_world_contact = false
	root.add_child(projectile)
	return projectile


func _tick() -> void:
	await physics_frame
	await physics_frame


func _on_parry_failed(_projectile: ParryableProjectile) -> void:
	_misses += 1


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
	print(("  ok    " if ok else "  FAIL  ") + what)
