extends RefCounted
## `-- --worldgen-hash`: prints one hash over a few hundred generated chunks and raw noise values,
## near the origin and far out, for two seeds. Builds on different CPUs (PC vs the Pi's ARM chip)
## must print the same hash, because clients generate terrain themselves (tools/check_worldgen.sh).


static func run(seed_v: int) -> void:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var chunks := 0
	for s in [seed_v, 987654]:
		var g := WorldGen.new(s)
		for base in [Vector2i(0, 0), Vector2i(3000, -2000), Vector2i(-4000, 6000)]:
			for dz in range(-3, 3):
				for dx in range(-3, 3):
					ctx.update(g.generate(base.x + dx, base.y + dz))
					chunks += 1
		var noise := PackedFloat32Array()
		for i in 2000:
			var x := (i * 7919) % 400000 - 200000
			var z := (i * 104729) % 400000 - 200000
			noise.append(g.n_height.get_noise_2d(x, z))
			noise.append(g.n_cave1.get_noise_3d(x, i % 64, z))
		ctx.update(noise.to_byte_array())
	print("WORLDGEN chunks=%d hash=%s" % [chunks, ctx.finish().hex_encode()])
	print("WORLDGEN DONE")
