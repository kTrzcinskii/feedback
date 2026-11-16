@tool
extends EditorInspectorPlugin

## Filters the emitter "Path" section down to the variables relevant to path_mode.

const LINE_PROPERTIES: PackedStringArray = ["launch_angle_deg"]
const SPLINE_PROPERTIES: PackedStringArray = ["path_node"]
const TRACK_PROPERTIES: PackedStringArray = [
	"target_node",
	"target_group",
	"turn_rate_deg",
	"tracking_duration",
]


func _can_handle(object: Object) -> bool:
	return object is ProjectileEmitter


func _parse_property(object: Object, _type: int, name: String, _hint: PropertyHint,
		_hint_string: String, _usage: int, _wide: bool) -> bool:
	var emitter := object as ProjectileEmitter
	match emitter.path_mode:
		ProjectileEmitter.PathMode.SPLINE:
			return name in LINE_PROPERTIES or name in TRACK_PROPERTIES
		ProjectileEmitter.PathMode.TRACK_TARGET:
			return name in LINE_PROPERTIES or name in SPLINE_PROPERTIES
		_:
			return name in SPLINE_PROPERTIES or name in TRACK_PROPERTIES
