class_name Hud
extends Node
## The bottom-bar HUD split out of main.gd: the resource bar, the info panel
## and the contextual action panel. Reads Main's selection state but never
## owns it — selection changes go through Main (select_building etc.), which
## then asks this to redraw.

var main: Main

## The action panel's grid always has exactly this many slots (4 columns x 3
## rows), padded with blank placeholders, so its size never changes with context.
const ACTION_PANEL_SLOT_COUNT: int = 12
const QUEUE_SLOT_TEXTURE: Texture2D = preload("res://assets/ui/HUD/elements/square_frame_dark.png")
const SELECTION_PORTRAIT_COLUMNS: int = 6
const SELECTION_PORTRAIT_LIMIT: int = 12
const RESOURCE_TICK_RATE: float = 6.0
const RESOURCE_TICK_MIN_SPEED: float = 12.0
const BAR_FRAME_TEXTURE: Texture2D = preload("res://assets/ui/HUD/scaled/bar_frame.png")
const BAR_FILL_TEXTURE: Texture2D = preload("res://assets/ui/HUD/scaled/bar_fill_green.png")
@onready var resource_label: RichTextLabel = main.get_node(^"UI/ResourceLabel")
@onready var info_panel_divider: TextureRect = main.get_node(^"UI/BottomBar/InfoPanel/Margin/VBox/TitleDivider")
@onready var info_panel_name_label: Label = main.get_node(^"UI/BottomBar/InfoPanel/Margin/VBox/BuildingNameLabel")
@onready var info_panel_content: VBoxContainer = main.get_node(^"UI/BottomBar/InfoPanel/Margin/VBox/InfoContainer")
@onready var portrait_frame: TextureRect = main.get_node(^"UI/BottomBar/InfoPanel/PortraitFrame")
@onready var portrait_rect: ColorRect = main.get_node(^"UI/BottomBar/InfoPanel/PortraitFrame/Portrait")
@onready var portrait_health_label: Label = main.get_node(^"UI/BottomBar/InfoPanel/PortraitHealthLabel")

## Single contextual action panel — always visible, its grid's contents and
## title change with the selection: nothing selected shows the construction
## menu, a selected building shows its producibles, selected units show the
## Move/Stop/Attack/Patrol commands.
@onready var action_panel_grid: GridContainer = main.get_node(^"UI/BottomBar/ActionPanel/Margin/VBox/Grid")

## Which unit selection the command panel's buttons were last built for, so
## update() only rebuilds them when the selection actually changed.
var _last_command_panel_units: Array[Unit] = []

## True while the action panel is showing the construction menu on behalf of
## a selected unit's Build button (as opposed to the always-available idle
## construction menu when nothing is selected).
var showing_build_submenu: bool = false
## Command panel info section — built once per selection change, then only
## had their values (not structure) updated every frame, to avoid rebuilding
## Control nodes 60 times a second for something that just needs a number to move.
var _info_progress_bar: TextureProgressBar = null
var _info_empty_label: Label = null
var _info_slot_row: HBoxContainer = null
var _info_last_queue_size: int = -1
## The building state the info section's structure was built for. Ownership and
## construction state both change what gets built (an enemy or half-built
## building has no queue rows), and both can flip while the building stays
## selected — capturing an objective being the obvious case — so the structure
## is rebuilt when either stops matching.
var _info_built_commandable: bool = false
var _info_built_under_construction: bool = false
## item_name -> its producible button's queued-count badge; updated every
## frame in _refresh_building_info() from ProductionBuilding.synced_queue_counts.
var _info_producible_badges: Dictionary = {}
var _info_stats_label: Label = null
## Parallel to _info_portrait_units when more than one is selected.
var _info_unit_portrait_bars: Array[ProgressBar] = []
## The multi-selection in portrait-grid order — monsters first, so they aren't
## lost past SELECTION_PORTRAIT_LIMIT behind a crowd of regular units.
var _info_portrait_units: Array[Unit] = []
## {"button": Button, "unit": Unit, "index": int, "sweep": ColorRect} per
## activated-ability button currently on the command card — see
## _refresh_ability_buttons.
var _ability_buttons: Array[Dictionary] = []
const COOLDOWN_SWEEP_SHADER: Shader = preload("res://shaders/cooldown_sweep.gdshader")
var _info_resource_label: Label = null

## resource_label shows every resource total plus population on one line;
## rebuilt in full on any single change since there are only a handful of values.
var _resource_totals: Dictionary = {}
var _population_used: int = 0
var _population_cap: int = 0

## resource_name -> true while it's one of the ones flashing red because the
## last attempted purchase couldn't afford it — see flash_missing_resources.
var _flashing_resource_names: Dictionary = {}
var _resource_display_totals: Dictionary = {}
var _resource_flash_on: bool = false
var _resource_flash_tween: Tween
const RESOURCE_FLASH_CYCLE_COUNT: int = 4
const RESOURCE_FLASH_INTERVAL: float = 0.15

## Called from Main._ready(), once Main's own @onready nodes exist.
func setup() -> void:
	ResourceStockpile.changed.connect(_on_stockpile_changed)
	Population.changed.connect(_on_population_changed)
	_populate_construction_buttons()

## Ticked by Main._process.
func update(delta: float) -> void:
	_update_resource_ticker(delta)
	if main.selected_building:
		_refresh_building_info()
	elif not main.selected_units.is_empty():
		## Catches every way selected_units can change (drag-select, control
		## groups, a selected unit dying mid-fight) without needing a refresh
		## call at each individual mutation site; only rebuilds the panel's
		## buttons/info structure when the selection actually changed since
		## last frame — otherwise just updates the already-built info values
		## (health, etc.) in place.
		main.prune_selected_units()
		if main.selected_units != _last_command_panel_units:
			refresh_command_panel()
		else:
			_refresh_unit_info_values()
	elif main.selected_resource != null:
		## A gathered-out resource node frees itself (Gatherable.gather()),
		## so this also has to notice when it's no longer valid.
		if not is_instance_valid(main.selected_resource):
			main.select_resource(null)
		else:
			_refresh_resource_info()

func _on_stockpile_changed(resource_name: String, amount: int) -> void:
	## First value for a resource (the starting stockpile) snaps — only later
	## changes are worth counting up to.
	if not _resource_display_totals.has(resource_name):
		_resource_display_totals[resource_name] = float(amount)
	_resource_totals[resource_name] = amount
	_update_resource_label()

## Eases each displayed total toward its real value so income reads as a
## counter ticking up rather than numbers popping between frames.
func _update_resource_ticker(delta: float) -> void:
	var changed := false
	for resource_name in _resource_totals:
		var target := float(_resource_totals[resource_name])
		var current: float = _resource_display_totals.get(resource_name, target)
		if is_equal_approx(current, target):
			continue
		var speed: float = maxf(absf(target - current) * RESOURCE_TICK_RATE, RESOURCE_TICK_MIN_SPEED)
		current = move_toward(current, target, speed * delta)
		if absf(target - current) < 0.5:
			current = target
		_resource_display_totals[resource_name] = current
		changed = true
	if changed:
		_update_resource_label()

func _on_population_changed(used: int, cap: int) -> void:
	_population_used = used
	_population_cap = cap
	_update_resource_label()

func _update_resource_label() -> void:
	var parts: Array[String] = []
	for resource_type in Main.DEBUG_RESOURCE_TYPES:
		var shown: int = int(round(_resource_display_totals.get(resource_type.display_name, float(_resource_totals.get(resource_type.display_name, 0)))))
		var text := "%s: %d" % [resource_type.display_name, shown]
		if _resource_flash_on and _flashing_resource_names.has(resource_type.display_name):
			text = "[color=#ff4433]%s[/color]" % text
		parts.append(text)
	parts.append("Population: %d/%d" % [_population_used, _population_cap])
	resource_label.text = "   ".join(parts)

## Mirrors ResourceStockpile.can_afford(), but against this client's own
## _resource_totals rather than the singleton directly — ResourceStockpile's
## totals are only meaningful on the host (see resource_stockpile.gd), so a
## non-host client calling can_afford() on it directly would always read 0.
func can_afford_locally(costs: Array[ResourceCost]) -> bool:
	for cost in costs:
		if _resource_totals.get(cost.resource_type.display_name, 0) < cost.amount:
			return false
	return true

## Returns the types themselves rather than just their display names so the
## caller can reach each one's insufficient_sound_effects as well as its label.
func _missing_resource_types(costs: Array[ResourceCost]) -> Array[ResourceType]:
	var missing: Array[ResourceType] = []
	for cost in costs:
		if _resource_totals.get(cost.resource_type.display_name, 0) < cost.amount:
			missing.append(cost.resource_type)
	return missing

## Called wherever a purchase is refused locally for lack of funds (building
## placement, producible items). No-ops (no flash) if the costs are actually
## affordable — callers don't need to check can_afford_locally themselves first.
func flash_missing_resources(costs: Array[ResourceCost]) -> void:
	var missing := _missing_resource_types(costs)
	if missing.is_empty():
		return

	## Only the first shortfall is sounded even when a purchase is short on
	## two resources at once: command_audio_player is a single stream, so
	## playing both would just cut the first off mid-sample. The bar still
	## flashes every missing resource.
	AudioUtils.play_random(main.command_audio_player, missing[0].insufficient_sound_effects)

	for resource_type in missing:
		_flashing_resource_names[resource_type.display_name] = true

	if _resource_flash_tween and _resource_flash_tween.is_valid():
		_resource_flash_tween.kill()
	_resource_flash_tween = create_tween()
	for i in RESOURCE_FLASH_CYCLE_COUNT:
		_resource_flash_tween.tween_callback(func():
			_resource_flash_on = not _resource_flash_on
			_update_resource_label()
		).set_delay(RESOURCE_FLASH_INTERVAL)
	_resource_flash_tween.tween_callback(func():
		_flashing_resource_names.clear()
		_resource_flash_on = false
		_update_resource_label()
	)

## The building half of Main.select_building: fills the info panel for any
## building, and the action panel with its producibles if it's ours.
func show_building(building: ProductionBuilding) -> void:
	_show_info_header()
	info_panel_name_label.text = building.building_name
	_update_portrait(building.team_tint, "")
	for child in action_panel_grid.get_children():
		child.queue_free()
	_build_building_info(building)

	if building.is_under_construction:
		if not building.construction_finished.is_connected(_on_selected_building_constructed):
			building.construction_finished.connect(_on_selected_building_constructed.bind(building), CONNECT_ONE_SHOT)
		_fill_action_panel_grid([])
		return

	## Info panel and portrait are filled in above for any owner; the action
	## panel is where "yours to command" starts, so an enemy building simply
	## gets an empty grid instead of its production buttons.
	if not main.can_command_building(building):
		_fill_action_panel_grid([])
		return

	## Rebuilds the menu whenever this building's queue changes — mainly so a
	## just-purchased Blacksmith upgrade's button disappears (and the next
	## tier's appears) immediately rather than only on next reselection.
	## Not CONNECT_ONE_SHOT since more items can complete later; guarded so
	## reselecting the same building doesn't stack duplicate connections.
	if not building.item_completed.is_connected(_on_selected_building_item_completed):
		building.item_completed.connect(_on_selected_building_item_completed.bind(building))

	var buttons: Array[Control] = []
	_info_producible_badges.clear()
	for i in building.producibles.size():
		var item: ProducibleItem = building.producibles[i]
		if not _producible_is_visible(building, item):
			continue
		## Hotkeys map to on-screen position, not the item's true index into
		## producibles — otherwise the visible buttons would jump to
		## whatever hotkey their hidden neighbors happened to occupy.
		var slot: int = buttons.size()
		var hotkey: String = OS.get_keycode_string(Main.PRODUCIBLE_HOTKEYS[slot]) if slot < Main.PRODUCIBLE_HOTKEYS.size() else "?"
		var tooltip := "%s (%s)" % [item.item_name, _format_item_costs(item)]
		var button := _make_command_button(hotkey, tooltip, item.icon, main.on_producible_button_pressed.bind(building, i))
		_info_producible_badges[item.item_name] = _add_queue_count_badge(button)
		buttons.append(button)
	_fill_action_panel_grid(buttons)

## A trainable UNIT is always offered. An UPGRADE is hidden once already
## purchased, and hidden until its prerequisite tier (if any) is purchased —
## only the next actually-buyable tier in a line should ever show, not the
## whole line at once (ProductionBuilding.enqueue() already refuses both
## cases server-side; this just keeps the menu matching what's legal).
func _producible_is_visible(building: ProductionBuilding, item: ProducibleItem) -> bool:
	if item.kind != ProducibleItem.Kind.UPGRADE:
		return true
	if building._purchased_upgrades.has(item):
		return false
	return item.requires_upgrade == null or building._purchased_upgrades.has(item.requires_upgrade)

## The action panel is always visible; this only rebuilds its grid/title and
## the info panel for the current selection when no building is selected:
## the four unit-command buttons if units are selected, a resource node's
## remaining amount if one is selected, otherwise the construction menu.
## (Building content is built by show_building instead.)
func refresh_command_panel() -> void:
	if main.selected_building != null:
		return
	for child in action_panel_grid.get_children():
		child.queue_free()
	for child in info_panel_content.get_children():
		child.queue_free()
	_info_stats_label = null
	_info_unit_portrait_bars.clear()
	_info_portrait_units.clear()
	_info_resource_label = null
	_last_command_panel_units = main.selected_units.duplicate()
	showing_build_submenu = false

	if not main.selected_units.is_empty():
		_show_info_header()
		_populate_unit_command_buttons()
		_build_unit_info()
		_refresh_unit_info_values()
		return

	_populate_construction_buttons()

	if main.selected_resource != null and is_instance_valid(main.selected_resource):
		_show_info_header()
		info_panel_name_label.text = main.selected_resource.display_name
		portrait_frame.visible = false
		portrait_health_label.visible = false
		_info_resource_label = Label.new()
		info_panel_content.add_child(_info_resource_label)
		_refresh_resource_info()
		return

	_clear_info_header()

func _refresh_resource_info() -> void:
	if _info_resource_label and is_instance_valid(main.selected_resource):
		_info_resource_label.text = "%d remaining" % main.selected_resource.amount_remaining

func _populate_construction_buttons() -> void:
	var my_building_types: Array[BuildingType] = main.my_faction().building_types
	var buttons: Array[Control] = []
	for i in my_building_types.size():
		var building_type: BuildingType = my_building_types[i]
		var hotkey: String = OS.get_keycode_string(Main.BUILDING_HOTKEYS[i]) if i < Main.BUILDING_HOTKEYS.size() else "?"
		var tooltip := "%s (%s)" % [building_type.building_name, format_costs(building_type.get_costs())]
		buttons.append(_make_command_button(hotkey, tooltip, building_type.icon, main.placement.on_construction_button_pressed.bind(building_type)))
	_fill_action_panel_grid(buttons)

## The action panel's grid is a fixed-size 4-column layout (see
## ACTION_PANEL_SLOT_COUNT) regardless of how many real buttons a given
## context has, so its on-screen size/shape never changes with selection —
## needed so a frame image can be overlaid on top of it consistently. Unused
## slots are filled with an invisible, non-interactive placeholder of the
## same size instead of just leaving the grid short.
func _fill_action_panel_grid(buttons: Array[Control]) -> void:
	for button in buttons:
		action_panel_grid.add_child(button)
	for i in range(buttons.size(), ACTION_PANEL_SLOT_COUNT):
		action_panel_grid.add_child(_make_empty_action_slot())

func _make_empty_action_slot() -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(40, 40)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot

func open_build_submenu() -> void:
	showing_build_submenu = true
	for child in action_panel_grid.get_children():
		child.queue_free()
	_populate_construction_buttons()
	main.play_command_sound()

func close_build_submenu() -> void:
	showing_build_submenu = false
	for child in action_panel_grid.get_children():
		child.queue_free()
	_populate_unit_command_buttons()

## --- Command panel info section ---

## The info panel's frame is part of the bottom bar's stonework, so it stays
## on screen with nothing selected — only its contents come and go.
func _show_info_header() -> void:
	info_panel_name_label.visible = true
	info_panel_divider.visible = true

func _clear_info_header() -> void:
	info_panel_name_label.visible = false
	info_panel_divider.visible = false
	portrait_frame.visible = false
	portrait_health_label.visible = false

func _update_portrait(tint: Color, health_text: String) -> void:
	portrait_frame.visible = true
	portrait_health_label.visible = true
	portrait_rect.color = tint
	portrait_health_label.text = health_text
	_punch_control(portrait_frame)

func _flat_bar_stylebox(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box

## TextureProgressBar rather than ProgressBar: it clips texture_progress to
## the current value instead of scaling it, so the fill art stays laid out
## across the bar's full width and is revealed as the value climbs. The
## nine-patch margins keep the art's end caps from smearing when the bar is
## wider than the source image.
func _make_progress_bar_with_overlay() -> TextureProgressBar:
	var bar := TextureProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 20)
	bar.max_value = 1.0
	bar.step = 0.0
	bar.texture_under = BAR_FRAME_TEXTURE
	bar.texture_progress = BAR_FILL_TEXTURE
	bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 10
	bar.stretch_margin_right = 10
	bar.stretch_margin_top = 6
	bar.stretch_margin_bottom = 6
	var overlay := Label.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.add_theme_font_size_override("font_size", 12)
	bar.add_child(overlay)
	return bar

## Builds the (structural) queue/construction display once per selection
## change; _refresh_building_info() then just updates values every frame.
func _build_building_info(building: ProductionBuilding) -> void:
	for child in info_panel_content.get_children():
		child.queue_free()
	_info_progress_bar = null
	_info_empty_label = null
	_info_slot_row = null
	_info_last_queue_size = -1
	_info_built_commandable = main.can_command_building(building)
	_info_built_under_construction = building.is_under_construction

	_info_progress_bar = _make_progress_bar_with_overlay()
	info_panel_content.add_child(_info_progress_bar)

	if building.is_under_construction:
		return

	## What an opponent has queued isn't observable from outside their base,
	## so the queue rows are only built for a building you own. Everything
	## above this (name, portrait, health, construction progress) still fills
	## in for an enemy building.
	if not main.can_command_building(building):
		return

	_info_progress_bar.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
				and building.synced_queue_size > 0:
			main.cancel_production(building, 0)
	)

	_info_empty_label = Label.new()
	_info_empty_label.text = "Queue: empty"
	info_panel_content.add_child(_info_empty_label)
	_info_slot_row = HBoxContainer.new()
	_info_slot_row.add_theme_constant_override("separation", 6)
	info_panel_content.add_child(_info_slot_row)

func _refresh_building_info() -> void:
	var building := main.selected_building
	var shown_health: int = int(round(building.health_fraction * building.max_health))
	portrait_health_label.text = "%d / %d" % [shown_health, building.max_health]
	if _info_progress_bar == null 			or _info_built_commandable != main.can_command_building(building) 			or _info_built_under_construction != building.is_under_construction:
		_build_building_info(building)

	if building.is_under_construction:
		_info_progress_bar.value = building.construction_progress
		(_info_progress_bar.get_node("Overlay") as Label).text = _format_construction_status(building)
		return

	## _build_building_info stops before creating the queue rows for a
	## building you don't own, so there's nothing further to update here.
	if not main.can_command_building(building):
		_info_progress_bar.visible = false
		return

	if building.synced_queue_size <= 0:
		_info_progress_bar.visible = false
		_info_empty_label.visible = true
		_info_slot_row.visible = false
		return

	_info_progress_bar.visible = true
	_info_empty_label.visible = false
	_info_slot_row.visible = true
	_info_progress_bar.value = building.synced_current_item_progress
	(_info_progress_bar.get_node("Overlay") as Label).text = "%s (%.1fs)" % [
		building.synced_current_item_name, building.synced_time_remaining
	]

	## Items queued behind the current one (synced_queue_size includes it),
	## shown as blank slots rather than icons since there's no per-item icon
	## art yet — just enough to see how deep the queue is at a glance.
	var queued_behind: int = building.synced_queue_size - 1
	if queued_behind != _info_last_queue_size:
		_info_last_queue_size = queued_behind
		for child in _info_slot_row.get_children():
			child.queue_free()
		for i in queued_behind:
			var slot := TextureButton.new()
			slot.custom_minimum_size = Vector2(24, 24)
			slot.texture_normal = QUEUE_SLOT_TEXTURE
			slot.ignore_texture_size = true
			slot.stretch_mode = TextureButton.STRETCH_SCALE
			slot.focus_mode = Control.FOCUS_NONE
			slot.pressed.connect(main.cancel_production.bind(building, i + 1))
			_info_slot_row.add_child(slot)

	_refresh_producible_badges(building)

func _refresh_producible_badges(building: ProductionBuilding) -> void:
	for item_name in _info_producible_badges:
		var badge: Label = _info_producible_badges[item_name]
		var count: int = building.synced_queue_counts.get(item_name, 0)
		badge.visible = count > 0
		if count > 0:
			badge.text = str(count)

## Builds either a single unit's stat readout or a grid of portrait+health
## widgets for a multi-unit selection — structural, called once per selection
## change; _refresh_unit_info_values() updates values every frame after.
func _build_unit_info() -> void:
	if main.selected_units.size() == 1:
		var unit := main.selected_units[0]
		info_panel_name_label.text = unit.display_name
		_update_portrait(unit.team_tint, "")
		_info_stats_label = Label.new()
		_info_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		_info_stats_label.add_theme_font_size_override("font_size", 14)
		info_panel_content.add_child(_info_stats_label)
		return

	info_panel_name_label.text = "%d units selected" % main.selected_units.size()
	_update_portrait(main.selected_units[0].team_tint, "%d units" % main.selected_units.size())
	var portrait_grid := GridContainer.new()
	portrait_grid.columns = SELECTION_PORTRAIT_COLUMNS
	## Shrink-to-fit, or the columns stretch across the panel and the square
	## portrait slots come out as wide rectangles.
	portrait_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait_grid.add_theme_constant_override("h_separation", 5)
	portrait_grid.add_theme_constant_override("v_separation", 5)
	## Two rows' worth is all the info panel has room for; the name label above
	## already reports the true count when the selection runs past that.
	## Monsters are the only units with innate abilities (Unit.abilities).
	## Stable partition rather than sort_custom, which isn't stable and would
	## shuffle units within each group.
	for unit in main.selected_units:
		if not unit.abilities.is_empty():
			_info_portrait_units.append(unit)
	for unit in main.selected_units:
		if unit.abilities.is_empty():
			_info_portrait_units.append(unit)
	_info_portrait_units.resize(mini(_info_portrait_units.size(), SELECTION_PORTRAIT_LIMIT))
	for unit in _info_portrait_units:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		var portrait := Button.new()
		portrait.custom_minimum_size = Vector2(27, 27)
		portrait.tooltip_text = unit.display_name
		portrait.add_theme_stylebox_override("normal", _flat_bar_stylebox(unit.team_tint))
		portrait.add_theme_stylebox_override("hover", _flat_bar_stylebox(unit.team_tint.lightened(0.3)))
		portrait.add_theme_stylebox_override("pressed", _flat_bar_stylebox(unit.team_tint.darkened(0.2)))
		portrait.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		portrait.pressed.connect(main.select_only_unit.bind(unit))
		cell.add_child(portrait)
		var health_bar := ProgressBar.new()
		health_bar.custom_minimum_size = Vector2(27, 5)
		health_bar.max_value = 1.0
		health_bar.step = 0.0
		health_bar.show_percentage = false
		health_bar.add_theme_stylebox_override("background", _flat_bar_stylebox(Color(0.08, 0.08, 0.09)))
		health_bar.add_theme_stylebox_override("fill", _flat_bar_stylebox(Color(0.35, 0.75, 0.3)))
		cell.add_child(health_bar)
		portrait_grid.add_child(cell)
		_info_unit_portrait_bars.append(health_bar)
	info_panel_content.add_child(portrait_grid)

func _refresh_unit_info_values() -> void:
	_refresh_ability_buttons()
	if main.selected_units.size() == 1:
		var unit := main.selected_units[0]
		portrait_health_label.text = "%d / %d" % [unit.status_current_health, unit.max_health]
		if _info_stats_label:
			_info_stats_label.text = _format_unit_stats(unit)
		return
	for i in _info_unit_portrait_bars.size():
		if is_instance_valid(_info_portrait_units[i]):
			var unit := _info_portrait_units[i]
			_info_unit_portrait_bars[i].value = float(unit.status_current_health) / float(maxi(unit.max_health, 1))

## Health already reads out under the portrait, and the info panel is only as
## wide as the console allows — so these stay short enough not to wrap.
func _format_unit_stats(unit: Unit) -> String:
	var lines: Array[String] = []
	if unit.can_fight:
		lines.append("Dmg %d / %.1fs (rng %.1f)" % [unit.attack_damage, unit.attack_cooldown, unit.attack_range])
	if unit.can_gather:
		lines.append("Gather lvl %d (carries %d)" % [unit.gather_level, unit.carry_capacity])
	lines.append("Speed %.1f" % unit.move_speed)
	return "\n".join(lines)

func _populate_unit_command_buttons() -> void:
	var buttons: Array[Control] = [
		_make_command_button(OS.get_keycode_string(Main.UNIT_MOVE_KEY), "Move", null, main.arm_move_mode),
		_make_command_button(OS.get_keycode_string(Main.UNIT_STOP_KEY), "Stop", null, main.issue_stop_order),
		_make_command_button(OS.get_keycode_string(Main.UNIT_ATTACK_KEY), "Attack", null, main.arm_attack_mode),
		_make_command_button(OS.get_keycode_string(Main.UNIT_PATROL_KEY), "Patrol", null, main.arm_patrol_mode),
	]
	if main.any_selected_can_build():
		buttons.append(_make_command_button(OS.get_keycode_string(Main.UNIT_BUILD_KEY), "Build", null, open_build_submenu))

	## Promotion and abilities only make sense for a single selected unit — a
	## group promote/activate has no sensible target.
	_ability_buttons.clear()
	if main.selected_units.size() == 1:
		var unit := main.selected_units[0]
		var unit_abilities: Array[Ability] = unit.get_abilities()
		for i in unit_abilities.size():
			var ability: Ability = unit_abilities[i]
			var hotkey_label: String = OS.get_keycode_string(Main.ABILITY_HOTKEYS[i]) if i < Main.ABILITY_HOTKEYS.size() else "?"
			var tooltip: String = "%s\n%s" % [ability.ability_name, ability.description] if ability.description != "" else ability.ability_name
			if not ability.is_activated():
				## Shown for visibility (so a player can see what their
				## Monarch grants) but never actionable — it just works
				## continuously, there's nothing to click.
				var button := _make_command_button(hotkey_label, tooltip, ability.icon, func(): pass)
				button.disabled = true
				buttons.append(button)
			else:
				var button := _make_command_button(hotkey_label, tooltip, ability.icon, main.arm_ability.bind(unit, i))
				_ability_buttons.append({"button": button, "unit": unit, "index": i, "sweep": _add_cooldown_sweep(button)})
				buttons.append(button)
		if not unit.is_monarch and unit.can_fight and not unit.monarch_abilities.is_empty() and main.player_has_monarch_unlocked(unit.owner_peer_id):
			buttons.append(_make_command_button("Promote", "Promote to Monarch", null, main.issue_promote_order.bind(unit)))
	_refresh_ability_buttons()
	_fill_action_panel_grid(buttons)

## Greys out an activated ability's button and winds its cooldown sweep down
## while it's cooling — ticked every frame from _refresh_unit_info_values.
func _refresh_ability_buttons() -> void:
	for entry in _ability_buttons:
		var button: Button = entry["button"]
		if not is_instance_valid(button) or not is_instance_valid(entry["unit"]):
			continue
		var remaining: float = entry["unit"].local_cooldown_remaining_fraction(entry["index"])
		button.disabled = not entry["unit"].is_ability_ready_locally(entry["index"])
		var sweep: ColorRect = entry["sweep"]
		sweep.visible = remaining > 0.0
		(sweep.material as ShaderMaterial).set_shader_parameter(&"remaining", remaining)

## Full-size overlay on top of the button (children draw over their parent),
## ignoring the mouse so clicks still reach the button underneath. Each gets
## its own material since `remaining` differs per button.
func _add_cooldown_sweep(button: Button) -> ColorRect:
	var sweep := ColorRect.new()
	sweep.set_anchors_preset(Control.PRESET_FULL_RECT)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = COOLDOWN_SWEEP_SHADER
	sweep.material = material
	sweep.visible = false
	button.add_child(sweep)
	return sweep

func _on_selected_building_constructed(building: ProductionBuilding) -> void:
	if main.selected_building == building:
		main.select_building(building)

func _on_selected_building_item_completed(_item: ProducibleItem, building: ProductionBuilding) -> void:
	if main.selected_building == building:
		main.select_building(building)

func _format_construction_status(building: ProductionBuilding) -> String:
	var percent := int(building.construction_progress * 100)
	if building.synced_builder_count <= 0:
		return "Constructing... %d%% (needs a builder)" % percent
	return "Constructing... %d%% (%d building)" % [percent, building.synced_builder_count]

## Shared by the construction menu, a building's production menu, and the new
## unit-command panel: a square button showing only its hotkey letter (icon
## stays null everywhere today — no icon art exists yet, but the field is
## wired so real art can be dropped in later without touching this code).
func _make_command_button(hotkey_label: String, tooltip: String, icon: Texture2D, callback: Callable) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"SquareButton"
	button.custom_minimum_size = Vector2(40, 40)
	button.text = hotkey_label
	button.tooltip_text = tooltip
	button.icon = icon
	button.pressed.connect(callback)
	button.pressed.connect(_punch_control.bind(button))
	return button

## Quick squash-and-settle on a HUD control, so a click or hotkey visibly
## registers on the panel itself rather than only in the world.
func _punch_control(control: Control) -> void:
	if control.size == Vector2.ZERO:
		return
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * 0.86
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.18)

## Hotkeys drive the same actions as the command-card buttons but never touch
## them, which left the panel looking inert during keyboard play. Buttons are
## labelled with their own hotkey, so that label is the lookup key.
func pulse_action_button(hotkey_label: String) -> void:
	for child in action_panel_grid.get_children():
		var button := child as Button
		if button and button.text == hotkey_label:
			_punch_control(button)
			return

## Small bottom-right count badge for a producible button, showing how many
## of that item are currently queued (including the one in progress). Hidden
## (count 0) rather than removed, so _refresh_building_info() can just flip
## visibility every frame instead of adding/removing nodes.
func _add_queue_count_badge(button: Button) -> Label:
	var badge := Label.new()
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	## Anchored corner is the growth pivot too, so a wider (multi-digit) label
	## expands up-and-left back into the button instead of out past its edge.
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	badge.offset_right = -3
	badge.offset_bottom = -1
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.add_theme_font_size_override("font_size", 20)
	badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	badge.add_theme_constant_override("shadow_offset_x", 1)
	badge.add_theme_constant_override("shadow_offset_y", 1)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	button.add_child(badge)
	return badge

func format_costs(costs: Array[ResourceCost]) -> String:
	var parts: Array[String] = []
	for cost in costs:
		parts.append("%d %s" % [cost.amount, cost.resource_type.display_name])
	return ", ".join(parts)

func _format_item_costs(item: ProducibleItem) -> String:
	var text := format_costs(item.get_costs())
	if item.kind == ProducibleItem.Kind.UNIT:
		text += ", %d Pop" % item.get_population_cost()
	return text
