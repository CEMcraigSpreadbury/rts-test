class_name PowerBar
extends VBoxContainer
## A column under the resource bar: the Research button (opens the
## ResearchPanel), then the local player's unlocked Ruler powers below it —
## one command-card button each, in tree order, hotkeyed from
## Main.POWER_HOTKEYS, with the same cooldown sweep a unit ability gets.
## Clicking (or the hotkey) arms the power; the next left-click on the ground
## casts it there (see Main.arm_power).

const BAR_POSITION: Vector2 = Vector2(16.0, 76.0)
const SEPARATION: int = 4

var main: Main

## [{button: Button, index: int (into the Ruler's nodes), sweep: ColorRect}]
var _entries: Array = []

func _ready() -> void:
	name = "PowerBar"
	position = BAR_POSITION
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", SEPARATION)
	var research_button := Button.new()
	research_button.name = "ResearchButton"
	research_button.text = "Research"
	research_button.focus_mode = Control.FOCUS_NONE
	research_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	research_button.pressed.connect(main.research_panel.toggle)
	## A tutorial can keep research off the HUD until it teaches it.
	research_button.visible = MatchRules.active().hud_allowed(main.my_peer_id(), "research")
	add_child(research_button)
	main.research.owned_changed.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	var research_button: Button = get_node_or_null(^"ResearchButton")
	if research_button != null:
		research_button.visible = MatchRules.active().hud_allowed(main.my_peer_id(), "research")
	for entry in _entries:
		remove_child(entry["button"])
		entry["button"].queue_free()
	_entries.clear()
	var ruler := Research.ruler_for(main.my_peer_id())
	if ruler == null:
		return
	for index in ruler.nodes.size():
		var node: ResearchNode = ruler.nodes[index]
		if node.kind != ResearchNode.Kind.POWER or not main.research.my_owned.has(index):
			continue
		var slot := _entries.size()
		var hotkey_label: String = OS.get_keycode_string(Main.POWER_HOTKEYS[slot]) if slot < Main.POWER_HOTKEYS.size() else ""
		var tooltip: String = "%s\n%s" % [node.node_name, node.description] if node.description != "" else node.node_name
		var button: Button = main.hud._make_command_button(hotkey_label, tooltip, node.icon, main.arm_power.bind(index))
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		add_child(button)
		_entries.append({"button": button, "index": index, "sweep": main.hud._add_cooldown_sweep(button)})

func _process(_delta: float) -> void:
	for entry in _entries:
		var remaining: float = main.research.power_cooldown_remaining_fraction(entry["index"])
		entry["button"].disabled = remaining > 0.0
		var sweep: ColorRect = entry["sweep"]
		sweep.visible = remaining > 0.0
		(sweep.material as ShaderMaterial).set_shader_parameter(&"remaining", remaining)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var slot := Main.POWER_HOTKEYS.find(event.keycode)
	if slot < 0 or slot >= _entries.size():
		return
	if main.game_over or main.local_player_out or main.chat.is_input_open() or main._is_pause_menu_open():
		return
	main.arm_power(_entries[slot]["index"])
	main.hud._punch_control(_entries[slot]["button"])
	get_viewport().set_input_as_handled()
