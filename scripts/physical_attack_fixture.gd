class_name PhysicalAttackFixture
extends Area2D

enum Phase { IDLE, TELEGRAPH, ACTIVE, RECOVERY }

@export var telegraph_duration: float = 0.55
@export var active_duration: float = 0.25
@export var recovery_duration: float = 0.80
@export var attack_radius: float = 44.0
## Direction of the impulse transferred to the player when parried (Section 2.5.B).
@export var impulse_direction: Vector2 = Vector2(0.75, -0.66)
## Optional override in CH/s; if <= 0, uses the player's physical_attack_impulse_ch.
@export var impulse_override_ch: float = -1.0
@export var auto_cycle: bool = true

var phase: Phase = Phase.TELEGRAPH
var phase_timer: float = 0.55
var _neutralized_in_current_swing: bool = false


func _ready() -> void:
	add_to_group("parryable_attacks")
	add_to_group("resettable")
	phase = Phase.TELEGRAPH if auto_cycle else Phase.IDLE
	phase_timer = telegraph_duration if auto_cycle else 0.0
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not auto_cycle and phase == Phase.IDLE:
		return

	phase_timer -= delta
	if phase_timer <= 0.0:
		match phase:
			Phase.IDLE:
				if auto_cycle:
					_enter_phase(Phase.TELEGRAPH, telegraph_duration)
			Phase.TELEGRAPH:
				_enter_phase(Phase.ACTIVE, active_duration)
			Phase.ACTIVE:
				_enter_phase(Phase.RECOVERY, recovery_duration)
			Phase.RECOVERY:
				_enter_phase(Phase.TELEGRAPH if auto_cycle else Phase.IDLE, telegraph_duration)
	queue_redraw()


func _enter_phase(new_phase: Phase, duration: float) -> void:
	phase = new_phase
	phase_timer = duration
	if new_phase == Phase.ACTIVE:
		_neutralized_in_current_swing = false
	queue_redraw()


func trigger_active_now(duration: float = -1.0) -> void:
	_enter_phase(Phase.ACTIVE, duration if duration > 0.0 else active_duration)


func is_attack_active() -> bool:
	return phase == Phase.ACTIVE and not _neutralized_in_current_swing


func get_attack_category() -> StringName:
	return &"physical"


func get_hit_radius() -> float:
	return attack_radius


func get_impulse_direction() -> Vector2:
	return impulse_direction.normalized() if impulse_direction.length_squared() > 1e-6 else Vector2.UP


func can_damage_player(_player: Node2D) -> bool:
	return is_attack_active()


func on_parried(_player: Node2D, _parry_dir: Vector2) -> bool:
	if not is_attack_active():
		return false
	_neutralized_in_current_swing = true
	queue_redraw()
	return true


func reset_state() -> void:
	_neutralized_in_current_swing = false
	phase = Phase.TELEGRAPH if auto_cycle else Phase.IDLE
	phase_timer = telegraph_duration if auto_cycle else 0.0
	queue_redraw()


func _draw() -> void:
	var fill_col: Color
	var ring_col: Color
	if phase == Phase.ACTIVE and not _neutralized_in_current_swing:
		fill_col = Color(0.94, 0.35, 0.30, 0.45)
		ring_col = Color(1.0, 0.55, 0.45, 0.95)
	elif phase == Phase.TELEGRAPH:
		var pulse: float = 1.0 - clampf(phase_timer / maxf(0.01, telegraph_duration), 0.0, 1.0)
		fill_col = Color(0.95, 0.75, 0.25, 0.15 + 0.25 * pulse)
		ring_col = Color(0.95, 0.80, 0.35, 0.85)
	else:
		fill_col = Color(0.35, 0.42, 0.50, 0.15)
		ring_col = Color(0.55, 0.62, 0.70, 0.45)

	draw_circle(Vector2.ZERO, attack_radius, fill_col)
	draw_arc(Vector2.ZERO, attack_radius, 0.0, TAU, 28, ring_col, 2.5)
	var dir_vec: Vector2 = get_impulse_direction() * (attack_radius * 0.75)
	draw_line(Vector2.ZERO, dir_vec, ring_col, 3.0)
