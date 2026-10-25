# Art credits

Everything in `assets/` is free to use (CC0 / public domain). Thanks to the authors.

## Textures — ambientCG (https://ambientcg.com), CC0 1.0

Combined into the files in `assets/textures/` by `tools/make_textures.py` (1K-JPG downloads):

| Used for | ambientCG material |
|---|---|
| Grass | Grass004 |
| Dirt | Ground067 |
| Stone (and the rock under the coal and iron ore spots) | Rock030 |
| Sand | Ground054 |
| Bedrock, forge top, Blood Forge top | Rock035 |
| Tree bark (log sides) | Bark014 |
| Planks, log ends (colour), workbench and bed sides | Planks037A |
| Workbench top | Planks023A |
| Cobblestone | PavingStones070 |
| Stone bricks, forge front; Blood Brick and the Blood Forge (tinted red) | Bricks076A |
| Reinforced wall | CorrugatedSteel009 |
| Wood Frame, Reinforced Wood, wooden doors and hatches | Planks037A |
| Iron, Steel and Blood-forged walls, doors and hatches; Iron Box (plates, tinted) | CorrugatedSteel009 |
| Wooden Box | Planks023A |
| Leaves (single leaves, arranged into a tile) | LeafSet024 |

The tools and weapons (0.15.0) are models made in code (`scripts/tool_models.gd`); their wood and
stone take the Planks037A and Rock030 pictures above.

The ore spots, log rings, fabric (bed, backpack), forge glow, frame struts, iron bands, rivets,
plate seams, handles and locks are painted by the script.

## Models — Quaternius (https://quaternius.com), CC0 1.0

In `assets/models/`, as downloaded (Godot imports them; `scripts/rig.gd` plays their animations
and paints over palette cells of their textures for the zombie skins):

| Used for | Pack | Files |
|---|---|---|
| Zombies: walker, runner, crawler, screamer | Zombie Apocalypse Kit (March 2024) | `zombies/Zombie_Basic.gltf` |
| Brute | Zombie Apocalypse Kit | `zombies/Zombie_Arm.gltf` |
| Spitter | Zombie Apocalypse Kit | `zombies/Zombie_Chubby.gltf` |
| Other players | Zombie Apocalypse Kit | `survivors/Characters_{Matt,Lis,Sam,Shaun}_SingleWeapon.gltf` (their weapons are hidden) |
| Boar (pig recoloured, tusks added) | Farm Animals | `animals/Pig.fbx` |
| Trees (broadleaf and pines), and from 0.18.0 the grass, flowers, ferns, clover, mushrooms, bushes, pebbles and rocks scattered over the land | Stylized Nature MegaKit (Standard, https://quaternius.itch.io/stylized-nature-megakit) | `nature/*.gltf` and their textures (the textures resized to at most 1024 pixels) |
