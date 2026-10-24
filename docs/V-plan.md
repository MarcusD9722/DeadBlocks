# Graphics overhaul (V) — plan

Marcus asked (after 0.9.0) for "more of a 3D feel with rounded edges to the world, zombies and all, closer to 7 Days to Die textures". His answers:

1. The PCs are an RTX 5080 and an RTX 3080, so the game can use the high-end renderer.
2. Use free texture and model packs.
3. Smooth terrain: yes.
4. Do the graphics first and pause M3 (M3.2–M3.4 wait).

## Decisions

- **Renderer: Forward+** (Vulkan/D3D12) with the OpenGL fallback for PCs that can't run it. The dedicated server is headless and draws nothing, so it is unaffected.
- **Graphics quality setting** (Low / Medium / High / Ultra), on the title screen and in the pause menu. It is saved in `user://settings.cfg` together with the mouse sensitivity. It sets:
  - anti-aliasing;
  - shadow quality and distance;
  - ambient occlusion (SSAO) and bounced light (SSIL);
  - volumetric fog;
  - view distance (5–8 chunks).
- **Smooth terrain is a picture only.**
  - Natural ground (grass, dirt, stone, sand, ores, bedrock) is drawn as a rounded surface. Built blocks stay cubes.
  - Collision, mining, placing, zombie movement and the server keep using whole blocks.
  - Why:
    - A collision surface that follows the rounding would shrink a dug 1×2 tunnel below player height.
    - It would change how zombies move and break in (the region-order and zombie-type tests depend on it).
    - It would make the Pi build a more expensive collision mesh.
  - To keep the picture close to the blocks, corners are cut by at most 0.45 m and hollows filled by at most 0.2 m. Tunnels and doorways therefore look about as big as they are.
  - The player steps up 1-block ledges by itself, with the camera easing up, so a rounded hill walks like a slope. Zombies already hop ledges.
- **Dark caves:** every vertex carries a sky-light value (how deep it is under cover, with light reaching a little into openings). It dims only the ambient light, so torches and the flashlight still light caves fully. The same applies under roofs.
- **Creatures and players** are built from boxes with rounded edges until real models arrive (V4).
- **Assets:**
  - Everything so far is still made in code: the terrain textures are painted from noise at startup and the sky is a shader.
  - Downloaded CC0 packs come in V3/V4 and must stay out of the dedicated-server export.

## Steps

| Step | What | Status |
|---|---|---|
| V1 | Forward+, soft shadows, SSAO/SSIL, glow, volumetric fog, AgX tonemapping, sky shader (clouds, stars, moon, Blood Moon), quality setting | built |
| V2 | Smooth terrain (surface nets, `smooth_mesher.gd`), triplanar terrain shader with blended materials and normal maps, sky light, auto-step, rounded models | built |
| V2.1 (0.10.1) | After Marcus's test of 0.10.0 (Ultra smooth, hills and building fine; "a little too dark"; zombies float a little; deaths freeze): a Settings screen with brightness, light in caves, FOV, shadows, AO, fog, AA, render scale, V-Sync, frame cap, window, FPS counter; creatures stand on the drawn ground; zombies and boars fall over when they die | built |
| V2.2 (0.10.2) | Marcus: "where some blocks connect you can see through the walls/terrain". The rounded ground stopped short of built blocks (thin slits) and some smoothed triangles folded over. Ground vertices touching a built block now stay on its corner, the ground is drawn double-sided, and `tests/meshtest.gd` (in the gate) fails on any hole | built |
| V3 (0.11.0) | CC0 photo textures (ambientCG) for the ground and the built blocks (`tools/make_textures.py`, credits in `assets/CREDITS.md`); log trunks drawn round with bark; leaves as swaying leafy clusters that let light through; nicer clouds (swirled shapes, self-shadowing, bright edges by the sun) | built |
| V4 | CC0 models (Quaternius Zombie Apocalypse Kit: zombies, survivors; a pig for the boar) with animations | waiting: Quaternius' Google Drive answers "Quota exceeded" to every download from here; Marcus downloads the packs and attaches them to a GitHub release |

To unblock V3/V4, these hosts must be allowed in the environment's network settings:

- ambientcg.com
- polyhaven.com, dl.polyhaven.org
- quaternius.com, drive.google.com

## How it works (code)

- `scripts/gfx.gd` (`G.gfx`) holds:
  - the WorldEnvironment, the sun/moon light and the sky material (`shaders/sky.gdshader`);
  - the day–night look (`update_sky`);
  - the quality presets (`apply_quality`, `set_quality`) and the settings file.
- `scripts/smooth_mesher.gd` builds the ground for one chunk from the chunk and its eight neighbours (4 blocks of each), so borders match:
  - it puts one vertex per mixed 2×2×2 group of blocks;
  - it moves the vertex within the limits above;
  - it smooths each vertex twice towards its neighbours;
  - it draws one quad where a natural block meets air;
  - each vertex gets material weights from the natural blocks around it and the sky light.
- `world.gd`:
  - draws a chunk only once all eight neighbours have data;
  - an edit within 4 blocks of a border remeshes the neighbours;
  - cube faces show next to the natural ground too, so no hole appears where the rounding dips;
  - on a server nothing changed (collision from the four side neighbours, as before).
- `shaders/terrain.gdshader`: triplanar textures from `Tex.terrain_albedo/terrain_normal` (texture arrays). Materials meet along their height maps; the sky light goes to `AO`.
- `shaders/blocks.gdshader`: the pixel atlas for cubes, boxes and plants, with the sky light.
- `scripts/round_box.gd`: rounded box meshes for the models (cached by size).
- `scripts/tests/scenery.gd`: `-- --scenery --shots=DIR [--gfx=0-3]` takes pictures (noon, dusk, night, Blood Moon, a cave, a torch-lit hut) for judging the look.
