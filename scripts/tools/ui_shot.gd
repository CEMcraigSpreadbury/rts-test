extends Node
## Boot half of the UI screenshot tool. Starts an offline match, then hands off to
## a director parented to the tree root -- SceneLoader.change_scene frees the boot
## scene, which would take a coroutine running here with it.
##
## Run it with:
##   godot --path . scenes/tools/ui_shot.tscn -- --out=C:/somewhere/after.png
##
## Flags:
##   --scene=P  shoot an arbitrary scene (a menu) instead of starting a match
##   --map=P    start the match on this map instead of MAP_PATH (use a scenario
##              scene to get the quest tracker, dialogue box and briefing)
##   --present=K  ask the quest UI to show "dialogue" or "briefing"
##   --plate    hide the UI layer, giving the bare 3D frame
##   --build    select a builder and open its build menu (shows the race tabs)
##   --pact=N   grant Pact race N first, so its tab is unlocked
##   --seed=N   RNG seed, default 12345; fixed so two runs frame the same view
##   --wait=N   seconds to let the match settle before the shot, default 10

const MAP_PATH: String = "res://scenes/maps/aethermoor_creek.tscn"
const DIRECTOR_SCRIPT: String = "res://scripts/tools/ui_shot_director.gd"

func _ready() -> void:
	var out: String = ""
	var scene: String = ""
	var plate: bool = false
	var build_menu: bool = false
	var pact: String = ""
	var race: String = ""
	var single: bool = false
	var queue: bool = false
	var switch: bool = false
	var chat: bool = false
	var show_node: String = ""
	var ai_count: int = -1
	var map: String = ""
	var present: String = ""
	var rng_seed: int = 12345
	var wait: float = 10.0

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--scene="):
			scene = arg.trim_prefix("--scene=")
		elif arg == "--plate":
			plate = true
		elif arg == "--build":
			build_menu = true
		elif arg.begins_with("--pact="):
			pact = arg.trim_prefix("--pact=")
		elif arg.begins_with("--race="):
			race = arg.trim_prefix("--race=")
		elif arg == "--single":
			single = true
		elif arg == "--queue":
			queue = true
		elif arg == "--switch":
			switch = true
		elif arg == "--chat":
			chat = true
		elif arg.begins_with("--show="):
			show_node = arg.trim_prefix("--show=")
		elif arg.begins_with("--skirmish="):
			ai_count = int(arg.trim_prefix("--skirmish="))
		elif arg.begins_with("--map="):
			map = arg.trim_prefix("--map=")
		elif arg.begins_with("--present="):
			present = arg.trim_prefix("--present=")
		elif arg.begins_with("--seed="):
			rng_seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--wait="):
			wait = float(arg.trim_prefix("--wait="))

	if out.is_empty():
		push_error("ui_shot: pass --out=<absolute png path>")
		get_tree().quit(1)
		return

	seed(rng_seed)
	if scene.is_empty():
		Network.start_offline()
		Network.add_ai_player()
		Network.resolve_random_rulers()

	var director := Node.new()
	director.name = "UiShotDirector"
	director.set_script(load(DIRECTOR_SCRIPT))
	director.out_path = out
	director.plate = plate
	director.settle = wait
	director.menu_only = not scene.is_empty()
	director.build_menu = build_menu
	director.pact = pact
	director.race = race
	director.single = single
	director.queue = queue
	director.switch = switch
	director.chat = chat
	director.show_node = show_node
	director.ai_count = ai_count
	director.present = present
	get_tree().root.add_child.call_deferred(director)

	var target: String = scene if not scene.is_empty() else (map if not map.is_empty() else MAP_PATH)
	SceneLoader.change_scene(target)
