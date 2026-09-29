extends SceneTree
## Works out the island's land and saves it (Island.BAKED, or the file given
## after --), so the game doesn't have to when it starts. The game's image
## runs this when it's built; for a checkout without Docker:
##   godot --headless --path game --script res://tools/bake_island.gd

const IslandScript := preload("res://scripts/island.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var file: String = args[0] if not args.is_empty() else IslandScript.BAKED
	var t0 := Time.get_ticks_msec()
	var island = IslandScript.new()
	island.build_roads()
	island.bake()
	var err: Error = island.save_baked(file)
	if err != OK:
		printerr("couldn't save %s: %s" % [file, error_string(err)])
		quit(1)
		return
	print("baked the island: %d x %d heights, %.1f s, %s" % [island.width, island.depth,
		(Time.get_ticks_msec() - t0) / 1000.0, file])
	quit(0)
