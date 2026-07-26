# Clockwork

> **GMTK Game Jam 2026 — Theme: Countdown**

## Status

**Skeleton shipped 2026-07-23** (commits `532a05a` → `55b2066` → `90995a8` → `f11b24e` → `dfcad97` → `ce685fb`): player (CharacterBody2D + collision + box visual, in "player" group), clock UI (CanvasLayer + Label counting 10→0), `RotatingLevelComponents` wrapper (since removed) for level rotation, `flag.tscn` + `level.gd` orchestrator (touch-to-win → clock pause → wait for input → `change_scene_to_file(next_level_path)`), `scenes/level_template.tscn` as the parent scene L1/L2/L3 inherit from, `scenes/main.tscn` as a thin pass-through to the template. **Death system + LevelCompleteUI landed 2026-07-24** (`0780a0c` → `d0b3ad4`): tilemap-based spike death zones, level reset on `Player.died`.

**Major design pivot 2026-07-25** — the level no longer rotates. Instead, the player's *perception* rotates: gravity direction, camera rotation, and gravity-relative input all stay locked to the player's frame. The level stays static; the world around the player appears to shift because the camera tweens to keep "down" pointing down on screen. Simpler implementation, no per-frame rotation math, no rotation-frame collision.

- **Phase 1 — cut rotation** (`e93eb10`): Removed `RotatingLevelComponents` wrapper + all moving-platform scripts/scenes (later re-added in v2). TileMapLayer + Flag are now direct children of Main.
- **Phase 2 — gravity rotation** (`ecc07f6` + fix `09fd3cc`): `Player.gravity_direction` rotates 90° CW on each `ClockUI.countdown_zero`. Applied to gravity, jump, down-boost, slope-slide, and `up_direction` (so `move_and_slide` uses the correct "up").
- **Phase 3 — camera rotation** (`e909f73` + fix `9dd3329`): `Camera2D` created programmatically as child of Player (follows automatically). `_rotate_gravity_cw()` tweens `_camera.rotation` to `gravity_direction.angle() - PI/2` over `camera_rotation_duration` seconds (default 0.25s). Fixes: `Camera2D.ignore_rotation = false` + `make_current()` (the tween was no-op'ing visually otherwise), plus shortest-arc delta so the camera doesn't spin 270° on the third tick.
- **Phase 4 — gravity-relative input** (`11a46fa`): `right_direction := gravity_direction.rotated(-PI/2)`. Lateral velocity projected onto right direction. "Press right" = right from the player's perspective, including walking up walls and along ceilings.

**Moving platforms v2 (gravity-driven)** (`405cc1d` + `2932d97` + `e52bb04`): platforms project gravity onto their rail axis — parallel = motion (WEIGHT: in gravity direction; BUOYANT: opposite), perpendicular = no motion. This gives "every two ticks" motion naturally, since gravity rotates 90° per tick and alternates between parallel and perpendicular to a given rail axis. Inspector exposes `motion_type` (WEIGHT/BUOYANT), `axis` (X/Y), `rail_length_units` (32px tile units), `starting_position` (0..1 slider), `motion_speed`. `Line2D` sibling shows the rail extent in the editor via `@tool` + setter-driven point updates.

**Other systems** (unchanged from skeleton follow-ups): `level_complete_ui.tscn` (fade-in win screen); `game_complete_ui.tscn` (end-game screen); `pause_menu.tscn` (ESC-toggled); `level_select.tscn` (L1/L2/L3 picker with completion state); `settings.tscn` (volume sliders wired to AudioServer, persistence pending).

## Concept

A single-screen platformer where a **clock counts down** in the top center of the screen. When it hits zero, **gravity rotates 90° clockwise** — and the camera tweens with it, so the player's "down" stays pointing down on screen while the world around them shifts. Input is gravity-relative: pressing right always means "right from the player's perspective", which after a 90° gravity rotation is now perpendicular to what it was.

The countdown IS the game: each tick rotates gravity, so the safe floor you were standing on becomes a wall, then a ceiling, then the other wall — but your muscle memory of "press right to go right" still works because the input frame rotated with you. Platforms feel gravity-driven too: a "weight" platform on a vertical rail falls; rotate gravity 90° and it now moves horizontally in your new frame.

The player is a small blob (sprite art later by Jason in LibreSprite). Levels are one screen — no scrolling. The whole game reads at a glance: clock, blob, flag, platforms.

## Core Loop

1. **Read** the level — see where the flag is relative to the player and the platforms.
2. **Move** with simple platformer controls (left/right + jump). Input is gravity-relative: "right" is always the player's right, regardless of which way gravity currently points.
3. **Watch the clock** — when it hits zero, gravity rotates 90° CW. The camera tweens to match (~0.25s), keeping your apparent "up" pointing up on screen.
4. **Adapt** — what was a floor is now a wall, but your buttons still work because the input frame rotated with you. Re-plan your route.
5. **Reach the flag** — touch it to win the level.
6. **Restart or advance** — death resets the level; reaching the flag advances to the next (L1 → L2 → L3 → end).

## Locked Mechanics

- **Single screen** — no scrolling, no transitions. One screen = one level.
- **Clock is the timer and the trigger.** When it hits zero, gravity rotates 90° CW (camera tween tracks it).
- **Gravity-driven platforms.** Platforms move only when gravity is along their rail axis (every two ticks for a given platform, alternating active/inactive). WEIGHT falls with gravity; BUOYANT rises against it.
- **Gravity-relative input.** The player presses "right" and goes right in their own frame, regardless of world orientation. No mental remapping required.
- **Win by touching the flag.** Touch-to-win, no additional interaction.
- **Death = full level reset.** Player respawns at spawn, clock resets to 10, no checkpoints. Levels are short, so the reset cost is fine.
- **Levels inherit from a single template.** All 3 levels (L1/L2/L3) are inherited scenes from `scenes/level_template.tscn` — same architecture, only the level-specific bits (tiles, flag position, player spawn, clock duration) vary.
- **Polish matters even for the jam.** Menu + level select get styled buttons, fade transitions, hover/click feedback — not just functional gray buttons. (Per Jason, 2026-07-23.)

## Open Questions

- **Clock duration.** 10s default for L1; can vary per level via `@export var STARTING_SECONDS` on the ClockUI node. Lock in when we playtest L1.
- **Tilemap source.** Jason looking at open-source options (Kenney is the strongest free source — CC0, no attribution hassle). OpenGameArt + itch.io packs as alternatives. Lock in once chosen — affects tile size, palette, what the TileSet looks like.
- **Platform rhythm tuning.** With gravity rotating every 10s and a platform alternating active/inactive per tick, each active period is up to 10s. Tune `motion_speed` and `rail_length_units` per level so the active period is long enough to be a puzzle, not so long it never reaches an endpoint between ticks. *Decided not to add per-platform motion during the inactive phase (no carry-over momentum, etc.); Jason said "may add later" (2026-07-25).*

## Technical Approach: Rotate the Player's Frame, Not the Level

The clock is the timer and the trigger. When it hits zero, three things happen together (all driven by the same `Player._rotate_gravity_cw()`):

1. **Gravity rotates.** `Player.gravity_direction` rotates 90° CW. Used by the player's gravity (`velocity += gravity_direction * gravity_strength * delta`), jump (`gravity_direction * JUMP_VELOCITY`), down-boost, slope-slide, and `up_direction` (so `move_and_slide` knows the new "up" for collision resolution and slope sliding).
2. **Camera tweens to match.** `_camera.rotation` tweens to `gravity_direction.angle() - PI/2` over `camera_rotation_duration` seconds (default 0.25, inspector-tunable). After a 90° CW gravity rotation, the camera also rotates 90° CW, so world +x (where gravity now points) appears at the bottom of the screen. Visually, the world "shifts" — but the player stays upright.
3. **Input remaps to gravity-relative.** `right_direction := gravity_direction.rotated(-PI/2)`. Lateral velocity is projected onto right direction. After gravity rotates 90°, "right" is now perpendicular to what it was — but it always means "the player's right", which is the natural interpretation for someone holding a controller.

**Why this design over rotating the level:** simpler implementation (no rotation-frame collision, no per-platform-per-tick rotation math, no separate `RotatingLevelComponents` wrapper). The visual feel is different — the world appears to "shift" rather than "tumble" — but the puzzle is the same: each tick changes the geometry from the player's perspective, so route planning has to adapt.

**Why `Camera2D` as a programmatic child of `Player`, not in the scene:** the camera follows the player automatically (parent-child transform), and rotates with the player (well, with the player's `gravity_direction` via the tween). No camera math needed; no hand-positioned Camera2D in the level scene.

**Why input is gravity-relative, not world-relative:** with world-relative input, after a 90° rotation the player's "press right" would now move them up the wall — confusing and requires mental remapping per tick. Gravity-relative input means the player always presses "right" and goes "right from where they're facing", which is the natural expectation for any platformer.

## Levels / Teaching Ramp

Single-screen levels, each inherits from `scenes/level_template.tscn` and only varies the level-specific bits. The teaching ramp is mostly about level design — introducing platform layouts that make rotation a meaningful puzzle.

- **L1: First rotation.** One straight gap the player needs to cross. After one rotation, the gap is now a wall to climb. Goal: prove the mechanic is readable end-to-end.
- **L2: Corner puzzle.** Two platforms at right angles. Player must wait for a rotation to make the second platform reachable.
- **L3: Multi-step.** Three or four rotations needed. Pattern emerges: route through the level by sequencing your moves between ticks.

## Systems

Five cross-level systems, designed up-front so they slot into the level template cleanly.

### Victory Flag

- `flag.tscn` — Area2D root with `CollisionShape2D` (rectangle) + `Polygon2D` visual (placeholder until art lands).
- Detects the player via `body_entered` + `is_in_group("player")` check (player was added to the group in Task 1 specifically to support this — per the MEMORY.md lesson on co-adding group checks).
- Emits a `player_won` signal.
- The level scene's `level.gd` catches the signal and runs the win flow: stop the clock, fade in `LevelCompleteUI`, wait for input, advance to the next level.
- Touch-to-win only. No "lower the flag" animation, no collectible sub-flags.

### Death System

- Death sources are spike tiles on the TileMap, marked via a dedicated `physics_layer_1` ("death") on the TileSet. `physics_layer_1/collision_layer = 2` is the death-detection bitmask; spike tiles get a `physics_layer_1/polygon_0/points` collision shape in the TileSet. Spike tiles may also keep their `physics_layer_0` polygon (physical obstacle you can't walk through) or omit it (pit-style: walk through, die).
- **Spike design rule:** the `physics_layer_1` (death) polygon must extend at least slightly past the `physics_layer_0` (solid) polygon in one direction. If the two polygons are the same size and shape, the player's CharacterBody2D lands on the solid surface tangent to it — the Area2D never overlaps the body, so `body_entered` doesn't fire. Make the death polygon larger (or the physics polygon smaller) so the player can step *into* the death area when standing on the physics surface. (Discovered the hard way, 2026-07-24 — Jason's first attempt had matching-size polygons, no death triggered.)
- The Player has a child `Area2D` ("DeathDetector") with `collision_mask = 2` and a `CollisionShape2D` mirroring the player's body. When a body on the death layer overlaps, `body_entered` fires and the death flow starts.
- Death flow: `_is_dying` flag freezes the player (`_physics_process` early-returns) → `modulate` flashes red for `DEATH_FLASH_TIME` (0.1s) → `visible = false` hides the player for `DEATH_HOLD_TIME` (0.2s) → `Player.died` signal is emitted → `level.gd` catches the signal and `get_tree().reload_current_scene()` resets the level.
- Full level reset on every death, no checkpoints. Levels are short enough that the cost is fine and the design is simpler.
- To add a spike to a level: open the TileSet in the editor, pick a spike-shaped tile, add a `physics_layer_1/polygon_0/points` collision shape on it. Then paint that tile in the level's TileMapLayer (the same one that handles solid collision). No code changes needed for any new spike.

### Moving Platforms

Two scene presets, both driven by `scripts/platform.gd`:
- `scenes/platform.tscn` — 30×30 (1×1 tile)
- `scenes/platform_2x1.tscn` — 30×60 (2 tiles perpendicular to the rail, 1 tile along)

Direction (`axis` + `motion_type`) and rail length (`rail_length_units`) are just per-instance inspector values, so the OLD 4-preset (WEIGHT_Y/X, BUOYANT_Y/X) scheme is collapsed to one script + two scene variants. The script auto-detects wide variants from the initial CollisionShape2D size (width != height) and swaps width/height when `axis` changes in the inspector, so the long side stays perpendicular to the rail.

**Spike platforms** ("kill-spikes" on a chosen side): both scene presets ship a `SpikesArea` StaticBody2D child of AnimatableBody2D with `collision_layer = 2` (matches the player's `DeathDetector` mask). Two new @export vars on the script: `has_spikes: bool` (toggle the spikes on/off) and `spike_direction: SpikeDirection` (UP/DOWN/LEFT/RIGHT — see the script doc for orientation semantics). When enabled, the script populates a CollisionPolygon2D + Polygon2D with 3 triangular spikes along the chosen side, each peak 30 px out from the platform's edge. For the 30x60 variant, the side length adapts to the platform's current orientation (axis=Y → long side is the spike side; axis=X → short side), so the spike count and width track the geometry automatically.

**Architecture** (Node2D wrapper + AnimatableBody2D child):

```
Platform (Node2D + script)
└── AnimatableBody2D
    ├── CollisionShape2D (RectangleShape2D, sized in editor)
    └── Polygon2D (placeholder visual; Sprite2D slot ready for real art)
```

The wrapper Node2D exists for editor ergonomics — the `CollisionShape2D` hijacks the drag handle if it's directly on the `AnimatableBody2D`, and the inspector on a bare `AnimatableBody2D` is empty. The script lives on the wrapper.

**Why AnimatableBody2D over the OLD `RigidBody2D` + freeze + KINEMATIC:** AnimatableBody2D is purpose-built for kinematic moving bodies (position changes via direct `position = X` work and are synced to physics automatically). Less configuration than the freeze trick.

**Motion logic (gravity-driven):**

The platform projects `Player.gravity_direction` onto its rail axis each tick:

- Parallel (|dot| > 0.5) → platform moves. `motion_type = WEIGHT`: motion in gravity direction. `motion_type = BUOYANT`: motion opposite (sign flipped). Direction reverses when gravity rotates 180° (every 2 ticks for a given platform).
- Perpendicular (|dot| < 0.5) → platform stays still.

This naturally gives "every two ticks" motion — gravity rotates 90° per tick and alternates between parallel and perpendicular to a given rail axis, so the platform is active on every other tick. No explicit "every 2 ticks" reversal logic; it falls out of the gravity projection.

At endpoints, `t` clamps (no ping-pong). The platform waits for the next active tick to reverse direction. Tune `motion_speed` and `rail_length` per level so the active period is long enough to be a puzzle, not so long it never reaches an endpoint between ticks.

**Listener pattern:** platform listens to `Player.gravity_changed` signal (not `ClockUI.countdown_zero` directly). The Player emits `gravity_changed(new_direction)` after rotating gravity; platforms compute their motion direction from the new gravity. Same sibling-lookup pattern (`get_parent().get_node_or_null("Player")`) as before, but decouples from the tick stream.

**@export tunables (on wrapper):**

- `motion_type: MotionType` (enum: WEIGHT / BUOYANT, default WEIGHT)
- `axis: Axis` (enum: X / Y, default Y) — X = horizontal rail (along +x), Y = vertical rail (along +y, i.e., downward in Godot screen coords)
- `rail_length_units: int` (default 3, range 1–16) — multiples of 32px (snaps to grid by design)
- `starting_position: float` (default 0.0, range 0..1 slider)
- `motion_speed: float` (default 60.0, px/s)

Setters on `axis`, `rail_length_units`, and `starting_position` call `_update_rail_preview()` + `_update_position()` so inspector changes show up live in the 2D editor.

**Editor experience:** drop the scene into Main directly (no `RotatingLevelComponents` wrapper to live under — that wrapper doesn't exist anymore). Drag the wrapper for the anchor; override `rail_end` for the other endpoint. For 32×64 variants: edit the `Sprite2D` texture and `CollisionShape2D` shape size on that instance. No scene duplication needed.

**Editor-visible rail preview:** `Line2D` sibling of `AnimatableBody2D`, points updated by setters, light yellow (width 2, alpha 0.8). The script uses `@tool` so setters fire and trigger viewport redraws in the editor; `Engine.is_editor_hint()` gates the runtime-only code (signal connection, `_physics_process` lerp).

**Reset on level reload:** `_ready()` resets `t = starting_position` (clamped) and the `AnimatableBody2D`'s `position` to `rail_direction * (rail_length * t)`. Death flow (`get_tree().reload_current_scene()`) automatically calls `_ready()` on the new instance, so the platform returns to its starting position.

### Main Menu + Level Select

- Separate scenes: `main_menu.tscn` (start) → click to start → `scenes/levels/L1.tscn` → ... → `scenes/levels/L3.tscn` → end screen.
- Transitions via `get_tree().change_scene_to_file(...)`.
- **Eventually:** real level select screen showing L1/L2/L3 with completion state. For the jam scope, just start → L1 → L2 → L3.
- **Polish matters** (per Jason, 2026-07-23): styled buttons, hover/click feedback, fade transitions between screens. Don't ship unstyled gray buttons.

### Level Template (Godot Inherited Scenes)

- `scenes/level_template.tscn` is the parent scene. It contains the full level architecture: `Level` (Node2D + `level.gd` orchestrator script), `TileMapLayer` (empty, ready to paint — child of `Main`), `Flag` (child of `Main`), `Player`, `ClockUI`, `LevelCompleteUI`.
- Each level (`L1.tscn`, `L2.tscn`, `L3.tscn`) is created via **File → New Inherited Scene from `level_template.tscn`**. Editing the inherited scene only touches level-specific bits: tile placements, Flag position, Player spawn, ClockUI's `STARTING_SECONDS`.
- **Why inherited scenes vs. copy-paste:** changes to the template (e.g., adding the death system later) propagate to all levels automatically. No risk of forgetting to update L2 when L1 gets a new feature. For 3 levels it's marginal benefit, but it pays off fast as we iterate.

## Tech Stack

- **Engine:** Godot 4.7 (2D), Forward+ renderer, Jolt 3D physics (default; 2D uses Godot Physics 2D which is unaffected by the Jolt setting).
- **Language:** GDScript.
- **Art:** Placeholder shapes during development; final pixel art by Jason in LibreSprite, dropped into `assets/sprites/`.
- **Tilemaps:** TBD — Jason evaluating open-source tilesets (Kenney is the strongest free source — CC0, no attribution hassle). Lock in once chosen.
- **Project structure:** Each level is an inherited scene from `scenes/level_template.tscn`. Levels live in `scenes/levels/`.

## MVP (Minimum Viable Product)

Skeleton (shipped 2026-07-23):

- [x] Clock UI (CanvasLayer + Label, top center, 10s countdown, `@export var STARTING_SECONDS`, pause/resume for the win flow)
- [x] Player blob (CharacterBody2D, placeholder Polygon2D visual, left/right + jump + gravity, in "player" group)
- [x] ~~`RotatingLevelComponents` rotation~~ — *removed in Phase 1 (commit `e93eb10`); replaced by gravity/camera/input rotation on the player frame*
- [x] `flag.tscn` (Area2D + Polygon2D visual + `player_won` signal, `body_entered` filtered via `is_in_group("player")`)
- [x] `level.gd` orchestrator (win flow → `LevelCompleteUI.show_win_screen()` → `await continue_pressed` → `change_scene_to_file(next_level_path)`; death flow → `get_tree().reload_current_scene()` on `Player.died`)
- [x] `scenes/level_template.tscn` (parent scene; `scenes/main.tscn` is a pass-through)
- [x] `scenes/main.tscn` is a thin pass-through to the template

Skeleton follow-ups:

- [ ] Swap Polygon2D player visual for AnimatedSprite2D when art lands

Phase 2/3/4 (gravity/camera/input, 2026-07-25):

- [x] **Gravity rotation.** `Player.gravity_direction` rotates 90° CW on each `countdown_zero`. Applied to gravity, jump, down-boost, slope-slide, `up_direction`. (`ecc07f6` + `09fd3cc`)
- [x] **Camera rotation.** `Camera2D` child of Player, tweens to `gravity_direction.angle() - PI/2` over `camera_rotation_duration` (default 0.25s, inspector-tunable). (`e909f73`)
- [x] **Camera fixes.** `Camera2D.ignore_rotation = false` + `make_current()` so the tween actually drives the view; shortest-arc delta so the camera doesn't spin 270° on the third tick. (`9dd3329`)
- [x] **Gravity-relative input.** `right_direction := gravity_direction.rotated(-PI/2)`; lateral velocity projected onto right. "Press right" = right from the player's perspective. (`11a46fa`)

Systems (unchanged from skeleton follow-ups):

- [x] `flag.tscn` (Area2D + visual + `player_won` signal)
- [x] `level.gd` orchestrator (win flow → `LevelCompleteUI.show_win_screen()` → `await continue_pressed` → `change_scene_to_file(next_level_path)`; death flow → `get_tree().reload_current_scene()` on `Player.died`)
- [x] `scenes/level_template.tscn` (parent scene; `scenes/main.tscn` is a pass-through)
- [x] `level_complete_ui.tscn` (fade-in win screen — replaces the `print()` placeholder in `level.gd`)
- [x] `game_complete_ui.tscn` (end-game screen with "Game Complete!" title + "Back to Main Menu" button; shown when L3 wins since there's no next level)
- [x] `pause_menu.tscn` (ESC-toggled pause menu with Resume / Restart / Back to Main Menu; uses `get_tree().paused = true` to freeze the game)
- [x] `settings.tscn` (Master / Music / SFX volume sliders wired to AudioServer; persistence still pending)
- [x] `main_menu.tscn` (styled Start / Settings / Level Select buttons; no fade transition yet — `change_scene_to_file` is instant)
- [x] `level_select.tscn` (3-button picker: L1 / L2 / L3 + Back; completion state via ProgressTracker autoload; in-memory only, resets per launch)

Moving platforms v2 (gravity-driven, 2026-07-25):

- [x] **`scenes/platform.tscn`** + **`scripts/platform.gd`** — AnimatableBody2D kinematic carrier, scripted lerp + gravity-projection motion. Inspector: `motion_type`, `axis`, `rail_length_units` (32px units), `starting_position` (0..1 slider), `motion_speed`. `Line2D` sibling for editor-visible rail preview. (`405cc1d`)
- [x] **Editor reactivity.** Setters use `get_node_or_null` (not `@onready`); script uses `@tool` + `Engine.is_editor_hint()` gates so rail preview and starting position update live in the editor. (`2932d97` + `e52bb04`)

Levels (placeholder tilemaps until Jason picks a tileset):

- [ ] L1 playable end-to-end (via inherited scene from template)
- [ ] L2 playable end-to-end
- [ ] L3 playable end-to-end

## Out of Scope (This Jam)

- Enemies, powerups.
- Multiple flags per level / branching paths.
- Persistent unlocks / meta-progression.
- Custom rotation angles (only 90° / cardinal directions).
- Audio (defer to last if time permits; not part of MVP).

## Risks

- **Platform rhythm tuning.** With gravity rotating every 10s and platforms alternating active/inactive, each active period is up to 10s. Tune `motion_speed` and `rail_length` per level so the active period is long enough to be a puzzle. *Mitigation:* ship L1 with default values, playtest, adjust.
- **Tilemap dependency.** Level design can't start until tilemaps are picked. *Mitigation:* pick tileset early; build the level template with placeholder tiles in the meantime.
- **Polish overhead on menus.** "Don't skip polish" could eat time. *Mitigation:* polish the menu/select as a single design pass once they're functional, not iteratively per-feature.
- **Scope creep via hazards.** Death system is meant for spikes + pits; temptation to add moving hazards, projectiles, etc. *Mitigation:* stick to static spike tiles for the jam; defer anything else.

## Backlog

*(Two-tier: **In Flight** for active work, **TODO** for forward-looking features/art/music/UI/tuning. Prioritized within each section.)*

### In Flight

- [ ] **Tilemap setup** — Jason assigns a TileSet to the `TileMapLayer` in the template, paints wall tiles + L1/L2/L3 geometry
- [ ] `scenes/levels/L1.tscn`, `L2.tscn`, `L3.tscn` — inherited scenes from `level_template.tscn` with per-level tile data, Flag position, Player spawn, and `next_level_path` overrides

- [x] Death zone prototype (tilemap-based, `physics_layer_1` + DeathDetector Area2D + `Player.died` signal + level reset on death)
- [x] **Jason:** add a death polygon to a spike tile in the TileSet, then paint at least one spike in L1 so the flow is testable end-to-end (confirmed by Jason 2026-07-24: "I put the spike in the level earlier for testing and it works fine")
- [x] `level_complete_ui.tscn` (fade-in win screen — replaces the `print()` placeholder in `level.gd`)
- [x] `level_select.tscn` (L1/L2/L3 list with completion state)
- [x] Gravity rotation + camera rotation + gravity-relative input (Phase 2/3/4)
- [x] Moving platforms v2 (gravity-driven motion, AnimatableBody2D + Line2D rail preview)
- [ ] Audio (SFX for tick, win, die, rotate)
- [ ] Visual polish on rotation (camera shake? quick zoom? particles?)
- [ ] AnimatedSprite2D swap when player art lands
- [ ] Tutorial / first-30-seconds UX
- [ ] Jam submission checklist — web build, trailer, itch.io page

### TODO

Forward-looking, prioritized within each category. Pick from here when in-flight items settle.

#### Features and Mechanics

- [ ] **Pause during gravity change** — so the platform doesn't keep moving during the camera tween. Currently motion continues uninterrupted; Jason said "may add later" (2026-07-25).
- [ ] **Visible square for level design** — debug overlay showing the play area boundary, toggleable in the inspector. Useful for placing tiles precisely during L1–L3 painting.
- [ ] **Platform motion during inactive ticks** — carry-over momentum, or similar, to make the platform feel less "binary". Jason said "may add later" (2026-07-25).

#### Art / Design

- [ ] Finalize character sprite and animations (LibreSprite, replace Polygon2D placeholder)
- [ ] Settle on tilemap spritesheet
- [ ] VFX, shaders, particle effects (TBD — low priority until core loop is solid)
- [ ] Replace digital countdown with analog clock face
- [x] **Level transition visual** — `scripts/level.gd` adds a fullscreen ColorRect on CanvasLayer 100 (`_create_fade_overlay`) animated by tween. `_fade_in()` runs in `_ready()` (level fades in on load); `_fade_out()` awaits before `change_scene_to_file` (so the screen is black when the old scene tears down). 0.4s duration.

#### Music

- [ ] One song at 120bpm, changes feel every 10 seconds (synced to clock cycles — section change on each `countdown_zero` signal)
- [ ] **Player action SFX** — jump and land sounds. The current SFX list covers "tick, win, die, rotate" but misses the two most frequent platformer actions. ~2-3 lines in `player.gd` (play on jump, play on `is_on_floor` transition).

#### Level Design

- [ ] Build 3–5 levels of increasing complexity (L1=First rotation, L2=Corner puzzle, L3=Multi-step, possibly L4–L5)

#### UI Elements

- [x] Pause menu: Back to Main Menu, Settings, Restart buttons
- [x] **Pause menu integration** — `get_tree().paused = true` freezes _process / _physics_process on all PAUSABLE nodes (default); _input still fires so the menu's buttons stay interactive. Resume / Restart / Main Menu unpause first to avoid inheriting a paused state in the next scene.
- [x] Settings menu:
  - [x] **Audio bus setup** — `default_bus_layout.tres` declares Master / Music / SFX buses; Music + SFX both send to Master.
  - [x] Audio: master, music, SFX volume (linear 0..100 slider -> -60..0 dB)
  - [x] **Settings persistence** — `ConfigFile`-based save/load in `scripts/settings.gd` (`_save_settings` on every slider change + `_load_settings` on entry, applied via `set_value_no_signal` to avoid re-triggering save during load). Persists master/music/SFX volume + chromatic aberration intensity to `user://settings.cfg`. Already implemented; README was stale.
  - [ ] Visual: VFX intensity, brightness, etc
- [ ] **Credits screen** — about the game / music credits / open-source asset attribution (Kenney tilesets, etc).

#### Tuning

- [ ] Gravity (`player.gd` — currently 1500, bumped from 980 on 2026-07-25 per Jason's slope-slide playtest)
- [ ] Player move speed, run/air accel, jump velocity, ground deceleration (`player.gd` exports: RUN_SPEED, RUN_ACCEL, AIR_ACCEL, JUMP_VELOCITY, GRAVITY, GROUND_DECEL)
- [ ] Down-boost magnitude for slope momentum (`player.gd:DOWN_BOOST` — currently 1500, ~1.5x GRAVITY)
- [ ] Friction values per surface (TileSet custom data — set after spritesheet is settled)
- [ ] Camera rotation duration (`camera_rotation_duration` — default 0.25s)
- [ ] Platform `motion_speed` and `rail_length_units` defaults — currently 60 px/s and 3 (96px). Tune per level for puzzle rhythm.