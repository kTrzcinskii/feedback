# Room transitions

Rooms can be linked without a central level list:

1. Add a `LevelStart` scene to a room and give it a unique `start_id`.
2. Add a `LevelExit` scene where the player should leave.
3. Set the exit's `destination_level` to a room scene and `destination_start_id` to a start marker in that scene.

The shared `LevelTransition` autoload changes the active scene. The destination room's `TestLevel` places its player at the requested marker, carries over HP, and resets movement, parry, and temporary effects. Existing rooms without transition markers continue to use their `SpawnPoint`.

The runnable demo starts in `scenes/levels/progression_room_01.tscn`; its exit leads to `progression_room_02.tscn`. Run the focused check with:

```text
godot --headless --path . -s res://tests/level_transition_test.gd
```

For future rooms, connect an exit to another scene and marker in the editor; no code change or central registry is needed.
