class_name PlayerAnimationTree
extends AnimationTree

## Locomotion motion states for the transition node in PlayerVisual/AnimationTree
enum Motion {
	IDLE,
	RUN,
	RISE,
	AIR_MOVE,
	FALL,
	LAND,
}

## Locomotion state names mapped from enum
const MOTION_NAMES: Dictionary = {
	Motion.IDLE: &"idle",
	Motion.RUN: &"run",
	Motion.RISE: &"rise",
	Motion.AIR_MOVE: &"air-move",
	Motion.FALL: &"fall",
	Motion.LAND: &"land",
}

## Locomotion state string constants
const IDLE: StringName = &"idle"
const RUN: StringName = &"run"
const RISE: StringName = &"rise"
const AIR_MOVE: StringName = &"air-move"
const FALL: StringName = &"fall"
const LAND: StringName = &"land"

## AnimationTree parameter path constants
const PARAM_LOCOMOTION_REQUEST: StringName = &"parameters/Locomotion/transition_request"
const PARAM_LOCOMOTION_SPEED: StringName = &"parameters/LocomotionSpeed/scale"
const PARAM_PARRY_REQUEST: StringName = &"parameters/Parry/request"


static func motion_to_name(motion: Motion) -> StringName:
	return MOTION_NAMES.get(motion, &"idle")


static func name_to_motion(motionString: StringName) -> Motion:
	match motionString:
		RUN, &"run": return Motion.RUN
		RISE, &"rise": return Motion.RISE
		AIR_MOVE, &"air-move": return Motion.AIR_MOVE
		FALL, &"fall": return Motion.FALL
		LAND, &"land": return Motion.LAND
		_: return Motion.IDLE


func set_motion(motion: Motion) -> void:
	set(PARAM_LOCOMOTION_REQUEST, motion_to_name(motion))


func set_motion_name(motion_name: StringName) -> void:
	set(PARAM_LOCOMOTION_REQUEST, motion_name)


func set_locomotion_scale(scale_val: float) -> void:
	set(PARAM_LOCOMOTION_SPEED, scale_val)


func fire_parry() -> void:
	set(PARAM_PARRY_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func abort_parry() -> void:
	set(PARAM_PARRY_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
