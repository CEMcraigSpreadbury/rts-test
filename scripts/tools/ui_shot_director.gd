extends Node
## Drives one UI screenshot and quits. Set up by scripts/tools/ui_shot.gd, which
## documents the flags.
##
## Two things have to be neutralised or an in-game frame is not reproducible:
## edge panning is a user setting and the capture leaves the mouse at (0,0),
## which reads as "pan left and up" and flies the camera off the map during the
## settle; and the camera rig's authored position is not the player's base.

var out_path: String = ""
var plate: bool = false
var settle: float = 10.0
var menu_only: bool = false
var build_menu: bool = false
var pact: String = ""
var race: String = ""
var single: bool = false
var queue: bool = false
var switch: bool = false
var chat: bool = false
var show_node: String = ""
## -1 leaves the skirmish screen alone; 0 or more opens it with that many AI.
var ai_count: int = -1
## "dialogue" or "briefing" -- only meaningful on a scenario map.
var present: String = ""

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if menu_only:
		await _run_menu()
		return
	await _run_match()

## --- menu scenes ---

func _run_menu() -> void:
	await _wait(settle)
	var scene: Node = get_tree().current_scene

	if ai_count >= 0:
		## The skirmish screen only grows player rows once an offline peer
		## exists, which is what the Single Player button sets up.
		if scene != null and scene.has_method("_on_single_player_pressed"):
			scene.call("_on_single_player_pressed")
			await _wait(0.4)
			for _i in ai_count:
				Network.add_ai_player()
			await _wait(0.5)
		await _shoot()
		return

	if not show_node.is_empty():
		_reveal(scene)
		await _wait(0.6)
	await _shoot()

## Shows a panel that starts hidden, and populates it if it knows how.
func _reveal(scene: Node) -> void:
	if scene == null:
		return
	var target: Control = scene.get_node_or_null(NodePath(show_node))
	if target == null:
		push_warning("ui_shot: no node at " + show_node)
		return
	target.visible = true
	for node in [target] + target.get_children():
		if _has_no_arg_open(node):
			node.call("open")
			return
		## CampaignMenu.open() needs a campaign, so it cannot be called blindly.
		if node.name == "CampaignMenu" and node.has_method("open"):
			var campaigns: Array = Campaign.list_all()
			if not campaigns.is_empty():
				node.call("open", campaigns[0])
			return

## --- in-game frames ---

func _run_match() -> void:
	## The boot scene is freed the moment the map loads, so the map's root has to
	## be waited for rather than read once -- reading it early hands back a
	## previously freed instance.
	var main: Node = await _await_map()
	if main == null:
		push_error("ui_shot: map never became the current scene")
		get_tree().quit(1)
		return

	## Disabled before the settle, not after: with the mouse at (0,0) edge
	## panning reads as "pan left and up" and flies the camera off the map.
	var rig: Node = main.get_node_or_null("CameraRig")
	if rig != null and "edge_pan_enabled" in rig:
		rig.edge_pan_enabled = false

	await _wait(settle)

	var town_centre: Object = null
	if main.get("town_centers") != null:
		town_centre = main.town_centers.get(main.my_peer_id())
	if town_centre != null and town_centre is Node3D:
		main.focus_camera_on(town_centre.global_position)

	if plate:
		var ui: CanvasLayer = main.get_node_or_null("UI")
		if ui != null:
			ui.visible = false
	elif build_menu:
		await _open_build_menu(main)
	elif switch:
		await _select_building_then_units(main, town_centre)
	elif single:
		main.call("_select_all_idle_villagers")
		await _wait(0.4)
		if not main.selected_units.is_empty():
			main.select_only_unit(main.selected_units[0])
	elif town_centre != null:
		main.select_building(town_centre)
		if queue:
			await _wait(0.3)
			for _i in 3:
				main.on_producible_button_pressed(town_centre, 0)

	if not show_node.is_empty():
		var node: Control = main.get_node_or_null(NodePath(show_node))
		if node == null:
			push_warning("ui_shot: no node at " + show_node)
		elif node.has_method("toggle"):
			## Panels that lay themselves out when opened (the research tree
			## positions its nodes in _refresh) must go through their own entry
			## point -- setting `visible` leaves every node stacked at the origin.
			node.call("toggle")
		else:
			node.visible = true

	if not present.is_empty():
		_present(main)
		await _wait(0.6)

	if chat:
		main.chat.send_line(main.my_peer_id(), "Ready when you are")
		main.chat.open_chat_input()

	await _wait(1.5)
	await _shoot()

## A builder with its build menu open: the one state that shows the race tabs.
## The tracker, dialogue box and briefing only exist on a scenario map, where
## Main builds a QuestUi. Presentations normally come from the host's
## QuestRunner; this pushes one straight in so the panel can be photographed.
func _present(main: Node) -> void:
	var quest_ui: Node = main.get("quest_ui")
	if quest_ui == null:
		push_warning("ui_shot: no quest_ui -- is this a scenario map?")
		return
	if present == "dialogue":
		## A scenario usually opens with its own briefing, and the dialogue box
		## deliberately hides behind one -- so dismiss it first.
		if quest_ui.call("is_presenting"):
			quest_ui.call("_close_briefing")
			await _wait(0.3)
		quest_ui.call("_on_presentation", {
			"kind": "dialogue",
			"speaker": "Thornwarden Ysolde",
			"text": "The grove remembers every axe that ever touched it. Cut here and the roots will answer, but spare the elder trees and my kin will march under your banner.",
		})
	elif present == "briefing":
		quest_ui.call("_on_presentation", {
			"kind": "briefing",
			"title": "The Druid's Grove",
			"text": "Come with fewer than ten soldiers, spare the elder trees, and the grove may yet march under your banner. Bring an army and Ysolde will bury it.",
		})

func _open_build_menu(main: Node) -> void:
	if not pact.is_empty():
		## Pacts declares a class_name, so the bare identifier is the class. The
		## live instance is a node on Main.
		main.pacts.grant(main.my_peer_id(), pact)
		await _wait(0.5)
	main.call("_select_all_idle_villagers")
	await _wait(0.4)
	main.hud.open_build_submenu()
	if not race.is_empty():
		await _wait(0.3)
		main.hud._race_tabs.select_race(StringName(race))

## Reproduces the reported sequence: a building selected (which builds the
## production queue row), then a unit selection. The queue row must not survive.
func _select_building_then_units(main: Node, town_centre: Object) -> void:
	if town_centre != null:
		main.select_building(town_centre)
		await _wait(0.4)
		main.on_producible_button_pressed(town_centre, 0)
		await _wait(0.6)
	main.call("_select_all_idle_villagers")
	await _wait(0.5)

## Polls until the map scene is up, or gives up after ~8 seconds.
func _await_map() -> Node:
	for _i in 160:
		var scene: Node = get_tree().current_scene
		if is_instance_valid(scene) and scene.get_node_or_null("CameraRig") != null:
			return scene
		await _wait(0.05)
	return null

## --- shared ---

## True when `node` has an `open()` that takes no arguments.
static func _has_no_arg_open(node: Object) -> bool:
	for method in node.get_method_list():
		if method["name"] == "open":
			return (method["args"] as Array).is_empty()
	return false

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _shoot() -> void:
	for _i in 6:
		await RenderingServer.frame_post_draw
	var image: Image = get_tree().root.get_texture().get_image()
	var err: int = image.save_png(out_path)
	print("UI_SHOT %s err=%d size=%s" % [out_path, err, image.get_size()])
	get_tree().quit(0 if err == OK else 1)
