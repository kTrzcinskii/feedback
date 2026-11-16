## Headless checks for the configurable projectile emitter: firing cadence,
## spline path following, homing tracking parameters and the parry fallback
## to straight flight. Mirrors the setups shown in emitter_test.tscn.
## Run: godot --headless --path . --import && godot --headless --path . -s res://tests/emitter_rules_test.gd
extends SceneTree

const TICKS_PER_SECOND: int = 60

var failures: int = 0
var _launched: int = 0
var _last_projectile: ParryableProjectile = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node2D.new()
	world.name = "EmitterTestWorld"
	root.add_child(world)

	await _test_firing_cadence(world)
	await _test_spline_flight(world)
	await _test_homing_flight(world)
	await _test_parry_converts_to_straight(world)

	print("emitter_rules_test: %s (%d failure(s))" % ["FAIL" if failures else "OK", failures])
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
	print(("  ok    " if ok else "  FAIL  ") + what)


func _on_launch(projectile: ParryableProjectile) -> void:
	_launched += 1
	_last_projectile = projectile


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


func _make_emitter(world: Node2D, pos: Vector2) -> ProjectileEmitter:
	var emitter := ProjectileEmitter.new()
	emitter.position = pos
	emitter.auto_start = false
	world.add_child(emitter)
	emitter.projectile_launched.connect(_on_launch)
	return emitter


## initial_delay 0.1s + attack_interval 0.5s => launches at t=0.1 and t=0.6.
func _test_firing_cadence(world: Node2D) -> void:
	_launched = 0
	var emitter := _make_emitter(world, Vector2(0, 0))
	emitter.initial_delay = 0.1
	emitter.attack_interval = 0.5
	emitter.projectile_speed = 100.0
	emitter.auto_start = true
	emitter.start_firing()
	await _ticks(45)  # 0.75 s
	_check(_launched == 2, "cadence: expected 2 launches in 0.75s, got %d" % _launched)
	emitter.stop_firing()
	await _ticks(30)
	_check(_launched == 2, "cadence: stop_firing halts launches")


## After 30 ticks the projectile has advanced speed*0.5 px along the curve.
func _test_spline_flight(world: Node2D) -> void:
	var curve := Curve2D.new()
	curve.add_point(Vector2.ZERO)
	curve.add_point(Vector2(-100, -100))
	curve.add_point(Vector2(-200, 0))
	var emitter := _make_emitter(world, Vector2(0, 2000))
	emitter.path_mode = ProjectileEmitter.PathMode.SPLINE
	(emitter.get_node("Path") as Path2D).curve = curve
	emitter.projectile_speed = 120.0
	emitter.fire_once()
	var proj := _last_projectile
	_check(proj != null and proj.is_inside_tree(), "spline: a projectile was launched")
	await _ticks(30)
	var expected := emitter.global_position + curve.sample_baked(120.0 * 30.0 / TICKS_PER_SECOND)
	var err := proj.global_position.distance_to(expected)
	_check(err < 3.0, "spline: follows the baked curve (off by %.2f px)" % err)
	# The full curve is ~283 px: past its end flight continues along the exit tangent.
	await _ticks(180)  # 210 ticks total = 3.5 s * 120 px/s = 420 px travelled
	var travel := 120.0 * 210.0 / TICKS_PER_SECOND
	var overshoot := travel - curve.get_baked_length()
	var exit_point := emitter.global_position + curve.sample_baked(curve.get_baked_length())
	var tangent := ParryableProjectile.curve_tangent(curve, curve.get_baked_length())
	var straight_expected := exit_point + tangent * overshoot
	err = proj.global_position.distance_to(straight_expected)
	_check(err < 3.0, "spline: continues straight along the exit tangent (off by %.2f px)" % err)


## Projectiles launch aimed at the target, steer after it moves mid-flight,
## then lock the heading once tracking_duration expires.
func _test_homing_flight(world: Node2D) -> void:
	var target := Node2D.new()
	target.position = Vector2(300, 3200)
	target.add_to_group("homing_test_target")
	world.add_child(target)
	var emitter := _make_emitter(world, Vector2(0, 3000))
	emitter.path_mode = ProjectileEmitter.PathMode.TRACK_TARGET
	emitter.target_group = &"homing_test_target"
	emitter.turn_rate_deg = 240.0
	emitter.tracking_duration = 0.2
	emitter.projectile_speed = 200.0
	emitter.fire_once()
	var proj := _last_projectile
	_check(proj != null, "homing: a projectile was launched")
	var aim := (target.position - emitter.global_position).normalized()
	_check(proj.direction.distance_to(aim) < 1e-3, "homing: launched aimed at the target")
	# Move the target mid-flight: the heading must steer toward the new spot.
	target.position = Vector2(0, 3500)
	var initial_angle := absf(proj.direction.angle_to(target.position - proj.global_position))
	await _ticks(12)  # 0.2 s at 240 deg/s allows up to 48 degrees of correction
	var steered_angle := absf(proj.direction.angle_to(target.position - proj.global_position))
	_check(steered_angle < initial_angle, "homing: heading steers toward a moved target (%.3f -> %.3f rad)" % [initial_angle, steered_angle])
	await _ticks(5)  # tracking expired at 0.2 s = tick 12
	var locked_dir := proj.direction
	await _ticks(10)
	_check(locked_dir.distance_to(proj.direction) < 1e-5, "homing: heading locks after tracking_duration")
	_check(is_equal_approx(proj.velocity.length(), 200.0), "homing: speed stays constant")


func _test_parry_converts_to_straight(world: Node2D) -> void:
	var curve := Curve2D.new()
	curve.add_point(Vector2.ZERO)
	curve.add_point(Vector2(0, -120))
	curve.add_point(Vector2(-160, -120))
	var emitter := _make_emitter(world, Vector2(0, 5000))
	emitter.path_mode = ProjectileEmitter.PathMode.SPLINE
	(emitter.get_node("Path") as Path2D).curve = curve
	emitter.projectile_speed = 160.0
	emitter.fire_once()
	var proj := _last_projectile
	await _ticks(1)
	var vel_before := proj.velocity
	proj.on_parried(null, Vector2.ZERO)
	_check(proj.velocity == -vel_before, "parry: velocity reversed")
	_check(proj.is_reflected, "parry: projectile marked reflected")
	var pos_after := proj.global_position
	await _ticks(1)
	var step := proj.global_position - pos_after
	_check(absf(step.length() - 160.0 / TICKS_PER_SECOND) < 1.0
			and step.normalized().distance_to(proj.direction) < 1e-3,
			"parry: flies straight after a parried spline shot")
