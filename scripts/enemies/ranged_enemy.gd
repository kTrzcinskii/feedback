class_name RangedEnemy
extends CharacterBody2D

signal enemy_damaged(source: Object, remaining_hp: int)
signal enemy_defeated(source: Object)

enum MovementType {
	PATROL,
	CHASE,
	STATIONARY,
}

@export_group("Movement")
@export var movement_type: MovementType = MovementType.PATROL
@export_range(0.0, 1000.0, 1.0, "suffix:px/s") var movement_speed: float = 100.0
@export_range(-1000.0, 0.0, 1.0, "suffix:px") var patrol_left_offset: float = -160.0
@export_range(0.0, 1000.0, 1.0, "suffix:px") var patrol_right_offset: float = 160.0
@export_range(0.0, 4000.0, 1.0, "suffix:px/s²") var gravity: float = 1200.0
@export_range(0.0, 100.0, 1.0, "suffix:px") var chase_stop_distance: float = 18.0

@export_group("Ranged Attack")
@export_range(0.0, 3000.0, 1.0, "suffix:px") var attack_range: float = 600.0
@export_range(0.05, 30.0, 0.05, "suffix:s") var attack_interval: float = 1.5
@export_range(0.0, 30.0, 0.05, "suffix:s") var initial_shot_delay: float = 0.5
@export_range(20.0, 2000.0, 1.0, "suffix:px/s") var projectile_speed: float = 340.0

@export_group("Health")
@export_range(1, 100, 1) var max_hp: int = 2
@export_range(1, 100, 1) var reflected_projectile_damage: int = 1
@export var center_offset: Vector2 = Vector2(0.0, -32.0)
@export_range(1.0, 100.0, 1.0, "suffix:px") var hit_radius: float = 22.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D as AnimatedSprite2D
@onready var projectile_emitter: ProjectileEmitter = $ProjectileEmitter as ProjectileEmitter

var hp: int = 0
var _is_defeated: bool = false
var _initial_position: Vector2 = Vector2.ZERO
var _patrol_origin_x: float = 0.0
var _patrol_direction: float = 1.0
var _action_animation_active: bool = false


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("resettable")
	hp = maxi(1, max_hp)
	_initial_position = position
	_patrol_origin_x = global_position.x
	animated_sprite.animation_finished.connect(_on_animation_finished)
	projectile_emitter.projectile_launched.connect(_on_projectile_launched)
	projectile_emitter.auto_start = false
	projectile_emitter.path_mode = ProjectileEmitter.PathMode.LINE
	projectile_emitter.attack_interval = maxf(0.05, attack_interval)
	projectile_emitter.initial_delay = maxf(0.0, initial_shot_delay)
	projectile_emitter.projectile_speed = maxf(20.0, projectile_speed)
	_play_locomotion_animation()


func _physics_process(delta: float) -> void:
	if _is_defeated:
		return

	var target := _find_player()
	_update_movement(target, delta)
	_update_firing(target)
	_update_facing(target)
	move_and_slide()
	_play_locomotion_animation()


func _update_movement(target: Node2D, delta: float) -> void:
	var move_direction: float = 0.0
	match movement_type:
		MovementType.PATROL:
			var left_bound: float = _patrol_origin_x + minf(patrol_left_offset, patrol_right_offset)
			var right_bound: float = _patrol_origin_x + maxf(patrol_left_offset, patrol_right_offset)
			if global_position.x <= left_bound:
				_patrol_direction = 1.0
			elif global_position.x >= right_bound:
				_patrol_direction = -1.0
			move_direction = _patrol_direction
		MovementType.CHASE:
			if target != null:
				var horizontal_distance: float = target.global_position.x - global_position.x
				if absf(horizontal_distance) > chase_stop_distance:
					move_direction = signf(horizontal_distance)
		MovementType.STATIONARY:
			pass

	velocity.x = move_direction * movement_speed
	if not is_on_floor():
		velocity.y += maxf(0.0, gravity) * delta
	else:
		velocity.y = 0.0


func _update_firing(target: Node2D) -> void:
	if target == null:
		projectile_emitter.stop_firing()
		return

	var target_center: Vector2 = ParryableProjectile.target_center(target)
	var to_target: Vector2 = target_center - projectile_emitter.global_position
	if to_target.length_squared() > attack_range * attack_range:
		projectile_emitter.stop_firing()
		return

	if to_target.length_squared() > 1e-6:
		projectile_emitter.launch_angle_deg = rad_to_deg(to_target.angle())
	if not projectile_emitter.is_firing():
		projectile_emitter.start_firing()


func _update_facing(target: Node2D) -> void:
	var direction_x: float = velocity.x
	if target != null:
		var horizontal_distance: float = target.global_position.x - global_position.x
		if absf(horizontal_distance) > 1.0:
			direction_x = horizontal_distance
	if absf(direction_x) > 1.0:
		animated_sprite.flip_h = direction_x < 0.0


func _find_player() -> Node2D:
	for node in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if "is_dead" in node and bool(node.get("is_dead")):
			continue
		return node as Node2D
	return null


func on_hit_by_reflected_projectile(projectile: Node2D) -> void:
	if _is_defeated or not is_instance_valid(projectile):
		return
	if not ("is_reflected" in projectile) or not bool(projectile.get("is_reflected")):
		return
	take_damage(maxi(1, reflected_projectile_damage), projectile)


func take_damage(amount: int, source: Object = null) -> void:
	if _is_defeated or amount <= 0:
		return
	hp = maxi(0, hp - amount)
	enemy_damaged.emit(source, hp)
	if hp == 0:
		_is_defeated = true
		projectile_emitter.stop_firing()
		var body_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
		if body_shape != null:
			body_shape.set_deferred("disabled", true)
		enemy_defeated.emit(source)
		hide()
		return
	_play_action_animation(&"hurt")


func reset_state() -> void:
	_is_defeated = false
	hp = maxi(1, max_hp)
	position = _initial_position
	velocity = Vector2.ZERO
	_patrol_origin_x = global_position.x
	_patrol_direction = 1.0
	_action_animation_active = false
	show()
	var body_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape != null:
		body_shape.set_deferred("disabled", false)
	projectile_emitter.reset_state()
	animated_sprite.play(&"idle")


func get_center_global() -> Vector2:
	return global_position + center_offset


func get_hit_radius() -> float:
	return hit_radius


func is_defeated() -> bool:
	return _is_defeated


func _play_action_animation(animation_name: StringName) -> void:
	_action_animation_active = true
	animated_sprite.play(animation_name)


func _play_locomotion_animation() -> void:
	if _is_defeated or _action_animation_active:
		return
	var next_animation: StringName = &"move" if absf(velocity.x) > 1.0 else &"idle"
	if animated_sprite.animation != next_animation:
		animated_sprite.play(next_animation)


func _on_projectile_launched(_projectile: ParryableProjectile) -> void:
	_play_action_animation(&"shoot")


func _on_animation_finished() -> void:
	if animated_sprite.animation == &"shoot" or animated_sprite.animation == &"hurt":
		_action_animation_active = false
		_play_locomotion_animation()
