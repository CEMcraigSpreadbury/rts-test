extends Node
## Throwaway: generates a Realm map from one of the generator scenes at a
## bigger size. Feature counts are totals for the whole map (split per player),
## so 2- and 4-player maps come out equally dense.
## Args after "--": --gen=res://scenes/tools/map_generator_four_kingdoms.tscn
##   --size=1024 --name="Four Kingdoms Realm" --settlements=12

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var gen: MapGenerator = load(args.get("gen", "res://scenes/tools/map_generator_four_kingdoms.tscn")).instantiate()
	var size: int = int(args.get("size", "1024"))
	var players: int = gen.player_count
	## Whole-map totals at 1 km, scaled by area for other sizes.
	var area: float = pow(size / 1024.0, 2.0)
	var per := func(total: float) -> int: return maxi(int(round(total * area / players)), 1)
	gen.map_name = args.get("name", gen.map_name + " Realm")
	gen.map_size = size
	gen.overwrite_existing = true
	gen.settlements_per_player = maxi(int(round(float(args.get("settlements", "12")) / players)), 1)
	gen.settlement_clear_radius = 16.0
	gen.settlement_min_base_distance = minf(size * 0.09, 120.0)
	gen.forest_clusters_per_player = per.call(64.0)
	gen.forest_cluster_radius = Vector2(6.0, 16.0)
	gen.props_per_player = mini(per.call(800.0), 300)
	gen.lakes_per_player = per.call(8.0)
	gen.rivers_per_player = mini(per.call(4.0), 3)
	gen.plateaus_per_player = mini(per.call(12.0), 6)
	gen.building_pockets_per_player = mini(per.call(16.0), 8)
	gen.dirt_patches_per_player = mini(per.call(24.0), 12)
	gen.grass_patches_per_player = mini(per.call(32.0), 12)
	gen.neutral_gold_per_player = mini(per.call(12.0), 4)
	gen.river_width = Vector2(6.0, 12.0)
	gen.lake_radius = Vector2(10.0, 30.0)
	add_child(gen)
	var t0 := Time.get_ticks_msec()
	if not gen.generate():
		print("SCALE: generate FAILED")
		get_tree().quit(1)
		return
	var t1 := Time.get_ticks_msec()
	var kinds := {}
	var tiers := {}
	for e in gen.layout.objects:
		kinds[e.kind] = kinds.get(e.kind, 0) + 1
		if e.get("props", {}).has("start_tier"):
			var t: int = e.props.start_tier
			tiers[t] = tiers.get(t, 0) + 1
	print("SCALE: %s layout+terrain %.1f s, kinds %s, tiers (0 village 1 town 2 city) %s" % [gen.map_name, (t1 - t0) / 1000.0, kinds, tiers])
	await gen.save_map()
	print("SCALE: save %.1f s" % ((Time.get_ticks_msec() - t1) / 1000.0))
	remove_child(gen)
	get_tree().quit(0)
