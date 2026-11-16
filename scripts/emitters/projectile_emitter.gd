## Configurable hazard emitter

@tool
class_name ProjectileEmitter
extends Node2D

signal projectile_launched(projectile: ParryableProjectile)

enum PathMode {
	LINE,
	SPLINE,
	TRACK_TARGET,
}

const PREVIEW_COLOR := Color("8ea6c8")
const PREVIEW_COLOR_ACTIVE := Color("d3dfee")
const GLYPH_OUTLINE := Color("55617a")
const GLYPH_FILL := Color("39415a")
const ARROW_HEAD := 10.0
const CURVE_TICK_SPACING := 64.0

const DEFAULT_PROJECTILE: PackedScene = preload("res://scenes/hazards/parryable_projectile.tscn")

@export_group("Path")
## Flight path un-parried projectiles follow.
@export var path_mode: PathMode = PathMode.LINE:
	set(value):
		path_mode = value
		_sync_path_child(is_inside_tree())
		queue_redraw()
		update_configuration_warnings()
		notify_property_list_changed()

## LINE: initial flight direction. 0 = right, 90 = down.
@export_range(0.0, 360.0, 0.5, "degrees") var launch_angle_deg: float = 180.0:
	set(value):
		launch_angle_deg = value
		queue_redraw()

## SPLINE: external Path2D owning the flight curve; empty uses the auto-managed "Path" child.
@export var path_node: NodePath:
	set(value):
		path_node = value
		queue_redraw()
		update_configuration_warnings()

## TRACK_TARGET: node homing projectiles steer toward; takes precedence over target_group.
@export var target_node: NodePath:
	set(value):
		target_node = value
		queue_redraw()
		update_configuration_warnings()

## TRACK_TARGET: group scanned when target_node is empty (first valid member wins).
@export var target_group: StringName = &"player":
	set(value):
		target_group = value
		queue_redraw()
		update_configuration_warnings()

## TRACK_TARGET: how fast homing projectiles may turn, in degrees per second.
@export_range(0.0, 720.0, 1.0, "degrees") var turn_rate_deg: float = 110.0:
	set(value):
		turn_rate_deg = value
		queue_redraw()

## TRACK_TARGET: seconds after launch during which the projectile homes. 0 = track forever.
@export_range(0.0, 30.0, 0.1, "suffix:s") var tracking_duration: float = 2.5:
	set(value):
		tracking_duration = value
		queue_redraw()

@export_group("Firing")
## Begin firing as soon as the level starts.
@export var auto_start: bool = true

## Delay before the first launch once firing starts.
@export_range(0.0, 30.0, 0.05, "suffix:s") var initial_delay: float = 0.5

## Seconds between launches.
@export_range(0.05, 30.0, 0.05, "suffix:s") var attack_interval: float = 1.5

## Projectile flight speed along its path, in px/s.
@export_range(20.0, 2000.0, 1.0, "suffix:px/s") var projectile_speed: float = 340.0:
	set(value):
		projectile_speed = value
		queue_redraw()

## Random per-shot speed offset in ±px/s applied on top of projectile_speed.
@export_range(0.0, 500.0, 1.0, "suffix:px/s") var speed_jitter: float = 0.0

@export_group("Projectile")
## Scene spawned on each launch. Must extend ParryableProjectile.
@export var projectile_scene: PackedScene = DEFAULT_PROJECTILE

@export_group("Debug")
## Keep drawing the path preview while the game runs.
@export var runtime_debug_draw: bool = false:
	set(value):
		runtime_debug_draw = value
		queue_redraw()

## How far the LINE-mode launch-direction preview arrow extends.
@export_range(40.0, 600.0, 10.0, "suffix:px") var preview_length: float = 160.0:
	set(value):
		preview_length = value
		queue_redraw()

var _firing: bool = false
var _cooldown: float = 0.0
var _watched_curve: Curve2D = null
var _stashed_curve: Curve2D = null


func _ready() -> void:
	add_to_group("resettable")
	_sync_path_child(true)
	if Engine.is_editor_hint():
		queue_redraw()
		_watch_curve(_resolve_spline()[0])
		return
	if auto_start:
		start_firing()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_watch_curve(_resolve_spline()[0])
	if path_mode == PathMode.TRACK_TARGET:
		queue_redraw()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _firing:
		return
	_cooldown -= delta
	if _cooldown <= 0.0:
		fire_once()
		_cooldown = attack_interval


func start_firing() -> void:
	_firing = true
	_cooldown = initial_delay


func stop_firing() -> void:
	_firing = false


func is_firing() -> bool:
	return _firing


func fire_once() -> void:
	if Engine.is_editor_hint():
		return
	var projectile := _create_projectile()
	if projectile == null:
		return
	_projectile_host().add_child(projectile)
	var jitter := randf_range(-speed_jitter, speed_jitter) if speed_jitter > 0.0 else 0.0
	var actual_speed := maxf(20.0, projectile_speed + jitter)
	match path_mode:
		PathMode.SPLINE:
			var spline := _resolve_spline()
			var curve := spline[0] as Curve2D
			if curve != null and curve.point_count >= 2:
				projectile.configure_spline_flight(global_position, curve,
						spline[1] as Transform2D, actual_speed, self)
			else:
				projectile.configure(global_position, _launch_direction(), actual_speed, self)
		PathMode.TRACK_TARGET:
			var target := _resolve_target()
			var heading := _launch_direction()
			if target != null:
				var to_center := ParryableProjectile.target_center(target) - global_position
				if to_center.length_squared() > 1e-6:
					heading = to_center.normalized()
				projectile.configure_homing_flight(global_position, heading,
						actual_speed, target, deg_to_rad(turn_rate_deg), tracking_duration, self)
			else:
				projectile.configure(global_position, heading, actual_speed, self)
		_:
			projectile.configure(global_position, _launch_direction(), actual_speed, self)
	projectile_launched.emit(projectile)


func reset_state() -> void:
	_firing = false
	_cooldown = 0.0
	if not Engine.is_editor_hint() and auto_start:
		start_firing()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if path_mode == PathMode.SPLINE:
		var curve := _resolve_spline()[0] as Curve2D
		if curve == null:
			warnings.append("Spline mode needs a Path2D with a curve: re-select SPLINE to auto-create one, or assign path_node.")
		elif curve.point_count < 2:
			warnings.append("The spline curve needs at least 2 points to fly along.")
	if path_mode == PathMode.TRACK_TARGET and _resolve_target() == null:
		warnings.append("Tracking mode could not resolve a target (check target_node or group '%s')." % target_group)
	return warnings


func _create_projectile() -> ParryableProjectile:
	if projectile_scene == null:
		push_error("ProjectileEmitter: projectile_scene is not assigned.")
		return null
	var node := projectile_scene.instantiate()
	if node is ParryableProjectile:
		return node as ParryableProjectile
	push_error("ProjectileEmitter: projectile_scene root must extend ParryableProjectile (got %s)." % node.get_class())
	node.free()
	return null


## Parent projectiles to the scene so they outlive this emitter.
func _projectile_host() -> Node:
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	return get_parent()


func _launch_direction() -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(launch_angle_deg))


## Returns [Curve2D, Transform2D] mapping curve-local points to world space.
func _resolve_spline() -> Array:
	var path_owner := _resolve_path_owner()
	if path_owner != null and path_owner.curve != null:
		return [path_owner.curve, path_owner.global_transform]
	return [null, global_transform]


func _resolve_path_owner() -> Path2D:
	if not path_node.is_empty():
		var node := get_node_or_null(path_node)
		if node is Path2D:
			return node as Path2D
	return get_node_or_null(^"Path") as Path2D


## Auto-create/remove the "Path" child when SPLINE is (de)selected.
func _sync_path_child(p_live: bool) -> void:
	if not p_live or not path_node.is_empty():
		return
	var child := get_node_or_null(^"Path") as Path2D
	if path_mode == PathMode.SPLINE:
		if child == null:
			_create_path_child()
	elif child != null:
		if child.curve != null:
			_stashed_curve = child.curve
		child.owner = null
		remove_child(child)
		child.queue_free()
	queue_redraw()


func _create_path_child() -> void:
	var child := Path2D.new()
	child.name = "Path"
	child.curve = _stashed_curve if _stashed_curve != null else _starter_curve()
	add_child(child)
	if Engine.is_editor_hint():
		var root := get_tree().edited_scene_root if is_inside_tree() else null
		if root != null and (root == self or root.is_ancestor_of(self)):
			child.owner = root
	_watch_curve(child.curve)
	queue_redraw()


func _starter_curve() -> Curve2D:
	var curve := Curve2D.new()
	curve.add_point(Vector2.ZERO, Vector2.ZERO, Vector2(0, -120))
	curve.add_point(Vector2(-180, -150), Vector2(110, 30), Vector2(-110, -30))
	curve.add_point(Vector2(-360, -40), Vector2(80, 60), Vector2.ZERO)
	return curve


func _resolve_target() -> Node2D:
	if not target_node.is_empty():
		var node := get_node_or_null(target_node)
		if is_instance_valid(node) and node is Node2D:
			return node as Node2D
	if target_group != &"" and is_inside_tree():
		for node in get_tree().get_nodes_in_group(target_group):
			if is_instance_valid(node) and node is Node2D:
				return node as Node2D
	return null


func _watch_curve(curve: Curve2D) -> void:
	if curve == _watched_curve:
		return
	if _watched_curve != null and _watched_curve.changed.is_connected(queue_redraw):
		_watched_curve.changed.disconnect(queue_redraw)
	_watched_curve = curve
	if curve != null:
		curve.changed.connect(queue_redraw)


func _draw() -> void:
	_draw_glyph()
	if Engine.is_editor_hint() or runtime_debug_draw:
		_draw_path_preview()


func _glyph_heading() -> Vector2:
	match path_mode:
		PathMode.SPLINE:
			var spline := _resolve_spline()
			var curve := spline[0] as Curve2D
			if curve != null and curve.point_count >= 2:
				var curve_to_local := global_transform.affine_inverse() * (spline[1] as Transform2D)
				return ParryableProjectile.transformed_tangent(curve, 0.0, curve_to_local)
			return Vector2.LEFT
		PathMode.TRACK_TARGET:
			var target := _resolve_target()
			if target != null and is_inside_tree():
				var local := global_transform.affine_inverse() * target.global_position
				if local.length_squared() > 1e-6:
					return local.normalized()
			return _launch_direction()
	return _launch_direction()


func _draw_glyph() -> void:
	var angle := _glyph_heading().angle()
	var points := PackedVector2Array()
	for base in [Vector2(11, 0), Vector2(0, 7), Vector2(-11, 0), Vector2(0, -7)]:
		points.append((base as Vector2).rotated(angle))
	draw_colored_polygon(points, GLYPH_FILL)
	points.append(points[0])
	draw_polyline(points, GLYPH_OUTLINE, 1.5)
	draw_line(Vector2.ZERO, Vector2(14, 0).rotated(angle), PREVIEW_COLOR_ACTIVE, 2.0)


func _draw_path_preview() -> void:
	match path_mode:
		PathMode.SPLINE:
			_draw_spline_preview()
		PathMode.TRACK_TARGET:
			var target := _resolve_target()
			if target != null and is_inside_tree():
				var local := global_transform.affine_inverse() * target.global_position
				draw_dashed_line(Vector2.ZERO, local, PREVIEW_COLOR_ACTIVE, 1.5, 10.0)
				draw_arc(local, 7.0, 0.0, TAU, 20, PREVIEW_COLOR_ACTIVE, 1.5)
		_:
			_draw_arrow(Vector2.ZERO, _launch_direction() * preview_length, PREVIEW_COLOR)


func _draw_spline_preview() -> void:
	var spline := _resolve_spline()
	var curve := spline[0] as Curve2D
	if curve == null or curve.point_count < 2:
		return
	var curve_to_local := global_transform.affine_inverse() * (spline[1] as Transform2D)
	var baked := curve.get_baked_points()
	var points := PackedVector2Array()
	for p in baked:
		points.append(curve_to_local * (p as Vector2))
	if points.size() >= 2:
		draw_polyline(points, PREVIEW_COLOR, 2.0)
	var length := curve.get_baked_length()
	var distance := CURVE_TICK_SPACING
	while distance < length:
		var pos := curve_to_local * curve.sample_baked(distance)
		var tangent := ParryableProjectile.transformed_tangent(curve, distance, curve_to_local)
		_draw_arrow(pos - tangent * 6.0, pos + tangent * 6.0, PREVIEW_COLOR_ACTIVE)
		distance += CURVE_TICK_SPACING
	draw_circle(curve_to_local * curve.sample_baked(0.0), 4.0, PREVIEW_COLOR_ACTIVE)


func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	draw_line(from, to, color, 2.0)
	var dir := to - from
	if dir.length_squared() < 1e-6:
		return
	dir = dir.normalized()
	var side := dir.orthogonal()
	var head_base := to - dir * ARROW_HEAD * 0.5
	draw_colored_polygon(PackedVector2Array([
		to + dir * ARROW_HEAD * 0.5,
		head_base + side * ARROW_HEAD * 0.4,
		head_base - side * ARROW_HEAD * 0.4,
	]), color)
