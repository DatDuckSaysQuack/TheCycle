# Extinction Cycle Prototype 0 (Godot 4.x)

A small 2D top-down god-game prototype where extinction is invoked by an unusual magical condition, not by a direct UI action.

## How to open/run

1. Install **Godot 4.x** (tested against the Godot 4 scene/script format).
2. Open Godot and click **Import**.
3. Select this folder (`TheCycle`) and import `project.godot`.
4. Run the project (F5).

## Controls

- **Build House** button: Adds one house to progress objective #1.
- **Reconciliation Pulse** button: Lowers conflict.
- **Left click on map (only during flood phase)**: Place magical barriers to slow the flood wall.

## Gameplay rules in prototype

1. Complete objectives:
   - Build 3 houses.
   - Keep at least 10 villagers alive.
   - Keep conflict below 50.
2. After objectives are complete, the world becomes extinction-vulnerable and a warning is shown.
3. If Polly is holding the yellow ball and stands on the marble rock for 5 seconds, extinction is invoked.
4. A flood wall moves left-to-right.
5. Place barriers to slow the flood.
6. If flood is held away from the settlement center for 30 seconds, world enters limbo survival state.
7. If flood reaches settlement center first, civilization is lost.

## Current limitations

- Single-scene architecture for clarity (not yet split into reusable components/systems).
- Villagers are simple circles represented as colored squares/placeholders (no pathfinding grid).
- No save/load, no audio, no economy/resource simulation.
- No advanced AI; movement is basic wandering/fleeing.
- Barrier effects are simple position-based flood slowdowns.

## Suggested next steps

- Replace placeholder rectangles with proper sprites/shapes and animations.
- Move logic into dedicated scripts: `GameState`, `VillagerController`, `FloodController`, `ObjectiveSystem`.
- Add nav/pathfinding and obstacle-aware fleeing.
- Add proper building placement UI on valid tiles.
- Expand objectives and events into a dynamic narrative system.
- Add restart/new-cycle flow and meta-progression.

<!-- test -->
