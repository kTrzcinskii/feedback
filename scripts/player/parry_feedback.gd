class_name ParryFeedback
extends Node2D

@export var use_voice_cues: bool = false
@export var success_voice: AudioStream
@export var failure_voice: AudioStream

@onready var _active_sector: Polygon2D = $ActiveSector
@onready var _success_burst: AnimatedSprite2D = $SuccessBurst
@onready var _failure_mark: Line2D = $FailureMark
@onready var _failure_timer: Timer = $FailureTimer
@onready var _success_sound: AudioStreamPlayer = $SuccessSound
@onready var _failure_sound: AudioStreamPlayer = $FailureSound


func _ready() -> void:
	if use_voice_cues:
		_success_sound.stream = success_voice
		_failure_sound.stream = failure_voice


func show_active_sector(active: bool, polygon: PackedVector2Array, direction: float) -> void:
	_active_sector.polygon = polygon
	_active_sector.rotation = direction
	_active_sector.visible = active


func clear_outcomes() -> void:
	_success_burst.stop()
	_success_burst.hide()
	_failure_timer.stop()
	_failure_mark.hide()
	_success_sound.stop()
	_failure_sound.stop()


func _on_parry_succeeded(_target: Object, _category: StringName, _direction: Vector2, _velocity: Vector2) -> void:
	_success_burst.stop()
	_success_burst.show()
	_success_burst.play(&"burst")
	_success_sound.play()


func _on_parry_failed(_projectile: ParryableProjectile) -> void:
	_failure_mark.show()
	_failure_timer.start()
	_failure_sound.play()
