# Clockwork

> **GMTK Game Jam 2026 — Theme: Countdown**

## Status

Phase 0 (scaffolding). Godot 4.7 project initialized in `clockwork/`. README written, repo not yet initialized.

## Concept

A single-screen platformer where a **clock counts down** in the top center of the screen. When it hits zero, **gravity rotates** — and the world tilts to match. Reach the flag. The countdown IS the game: each tick rewrites where "down" is, so the safe floor you were standing on becomes a wall, then a ceiling, then the other wall.

The player is a small blob (sprite art later by Jason in LibreSprite). Levels are one screen — no scrolling. The whole game reads at a glance: clock, blob, flag, platforms.

## Core Loop

1. **Read** the level — see where the flag is relative to the player and the platforms.
2. **Move** with simple platformer controls (left/right + jump). Gravity currently points one of the four cardinal directions.
3. **Watch the clock** — when it hits zero, the world rotates 90° (default; see Open Questions). The blob falls toward the new "down".
4. **Adapt** — what was a floor is now a wall. Re-plan your route.
5. **Reach the flag** — touch it to win the level.

## Locked Mechanics

- **Single screen** — no scrolling, no transitions. One screen = one level.
- **Clock is the timer and the trigger.** When it hits zero, gravity rotates.
- **Rotating gravity is the only verb.** No enemies, no hazards, no powerups (this jam).
- **Win by touching the flag.** That's it.

## Open Questions

- **Clock duration.** 10s default, but probably needs to vary per level (or stay constant — decide by playtest).
- **Rotation amount per tick.** Defaulting to 90° (4 distinct gravity states per cycle). 180° is simpler (2 states) but less interesting. Lock once we have a test level.
- **Cumulative vs. resetting rotation.** Each tick rotates the world 90° from its current orientation (so over 4 ticks you've done a full revolution), vs. snapping back to a fixed orientation each tick. Cumulative feels more chaotic and platformery; resetting feels more predictable and timing-focused. **Leaning cumulative.**
- **Win condition strictness.** Reach the flag at any time during the countdown, OR reach it before N total rotations elapse (i.e. the clock also counts down to "level failed"). The first is pure puzzle; the second adds urgency. **Leaning pure puzzle** for the jam — keep it about reading the rotation, not reaction speed.
- **Number of rotations per level.** Some levels may need 1-2 rotations to solve; others may need 4-6. Decide per level once we know the mechanic's feel.

## Technical Approach: Rotate the World vs. Rotate the Gravity Vector

The visual effect of "gravity rotates" can be achieved two ways. Jason flagged this as an open decision; here's my recommendation:

### Option A: Rotate the level (world root Node2D), keep gravity static.

- The level root rotates 90° around the level's center. Platforms visually tilt and become walls / ceilings.
- Camera stays fixed (doesn't rotate with the world) so the player sees the tilt happen.
- Player input is remapped to the *current* gravity direction: pressing "right" always pushes the blob toward whatever is currently "down's right" in world space.
- Pros: visually striking — the whole world tumbles. Easy to reason about level geometry (each platform is a fixed child of the rotating world).
- Cons: input remapping needs care so the controls feel right after each rotation.

### Option B: Rotate the gravity vector, keep the level static.

- Level geometry never moves. The physics gravity vector rotates 90° around the level center. Player falls toward the new "down".
- Camera stays fixed (no rotation).
- Pros: simplest mechanically — input is always screen-relative. No remapping.
- Cons: less visually striking. The "world" doesn't visibly change; only the blob's fall direction does.

### Recommendation: Option A (rotate the world).

The visual drama of watching platforms tumble into new positions is what makes this concept feel like a game rather than a physics demo. Input remapping is a one-line lookup against a `GravityDirection` enum (`DOWN`, `LEFT`, `UP`, `RIGHT`). The complication is small; the payoff is large.

## Levels / Teaching Ramp

Single-screen levels, each builds on the previous. The mechanic is so simple that the **teaching ramp is mostly about level design** — introducing new platform layouts that make rotation a meaningful puzzle.

- **L1: First rotation.** One straight gap the player needs to cross. After one rotation, the gap is now a wall to climb. Goal: prove the mechanic is readable.
- **L2: Corner puzzle.** Two platforms at right angles. Player must wait for a rotation to make the second platform reachable.
- **L3: Multi-step.** Three or four rotations needed. Pattern emerges: route through the level by sequencing your moves between ticks.
- **L4+:** Jam scope permitting — more complex layouts, maybe a level where rotation goes BACKWARDS or skips.

## Tech Stack

- **Engine:** Godot 4.7 (2D), Forward+ renderer, Jolt 3D physics (default; 2D uses Godot Physics 2D which is unaffected by the Jolt setting).
- **Language:** GDScript.
- **Art:** Placeholder shapes during development; final pixel art by Jason in LibreSprite, dropped into `assets/sprites/`.
- **Project structure:** Single scene `main.tscn` per level (or one shared scene with level data). TBD once we have the player + clock working.

## MVP (Minimum Viable Product)

- [ ] Clock UI (label + countdown animation, top center of screen)
- [ ] Player blob (CharacterBody2D, placeholder circle, basic left/right + jump)
- [ ] Level rotation (90° per clock tick, smooth or snap)
- [ ] Gravity follows rotation (player falls toward new "down")
- [ ] Input remapping so controls feel correct post-rotation
- [ ] Flag (Area2D, touches → win)
- [ ] Win screen / next-level transition
- [ ] L1 playable end-to-end
- [ ] L2 playable end-to-end
- [ ] L3 playable end-to-end

## Out of Scope (This Jam)

- Enemies, hazards, powerups.
- Multiple flags per level / branching paths.
- Persistent unlocks / meta-progression.
- Audio (defer to last if time permits).
- Custom rotation angles (only 90° / cardinal directions).
- Variable clock duration (TBD — locked once we playtest L1).

## Risks

- **Input feel after rotation.** If "right" doesn't feel like "right" after a 90° rotation, the game is unplayable. *Mitigation:* remap early; playtest the input feel before building levels.
- **Rotation timing.** Too fast = chaotic, too slow = boring. *Mitigation:* make clock duration an @export on the level scene so we can tune in seconds.
- **Camera framing.** The blob can drift off-screen when gravity changes. *Mitigation:* Camera2D with limits tied to the level bounds, never rotates with the world.
- **Scope creep.** Tempting to add enemies or hazards once the basic loop works. *Mitigation:* MVP checklist is the contract; defer anything else.

## Backlog

*(Grows as we work. Highest priority first.)*

- [ ] Lock the 4 open questions above (clock duration, rotation amount, cumulative vs resetting, win strictness) — call it after L1 is playable.
- [ ] Decide the level-data model (one .tscn per level vs. data-driven)
- [ ] Audio (SFX for tick, win, rotate)
- [ ] Visual polish on rotation (camera shake? quick zoom?)
- [ ] More levels beyond L3 if jam scope allows
- [ ] Tutorial / first-30-seconds UX
- [ ] Jam submission checklist — web build, trailer, itch.io page