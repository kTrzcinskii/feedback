# Feedback

2D puzzle-action platformer built around an 8-directional parry mechanic (Godot 4.7).

## Project Structure

- [`scenes/TestLevel.tscn`](scenes/TestLevel.tscn): Playable test room with projectile sentinel, switch & door, telegraphed physical attack fixture, bounce walls/surfaces, spikes hazard, and HUD.
- [`scenes/character.tscn`](scenes/character.tscn) & [`scripts/character.gd`](scripts/character.gd): Player character controller.
- [`assets/environment/`](assets/environment/): Original SVG architecture for the Proving Hall, including beveled ledges, reinforced walls, and a mechanical attack fixture. Surface artwork follows the collision geometry; the backdrop is decorative.
- [`scripts/test_parry_suite.gd`](scripts/test_parry_suite.gd): Headless automated verification suite.

## Running the Game & Tests

Open [`project.godot`](project.godot) in Godot 4.7 and press **F5**, or run from the terminal:

```sh
godot --path .
godot --headless --path . -s res://scripts/test_parry_suite.gd
godot --headless --path . --fixed-fps 60 -s res://scripts/test_level_geometry.gd
```

## Proving Hall Layout

The room runs from the impact alcove on the left through a safe central spawn,
a four-step ascent, a spike trench, and the projectile range on the right.
The ascent uses 72px rises (below the controller's roughly 105px jump height),
with an upper crossing and descending steps that also support the return trip.
A running jump crosses the 192px trench at floor level as a shorter route.
The floor and outer walls have finite collision geometry; the camera stays inside
these room bounds. Falling into the trench resets the room.

The sentinel fires away from the spawn, toward the switch and door fixtures.
These remain a testing area: this branch does not yet implement player parry
input, and projectiles do not collide with terrain. Neither mechanic is required
to traverse the level.

The geometry suite drives the actual player controller through the route in both
directions, checks the lower crossing, safe spawn, trench reset, and finite floor.
