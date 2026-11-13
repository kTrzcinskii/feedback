class_name ParrySurface
extends StaticBody2D

## Coefficient of restitution 'e' used in v_reflected = v - (1 + e) * dot(v, n) * n (Section 3.5).
@export var restitution: float = 0.45

## Optional surface-specific parry impulse magnitude 'J' in CH/s (Section 3.5).
## When < 0.0, falls back to the player's surface_parry_impulse_ch.
@export var surface_impulse_ch: float = -1.0

## Multiplier applied to the surface parry impulse 'J' on this surface.
@export var impulse_multiplier: float = 1.0


func get_surface_impulse_px(default_impulse_ch: float, character_height_px: float) -> float:
	var base_ch: float = surface_impulse_ch if surface_impulse_ch >= 0.0 else default_impulse_ch
	return base_ch * character_height_px * impulse_multiplier
