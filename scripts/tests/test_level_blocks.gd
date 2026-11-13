extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	for kind in ["platform", "wall"]:
		var path := "res://scenes/terrain/%s.tscn" % kind
		if not ResourceLoader.exists(path):
			printerr("Missing block: ", path)
			quit(1)
			return
		var packed: PackedScene = load(path)
		var first = packed.instantiate()
		var second = packed.instantiate()
		root.add_child(first)
		root.add_child(second)
		var original: Vector2 = second.get_node("CollisionShape2D").shape.size
		first.size = Vector2(256, 64)
		assert(first is ParryableSurface)
		assert(first.get_node("CollisionShape2D").shape.size == Vector2(256, 64))
		assert(first.get_node("SurfaceVisual").size == Vector2(256, 64))
		assert(first.get_node("SurfaceVisual").position == Vector2(-128, -32))
		assert(second.get_node("CollisionShape2D").shape.size == original)
		assert(first.one_way == (kind == "platform"))
		first.one_way = not first.one_way
		assert(first.get_node("CollisionShape2D").one_way_collision == first.one_way)
		first.free()
		second.free()
	var floor_scene: PackedScene = load("res://scenes/terrain/floor.tscn")
	var floor_a = floor_scene.instantiate()
	var floor_b = floor_scene.instantiate()
	root.add_child(floor_a)
	root.add_child(floor_b)
	floor_a.size = Vector2(250, 160)
	assert(floor_a.get_node("CollisionShape2D").shape.size == Vector2(250, 160))
	assert(floor_a.get_node("CollisionShape2D").position == Vector2(125, 80))
	assert(floor_b.get_node("CollisionShape2D").shape.size == Vector2(192, 96))
	floor_a.size = Vector2.ZERO
	assert(floor_a.size == Vector2(16, 32))
	floor_a.free()
	floor_b.free()
	print("Level block resizing, isolation, and collision checks passed")
	quit()
