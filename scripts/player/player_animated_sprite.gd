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


func is_hurt() -> bool:
	return animation == HURT


func play_if_not(anim_name: StringName) -> void:
	if animation != anim_name and animation != HURT:
		play(anim_name)
