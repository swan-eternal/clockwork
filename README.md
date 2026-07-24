# Clockwork

> **GMTK Game Jam 2026 — Theme: Countdown**

## Status

Skeleton shipped 2026-07-23 (commits `532a05a` → `55b2066` → `90995a8` → `f11b24e` → `dfcad97` → `ce685fb`): player (CharacterBody2D + collision + box visual, in "player" group), 4 enclosing walls (square 568×568 inner play area), clock UI (CanvasLayer + Label counting 10→0), Walls rotation (90° per clock tick, animated via Tween, speed tunable via `@export var rotation_speed` on the Walls node). **Next layer:** tilemap-based levels (Jason evaluating open-source tilesets) + four system designs locked in below (victory flag, death, main menu + level select, level template).

## Concept

A single-screen platformer where a **clock counts down** in the top center of the screen. When it hits zero, **gravity rotates** — and the world tilts to match. Reach the flag. The countdown IS the game: each tick rewrites where "down" is, so the safe floor you were standing on becomes a wall, then a ceiling, then the other wall.

The player is a small blob (sprite art later by Jason in LibreSprite). Levels are one screen — no scrolling. The whole game reads at a glance: clock, blob, flag, platforms.

## Core Loop

1. **Read** the level — see where the flag is relative to the player and the platforms.
2. **Move** with simple platformer controls (left/right + jump). Gravity currently points one of the four cardinal directions.
3. **Watch the clock** — when it hits zero, the world rotates 90°. The blob falls toward the new "down".
4. **Adapt** — what was a floor is now a wall. Re-plan your route.
5. **Reach the flag** — touch it to win the level.
6. **Restart or advance** — death resets the level; reaching the flag advances to the next (L1 → L2 → L3 → end).

## Locked Mechanics

- **Single screen** — no scrolling, no transitions. One screen = one level.
- **Clock is the timer and the trigger.** When it hits zero, gravity rotates.
- **Rotating gravity is the only verb.** No enemies, no powerups in the jam scope. Hazards (spikes) exist for the death system but are static tiles, not actors.
- **Win by touching the flag.** Touch-to-win, no additional interaction.
- **Death = full level reset.** Player respawns at spawn, clock resets to 10, no checkpoints. Levels are short, so the reset cost is fine.
- **Levels inherit from a single template.** All 3 levels (L1/L2/L3) are inherited scenes from `scenes/level_template.tscn` — same architecture, only the level-specific bits (tiles, flag position, player spawn, clock duration) vary.
- **Polish matters even for the jam.** Menu + level select get styled buttons, fade transitions, hover/click feedback — not just functional gray buttons. (Per Jason, 2026-07-23.)

## Open Questions

- **Clock duration.** 10s default for L1; can vary per level via `@export var STARTING_SECONDS` on the ClockUI node. Lock in when we playtest L1.
- **Tilemap source.** Jason looking at open-source options (Kenney is the strongest free source — CC0, no attribution hassle). OpenGameArt + itch.io packs as alternatives. Lock in once chosen — affects tile size, palette, what the TileSet looks like.
- **Cumulative vs. resetting rotation.** Each tick rotates the world 90° from its current orientation (full revolution over 4 ticks) vs. snapping back to a fixed orientation each tick. **Leaning cumulative** — feels more chaotic and platformery.

## Technical Approach: Rotate the World (Around the Play Area Center)

The visual effect of "gravity rotates" is achieved by rotating the level wrapper (`Walls` Node2D) around its position `(576, 324)` — the play area center. Walls contain the 4 wall StaticBody2Ds at local positions `(-304, 0)`, `(304, 0)`, `(0, -304)`, `(0, 304)` so they spin in place. The Player, ClockUI, and (eventual) Camera2D are **siblings** of Walls, not children, so they stay in world / screen space — the world tumbles around them, not the other way around.

**Why pivot at the play area center, not at world origin:** the pivot has to be where the geometry is. With Walls at `(576, 324)` and walls in local coords near that, the frame spins in place. With Walls at `(0, 0)`, walls would have to be near origin (off-screen by default) and require a Camera2D + position shifting. The current setup needs no camera math. TileMapLayer doesn't change this — cell coordinates are local to the TileMapLayer's grid origin, set once and forgotten.

**Why we picked rotate-the-world over rotate-the-gravity-vector:** the visual drama of watching platforms tumble is what makes this concept feel like a game rather than a physics demo. Input remapping is a one-line lookup against a `GravityDirection` enum; the complication is small, the payoff large.

**Input remapping (TODO before L1 ships):** Player input is currently screen-relative, so pressing "right" after a 90° rotation sends the player in the wrong direction relative to the new ground. Needs remapping against a `GravityDirection` enum — about 20 lines in `player.gd`.

## Levels / Teaching Ramp

Single-screen levels, each inherits from `scenes/level_template.tscn` and only varies the level-specific bits. The teaching ramp is mostly about level design — introducing platform layouts that make rotation a meaningful puzzle.

- **L1: First rotation.** One straight gap the player needs to cross. After one rotation, the gap is now a wall to climb. Goal: prove the mechanic is readable end-to-end.
- **L2: Corner puzzle.** Two platforms at right angles. Player must wait for a rotation to make the second platform reachable.
- **L3: Multi-step.** Three or four rotations needed. Pattern emerges: route through the level by sequencing your moves between ticks.

## Systems

Four cross-level systems, designed up-front so they slot into the level template cleanly.

### Victory Flag

- `flag.tscn` — Area2D root with `CollisionShape2D` (rectangle) + `Polygon2D` visual (placeholder until art lands).
- Detects the player via `body_entered` + `is_in_group("player")` check (player was added to the group in Task 1 specifically to support this — per the MEMORY.md lesson on co-adding group checks).
- Emits a `player_won` signal.
- The level scene's `level.gd` catches the signal and runs the win flow: stop the clock, fade in `LevelCompleteUI`, wait for input, advance to the next level.
- Touch-to-win only. No "lower the flag" animation, no collectible sub-flags.

### Death System

- Death sources are `Area2D` nodes in the `death_zones` group. The first concrete instance will be spike tiles on the TileMap (custom metadata or a dedicated spike scene). Future pits, etc., follow the same pattern.
- Player's `_on_area_entered` checks `is_in_group("death_zones")` and calls `_die()`.
- Death flow: brief input disable → visual feedback (flash, hide) → reset the level (player position + clock back to 10).
- Full level reset on every death, no checkpoints. Levels are short enough that the cost is fine and the design is simpler.

### Main Menu + Level Select

- Separate scenes: `main_menu.tscn` (start) → click to start → `scenes/levels/L1.tscn` → ... → `scenes/levels/L3.tscn` → end screen.
- Transitions via `get_tree().change_scene_to_file(...)`.
- **Eventually:** real level select screen showing L1/L2/L3 with completion state. For the jam scope, just start → L1 → L2 → L3.
- **Polish matters** (per Jason, 2026-07-23): styled buttons, hover/click feedback, fade transitions between screens. Don't ship unstyled gray buttons.

### Level Template (Godot Inherited Scenes)

- `scenes/level_template.tscn` is the parent scene. It contains the full level architecture: `Level` (Node2D + `level.gd` orchestrator script), `RotatingLevelComponents` (Node2D + `rotating_level_components.gd` rotation script), `TileMapLayer` (empty, ready to paint — child of `RotatingLevelComponents`), `Flag` (child of `RotatingLevelComponents`), `Player`, `ClockUI`, `LevelCompleteUI`.
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
- [x] Clock UI (CanvasLayer + Label, top center, 10s countdown, `@export var STARTING_SECONDS`)
- [x] Player blob (CharacterBody2D, placeholder Polygon2D visual, left/right + jump + gravity, in "player" group)
- [x] 4 enclosing walls (StaticBody2D + Polygon2D visual, square 568×568 play area)
- [x] Walls rotation (90° per clock tick, animated via Tween, speed tunable via `@export var rotation_speed` on Walls)

Skeleton follow-ups:
- [ ] Input remapping so "right" feels right after rotation (GravityDirection enum, ~20 lines in player.gd)
- [ ] Swap Polygon2D player visual for AnimatedSprite2D when art lands

Systems (designed, not yet implemented):
- [ ] `flag.tscn` (Area2D + visual + `player_won` signal)
- [ ] `level.gd` orchestrator (catches flag/died signals, runs win/reset flow)
- [ ] Death zones (Area2D group + spike prototype)
- [ ] `level_complete_ui.tscn` (CanvasLayer + fade-in animation + click-to-continue)
- [ ] `main_menu.tscn` (styled start button + fade transition)
- [ ] `level_select.tscn` (L1/L2/L3 list with completion state — built before final ship)
- [ ] `scenes/level_template.tscn` (parent scene that L1/L2/L3 inherit from)

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

- **Input feel after rotation.** Without remapping, pressing "right" after a 90° rotation sends the player in the wrong direction. *Mitigation:* remap before building levels so playtesting is meaningful.
- **Tilemap dependency.** Level design can't start until tilemaps are picked. *Mitigation:* pick tileset early; build the level template with placeholder tiles in the meantime.
- **Polish overhead on menus.** "Don't skip polish" could eat time. *Mitigation:* polish the menu/select as a single design pass once they're functional, not iteratively per-feature.
- **Scope creep via hazards.** Death system is meant for spikes + pits; temptation to add moving hazards, projectiles, etc. *Mitigation:* stick to static spike tiles for the jam; defer anything else.

## Backlog

*(Grows as we work. Highest priority first.)*

- [ ] Input remapping (GravityDirection enum + remapped player input)
- [ ] `level.gd` orchestrator script (catches Flag.player_won, Player.died)
- [ ] `flag.tscn` (reusable flag area scene)
- [ ] `scenes/level_template.tscn` (parent scene for L1/L2/L3)
- [ ] Death zone prototype + spike tile (Area2D in `death_zones` group)
- [ ] `level_complete_ui.tscn` (fade-in win screen)
- [ ] `main_menu.tscn` (styled start button + fade transition)
- [ ] `level_select.tscn` (L1/L2/L3 list with completion state)
- [ ] Audio (SFX for tick, win, die, rotate)
- [ ] Visual polish on rotation (camera shake? quick zoom? particles?)
- [ ] AnimatedSprite2D swap when player art lands
- [ ] Tutorial / first-30-seconds UX
- [ ] Jam submission checklist — web build, trailer, itch.io page
