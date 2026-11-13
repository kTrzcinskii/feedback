# Feedback

2D puzzle-action platformer built around an 8-directional parry mechanic (Godot 4.7).

## Project Structure

- [`scenes/TestLevel.tscn`](scenes/TestLevel.tscn): Playable test room with projectile sentinel, switch & door, telegraphed physical attack fixture, bounce walls/surfaces, spikes hazard, and HUD.
- [`scenes/character.tscn`](scenes/character.tscn) & [`scripts/character.gd`](scripts/character.gd): Player character controller.
- [`scripts/test_parry_suite.gd`](scripts/test_parry_suite.gd): Headless automated verification suite.

## Running the Game & Tests

Open [`project.godot`](project.godot) in Godot 4.7 and press **F5**, or run from the terminal:

```sh
godot --path .
godot --headless --path . -s res://scripts/test_parry_suite.gd
```
