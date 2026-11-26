extends Area2D

@onready var completion_label: Label = $CompletionLabel


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerCharacter:
		completion_label.show()


func reset_state() -> void:
	completion_label.hide()
