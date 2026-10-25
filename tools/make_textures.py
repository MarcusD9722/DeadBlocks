#!/usr/bin/env python3
"""Builds the game's texture files in assets/textures/ from CC0 ambientCG materials.

Usage: python3 tools/make_textures.py SOURCE_DIR
SOURCE_DIR holds the unzipped 1K-JPG downloads, one folder per material, e.g.
SOURCE_DIR/Grass004/Grass004_1K-JPG_Color.jpg (download https://ambientcg.com/get?file=Grass004_1K-JPG.zip).
The materials used are listed in assets/CREDITS.md.

Outputs (strips of square layers, imported by Godot as Texture2DArrays; see the .import files):
  terrain_albedo.jpg / terrain_normal.jpg   7 layers of 1024 px: grass, dirt, stone, sand,
                                            coal ore, iron ore, bedrock (SmoothMesher's layers)
  blocks_albedo.jpg / blocks_normal.jpg     the built blocks, 512 px (tex.gd BLOCK_LAYERS)
  leaves_albedo.png / leaves_normal.jpg     a tile of leaves with see-through gaps, 512 px
Normal maps are OpenGL style (green up) with the height map in the blue channel (the shaders
rebuild the normal's z).
"""
import math
import os
import sys

import numpy as np
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "."
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures")


def load(mat, kind, size, mode="RGB"):
    path = os.path.join(SRC, mat, "%s_1K-JPG_%s.jpg" % (mat, kind))
    im = Image.open(path).convert(mode)
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im).astype(np.float32) / 255.0


def material(mat, size):
    """Albedo (h, w, 3) and normal+height (h, w, 3) of an ambientCG material."""
    alb = load(mat, "Color", size)
    nrm = load(mat, "NormalGL", size)
    hgt = load(mat, "Displacement", size, "L")
    lo, hi = np.percentile(hgt, 2), np.percentile(hgt, 98)
    nrm[:, :, 2] = np.clip((hgt - lo) / max(hi - lo, 1e-3), 0.0, 1.0)
    return alb, nrm


def height_to_normal(h, strength):
    """A tileable normal map (xy in 0-1, OpenGL style) from a height field."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    nx, ny, nz = -dx, dy, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, h], axis=2)


def blob_mask(size, count, rmin, rmax, rng):
    """Soft tileable blobs (ore spots): 0-1."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    m = np.zeros((size, size), np.float32)
    for _ in range(count):
        cx, cy = rng.uniform(0, size, 2)
        for _ in range(rng.integers(3, 7)):
            ox, oy = rng.normal(0, rmax * 0.6, 2)
            r = rng.uniform(rmin, rmax)
            dx = np.abs(xx - (cx + ox) % size)
            dy = np.abs(yy - (cy + oy) % size)
            dx = np.minimum(dx, size - dx)
            dy = np.minimum(dy, size - dy)
            d = np.sqrt(dx * dx + dy * dy) / r
            m = np.maximum(m, np.clip(1.4 - d * 1.4, 0, 1))
    return np.clip(m * 1.6, 0, 1)


def ore(stone_alb, stone_nrm, col, seed):
    size = stone_alb.shape[0]
    rng = np.random.default_rng(seed)
    m = blob_mask(size, 30, size * 0.006, size * 0.018, rng)[:, :, None]
    lum = stone_alb.mean(axis=2, keepdims=True)
    spot = np.array(col, np.float32) * (0.55 + 0.9 * lum)
    alb = stone_alb * (1 - m) + spot * m
    h = stone_nrm[:, :, 2] * 0.6 + m[:, :, 0] * 0.4
    bump = height_to_normal(m[:, :, 0], 3.0)
    nrm = stone_nrm.copy()
    w = m
    nrm[:, :, :2] = stone_nrm[:, :, :2] * (1 - w) + bump[:, :, :2] * w
    nrm[:, :, 2] = h
    return alb, nrm


def frame(alb, nrm, width, dark):
    """A darker border (the edge of a crafted block)."""
    size = alb.shape[0]
    m = np.zeros((size, size), np.float32)
    m[:width, :] = m[-width:, :] = m[:, :width] = m[:, -width:] = 1
    alb = alb * (1 - m[:, :, None] * dark)
    h = nrm[:, :, 2] * (1 - m * 0.5) + m * 0.9
    nrm = nrm.copy()
    nrm[:, :, 2] = h
    return alb, nrm


def log_top(planks_alb, size, rng):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size - 0.5
    r = np.sqrt(xx * xx + yy * yy)
    ang = np.arctan2(yy, xx)
    wob = 0.004 * np.sin(ang * 5 + 1.3) + 0.003 * np.sin(ang * 11) + 0.006 * rng.random((size, size))
    rings = 0.5 + 0.5 * np.sin((r + wob) * 2 * math.pi * 11)
    base = planks_alb.reshape(-1, 3).mean(axis=0) * 1.25
    light = np.clip(base * 1.15, 0, 1)
    dark = base * 0.62
    alb = light * (1 - rings[:, :, None] * 0.5) + dark * (rings[:, :, None] * 0.5)
    alb *= (0.9 + 0.1 * rng.random((size, size, 1)))
    bark = np.clip((r - 0.43) / 0.03, 0, 1)[:, :, None]
    alb = alb * (1 - bark) + np.array([0.23, 0.16, 0.1]) * bark
    h = rings * 0.4 + 0.3 - bark[:, :, 0] * 0.2
    return np.clip(alb, 0, 1), height_to_normal(h, 4.0)


def fabric(size, col, rng, stripes=False):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    weave = 0.5 + 0.25 * np.sin(xx * 1.4) + 0.25 * np.sin(yy * 1.4)
    noise = rng.random((size, size)) * 0.15
    h = weave * 0.6 + noise
    alb = np.array(col, np.float32) * (0.78 + 0.3 * h[:, :, None])
    if stripes:
        s = ((xx // 24) % 2 == 0).astype(np.float32)[:, :, None]
        alb = alb * (1 - s * 0.12)
    return np.clip(alb, 0, 1), height_to_normal(h, 2.0)


def leaves_tile(size, rng):
    """Leaves scattered (wrapping at the edges) over a see-through tile: RGBA and normal+height."""
    col = Image.open(os.path.join(SRC, "LeafSet024", "LeafSet024_1K-JPG_Color.jpg")).convert("RGB")
    opa = Image.open(os.path.join(SRC, "LeafSet024", "LeafSet024_1K-JPG_Opacity.jpg")).convert("L")
    cell = col.size[0] // 3
    sprites = []
    for gy in range(3):
        for gx in range(3):
            box = (gx * cell, gy * cell, (gx + 1) * cell, (gy + 1) * cell)
            sp = col.crop(box).convert("RGBA")
            sp.putalpha(opa.crop(box))
            sprites.append(sp)
    canvas = Image.new("RGBA", (size * 3, size * 3), (0, 0, 0, 0))
    hcanvas = Image.new("L", (size * 3, size * 3), 0)
    for i in range(150):
        depth = i / 150.0  # later leaves lie on top: lighter
        sp = sprites[rng.integers(0, len(sprites))]
        s = int(size * rng.uniform(0.13, 0.22))
        sp = sp.resize((s, s), Image.LANCZOS).rotate(rng.uniform(0, 360), resample=Image.BICUBIC, expand=True)
        a = np.asarray(sp).astype(np.float32)
        tint = np.array([rng.uniform(0.55, 0.8), rng.uniform(0.75, 1.0), rng.uniform(0.45, 0.65)]) * (0.55 + 0.55 * depth)
        a[:, :, :3] = np.clip(a[:, :, :3] * tint, 0, 255)
        sp = Image.fromarray(a.astype(np.uint8), "RGBA")
        hs = Image.new("L", sp.size, int(60 + 190 * depth))
        x, y = rng.integers(0, size, 2)
        for ox in (0, size, size * 2):
            for oy in (0, size, size * 2):
                canvas.alpha_composite(sp, (int(x + ox - sp.size[0] // 2), int(y + oy - sp.size[1] // 2)))
                hcanvas.paste(hs, (int(x + ox - sp.size[0] // 2), int(y + oy - sp.size[1] // 2)), sp.split()[3])
    tile = canvas.crop((size, size, size * 2, size * 2))
    h = np.asarray(hcanvas.crop((size, size, size * 2, size * 2))).astype(np.float32) / 255.0
    return tile, height_to_normal(h * 0.6 + np.asarray(tile.convert("L")).astype(np.float32) / 255.0 * 0.4, 3.0)


def save_strip(layers, name, quality):
    strip = np.concatenate(layers, axis=1)
    Image.fromarray((np.clip(strip, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(
        os.path.join(OUT, name), quality=quality, subsampling=0)
    print("wrote %s (%d layers)" % (name, len(layers)))


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(4242)
    # Smooth ground: grass, dirt, stone, sand, coal ore, iron ore, bedrock.
    T = 1024
    grass = material("Grass004", T)
    lum = grass[0].mean(axis=2, keepdims=True)
    grass = (np.clip((lum + (grass[0] - lum) * 1.3) * np.array([0.92, 1.0, 0.85]), 0, 1), grass[1])  # a greener lawn
    dirt = material("Ground067", T)
    stone = material("Rock030", T)
    sand = material("Ground054", T)
    bedrock = material("Rock035", T)
    coal = ore(stone[0], stone[1], (0.06, 0.06, 0.065), 11)
    iron = ore(stone[0], stone[1], (0.74, 0.48, 0.3), 12)
    terrain = [grass, dirt, stone, sand, coal, iron, (bedrock[0] * 0.75, bedrock[1])]
    save_strip([t[0] for t in terrain], "terrain_albedo.jpg", 90)
    save_strip([t[1] for t in terrain], "terrain_normal.jpg", 88)
    # Built blocks (order = tex.gd BLOCK_LAYERS).
    B = 512
    cobble = material("PavingStones070", B)
    bark = material("Bark014", B)
    planks = material("Planks037A", B)
    planks_old = material("Planks023A", B)
    bricks = material("Bricks076A", B)
    steel = material("CorrugatedSteel009", B)
    rock_dark = material("Rock035", B)
    ltop = log_top(planks[0], B, rng)
    bench_top = frame(planks_old[0], planks_old[1], 26, 0.45)
    bench_side = frame(planks[0] * 0.85, planks[1], 34, 0.5)
    forge_top = frame(rock_dark[0] * 0.8, rock_dark[1], 30, 0.5)
    fs_alb = bricks[0].copy()
    yy, xx = np.mgrid[0:B, 0:B].astype(np.float32) / B
    mouth = (np.abs(xx - 0.5) < 0.24) & (yy > 0.45) & (yy < 0.9) & (((xx - 0.5) / 0.24) ** 2 + ((yy - 0.62) / 0.17) ** 2 < 1.3)
    glow = np.clip(1.0 - (yy - 0.55) * 1.5, 0.3, 1.0)
    fs_alb[mouth] = np.stack([np.ones_like(glow), 0.42 * glow, 0.08 * glow], axis=2)[mouth]
    forge_side = (fs_alb, bricks[1])
    bed_top = fabric(B, (0.55, 0.1, 0.1), rng)
    pillow = (yy < 0.28)[:, :, None]
    bed_top = (bed_top[0] * (1 - pillow) + np.clip(bed_top[0] * 0 + 0.82 * (0.9 + 0.1 * rng.random((B, B, 1))), 0, 1) * pillow, bed_top[1])
    bed_side = (planks[0] * 0.8, planks[1])
    pack_top = fabric(B, (0.36, 0.38, 0.22), rng)
    pack_side = fabric(B, (0.33, 0.35, 0.2), rng, stripes=True)
    # Blood Forge (M4.1): dark red stone over a red glow; Blood Brick: the bricks in dark blood red.
    blood_tint = np.array([0.62, 0.2, 0.22])
    blum = bricks[0].mean(axis=2, keepdims=True)
    blood_bricks = (np.clip(blum * blood_tint * 1.6, 0, 1), bricks[1])
    bf_top = frame(np.clip(rock_dark[0].mean(axis=2, keepdims=True) * np.array([0.55, 0.3, 0.32]), 0, 1), rock_dark[1], 30, 0.5)
    bfs_alb = blood_bricks[0].copy()
    bfs_alb[mouth] = np.stack([np.ones_like(glow), 0.16 * glow, 0.12 * glow], axis=2)[mouth]
    bf_side = (bfs_alb, bricks[1])
    blocks = [cobble, bark, ltop, planks, bench_top, bench_side, forge_top, forge_side, bricks, steel,
        bed_top, bed_side, pack_top, pack_side, bf_top, bf_side, blood_bricks]
    save_strip([b[0] for b in blocks], "blocks_albedo.jpg", 90)
    save_strip([b[1] for b in blocks], "blocks_normal.jpg", 95)
    # Leaves.
    tile, lnrm = leaves_tile(512, rng)
    tile.save(os.path.join(OUT, "leaves_albedo.png"))
    Image.fromarray((np.clip(lnrm, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, "leaves_normal.jpg"), quality=95)
    print("wrote leaves")


main()
