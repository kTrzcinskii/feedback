@tool
extends EditorPlugin

const INSPECTOR_PLUGIN: Script = preload("emitter_inspector_plugin.gd")

var _inspector_plugin: EditorInspectorPlugin = null


func _enter_tree() -> void:
	_inspector_plugin = INSPECTOR_PLUGIN.new() as EditorInspectorPlugin
	add_inspector_plugin(_inspector_plugin)


func _exit_tree() -> void:
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
