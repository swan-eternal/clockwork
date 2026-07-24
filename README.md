# Clockwork

> **GMTK Game Jam 2026 — Theme: Countdown**

## Status

Skeleton shipped 2026-07-23 (commits `532a05a` → `55b2066` → `90995a8` → `f11b24e` → `dfcad97` → `ce685fb`): player (CharacterBody2D + collision + box visual, in "player" group), clock UI (CanvasLayer + Label counting 10→0), `RotatingLevelComponents` rotation (90° per clock tick, animated via Tween, speed tunable via `@export var rotation_speed` on the node). **Refactor + system layers landed same day** (`8b23903` → `aec3d3d` → `b021b65`): wrapper renamed `Walls` → `RotatingLevelComponents` (rotating-by-default — anything that's "part of the level" is a child of this node, so it spins with the world); the 4 StaticBody2D walls were replaced with an empty `TileMapLayer` (Jason paints wall tiles + level geometry in the tilemap); `flag.tscn` + `level.gd` orchestrator added (touch-to-win → clock pause → wait for input → `change_scene_to_file(next_level_path)`); `scenes/level_template.tscn` built as the parent scene L1/L2/L3 inherit from; `scenes/main.tscn` is now a thin pass-through to the template. **Next layer:** tilemap setup (Jason assigns a TileSet in the editor and paints), then `level_complete_ui.tscn`, death system, main menu, level select.

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
- [x] Clock UI (CanvasLayer + Label, top center, 10s countdown, `@export var STARTING_SECONDS`, pause/resume for the win flow)
- [x] Player blob (CharacterBody2D, placeholder Polygon2D visual, left/right + jump + gravity, in "player" group)
- [x] `RotatingLevelComponents` rotation (90° per clock tick, animated via Tween, speed tunable via `@export var rotation_speed` on the node)
- [x] `flag.tscn` (Area2D + Polygon2D visual + `player_won` signal, `body_entered` filtered via `is_in_group("player")`)
- [x] `level.gd` orchestrator (catches `Flag.player_won` → pause clock → await `ui_accept` → `change_scene_to_file(next_level_path)`)
- [x] `scenes/level_template.tscn` (parent scene: Main + `RotatingLevelComponents` + TileMapLayer + Flag + Player + ClockUI — what L1/L2/L3 inherit from)
- [x] `scenes/main.tscn` is a thin pass-through to the template

Skeleton follow-ups:
- [ ] Input remapping so "right" feels right after rotation (GravityDirection enum, ~20 lines in player.gd)
- [ ] Swap Polygon2D player visual for AnimatedSprite2D when art lands

Systems:
- [x] `flag.tscn` (Area2D + visual + `player_won` signal)
- [x] `level.gd` orchestrator (win flow done; death flow pending — needs `Player.died` signal)
- [x] `scenes/level_template.tscn` (parent scene; `scenes/main.tscn` is a pass-through)
- [ ] Death zones (Area2D group + spike prototype + `Player.died` signal on the player)
- [ ] `level_complete_ui.tscn` (CanvasLayer + fade-in animation + click-to-continue — replaces the `print()` placeholder)
- [ ] `main_menu.tscn` (styled start button + fade transition)
- [ ] `level_select.tscn` (L1/L2/L3 list with completion state — built before final ship)

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

*(Two-tier: **In Flight** for active work, **TODO** for forward-looking features/art/music/UI/tuning. Prioritized within each section.)*

### In Flight

- [ ] **Tilemap setup** — Jason assigns a TileSet to the `TileMapLayer` in the template, paints wall tiles + L1/L2/L3 geometry
- [ ] `scenes/levels/L1.tscn`, `L2.tscn`, `L3.tscn` — inherited scenes from `level_template.tscn` with per-level tile data, Flag position, Player spawn, and `next_level_path` overrides
- [ ] Input remapping (GravityDirection enum + remapped player input)
- [ ] Death zone prototype + spike tile (Area2D in `death_zones` group) + `Player.died` signal
- [ ] `level_complete_ui.tscn` (fade-in win screen — replaces the `print()` placeholder in `level.gd`)
- [ ] `level_select.tscn` (L1/L2/L3 list with completion state)
- [ ] Audio (SFX for tick, win, die, rotate)
- [ ] Visual polish on rotation (camera shake? quick zoom? particles?)
- [ ] AnimatedSprite2D swap when player art lands
- [ ] Tutorial / first-30-seconds UX
- [ ] Jam submission checklist — web build, trailer, itch.io page

### TODO

Forward-looking, prioritized within each category. Pick from here when in-flight items settle.

#### Features and Mechanics

- [ ] **Visible square for level design** — debug overlay showing the play area boundary, toggleable in the inspector. Useful for placing tiles precisely during L1–L3 painting.
- [ ] **Moving platforms** — weighted platforms (slide down under gravity) and balloon platforms (rise against gravity). Both are children of `RotatingLevelComponents` so they rotate with the world.
- [ ] **Pause countdown clock while rotation is happening** — so the player doesn't lose time during the rotation animation. Currently the clock continues ticking during the tween.
- [ ] **Game over / retry UI** — when the player dies, what shows? Currently `level.gd` just resets silently. A brief "you died" / "spikes!" overlay for ~0.5s before the reset would make death feel intentional rather than a glitch.

#### Art / Design

- [ ] Finalize character sprite and animations (LibreSprite, replace Polygon2D placeholder)
- [ ] Settle on tilemap spritesheet
- [ ] VFX, shaders, particle effects (TBD — low priority until core loop is solid)
- [ ] Replace digital countdown with analog clock face
- [ ] **Level transition visual** — fade-to-black on win and fade-in on next level. Currently `change_scene_to_file` is instant, which makes the win flow feel abrupt and exposes any scene-loading hitches.

#### Music

- [ ] One song at 120bpm, changes feel every 10 seconds (synced to clock cycles — section change on each `countdown_zero` signal)
- [ ] **Player action SFX** — jump and land sounds. The current SFX list covers "tick, win, die, rotate" but misses the two most frequent platformer actions. ~2-3 lines in `player.gd` (play on jump, play on `is_on_floor` transition).

#### Level Design

- [ ] Build 3–5 levels of increasing complexity (L1=First rotation, L2=Corner puzzle, L3=Multi-step, possibly L4–L5)

#### UI Elements

- [ ] Pause menu: Back to Main Menu, Settings, Restart buttons
- [ ] **Pause menu integration** — wiring (input suppression, animation pause, gameplay freeze). The visual design is in the pause menu item above; this is the actual gameplay integration.
- [ ] Settings menu:
  - [ ] **Audio bus setup** — actual `AudioBus` entries in `project.godot` for master/music/SFX. Without these, the audio sliders are non-functional. ~5min setup once you decide on bus names.
  - [ ] Audio: master, music, SFX volume
  - [ ] **Settings persistence** — save audio/volume/brightness/VFX to disk so they survive across game launches. ~10 lines with `ConfigFile`.
  - [ ] Visual: VFX intensity, brightness, etc
- [ ] **Credits screen** — about the game / music credits / open-source asset attribution (Kenney tilesets, etc).

#### Tuning

- [ ] Gravity (`player.gd` — currently 980)
- [ ] Player move speed, jump velocity, ground deceleration (`player.gd` exports)
- [ ] Down-boost magnitude for slope momentum (`player.gd:DOWN_BOOST` — currently 1500, ~1.5x GRAVITY)
- [ ] Friction values per surface (TileSet custom data — set after spritesheet is settled)
- [ ] Rotation timer and speed (`RotatingLevelComponents.rotation_speed` + `ClockUI.STARTING_SECONDS`)
