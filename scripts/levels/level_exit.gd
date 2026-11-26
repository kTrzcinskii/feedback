class_name LevelExit
extends Area2D

@export var destination_level: PackedScene
@export var destination_start_id: StringName = &"entry"

var _transition_started: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _transition_started or not body is PlayerCharacter:
		return
	var player := body as PlayerCharacter
	if player.is_dead or player.hp <= 0:
		return

	var transition_service := get_node_or_null("/root/LevelTransition") as LevelTransitionService
	if transition_service == null:
		push_error("Cannot use room exit: LevelTransition autoload is missing.")
		return

	var result: Error = transition_service.transition_to(
			destination_level, destination_start_id, player)
	if result == OK:
		_transition_started = true
