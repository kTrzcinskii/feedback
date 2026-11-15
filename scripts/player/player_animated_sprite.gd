class_name PlayerAnimatedSprite
extends AnimatedSprite2D

const HURT: StringName = &"hurt"
const IDLE: StringName = &"idle"
const MOVE: StringName = &"move"
const JUMP: StringName = &"jump"
const PARRY: StringName = &"parry"


func play_hurt() -> void:
	play(HURT)


func play_idle() -> void:
	play(IDLE)


func play_jump() -> void:
	play(JUMP)


func play_move() -> void:
	play(MOVE)


func play_parry() -> void:
	if animation != PARRY:
		play(PARRY)


func play_locomotion(grounded: bool, moving: bool) -> void:
	if animation == PARRY or animation == HURT:
		return

	if not grounded:
		play_if_not(JUMP)
	elif moving:
		play_if_not(MOVE)
	else:
		play_if_not(IDLE)


func is_hurt() -> bool:
	return animation == HURT


func play_if_not(anim_name: StringName) -> void:
	if animation != anim_name and animation != HURT:
		play(anim_name)
