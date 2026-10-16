# Dead Blocks

A first-person voxel zombie survival-craft game built in Godot 4.7.2 (GDScript, no asset files). It mixes a Minecraft-style block world, 7 Days to Die-style Blood Moon hordes, and ARK-style creatures. The goal is 4–8 player co-op on a dedicated server.

- **How the code works, and how to run, test and build it:** see [CLAUDE.md](CLAUDE.md).
- **Design decisions and the milestone plan:** see [DESIGN.md](DESIGN.md).

## Quick start
1. Install [Godot 4.7.2](https://godotengine.org/) (standard build, not .NET).
2. Open `project.godot` in Godot and press F5.

Automated playtest: `godot --headless --path . -- --autotest --seed=4242` (should end with `AUTOTEST DONE fails=0`).
