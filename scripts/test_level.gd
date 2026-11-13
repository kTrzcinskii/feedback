class_name TestLevel
extends Node2D

const PLATFORM_GROUND: SpriteFrames = preload("res://assets/godot/platform-ground.tres")

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

	_setup_level_fixtures()
	_setup_hud()

	if player != null:
		player.player_died.connect(_on_player_died)


func _setup_level_fixtures() -> void:
	var decor := Node2D.new()
	decor.name = "TileDecor"
	decor.z_index = -2
	add_child(decor)

	for i in range(-9, 14):
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = PLATFORM_GROUND
		spr.centered = false
		spr.offset = Vector2(-48, -48)
		spr.position = Vector2(i * 96, 48)
		spr.stop()
		spr.frame = posmod(i, 4)
		decor.add_child(spr)

	if get_node_or_null("BounceWallLeft") == null:
		_create_box_surface("BounceWallLeft", Vector2(-420, -140), Vector2(40, 280), 0.0, 0.55, 1.1, Color(0.24, 0.32, 0.42))

	if get_node_or_null("AngledSurface") == null:
		_create_box_surface("AngledSurface", Vector2(-220, -110), Vector2(120, 28), deg_to_rad(-35.0), 0.65, 1.15, Color(0.38, 0.48, 0.35))

	if get_node_or_null("LowPlatform") == null:
		_create_box_surface("LowPlatform", Vector2(180, -110), Vector2(192, 28), 0.0, 0.45, 1.0, Color(0.28, 0.36, 0.44))

	if get_node_or_null("HighPlatform") == null:
		_create_box_surface("HighPlatform", Vector2(180, -270), Vector2(192, 28), 0.0, 0.50, 1.05, Color(0.40, 0.34, 0.55))

	if get_node_or_null("CeilingPlatform") == null:
		_create_box_surface("CeilingPlatform", Vector2(-40, -340), Vector2(220, 28), 0.0, 0.50, 1.0, Color(0.24, 0.30, 0.38))

	if get_node_or_null("PhysicalFixture") == null:
		var phys := PhysicalAttackFixture.new()
		phys.name = "PhysicalFixture"
		phys.position = Vector2(-60, -44)
		phys.impulse_direction = Vector2(0.65, -0.76)
		add_child(phys)

	var door_node: EnvDoor = get_node_or_null("PuzzleDoor") as EnvDoor
	if door_node == null:
		door_node = EnvDoor.new()
		door_node.name = "PuzzleDoor"
		door_node.position = Vector2(640, -48)
		add_child(door_node)

	var switch_node: EnvSwitch = get_node_or_null("PuzzleSwitch") as EnvSwitch
	if switch_node == null:
		switch_node = EnvSwitch.new()
		switch_node.name = "PuzzleSwitch"
		switch_node.position = Vector2(560, -48)
		add_child(switch_node)
		switch_node.linked_door = switch_node.get_path_to(door_node)

	if get_node_or_null("SentinelEmitter") == null:
		var emitter := ProjectileEmitter.new()
		emitter.name = "SentinelEmitter"
		emitter.position = Vector2(460, 0)
		emitter.fire_direction = Vector2.LEFT
		emitter.projectile_speed = 320.0
		emitter.fire_interval = 2.0
		emitter.respawn_after_defeat_delay = 3.0
		add_child(emitter)

	if get_node_or_null("SpikesHazard") == null:
		var spikes := LethalHazard.new()
		spikes.name = "SpikesHazard"
		spikes.position = Vector2(-560, -48)
		add_child(spikes)


func _create_box_surface(
	p_name: String,
	p_pos: Vector2,
	p_size: Vector2,
	p_rot: float,
	p_restitution: float,
	p_impulse_mult: float,
	p_color: Color
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

	var poly := Polygon2D.new()
	var hw: float = p_size.x * 0.5
	var hh: float = p_size.y * 0.5
	poly.polygon = PackedVector2Array([
		Vector2(-hw, -hh),
		Vector2(hw, -hh),
		Vector2(hw, hh),
		Vector2(-hw, hh),
	])
	poly.color = p_color
	body.add_child(poly)

	add_child(body)
	return body


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	canvas.add_child(panel)

	_hud_label = Label.new()
	_hud_label.name = "TelemetryLabel"
	_hud_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(_hud_label)


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
	var invuln_str: String = "INVULN (%.2fs)" % player.invulnerability_timer if player.is_invulnerable() else "NO"
	var lines: PackedStringArray = [
		"FEEDBACK — Test Room",
		"Controls: Move [A/D or Left/Right] | Jump [Space] | Reset [R]",
		"HP: %d/%d | Invulnerable: %s | Velocity: (%.0f, %.0f) px/s [(%.1f, %.1f) CH/s] | Grounded: %s" % [
			player.hp,
			player.max_hp,
			invuln_str,
			player.velocity.x,
			player.velocity.y,
			vel_ch.x,
			vel_ch.y,
			str(player.is_on_floor())
		],
	]
	_hud_label.text = "\n".join(lines)
