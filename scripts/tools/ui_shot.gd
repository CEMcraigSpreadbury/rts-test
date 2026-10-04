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
##   --army     field a few bodies of soldiers (one a regiment) and select one,
##              for the unit cards
##   --look     point the camera at the capture point nearest the base
##   --realm    play the match as Realm (settlements, food, no houses)
##   --walls    with --look --realm: wall the settlement in, gates shut
##   --build    select a builder and open its build menu
##   --controls open the controls card
##   --zoom=N   camera distance (gameplay starts at 22, the wheel pulls out to 110)
##   --nograss  hide the Binbun grass blades, as the Grass option does (not saved)
##   --grass    show them even if the player's saved Grass option is off (not saved)
##   --art      the art-reference close-up: a Barracks and Archery Range set
##              down by the Town Center, villagers gathered, trees on the left
##              (the framing of the art-direction reference image)
##   --seed=N   RNG seed, default 12345; fixed so two runs frame the same view
##   --wait=N   seconds to let the match settle before the shot, default 10
##   --tod=F    time of day: 0..1 round a day and night from sunrise (night
##              starts at DayNight.day_share(), about 0.71)

const MAP_PATH: String = "res://scenes/maps/angel_crossing_realm.tscn"
const DIRECTOR_SCRIPT: String = "res://scripts/tools/ui_shot_director.gd"

func _ready() -> void:
	var out: String = ""
	var scene: String = ""
	var plate: bool = false
	var build_menu: bool = false
	var single: bool = false
	var queue: bool = false
	var switch: bool = false
	var army: bool = false
	var look: bool = false
	var realm: bool = false
	var walls: bool = false
	var chat: bool = false
	var controls: bool = false
	var art: bool = false
	var zoom: float = -1.0
	## -1 leaves the player's Grass option alone; 0 forces it off, 1 on.
	var grass: int = -1
	var show_node: String = ""
	var ai_count: int = -1
	var map: String = ""
	var present: String = ""
	var rng_seed: int = 12345
	var wait: float = 10.0
	var time_of_day: float = -1.0

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--scene="):
			scene = arg.trim_prefix("--scene=")
		elif arg == "--plate":
			plate = true
		elif arg == "--build":
			build_menu = true
		elif arg == "--single":
			single = true
		elif arg == "--queue":
			queue = true
		elif arg == "--switch":
			switch = true
		elif arg == "--chat":
			chat = true
		elif arg == "--controls":
			controls = true
		elif arg == "--art":
			art = true
		elif arg == "--nograss":
			grass = 0
		elif arg == "--grass":
			grass = 1
		elif arg.begins_with("--zoom="):
			zoom = float(arg.trim_prefix("--zoom="))
		elif arg == "--army":
			army = true
		elif arg == "--look":
			look = true
		elif arg == "--realm":
			realm = true
		elif arg == "--walls":
			walls = true
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
		elif arg.begins_with("--tod="):
			time_of_day = float(arg.trim_prefix("--tod="))

	if out.is_empty():
		push_error("ui_shot: pass --out=<absolute png path>")
		get_tree().quit(1)
		return

	seed(rng_seed)
	if scene.is_empty():
		Network.start_offline()
		if realm:
			Network.set_match_settings(Network.GameMode.REALM, 0)
		Network.add_ai_player()
		Network.resolve_random_rulers()

	var director := Node.new()
	director.name = "UiShotDirector"
	director.set_script(load(DIRECTOR_SCRIPT))
	director.out_path = out
	director.plate = plate
	director.army = army
	director.look = look
	director.walls = walls
	director.settle = wait
	director.menu_only = not scene.is_empty()
	director.build_menu = build_menu
	director.single = single
	director.queue = queue
	director.switch = switch
	director.chat = chat
	director.controls = controls
	director.art = art
	director.zoom = zoom
	director.grass = grass
	director.show_node = show_node
	director.ai_count = ai_count
	director.present = present
	director.time_of_day = time_of_day
	get_tree().root.add_child.call_deferred(director)

	var target: String = scene if not scene.is_empty() else (map if not map.is_empty() else MAP_PATH)
	SceneLoader.change_scene(target)
