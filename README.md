# Feedback

2D puzzle-action platformer built around an 8-directional parry mechanic (Godot 4.7).

## Project Structure

- [`scenes/TestLevel.tscn`](scenes/levels/the_proving_hall.tscn): Playable test room with projectile sentinel,
  switch & door, telegraphed physical attack fixture, bounce walls/surfaces, spikes hazard, and HUD.
- [`scenes/character.tscn`](scenes/character.tscn) & [
  `scripts/player/player_character.gd`](scripts/player/player_character.gd): Player character controller.
- [`assets/environment/`](assets/environment/):  SVG architecture for the Proving Hall,
  including beveled ledges, reinforced walls, and a mechanical attack fixture.
  Surface artwork follows the collision geometry.
- [`scripts/tests/test_parry_suite.gd`](scripts/tests/test_parry_suite.gd): Headless .

## Controls

| Action | Input Map Actions | Default Keys |
| --- | --- | --- |
| Move Left / Right | `MoveLeft`, `MoveRight` | `A` / `D` or `Left` / `Right` |
| Aim Parry (8-Way) | `ParryUp`, `ParryDown`, `ParryLeft`, `ParryRight` | `WASD` or `Arrow Keys` (defaults to facing direction if neutral) |
| Jump | `Jump` | `Space` |
| Parry | `Parry` | `E`, `J`, or `Shift` |
| Reset Room | `Restart` | `R` |
| Toggle Surface Parry Cooldown Reset | `ToggleCooldownReset` | `T` |

## Running the Game & Tests

Open [`project.godot`](project.godot) in Godot 4.7 and press **F5**, or run from the terminal:

```sh
godot --path .
godot --headless --path . -s res://scripts/tests/test_parry_suite.gd
godot --headless --path . --fixed-fps 60 -s res://scripts/test_level/test_level_geometry.gd
```

## Mechanics

- Projectile collision is not implemented yet.
- FB023 implements the parry activation window, cooldown, directional lock, and 8-way sector hitbox. Combat contact resolution follows in FB024.

## Levels

Features a single test level: The Proving Hall. 
