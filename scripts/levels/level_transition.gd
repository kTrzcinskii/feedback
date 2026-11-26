class_name LevelTransitionService
extends Node

var _pending_start_id: StringName = &""
var _pending_player_hp: int = -1
var _transition_pending: bool = false


func transition_to(destination: PackedScene, start_id: StringName, player: PlayerCharacter) -> Error:
	if _transition_pending:
		push_error("A room transition is already in progress.")
		return ERR_BUSY
	if destination == null or str(start_id).is_empty() or not is_instance_valid(player):
		push_error("Room transition requires a destination scene, start ID, and valid player.")
		return ERR_INVALID_PARAMETER

	_pending_start_id = start_id
	_pending_player_hp = player.hp
	_transition_pending = true
	call_deferred("_change_scene", destination)
	return OK


func _change_scene(destination: PackedScene) -> void:
	var result: Error = get_tree().change_scene_to_packed(destination)
	if result != OK:
		_clear_pending_transition()
		push_error("Could not change to destination room (error %d)." % result)


func consume_pending_transition() -> Dictionary:
	if not _transition_pending:
		return {}
	var transition := {
		"start_id": _pending_start_id,
		"player_hp": _pending_player_hp,
	}
	_clear_pending_transition()
	return transition


func _clear_pending_transition() -> void:
	_pending_start_id = &""
	_pending_player_hp = -1
	_transition_pending = false
