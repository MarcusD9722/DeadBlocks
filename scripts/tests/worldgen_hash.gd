extends RefCounted
## `-- --worldgen-hash`: prints one hash over a few hundred generated chunks and raw noise values,
## near the origin and far out, for two seeds. Builds on different CPUs (PC vs the Pi's ARM chip)
## must print the same hash, because clients generate terrain themselves (tools/check_worldgen.sh).


## Version 1's hash for seed 4242 as 0.18.0 printed it: old worlds must keep their terrain.
const V1_HASH_4242 := "6aa5d49d2a1ebf684043cd2e70441189634ca50db9772270cc3592234bd5bdcb"


static func run(seed_v: int) -> void:
	var fails := 0
	for version in range(1, WorldGen.VERSION + 1):
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		var chunks := 0
		for s in [seed_v, 987654]:
			var g := WorldGen.new(s, version)
			for base in [Vector2i(0, 0), Vector2i(3000, -2000), Vector2i(-4000, 6000)]:
				for dz in range(-3, 3):
					for dx in range(-3, 3):
						var d := g.generate(base.x + dx, base.y + dz)
						# (Version 1 fills only the lowest 64 blocks, as it always did.)
						ctx.update(d.slice(0, 16 * 16 * WorldGen.V1_H) if version == 1 else d)
						chunks += 1
			var noise := PackedFloat32Array()
			for i in 2000:
				var x := (i * 7919) % 400000 - 200000
				var z := (i * 104729) % 400000 - 200000
				noise.append(g.n_height.get_noise_2d(x, z))
				noise.append(g.n_cave1.get_noise_3d(x, i % 64, z))
				if version >= 2:
					noise.append(g.n_ridge.get_noise_2d(x, z))
					noise.append(g.n_mount.get_noise_2d(x, z))
			ctx.update(noise.to_byte_array())
		var h := ctx.finish().hex_encode()
		print("WORLDGEN v%d chunks=%d hash=%s" % [version, chunks, h])
		if version == 1 and seed_v == 4242:
			var ok := h == V1_HASH_4242
			fails += 0 if ok else 1
			print("WORLDGEN %s version 1 is the terrain old worlds were made with" % ("PASS" if ok else "FAIL"))
	print("WORLDGEN DONE fails=%d" % fails)
