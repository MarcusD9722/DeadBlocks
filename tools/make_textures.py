#!/usr/bin/env python3
"""Builds the game's texture files in assets/textures/ from CC0 ambientCG materials.

Usage: python3 tools/make_textures.py SOURCE_DIR
   or: python3 tools/make_textures.py --add-m47-layers   (adds snow and crystal ore to the
       7-layer terrain strips already in assets/textures)
SOURCE_DIR holds the unzipped 1K-JPG downloads, one folder per material, e.g.
SOURCE_DIR/Grass004/Grass004_1K-JPG_Color.jpg (download https://ambientcg.com/get?file=Grass004_1K-JPG.zip).
The materials used are listed in assets/CREDITS.md.

Outputs (strips of square layers, imported by Godot as Texture2DArrays; see the .import files):
  terrain_albedo.jpg / terrain_normal.jpg   9 layers of 1024 px: grass, dirt, stone, sand,
                                            coal ore, iron ore, bedrock, snow and crystal ore
                                            (SmoothMesher's layers; the last two made here, M4.7)
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


def tile_noise(size, scale, rng):
    """Tileable smooth noise (0-1): white noise blurred through the FFT, `scale` px wide."""
    w = rng.standard_normal((size, size))
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    g = np.exp(-(fx * fx + fy * fy) * (scale * scale) * 2.0)
    n = np.real(np.fft.ifft2(np.fft.fft2(w) * g))
    n -= n.min()
    return n / max(n.max(), 1e-6)


def snow(size, rng):
    """Fresh snow (M4.7): soft drifts, faint wind ripples and glints, white with blue shadows."""
    big = tile_noise(size, size * 0.08, rng)
    mid = tile_noise(size, size * 0.02, rng)
    fine = tile_noise(size, size * 0.004, rng)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size
    ripple = 0.5 + 0.5 * np.sin((xx * 9 + yy * 4 + big * 1.5) * 2 * math.pi)
    h = np.clip(big * 0.55 + mid * 0.3 + fine * 0.1 + ripple * 0.05, 0, 1)
    shade = 0.86 + 0.14 * h
    alb = np.stack([shade * 0.9, shade * 0.93, shade * 0.98], axis=2)
    glints = (fine > 0.93).astype(np.float32) * (mid > 0.5)
    alb = np.clip(alb + glints[:, :, None] * 0.08, 0, 1)
    return alb, height_to_normal(h, 2.2)


def crystal_ore(stone_alb, stone_nrm, seed):
    """Crystal ore (M4.7): stone with clusters of blue-violet crystal, bright at their edges."""
    size = stone_alb.shape[0]
    rng = np.random.default_rng(seed)
    # Clusters of pointed shards (thin diamonds) fanning out from a point.
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    m = np.zeros((size, size), np.float32)
    facets = np.zeros((size, size), np.float32)
    for _ in range(22):
        cx, cy = rng.uniform(0, size, 2)
        base = rng.uniform(0, 2 * math.pi)
        for k in range(rng.integers(4, 8)):
            a = base + rng.normal(0, 0.8)
            ln = rng.uniform(size * 0.035, size * 0.085)
            wd = ln * rng.uniform(0.18, 0.3)
            ox, oy = math.cos(a) * ln * 0.5, math.sin(a) * ln * 0.5
            dx = (xx - (cx + ox)) % size
            dy = (yy - (cy + oy)) % size
            dx = np.where(dx > size / 2, dx - size, dx)
            dy = np.where(dy > size / 2, dy - size, dy)
            u = dx * math.cos(a) + dy * math.sin(a)
            v = -dx * math.sin(a) + dy * math.cos(a)
            d = np.abs(u) / (ln * 0.5) + np.abs(v) / wd
            inside = np.clip((1.0 - d) * 6.0, 0, 1)
            m = np.maximum(m, inside)
            # One face of each shard lit, the other darker.
            facets = np.where(inside > 0, np.where(v > 0, 0.95, 0.45) * (1.0 - 0.4 * np.abs(u) / (ln * 0.5)), facets)
    col = np.array([0.42, 0.62, 1.0], np.float32)
    deep = np.array([0.36, 0.2, 0.75], np.float32)
    mix = np.clip(facets, 0, 1)[:, :, None]
    crystal = (col * mix + deep * (1 - mix)) * (0.7 + 0.5 * m[:, :, None])
    w = m[:, :, None]
    alb = np.clip(stone_alb * 0.8 * (1 - w) + crystal * w, 0, 1)
    h = np.clip(stone_nrm[:, :, 2] * (1 - m) + (0.6 + facets * 0.4) * m, 0, 1)
    bump = height_to_normal(m * 0.7 + facets * m * 0.3, 4.0)
    nrm = stone_nrm.copy()
    nrm[:, :, :2] = stone_nrm[:, :, :2] * (1 - w) + bump[:, :, :2] * w
    nrm[:, :, 2] = h
    return alb, nrm


def add_m47_layers():
    """Make the snow and crystal ore layers and add them to the existing 7-layer terrain strips
    (when the ambientCG downloads aren't at hand)."""
    T = 1024
    alb = np.asarray(Image.open(os.path.join(OUT, "terrain_albedo.jpg")).convert("RGB")).astype(np.float32) / 255.0
    nrm = np.asarray(Image.open(os.path.join(OUT, "terrain_normal.jpg")).convert("RGB")).astype(np.float32) / 255.0
    n = alb.shape[1] // T
    if n != 7:
        print("terrain strips have %d layers already" % n)
        return
    albs = [alb[:, i * T:(i + 1) * T] for i in range(n)]
    nrms = [nrm[:, i * T:(i + 1) * T] for i in range(n)]
    rng = np.random.default_rng(4747)
    sn = snow(T, rng)
    cr = crystal_ore(albs[2], nrms[2], 13)
    save_strip(albs + [sn[0], cr[0]], "terrain_albedo.jpg", 90)
    save_strip(nrms + [sn[1], cr[1]], "terrain_normal.jpg", 88)


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


def paint(alb, nrm, mask, col, height):
    """Paint a mask (0-1, h x w) in a colour (or a picture) and set the height under it."""
    m = mask[:, :, None]
    alb = alb * (1 - m) + np.asarray(col, np.float32) * m
    nrm = nrm.copy()
    nrm[:, :, 2] = nrm[:, :, 2] * (1 - mask) + height * mask
    return alb, nrm


def rect(size, x0, y0, x1, y1):
    m = np.zeros((size, size), np.float32)
    m[int(y0 * size):int(y1 * size), int(x0 * size):int(x1 * size)] = 1
    return m


def discs(size, pts, r):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size
    m = np.zeros((size, size), np.float32)
    for (cx, cy) in pts:
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
        m = np.maximum(m, np.clip(1.5 - d * 1.5, 0, 1))
    return m


def door_pair(base, size, rim, dark):
    """A door two blocks tall from one material: (upper, lower), one border around both."""
    alb = np.concatenate([base[0], base[0]], axis=0)
    nrm = np.concatenate([base[1], base[1]], axis=0)
    m = np.zeros(alb.shape[:2], np.float32)
    m[:rim, :] = m[-rim:, :] = m[:, :rim] = m[:, -rim:] = 1
    alb = alb * (1 - m[:, :, None] * dark)
    nrm = nrm.copy()
    nrm[:, :, 2] = nrm[:, :, 2] * (1 - m * 0.5) + m * 0.9
    return (alb[:size], nrm[:size]), (alb[size:], nrm[size:])


def metal(steel, col, lum_gain=1.6):
    """Corrugated steel turned into flat plates of a colour (iron, steel, blood-forged)."""
    lum = steel[0].mean(axis=2, keepdims=True)
    lum = 0.6 + (lum - lum.mean()) * 0.5  # (flatter: plates, not corrugation)
    alb = np.clip(lum * np.array(col, np.float32) * lum_gain, 0, 1)
    nrm = steel[1].copy()
    nrm[:, :, :2] = 0.5 + (nrm[:, :, :2] - 0.5) * 0.25
    nrm[:, :, 2] = 0.5 + (nrm[:, :, 2] - 0.5) * 0.3
    return alb, nrm


def plates(base, size, rivet_col, seam=True):
    """Riveted plates: a frame, seams across the middle and rivets in the corners."""
    alb, nrm = frame(base[0], base[1], size // 20, 0.35)
    if seam:
        m = np.maximum(rect(size, 0.49, 0, 0.51, 1), rect(size, 0, 0.49, 1, 0.51))
        alb, nrm = paint(alb, nrm, m, alb * 0.55, 0.1)
    pts = [(x, y) for x in (0.08, 0.92) for y in (0.08, 0.92)] + [(0.5, 0.08), (0.5, 0.92), (0.08, 0.5), (0.92, 0.5)]
    alb, nrm = paint(alb, nrm, discs(size, pts, 0.025), rivet_col, 0.95)
    return alb, nrm


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
    terrain = [grass, dirt, stone, sand, coal, iron, (bedrock[0] * 0.75, bedrock[1]),
        snow(T, np.random.default_rng(4747)), crystal_ore(stone[0], stone[1], 13)]
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
    # M4.2: the structure tiers, doors, hatches and boxes (tex.gd tiles 30-44).
    xx01, yy01 = np.mgrid[0:B, 0:B].astype(np.float32)[::-1] / B
    border = 1 - rect(B, 0.11, 0.11, 0.89, 0.89)
    diag = (np.abs(xx01 - yy01) < 0.07).astype(np.float32)
    wood_frame = paint(planks[0] * 0.8, planks[1], 1 - np.maximum(border, diag), planks[0] * 0.22, 0.05)
    bands = np.maximum(rect(B, 0, 0.18, 1, 0.3), rect(B, 0, 0.7, 1, 0.82))
    iron_col = (0.36, 0.36, 0.38)
    iron = metal(steel, iron_col)
    rwood = paint(planks[0], planks[1], bands, iron[0] * 0.8, 0.8)
    rwood = paint(rwood[0], rwood[1], discs(B, [(x, y) for x in (0.1, 0.5, 0.9) for y in (0.24, 0.76)], 0.025), (0.62, 0.6, 0.58), 0.95)
    iron_wall = plates(iron, B, (0.55, 0.5, 0.45))
    steel_m = metal(steel, (0.6, 0.64, 0.7))
    steel_wall = plates(steel_m, B, (0.8, 0.82, 0.85))
    blood_m = metal(steel, (0.36, 0.07, 0.08))
    blood_wall = plates(blood_m, B, (0.75, 0.3, 0.3))
    vplanks = (np.rot90(planks[0]), np.rot90(planks[1]))
    # Doors: the lower half has the handle (near its top, about 0.8 m up), the upper half the
    # steel door's window (tex.gd tiles 35-37 lower, 45-47 upper).
    handle = discs(B, [(0.82, 0.2)], 0.045)
    wood_door_up, wood_door = door_pair(vplanks, B, B // 14, 0.45)
    wood_door = paint(wood_door[0], wood_door[1], handle, (0.25, 0.24, 0.23), 0.95)
    iron_door_up = plates(iron, B, (0.55, 0.5, 0.45), seam=False)
    iron_door = paint(*plates(iron, B, (0.55, 0.5, 0.45), seam=False), handle, (0.2, 0.2, 0.2), 0.95)
    steel_door_up = plates(steel_m, B, (0.8, 0.82, 0.85), seam=False)
    steel_door_up = paint(steel_door_up[0], steel_door_up[1], rect(B, 0.3, 0.3, 0.7, 0.55), (0.08, 0.1, 0.12), 0.1)
    steel_door = plates(steel_m, B, (0.8, 0.82, 0.85), seam=False)
    steel_door = paint(steel_door[0], steel_door[1], handle, (0.25, 0.25, 0.27), 0.95)
    wood_hatch = frame(planks[0], planks[1], B // 12, 0.45)
    wood_hatch = paint(wood_hatch[0], wood_hatch[1], diag, planks[0] * 0.7, 0.9)
    iron_hatch = plates(iron, B, (0.55, 0.5, 0.45))
    steel_hatch = plates(steel_m, B, (0.8, 0.82, 0.85))
    box_side = frame(planks_old[0] * 0.9, planks_old[1], B // 10, 0.5)
    box_side = paint(box_side[0], box_side[1], np.maximum(diag, (np.abs(xx01 + yy01 - 1) < 0.07).astype(np.float32)) * (1 - border), planks_old[0] * 0.65, 0.9)
    box_top = frame(planks_old[0], planks_old[1], B // 10, 0.5)
    box_top = paint(box_top[0], box_top[1], rect(B, 0, 0.48, 1, 0.52), planks_old[0] * 0.4, 0.1)
    ibox_side = plates(iron, B, (0.55, 0.5, 0.45), seam=False)
    ibox_side = paint(ibox_side[0], ibox_side[1], rect(B, 0.42, 0.1, 0.58, 0.3), (0.62, 0.55, 0.3), 0.95)
    ibox_top = plates(iron, B, (0.55, 0.5, 0.45))
    blocks = [cobble, bark, ltop, planks, bench_top, bench_side, forge_top, forge_side, bricks, steel,
        bed_top, bed_side, pack_top, pack_side, bf_top, bf_side, blood_bricks,
        wood_frame, rwood, iron_wall, steel_wall, blood_wall, wood_door, iron_door, steel_door,
        wood_hatch, iron_hatch, steel_hatch, box_side, box_top, ibox_side, ibox_top,
        wood_door_up, iron_door_up, steel_door_up]
    save_strip([b[0] for b in blocks], "blocks_albedo.jpg", 90)
    save_strip([b[1] for b in blocks], "blocks_normal.jpg", 95)
    # Leaves.
    tile, lnrm = leaves_tile(512, rng)
    tile.save(os.path.join(OUT, "leaves_albedo.png"))
    Image.fromarray((np.clip(lnrm, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, "leaves_normal.jpg"), quality=95)
    print("wrote leaves")


if len(sys.argv) > 1 and sys.argv[1] == "--add-m47-layers":
    add_m47_layers()
else:
    main()
