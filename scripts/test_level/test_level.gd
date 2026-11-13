class_name TestLevel
extends Node2D


@export var fall_limit_y: float = 360.0
@export var death_reset_delay: float = 0.35

@onready var player: PlayerCharacter = $CharacterBody2D as PlayerCharacter
@onready var spawn_point: Marker2D = get_node_or_null("SpawnPoint") as Marker2D

var _initial_spawn_pos: Vector2 = Vector2.ZERO
var _reset_pending: bool = false
var _reset_timer: float = 0.0
var _hud_label: Label = null


func _ready() -> void:
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
	subtitle.text = "01  /  THE PROVING HALL"
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color("9da4b7"))
	layout.add_child(subtitle)

	_hud_label = Label.new()
	_hud_label.name = "TelemetryLabel"
	layout.add_child(_hud_label)
	_hud_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hud_label.position += Vector2(-350, 24)
	_hud_label.size = Vector2(322, 60)
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_label.add_theme_font_size_override("font_size", 13)
	_hud_label.add_theme_color_override("font_color", Color("b5c2ce"))

	var controls := Label.new()
	layout.add_child(controls)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.position += Vector2(28, -40)
	controls.text = "A / D  or  ← / →   MOVE       SPACE   JUMP       R   RESET"
	controls.add_theme_font_size_override("font_size", 12)
	controls.add_theme_color_override("font_color", Color("a0afbc"))


func _physics_process(delta: float) -> void:
	if InputMap.has_action("Restart") and Input.is_action_just_pressed("Restart"):
		reset_room()
		return

	# Section 3.6: Bottomless pits are instant-death hazards that kill the player immediately
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
	_hud_label.text = "HP  %d / %d     •     %s\nVELOCITY   %.0f, %.0f px/s  /  %.1f, %.1f CH/s" % [
		player.hp, player.max_hp, state,
		player.velocity.x, player.velocity.y, vel_ch.x, vel_ch.y,
	]
