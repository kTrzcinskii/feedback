class_name TestLevel
extends Node2D


## World Y below which the player dies.
@export var fall_limit_y: float = 360.0
## Delay in seconds before the room resets after a death.
@export var death_reset_delay: float = 0.35
## Subtitle text shown on the room HUD.
@export var room_subtitle: String = "01  /  THE PROVING HALL"
## Extra room around the terrain before projectiles are out of bounds.
@export_range(0.0, 2000.0, 10.0, "suffix:px") var projectile_bounds_margin: float = 240.0

@onready var player: PlayerCharacter = $CharacterBody2D as PlayerCharacter
@onready var spawn_point: Marker2D = get_node_or_null("SpawnPoint") as Marker2D

var _initial_spawn_pos: Vector2 = Vector2.ZERO
var _reset_pending: bool = false
var _reset_timer: float = 0.0
var _hud_label: Label = null
var _projectile_bounds: Rect2 = Rect2()
var _bounds_ready: bool = false


func _ready() -> void:
	add_to_group("level")
	if spawn_point != null:
		_initial_spawn_pos = spawn_point.global_position
	elif player != null:
		_initial_spawn_pos = player.global_position

	_setup_hud()
	_update_hud()

	if player != null:
		player.player_died.connect(_on_player_died)


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	var layout := Control.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(layout)

	var title := Label.new()
	title.position = Vector2(28, 22)
	title.text = "F E E D B A C K"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("d1d9df"))
	layout.add_child(title)

	var subtitle := Label.new()
	subtitle.position = Vector2(29, 52)
	subtitle.text = room_subtitle
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color("9da4b7"))
	layout.add_child(subtitle)

	_hud_label = Label.new()
	_hud_label.name = "TelemetryLabel"
	layout.add_child(_hud_label)
	_hud_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hud_label.position += Vector2(-350, 24)
	_hud_label.size = Vector2(322, 80)
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_label.add_theme_font_size_override("font_size", 13)
	_hud_label.add_theme_color_override("font_color", Color("b5c2ce"))

	var controls := Label.new()
	layout.add_child(controls)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.position += Vector2(28, -40)
	controls.text = "A / D  or  ← / →   MOVE / AIM       SPACE   JUMP       E / J / SHIFT   PARRY       R   RESET       T   SURFACE CD"
	controls.add_theme_font_size_override("font_size", 12)
	controls.add_theme_color_override("font_color", Color("a0afbc"))


func _physics_process(delta: float) -> void:
	if InputMap.has_action("Restart") and Input.is_action_just_pressed("Restart"):
		reset_room()
		return

	if InputMap.has_action("ToggleCooldownReset") and Input.is_action_just_pressed("ToggleCooldownReset"):
		if player != null:
			player.reset_cooldown_on_surface_parry = not player.reset_cooldown_on_surface_parry

	# Bottomless pits, out of bounds etc. death (y grows down)
	if player != null and not _reset_pending and player.global_position.y > fall_limit_y:
		player.instant_kill(self)
		reset_room()
		return

	if _reset_pending:
		_reset_timer -= delta
		if _reset_timer <= 0.0:
			reset_room()

	_update_hud()


func reset_room() -> void:
	_reset_pending = false
	_reset_timer = 0.0

	for proj in get_tree().get_nodes_in_group("projectiles"):
		if is_instance_valid(proj):
			proj.queue_free()

	for node in get_tree().get_nodes_in_group("resettable"):
		if is_instance_valid(node) and node.has_method("reset_state"):
			node.call("reset_state")

	if player != null:
		player.reset_player_state(_initial_spawn_pos)


## Terrain union grown by the margin, computed once on first request.
func get_projectile_bounds() -> Rect2:
	if not _bounds_ready:
		_projectile_bounds = _compute_world_bounds().grow(projectile_bounds_margin)
		_bounds_ready = true
	return _projectile_bounds


func _compute_world_bounds() -> Rect2:
	var rect := Rect2()
	var found := false
	for body in find_children("*", "StaticBody2D", true, true):
		for child in (body as Node).find_children("*", "CollisionShape2D", false, false):
			var collision := child as CollisionShape2D
			if collision == null or collision.shape == null:
				continue
			var shape_rect := _shape_world_rect(collision)
			if shape_rect.size == Vector2.ZERO:
				continue
			rect = shape_rect if not found else rect.merge(shape_rect)
			found = true
	return rect if found else rect


## AABB for rect/circle/segment shapes, others fall back to their origin.
func _shape_world_rect(collision: CollisionShape2D) -> Rect2:
	var xform: Transform2D = collision.get_global_transform()
	var shape := collision.shape
	if shape is RectangleShape2D:
		var half: Vector2 = (shape as RectangleShape2D).size * 0.5
		return _rect_from_corners(
				xform * Vector2(-half.x, -half.y),
				xform * Vector2(half.x, half.y))
	if shape is CircleShape2D:
		var r: float = (shape as CircleShape2D).radius
		var c: Vector2 = xform.origin
		return Rect2(c - Vector2.ONE * r, Vector2.ONE * r * 2.0)
	if shape is SegmentShape2D:
		var seg := shape as SegmentShape2D
		return _rect_from_corners(xform * seg.a, xform * seg.b)
	return Rect2(xform.origin, Vector2.ZERO)


static func _rect_from_corners(a: Vector2, b: Vector2) -> Rect2:
	var pos := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	return Rect2(pos, (Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) - pos).abs())


func _on_player_died(_source: Object) -> void:
	if _reset_pending:
		return
	_reset_pending = true
	_reset_timer = death_reset_delay


func _update_hud() -> void:
	if _hud_label == null or player == null:
		return
	var ch: float = maxf(1.0, player.character_height)
	var vel_ch: Vector2 = player.velocity / ch
	var state: String = "GROUNDED" if player.is_on_floor() else "AIRBORNE"
	if player.is_invulnerable():
		state = "INVULNERABLE  %.2fs" % player.invulnerability_timer
	_hud_label.text = "\n".join([
		"HP  %d / %d     •     %s" % [player.hp, player.max_hp, state],
		"VELOCITY   %.0f, %.0f px/s  /  %.1f, %.1f CH/s" % [
			player.velocity.x, player.velocity.y, vel_ch.x, vel_ch.y,
		],
		"FPS  %d     •     PHYSICS  %d Hz" % [
			Engine.get_frames_per_second(), Engine.physics_ticks_per_second,
		],
		"PARRY %s  %.2fs" % [player.get_parry_state_name(), player.parry_timer],
		"AIM %s  LOCK %s" % [
			_format_dir(player.get_aim_direction_preview()), _format_dir(player.parry_direction),
		],
		"RANGE %.1f CH  ±%.1f°" % [player.parry_hitbox_range_ch, player.parry_angular_coverage_deg],
		"CD RESET: ATTACK %s / SURFACE %s" % [
			str(player.reset_cooldown_on_attack_parry), str(player.reset_cooldown_on_surface_parry),
		],
	])


static func _format_dir(d: Vector2) -> String:
	var n: Vector2 = d.normalized()
	return "(%.2f, %.2f)" % [n.x, n.y]
