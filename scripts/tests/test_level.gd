class_name TestLevel
extends Node2D

const PLATFORM_GROUND: SpriteFrames = preload("res://assets/godot/platform-ground.tres")
const FOUNDATION_TEXTURE: Texture2D = preload("res://assets/environment/foundation.svg")
const LEDGE_TEXTURE: Texture2D = preload("res://assets/environment/training-ledge.svg")
const HALL_TEXTURE: Texture2D = preload("res://assets/environment/training-hall.svg")
const WALL_TEXTURE: Texture2D = preload("res://assets/environment/training-wall.svg")

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

	_setup_backdrop()
	_setup_geometry()
	_setup_level_fixtures()
	_setup_hud()
	_update_hud()

	if player != null:
		player.player_died.connect(_on_player_died)


func _setup_backdrop() -> void:
	var hall := Sprite2D.new()
	hall.name = "TrainingHall"
	hall.texture = HALL_TEXTURE
	hall.centered = false
	hall.position = Vector2(-768, -768)
	hall.region_enabled = true
	hall.region_rect = Rect2(0, 0, 3072, 768)
	hall.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	hall.z_index = -10
	hall.modulate = Color(0.76, 0.80, 0.85)
	add_child(hall)


func _setup_geometry() -> void:
	_create_floor("Ground", Rect2(-576, 0, 1344, 384))
	_create_floor("LandingGround", Rect2(960, 0, 864, 384))
	_create_floor("TrenchFloor", Rect2(768, 160, 192, 224))
	_create_surface("BounceWallLeft", Vector2(-596, -96), Vector2(40, 960), 0.0, 0.55, 1.1)
	_create_surface("EndWall", Vector2(1844, -96), Vector2(40, 960), 0.0, 0.55, 1.1)

	# 72px rises stay comfortably inside the current controller's 105px jump arc.
	_create_surface("LowPlatform", Vector2(200, -58), Vector2(160, 28), 0.0, 0.45, 1.0)
	_create_surface("MiddlePlatform", Vector2(360, -130), Vector2(160, 28), 0.0, 0.50, 1.05)
	_create_surface("HighPlatform", Vector2(520, -202), Vector2(160, 28), 0.0, 0.50, 1.05)
	_create_surface("SummitPlatform", Vector2(680, -274), Vector2(160, 28), 0.0, 0.50, 1.05)
	_create_surface("TrenchBridge", Vector2(864, -202), Vector2(128, 28), 0.0, 0.50, 1.0)
	_create_surface("LandingPlatform", Vector2(1056, -130), Vector2(192, 28), 0.0, 0.50, 1.0)
	_create_surface("ReturnStep", Vector2(1216, -58), Vector2(128, 28), 0.0, 0.45, 1.0)
	_create_surface("AngledSurface", Vector2(-432, -100), Vector2(144, 28), deg_to_rad(-25.0), 0.65, 1.15)
	_create_surface("CeilingPlatform", Vector2(-384, -290), Vector2(240, 28), 0.0, 0.50, 1.0)

	_add_room_label(Vector2(-512, -400), "01 / IMPACT ALCOVE")
	_add_room_label(Vector2(128, -400), "02 / ASCENT")
	_add_room_label(Vector2(792, 208), "SPIKE TRENCH")
	_add_room_label(Vector2(1320, -240), "03 / PROJECTILE RANGE")


func _create_floor(p_name: String, bounds: Rect2) -> void:
	var floor_body := ParrySurface.new()
	floor_body.name = p_name
	floor_body.position = bounds.position
	floor_body.restitution = 0.45
	add_child(floor_body)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = bounds.size
	collision.shape = shape
	collision.position = bounds.size * 0.5
	floor_body.add_child(collision)

	var foundation := TextureRect.new()
	foundation.texture = FOUNDATION_TEXTURE
	foundation.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	foundation.stretch_mode = TextureRect.STRETCH_TILE
	foundation.position.y = 20
	foundation.size = bounds.size - Vector2(0, 20)
	foundation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_body.add_child(foundation)

	for i in range(int(bounds.size.x / 96)):
		var tile := Sprite2D.new()
		tile.texture = PLATFORM_GROUND.get_frame_texture(&"ground", i % 4)
		tile.centered = false
		tile.position.x = i * 96
		floor_body.add_child(tile)


func _add_room_label(at: Vector2, text: String) -> void:
	var label := Label.new()
	label.position = at
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("7e8e9e"))
	add_child(label)


func _setup_level_fixtures() -> void:
	if get_node_or_null("PhysicalFixture") == null:
		var phys := PhysicalAttackFixture.new()
		phys.name = "PhysicalFixture"
		phys.position = Vector2(-300, -44)
		phys.impulse_direction = Vector2(0.65, -0.76)
		add_child(phys)

	var door_node: EnvDoor = get_node_or_null("PuzzleDoor") as EnvDoor
	if door_node == null:
		door_node = EnvDoor.new()
		door_node.name = "PuzzleDoor"
		door_node.position = Vector2(1760, -48)
		add_child(door_node)

	var switch_node: EnvSwitch = get_node_or_null("PuzzleSwitch") as EnvSwitch
	if switch_node == null:
		switch_node = EnvSwitch.new()
		switch_node.name = "PuzzleSwitch"
		switch_node.position = Vector2(1680, -48)
		add_child(switch_node)
		switch_node.linked_door = switch_node.get_path_to(door_node)

	if get_node_or_null("SentinelEmitter") == null:
		var emitter := ProjectileEmitter.new()
		emitter.name = "SentinelEmitter"
		emitter.position = Vector2(1344, 0)
		emitter.fire_direction = Vector2.RIGHT
		emitter.projectile_speed = 320.0
		emitter.fire_interval = 2.0
		emitter.respawn_after_defeat_delay = 3.0
		add_child(emitter)

	for i in range(2):
		var spikes := LethalHazard.new()
		spikes.name = "SpikesHazard%d" % i
		spikes.position = Vector2(816 + i * 96, 112)
		spikes.hit_radius = 32.0
		add_child(spikes)


func _create_surface(
	p_name: String,
	p_pos: Vector2,
	p_size: Vector2,
	p_rot: float,
	p_restitution: float,
	p_impulse_mult: float
) -> ParrySurface:
	var body := ParrySurface.new()
	body.name = p_name
	body.position = p_pos
	body.rotation = p_rot
	body.restitution = p_restitution
	body.impulse_multiplier = p_impulse_mult

	var col := CollisionShape2D.new()
	col.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = p_size
	col.shape = rect
	body.add_child(col)

	var visual := NinePatchRect.new()
	visual.name = "SurfaceVisual"
	visual.position = -p_size * 0.5
	visual.size = p_size
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if p_size.y > p_size.x:
		visual.texture = WALL_TEXTURE
		visual.patch_margin_top = 12
		visual.patch_margin_bottom = 12
		visual.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	else:
		visual.texture = LEDGE_TEXTURE
		visual.patch_margin_left = 18
		visual.patch_margin_right = 18
	body.add_child(visual)

	add_child(body)
	return body


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
