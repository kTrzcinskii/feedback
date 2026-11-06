# Feedback - Gameplay Ruleset

## IMPORTANT NOTE

All proposed values need to be tested in the actual game once the test level is implemented and adjusted so that they "feel right".

## 1. Design principles

The gameplay should revolve around mastering a single mechanic: parrying. It should serve three purposes:

1. **Defence:** Neutralizing enemy attacks and avoiding damage.
2. **Offence:** Redirecting enemy projectiles and using enemy attacks against enemies or environmental objects.
3. **Movement:** Manipulating the player's momentum to perform advanced platforming manoeuvres.

The parry system should reward precise timing and directional input. It should not become a continuously active shield.

The initial implementation should support eight-directional parrying and two categories of parry targets:

- Enemy attacks (projectiles and physical attacks).
- Solid environmental surfaces (walls, ceilings and floors).

## 2. Parry

### 2.1. Directions

The player can perform a parry in eight directions:

- Horizontal: left and right.
- Vertical: up and down.
- Diagonal: up-left, up-right, down-left and down-right.

The direction is determined by the directional input held at the moment the parry button is pressed.

The directional input is sampled once when the parry starts and remains locked throughout its active duration.

If no directional input is provided, the parry defaults to the direction the character is facing.

Diagonal directions are normalized to prevent diagonal parries from having a larger effective range.

### 2.2. Hitbox

The parry hitbox is directional rather than surrounding the entire character.

It should be implemented as an angular sector (arc) originating near the player's centre and extending in the selected direction.

Initial parameters:

| Parameter | Proposed value |
| --- | ---: |
| Number of directions | 8 |
| Hitbox range | 1.0 character heights |
| Angular coverage | ±22.5° |
| Direction changes during parry | Not allowed |

The hitbox should be sufficiently large to make parrying reliable while still requiring the player to face the incoming attack.

### 2.3. Activation and input behaviour

Parrying is activated by pressing a dedicated button.

Rules:

- Pressing the parry button starts the parry window immediately.
- Holding the button does not extend the active duration.
- Holding the button does not automatically trigger another parry after the cooldown.
- A new parry requires releasing and pressing the button again.
- Pressing the button during cooldown has no effect.
- Parrying is available both on the ground and in the air.

This makes the mechanic dependent on timing rather than button holding.

### 2.4. Active duration and cooldown

The parry has two distinct time intervals:

**Active duration:** The period during which the directional hitbox can interact with attacks or surfaces.

**Cooldown:** The period after the active window during which another parry cannot be initiated.

Initial parameters:

| Parameter | Proposed value |
| --- | ---: |
| Active duration | 0.20 s |
| Cooldown | 0.20 s |
| Total time between activations | 0.40 s |

The active window begins immediately upon button activation. There is no startup animation that delays the hitbox.

The cooldown starts when the active window ends.

### 2.5. Successful parry resolution

A parry is successful when a valid attack or surface intersects the directional parry hitbox during the active window.

Different interactions produce different results.

#### A. Projectile parry

When an enemy projectile enters the active parry hitbox:

- The projectile is successfully parried.
- Its velocity is reversed by 180 degrees, preserving its original speed.
- The projectile can damage enemies and activate environmental mechanisms.
- The projectile can still damage the player if it subsequently collides with them.

#### B. Physical attack parry

When an enemy's physical attack intersects the active parry hitbox:

- The attack is neutralized.
- The player receives an impulse based on the incoming attack direction (player's existing velocity is increased).
- The resulting velocity can be used to perform movement manoeuvres, such as crossing gaps or reaching elevated platforms.

#### C. Environmental surface parry

The player can also parry solid surfaces without requiring an enemy attack.

When the player activates a parry directed towards a solid surface and the surface intersects the active parry hitbox:

- The player receives an impulse directed away from the contacted surface.
- The impulse is based on the surface normal.
- Existing tangential velocity is preserved.
- The resulting movement allows the player to bounce off walls, ceilings and floors.

This mechanic is intended to provide an alternative to conventional wall jumping.

For example, a player approaching a vertical wall can perform a right-facing parry to propel themselves to the left. Similarly, a downward-facing parry against the floor can produce an upward impulse.

Ordinary surface collisions must not produce this effect. The player must explicitly perform a successful surface parry.

### 2.6. Same-tick parry and death priority

A successful parry must take priority over death caused by the specific attack being parried.

If an enemy attack and the player's parry hitbox collide during the same physics tick, the parry is resolved first.

The following rules apply:

1. Check whether the parry is active.
2. Check whether the incoming attack intersects the directional hitbox.
3. If successful, neutralize or redirect the attack.
4. Apply the corresponding momentum effect, if applicable.
5. Resolve any remaining collisions and damage.

A successfully parried attack cannot decrease player hp during the same tick.

However, independent hazards are still lethal. For example, successfully parrying an enemy projectile does not protect the player from simultaneously touching spikes.

This ordering prevents ambiguous situations in which a visually successful parry still results in death.

Note: I didn't check whether it's possible in godot to enforce such order of colission resolving, need to be checked in development.

## 3. Movement and collision rules

### 3.1. Ordinary horizontal movement

Horizontal movement is controlled using left (A/left arrow) and right(D/ right arrow) directional input.

Initial rules:

- Pressing a horizontal movement key immediately sets the player's ordinary horizontal velocity to the configured movement speed in the corresponding direction.
- Releasing the movement key immediately stops ordinary horizontal movement.
- Pressing the opposite direction immediately changes the direction of ordinary horizontal movement.
- Ordinary horizontal movement does not introduce additional inertia or acceleration.

An important exception is momentum obtained through parrying.

Parry-generated momentum should not be discarded simply because the player releases the movement button.

### 3.2. Jumping and gravity

The player can perform a conventional jump while standing on a solid surface.

Initial rules:

- Jumping is only available while grounded.
- Jumping applies an upward velocity impulse.
- The player cannot perform another conventional jump while airborne.
- Gravity continuously accelerates the player downwards.
- Gravity is not disabled during ordinary parrying.

The parry mechanic provides an additional way to generate upward momentum, meaning the player can reach heights that would not be accessible through conventional jumping alone.

### 3.3. Air control

The player retains limited directional control while airborne.

Air control should be weaker than ground movement to preserve the importance of momentum.

Rules:

- Left/right input applies horizontal acceleration while airborne.
- Air control does not immediately overwrite the player's velocity.
- Parry-generated momentum is preserved and can be adjusted through air control.
- The player cannot completely cancel a strong parry impulse instantaneously through ordinary movement input.

This distinction is important because movement should feel responsive without making parry-generated momentum irrelevant.

### 3.4. Momentum and impulse application

The player's movement is represented by a velocity vector:

`v = (vx, vy)`

A successful parry applies an impulse that modifies the existing velocity:

`v_new = v_old + Δv`

Where:

- `v_old` is the velocity before the parry.
- `Δv` is the velocity change produced by the successful parry.
- `v_new` is the resulting velocity.

This means consecutive parries can build upon previously acquired momentum.

Gravity and air control continue to influence the player after the impulse is applied.

The player retains the resulting momentum while airborne until another force or collision modifies it.

### 3.5. Surface collision and bouncing

Ordinary surface collisions and parry-based surface interactions must be treated as different operations.

**Ordinary collision:**

- The player cannot pass through solid surfaces.
- Velocity directed into the surface is cancelled.
- Contact with a floor establishes the grounded state.
- Contact with a wall does not automatically propel the player in the opposite direction.

**Parry-based collision:**

When a successful surface parry occurs, the player's velocity is reflected or modified using the surface normal.

The surface normal determines the direction away from the contacted surface.

The tangential component of the player's velocity should be preserved to maintain smooth movement.

For a surface with outward unit normal `n`, a conventional velocity reflection can be expressed as:

`v_reflected = v - (1 + e) * dot(v, n) * n`

Where `e` is the coefficient of restitution. We can have different type of surfaces with different values of `e` giving us more content for level design.

### 3.6. Collision with hazards

The following rules apply to lethal collisions:

- Contact with an un-parried enemy attack decreases player hp.
- Contact with an enemy body decreases player hp unless the corresponding physical attack is successfully parried.
- Contact with an enemy projectile decreases player hp unless it is successfully parried.
- Contact with spikes or other lethal environmental hazards decreases player hp.
- A successful parry only neutralizes the specific attack or interaction that was successfully parried.

Upon death, the level is restarted according to the existing project requirements.

## 4. Initial tunable parameters

The following table collects the parameters that should be exposed for testing and balancing.

| Parameter | Initial value | Unit |
| --- | ---: | --- |
| Parry active duration | 0.20 | s |
| Parry cooldown | 0.20 | s |
| Parry hitbox range | 1.0 | CH |
| Parry angular coverage | ±22.5 | degrees |
| Ground movement speed | TBD | CH/s |
| Ground acceleration | TBD | CH/s² |
| Jump velocity | TBD | CH/s |
| Gravity | TBD | CH/s² |
| Air control acceleration | TBD | CH/s² |
| Physical attack impulse | TBD | CH/s |
| Surface parry impulse | TBD | CH/s |

where CH is character height. I guess it would be convenient to make units dependent on player size, but we will figure it out during development.
