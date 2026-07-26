class_name PlayerData
extends Resource

# All player movement tunables in one place. Edit
# default_player_data.tres in the inspector to update every Player
# instance at once — all Player.tscn instances that reference this
# resource will pick up the change without needing to be re-saved.

## Horizontal speed (px/s) the input drives the player toward.
## The player can EXCEED this via ramp launches and drops — this is
## a target, not a hard cap.
@export var run_speed: float = 200.0
## Lateral acceleration toward run_speed (px/s²) on the ground.
@export var run_accel: float = 1500.0
## Lateral acceleration toward run_speed (px/s²) in the air. Reduced
## vs run_accel so jumps feel committed and momentum is preserved —
## the player can nudge their trajectory mid-air but not redirect it.
@export var air_accel: float = 700.0
## Jump impulse magnitude. Applied in the current "up" direction
## (opposite of gravity). Stored as a negative number (up); the
## magnitude is |jump_velocity|.
@export var jump_velocity: float = -400.0
## Gravitational acceleration magnitude (px/s²). Used together with
## gravity_direction to apply gravity in the current "down" direction.
@export var gravity_strength: float = 1500.0
## If true, the body keeps the same horizontal speed on slopes (no
## acceleration downhill, no deceleration uphill). Without this,
## gravity 1500 + low-friction slopes makes the player build speed
## quickly on downhills.
@export var floor_constant_speed: bool = true
## How far (px) along the body's up_direction the engine will try to
## keep the player snapped to the floor on slope transitions.
@export var floor_snap_length: float = 4.0
## How fast the player stops on flat ground (px/s²). On slopes,
## momentum is preserved — the slope slide + friction handle
## deceleration instead.
@export var ground_decel: float = 1500.0
## Extra acceleration while the down arrow is held. Applied in the
## current gravity direction.
@export var down_boost: float = 1500.0
## Number of physics frames a jump press is remembered while airborne.
@export var jump_buffer_frames: int = 5
## Number of physics frames AFTER leaving the floor that the player
## can still jump (coyote time).
@export var coyote_frames: int = 5
## Number of physics frames AFTER dislodging from a sticky wall during
## which the player cannot re-engage a sticky tile.
@export var sticky_refraction_frames: int = 4
## Sample depth (px) below the player's bottom to look for the contact cell.
@export var surface_query_depth: float = 4.0
## X offsets (relative to player center) of the surface query points.
@export var surface_query_x_offsets: PackedFloat32Array = [-12.0, 0.0, 12.0]
## Master toggle for the per-frame debug print.
@export var debug_output: bool = true
## Seconds between debug prints.
@export var debug_poll_interval: float = 0.5
## How long the camera rotation takes to complete after each gravity change.
@export var camera_rotation_duration: float = 0.25
## Camera zoom multiplier. Values < 1 zoom out, values > 1 zoom in.
@export var camera_zoom: Vector2 = Vector2(1, 1)
