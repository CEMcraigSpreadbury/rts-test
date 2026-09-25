class_name Hud
extends Node
## The bottom-bar HUD split out of main.gd: the resource bar, the info panel
## and the contextual action panel. Reads Main's selection state but never
## owns it — selection changes go through Main (select_building etc.), which
## then asks this to redraw.

var main: Main

## The action panel's grid always has exactly this many slots (4 columns x 3
## rows), padded with blank placeholders, so its size never changes with context.
## 9 x 2. Every roster in the game fits, so the command grid never pages.
const ACTION_PANEL_SLOT_COUNT: int = 18
## The queue row is always this many slots, filled from the left by queue depth.
## A row that appeared and grew with the queue pushed the command grid down every
## time production started.
const QUEUE_SLOT_COUNT: int = 5
const SELECTION_PORTRAIT_COLUMNS: int = 9
const SELECTION_PORTRAIT_LIMIT: int = 9
const RESOURCE_TICK_RATE: float = 6.0
const RESOURCE_TICK_MIN_SPEED: float = 12.0
@onready var stockpile: StockpileBar = main.get_node(^"UI/Stockpile")
@onready var info_panel_divider: Control = main.get_node(^"UI/BottomBar/InfoPanel/Margin/VBox/TitleDivider")
@onready var info_panel_name_label: Label = main.get_node(^"UI/BottomBar/InfoPanel/Margin/VBox/BuildingNameLabel")
@onready var info_panel_content: VBoxContainer = main.get_node(^"UI/BottomBar/InfoPanel/Margin/VBox/InfoContainer")
@onready var info_panel: Control = main.get_node(^"UI/BottomBar/InfoPanel")
@onready var portrait_frame: Control = main.get_node(^"UI/BottomBar/InfoPanel/PortraitFrame")
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
## Which page of the construction menu is showing. The action panel's frame
## art fixes it at ACTION_PANEL_SLOT_COUNT slots, and the Human roster already
## fills every one, so anything past that (the Pact Hall, and an allied race's
## buildings in due course) lives on a further page reached by the last slot.
## Which allied race's buildings the construction menu is showing, or null for
## the player's own (Human) roster. Set by the category buttons a Pact adds to
## the build menu (see Pacts).
var _construction_race: PactRace = null
var _race_tabs: RaceTabStrip = null
## Command panel info section — built once per selection change, then only
## had their values (not structure) updated every frame, to avoid rebuilding
## Control nodes 60 times a second for something that just needs a number to move.
var _info_progress_bar: ProgressBar = null
var _info_slot_row: HBoxContainer = null
var _info_last_queue_size: int = -1
## Depth plus contents, so a same-depth change of item still restyles.
var _info_last_queue_signature: String = ""
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
## item_name -> its UNIT button's infinity badge, shown while that item is the
## building's synced_repeat_item_name.
var _info_repeat_badges: Dictionary = {}
## The selected building's UNIT buttons, greyed out alongside the badges above
## while ProductionBuilding.synced_unit_limit_reached. Untyped: they're freed
## whenever the panel rebuilds.
var _info_unit_buttons: Array = []
## Caption -> the value line under it, for the single-unit stat row.
var _info_stat_values: Dictionary = {}
## Parallel to _info_portrait_units when more than one is selected.
var _info_unit_portrait_bars: Array[ProgressBar] = []
## The multi-selection in portrait-grid order — monsters first, so they aren't
## lost past SELECTION_PORTRAIT_LIMIT behind a crowd of regular units.
var _info_portrait_units: Array[Unit] = []
## The selected unit's face, drawn over portrait_rect's team colour. Built on
## first use.
var _portrait_head: TextureRect = null
## {"button": Button, "unit": Unit, "index": int, "sweep": ColorRect} per
## activated-ability button currently on the command card — see
## _refresh_ability_buttons.
var _ability_buttons: Array[Dictionary] = []
## Toggle-mode command button; its pressed look follows the selection's
## replicated hold_position every frame rather than the click itself.
var _hold_button: Button = null
const COOLDOWN_SWEEP_SHADER: Shader = preload("res://shaders/cooldown_sweep.gdshader")
var _info_resource_label: Label = null

## resource_label shows every resource total plus population on one line;
## rebuilt in full on any single change since there are only a handful of values.
var _resource_totals: Dictionary = {}
var _population_used: int = 0
var _population_cap: int = 0
## The separate allied-race pool (see PopulationPool.Kind.PACT), only shown once
## the player has actually built something that grants pact room.
var _pact_population_used: int = 0
var _pact_population_cap: int = 0
## Realm only: what this player's army eats a minute (see RealmEconomy).
var _food_upkeep: int = 0
## The army's cards along the bottom of the screen.
var unit_cards: UiUnitCardStrip

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
	main.realm_economy.upkeep_changed.connect(_on_upkeep_changed)
	## An unlock is granted at one building and opens buttons on another, so
	## the selected building's own item_completed never fires for it.
	UnitUnlocks.unlocks_changed.connect(_on_unlocks_changed)
	portrait_frame.add_theme_stylebox_override("panel",
			UiStyle.slot_box(UiStyle.LINE_STRONG))
	unit_cards = UiUnitCardStrip.new()
	unit_cards.setup(main)
	main.get_node(^"UI").add_child(unit_cards)
	_build_race_tabs()
	_populate_construction_buttons()

## The Pact race tabs. They live above the selection panel rather than inside
## it, so switching race can never move or resize the panel, and they are only
## visible while a builder is selected -- a barracks has no races to offer.
func _build_race_tabs() -> void:
	_race_tabs = RaceTabStrip.new()
	_race_tabs.name = "RaceTabs"
	_race_tabs.visible = false
	_race_tabs.race_selected.connect(_on_race_tab_selected)
	info_panel.get_parent().add_child(_race_tabs)
	_race_tabs.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_position_race_tabs()

func _position_race_tabs() -> void:
	if _race_tabs == null:
		return
	## The strip's height is not known until it has been laid out once, so it
	## re-seats itself on every resize instead of being placed a single time.
	if not _race_tabs.resized.is_connected(_position_race_tabs):
		_race_tabs.resized.connect(_position_race_tabs)
	## Anchored to the bottom edge like the panel, then lifted by the panel's
	## own height plus the strip's, so it sits on the panel's top border.
	_race_tabs.offset_left = info_panel.offset_left + RaceTabStrip.OFFSET_FROM_INSET
	_race_tabs.offset_top = info_panel.offset_top - _race_tabs.size.y
	_race_tabs.offset_bottom = info_panel.offset_top

func _on_race_tab_selected(race_id: StringName) -> void:
	var race: PactRace = null
	if race_id != &"aldmere":
		for page in Pacts.building_pages(main.my_peer_id()):
			if StringName(str(page["race"].race_name).to_snake_case()) == race_id:
				race = page["race"]
				break
	if race == _construction_race:
		return
	_construction_race = race
	_clear_command_column()
	_populate_construction_buttons()

## Rebuilt whenever the construction menu is populated, because a Pact sealed
## mid-match adds a tab.
func _refresh_race_tabs() -> void:
	if _race_tabs == null:
		return
	var pages: Array[Dictionary] = Pacts.building_pages(main.my_peer_id())
	var wanted: Array = [{"id": &"aldmere", "name": "Aldmere", "colour": UiStyle.ACCENT, "unlocked": true}]
	for race_all in Pacts.list_all():
		var unlocked := false
		for page in pages:
			if page["race"] == race_all:
				unlocked = true
				break
		wanted.append({
			"id": StringName(str(race_all.race_name).to_snake_case()),
			"name": race_all.race_name,
			"colour": race_all.display_color,
			"unlocked": unlocked,
		})
	if _race_tabs.matches(wanted):
		_race_tabs.visible = showing_build_submenu
		return
	_race_tabs.rebuild(wanted)
	_race_tabs.visible = showing_build_submenu
	_position_race_tabs()

func _on_unlocks_changed() -> void:
	if main.selected_building != null:
		show_building(main.selected_building)

## Ticked by Main._process.
func update(delta: float) -> void:
	_update_resource_ticker(delta)
	if main.selected_building:
		## A building that has started sinking (razed, or a site its owner
		## cancelled) is gone as far as commands go, so it hands the panels
		## back immediately instead of sitting there until it frees itself.
		if main.selected_building.is_destroyed:
			main.select_building(null)
		else:
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

func _on_population_changed(used: int, cap: int, pool: int) -> void:
	if pool == int(PopulationPool.Kind.PACT):
		_pact_population_used = used
		_pact_population_cap = cap
	else:
		_population_used = used
		_population_cap = cap
	_update_resource_label()

func _on_upkeep_changed(food_per_minute: int, _gold_per_minute: int, _starving: bool) -> void:
	_food_upkeep = food_per_minute
	_update_resource_label()

func _update_resource_label() -> void:
	var entries: Array = []
	var realm := MatchRules.realm()
	for resource_type in Main.DEBUG_RESOURCE_TYPES:
		## Favour is the Conquest score and nothing else: it's shown on the
		## ConquestHud's score bars, never spent, so it has no place here.
		if resource_type == Main.FAVOUR_RESOURCE:
			continue
		## Food only exists in a Realm match, where it carries the army's upkeep.
		if resource_type == RealmEconomy.FOOD:
			if realm:
				var food := _stockpile_entry(resource_type.display_name, false)
				food["rate"] = -_food_upkeep
				entries.append(food)
			continue
		entries.append(_stockpile_entry(resource_type.display_name, false))
	## An allied race's currency joins the bar only once its Pact is made --
	## before that it is nothing the player can earn or spend.
	for page in Pacts.building_pages(main.my_peer_id()):
		var currency: ResourceType = page["race"].currency
		if currency == null:
			continue
		entries.append(_stockpile_entry(currency.display_name, true))
	## Realm has no population cap to show (only a ceiling nobody meets).
	if not realm:
		entries.append({"name": "Population", "amount": _population_used,
				"cap": _population_cap, "flash": false, "accent": false})
	if _pact_population_cap > 0:
		entries.append({"name": "Pact", "amount": _pact_population_used,
				"cap": _pact_population_cap, "flash": false, "accent": true})
	stockpile.set_entries(entries)

func _stockpile_entry(display_name: String, accent: bool) -> Dictionary:
	var shown: int = int(round(_resource_display_totals.get(display_name,
			float(_resource_totals.get(display_name, 0)))))
	return {
		"name": display_name,
		"amount": shown,
		"flash": _resource_flash_on and _flashing_resource_names.has(display_name),
		"accent": accent,
	}

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
	_update_portrait(building.team_tint, "", _building_icon(building.building_name))
	_clear_command_column()
	_build_building_info(building)

	if building.is_under_construction:
		if not building.construction_finished.is_connected(_on_selected_building_constructed):
			building.construction_finished.connect(_on_selected_building_constructed.bind(building), CONNECT_ONE_SHOT)
		## Nothing can be produced here yet, so the only command a half-built
		## site of yours offers is abandoning it for a refund.
		var construction_buttons: Array[Control] = []
		if main.can_command_building(building):
			construction_buttons.append(
				_make_command_button("X", "Cancel Construction", [], null, main.cancel_construction.bind(building))
			)
		_fill_action_panel_grid(construction_buttons)
		return

	## Info panel and portrait are filled in above for any owner; the action
	## panel is where "yours to command" starts, so an enemy building simply
	## gets an empty grid instead of its production buttons.
	if not main.can_command_building(building):
		## Cleared here as well as below: these hold Labels living inside the
		## buttons this grid is about to drop. Leaving them behind is what
		## made capturing a Shrine you had selected walk freed nodes in
		## _refresh_producible_badges.
		_info_producible_badges.clear()
		_info_repeat_badges.clear()
		_info_unit_buttons.clear()
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
	_info_repeat_badges.clear()
	_info_unit_buttons.clear()
	for i in building.producibles.size():
		var item: ProducibleItem = building.producibles[i]
		if not _producible_is_visible(building, item):
			continue
		## A scenario may not have unlocked this one yet.
		if not MatchRules.active().item_allowed(building.owner_peer_id, item.item_name):
			continue
		## Hotkeys map to on-screen position, not the item's true index into
		## producibles — otherwise the visible buttons would jump to
		## whatever hotkey their hidden neighbors happened to occupy.
		var slot: int = buttons.size()
		var hotkey: String = OS.get_keycode_string(Main.PRODUCIBLE_HOTKEYS[slot]) if slot < Main.PRODUCIBLE_HOTKEYS.size() else "?"
		var tooltip := "%s (%s)" % [item.item_name, _format_item_costs(item, building)]
		var button := _make_command_button(hotkey, item.item_name,
				_tooltip_costs(building.costs_for(item)), item.icon,
				main.on_producible_button_pressed.bind(building, i))
		_info_producible_badges[item.item_name] = _add_queue_count_badge(button)
		if item.kind == ProducibleItem.Kind.UNIT:
			_info_unit_buttons.append(button)
			_info_repeat_badges[item.item_name] = _add_repeat_badge(button)
			button.gui_input.connect(_on_producible_gui_input.bind(building, i))
		buttons.append(button)
	_fill_action_panel_grid(buttons)

## A trainable UNIT is always offered. An UPGRADE is hidden once already
## purchased, and hidden until its prerequisite tier (if any) is purchased —
## only the next actually-buyable tier in a line should ever show, not the
## whole line at once (ProductionBuilding.enqueue() already refuses both
## cases server-side; this just keeps the menu matching what's legal).
func _producible_is_visible(building: ProductionBuilding, item: ProducibleItem) -> bool:
	## Not researched yet: the Cavalier stays off the Stables until Lances is
	## bought, and the upgrade that granted it leaves every Blacksmith's menu
	## once it has been (ProductionBuilding.enqueue() refuses both server-side).
	if not UnitUnlocks.has(building.owner_peer_id, item.requires_unlock):
		return false
	if item.grants_unlock != &"" and UnitUnlocks.has(building.owner_peer_id, item.grants_unlock):
		return false
	## A Pact leaves the menu once this hall has sealed one, and a race
	## already allied with elsewhere is off the menu everywhere.
	if item.kind == ProducibleItem.Kind.PACT:
		if not building.synced_pact_name.is_empty():
			return false
		return item.pact_race != null and not Pacts.has_pact(building.owner_peer_id, item.pact_race.race_name)
	if item.kind == ProducibleItem.Kind.SLOT:
		return building.settlement != null and building.settlement.slot_open(item) \
				and building.settlement.choice_peer != building.owner_peer_id
	if item.kind == ProducibleItem.Kind.CHOICE:
		return building.settlement != null and building.settlement.choice_peer == building.owner_peer_id
	if item.kind == ProducibleItem.Kind.TIER:
		return building.settlement != null and building.settlement.tier == item.tier_to - 1 \
				and building.settlement.choice_peer != building.owner_peer_id
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
	_clear_command_column()
	for child in info_panel_content.get_children():
		child.queue_free()
	_info_stat_values.clear()
	_info_unit_portrait_bars.clear()
	_info_portrait_units.clear()
	_info_resource_label = null
	_last_command_panel_units = main.selected_units.duplicate()
	showing_build_submenu = false
	_construction_race = null

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
		_info_resource_label.text = "%d remaining" % main.selected_resource.display_remaining()

func _populate_construction_buttons() -> void:
	var building_types: Array[BuildingType] = current_construction_types()
	var buttons: Array[Control] = []
	var rules := MatchRules.active()
	var me: int = main.my_peer_id()
	for i in building_types.size():
		var building_type: BuildingType = building_types[i]
		## Each type keeps its own hotkey whether or not the ones before it are
		## available, so a scenario locking one doesn't move the others.
		if not rules.building_allowed(me, building_type.building_name):
			continue
		var hotkey: String = OS.get_keycode_string(Main.BUILDING_HOTKEYS[i]) if i < Main.BUILDING_HOTKEYS.size() else "?"
		var costs: Array[ResourceCost] = rules.scaled_costs(me, building_type.get_costs())
		buttons.append(_make_letter_slot(hotkey, building_type.building_name,
				_tooltip_costs(costs), can_afford_locally(costs),
				main.placement.on_construction_button_pressed.bind(building_type)))
	## Allied races are reached by the tab strip above the panel rather than by a
	## category button that would spend a command slot and hide the roster.
	_refresh_race_tabs()
	_fill_action_panel_grid(buttons)

## Which roster the construction menu is currently offering — the player's own
## or, on a Pact race's page, that race's. Also what the build hotkeys place,
## so they always match what's on screen (see Main._unhandled_input).
func current_construction_types() -> Array[BuildingType]:
	if _construction_race != null:
		return _construction_race.building_types
	return main.my_faction().building_types

func _fill_action_panel_grid(buttons: Array[Control]) -> void:
	for button in buttons:
		action_panel_grid.add_child(button)
	for i in range(buttons.size(), _grid_slot_count(buttons.size())):
		action_panel_grid.add_child(_make_empty_action_slot())

## The command area is a fixed height, and a selected building spends its top row
## on the production queue -- so a building pads to one row of slots and
## everything else to the full two.
func _grid_slot_count(used: int) -> int:
	if main.selected_building == null:
		return ACTION_PANEL_SLOT_COUNT
	var rows: int = maxi(1, ceili(float(used) / float(UiStyle.CMD_COLUMNS)))
	return rows * UiStyle.CMD_COLUMNS

## Clears everything the command column owns. The production queue row is a
## sibling of the grid, not one of its children, so clearing only the grid
## left a stale queue row behind after a building selection -- the "stuck
## extra row".
## A building's producible list is the only place an item's icon lives.
func _producible_icon(building: ProductionBuilding, item_name: String) -> Texture2D:
	if item_name.is_empty():
		return null
	for item in building.producibles:
		if item.item_name == item_name:
			return item.icon
	return null

func _clear_command_column() -> void:
	for child in action_panel_grid.get_children():
		child.queue_free()
	if _info_slot_row != null and is_instance_valid(_info_slot_row):
		_info_slot_row.queue_free()
	_info_slot_row = null
	_info_last_queue_size = -1
	_info_last_queue_signature = ""

func _make_empty_action_slot() -> Control:
	var slot := CommandSlot.new()
	slot.make_empty()
	return slot

func open_build_submenu() -> void:
	if not MatchRules.active().hud_allowed(main.my_peer_id(), "build"):
		return
	showing_build_submenu = true
	_construction_race = null
	if _race_tabs != null:
		_race_tabs.select_race(&"aldmere")
	_clear_command_column()
	_populate_construction_buttons()
	main.play_command_sound()

func close_build_submenu() -> void:
	showing_build_submenu = false
	if _race_tabs != null:
		_race_tabs.visible = false
	_clear_command_column()
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

## `head`: the selected unit's face (UnitPortrait) over its team colour;
## null for a building, which shows the colour alone.
func _update_portrait(tint: Color, health_text: String, head: Texture2D = null) -> void:
	portrait_frame.visible = true
	portrait_health_label.visible = true
	## A wash rather than a fill: the well stays dark so the sprite on top of it
	## reads, and the team colour is still legible around it.
	portrait_rect.color = Color(tint.r, tint.g, tint.b, 0.22)
	if _portrait_head == null:
		_portrait_head = TextureRect.new()
		_portrait_head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_portrait_head.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		## Pixel art: crisp rather than smeared when blown up.
		_portrait_head.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_portrait_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_rect.add_child(_portrait_head)
		_portrait_head.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait_head.texture = head
	_portrait_head.visible = head != null
	portrait_health_label.text = health_text
	_punch_control(portrait_frame)

## A placed building knows its name but not its BuildingType, and the icon lives
## on the type. Searched across the player's own roster and every Pact race so an
## allied building gets its portrait too.
func _building_icon(building_name: String) -> Texture2D:
	for building_type in main.my_faction().building_types:
		if building_type.building_name == building_name:
			return building_type.icon
	for race in Pacts.list_all():
		for building_type in race.building_types:
			if building_type.building_name == building_name:
				return building_type.icon
	return null

## A tray portrait slot: the command-slot well, washed with the unit's team
## colour so sides stay tellable apart without hiding the sprite.
func _tray_slot_box(tint: Color, border: Color = UiStyle.LINE) -> StyleBoxFlat:
	var box := UiStyle.slot_box(border)
	box.bg_color = Color(tint.r, tint.g, tint.b, 0.30).blend(UiStyle.SLOT)
	return box

func _flat_bar_stylebox(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box

## TextureProgressBar rather than ProgressBar: it clips texture_progress to
## the current value instead of scaling it, so the fill art stays laid out
## across the bar's full width and is revealed as the value climbs. The
## nine-patch margins keep the art's end caps from smearing when the bar is
## wider than the source image.
## A themed ProgressBar rather than a stretched bitmap: the well and the fill
## both come from the tokens, so it matches every other bar in the game.
func _make_progress_bar_with_overlay() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0.0, 30.0)
	bar.max_value = 1.0
	bar.step = 0.0
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", UiStyle.slot_box())
	bar.add_theme_stylebox_override("fill",
			UiStyle.flat(UiStyle.GOOD, UiStyle.GOOD, UiStyle.RADIUS_SLOT))
	var overlay := Label.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.add_theme_font_size_override("font_size", 20)
	bar.add_child(overlay)
	return bar

## Builds the (structural) queue/construction display once per selection
## change; _refresh_building_info() then just updates values every frame.
func _build_building_info(building: ProductionBuilding) -> void:
	for child in info_panel_content.get_children():
		child.queue_free()
	_info_progress_bar = null
	_info_slot_row = null
	_info_last_queue_size = -1
	_info_last_queue_signature = ""
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

	_info_slot_row = HBoxContainer.new()
	_info_slot_row.add_theme_constant_override("separation", 6)
	## Fixed height, always present, always the same number of slots -- nothing
	## below it may move when the queue changes.
	_info_slot_row.custom_minimum_size = Vector2(0, UiStyle.SLOT_QUEUE)
	for i in QUEUE_SLOT_COUNT:
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(UiStyle.SLOT_QUEUE, UiStyle.SLOT_QUEUE)
		slot.focus_mode = Control.FOCUS_NONE
		slot.pressed.connect(main.cancel_production.bind(building, i + 1))
		## The portrait is added now and only its texture changes later, so the
		## row's size never depends on what is queued.
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		UiStyle.make_pixel_crisp(icon)
		slot.add_child(icon)
		_info_slot_row.add_child(slot)
	## Above the command grid rather than in the info band: the band has room
	## for a name and one row, and the queue is the row players watch.
	var command_column: Node = action_panel_grid.get_parent()
	command_column.add_child(_info_slot_row)
	command_column.move_child(_info_slot_row, 0)
	_info_last_queue_size = -1
	_info_last_queue_signature = ""

func _refresh_building_info() -> void:
	var building := main.selected_building
	var shown_health: int = int(round(building.health_fraction * building.max_health))
	portrait_health_label.text = "%d / %d" % [shown_health, building.max_health]
	if _info_built_commandable != main.can_command_building(building):
		## It changed hands (or finished being captured) while selected: the
		## action panel's producibles belong to the new owner now, so the
		## whole selection is rebuilt rather than just the info side.
		show_building(building)
		return
	if _info_progress_bar == null \
			or _info_built_under_construction != building.is_under_construction:
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

	_refresh_producible_badges(building)

	if building.synced_queue_size <= 0:
		_info_progress_bar.visible = false
		_style_queue_slots(0, building)
		return

	_info_progress_bar.visible = true
	_info_progress_bar.value = building.synced_current_item_progress
	(_info_progress_bar.get_node("Overlay") as Label).text = "%s (%.1fs)" % [
		building.synced_current_item_name, building.synced_time_remaining
	]

	## Items queued behind the current one (synced_queue_size includes it),
	## shown as blank slots rather than icons since there's no per-item icon
	## art yet — just enough to see how deep the queue is at a glance.
	_style_queue_slots(building.synced_queue_size - 1, building)

## `filled` slots read as occupied and cancel on click; the rest stay as empty
## wells. Only the queue's DEPTH is synced, not its order, so an occupied slot
## carries no icon.
func _style_queue_slots(filled: int, building: ProductionBuilding) -> void:
	if _info_slot_row == null:
		return
	## Keyed on the queue's contents, not just its depth, so replacing a Soldier
	## with an Archer at the same depth still updates the portraits.
	var signature: String = "%d|%s" % [filled, ",".join(building.synced_queue_names)]
	if signature == _info_last_queue_signature:
		return
	_info_last_queue_signature = signature
	_info_last_queue_size = filled
	var pending: PackedStringArray = building.synced_queue_names
	for i in _info_slot_row.get_child_count():
		var slot := _info_slot_row.get_child(i) as Button
		if slot == null:
			continue
		var occupied: bool = i < filled
		slot.disabled = not occupied
		## Index 0 of the synced queue is the item in production, which the
		## progress bar already shows -- these slots are the ones behind it.
		var item_name: String = pending[i + 1] if occupied and pending.size() > i + 1 else ""
		slot.tooltip_text = item_name if occupied else ""
		var icon := slot.get_node_or_null("Icon") as TextureRect
		if icon != null:
			icon.texture = _producible_icon(building, item_name) if occupied else null
		var normal := UiStyle.slot_box() if occupied else UiStyle.empty_slot_box()
		slot.add_theme_stylebox_override("normal", normal)
		slot.add_theme_stylebox_override("disabled", normal)
		slot.add_theme_stylebox_override("hover",
				UiStyle.slot_box(UiStyle.LINE_STRONG) if occupied else normal)
		slot.add_theme_stylebox_override("pressed",
				UiStyle.slot_box(UiStyle.ACCENT) if occupied else normal)

## Counts are totalled over a double-click group, since that's where the
## clicks went.
func _refresh_producible_badges(building: ProductionBuilding) -> void:
	var group: Array[ProductionBuilding] = main.selected_building_group()
	for item_name in _info_producible_badges:
		var badge = _info_producible_badges[item_name]
		if not is_instance_valid(badge):
			continue
		var count: int = 0
		for member in group:
			count += member.synced_queue_counts.get(item_name, 0)
		badge.visible = count > 0
		if count > 0:
			badge.text = str(count)
	for button in _info_unit_buttons:
		if is_instance_valid(button):
			button.disabled = building.synced_unit_limit_reached
	for item_name in _info_repeat_badges:
		var repeat_badge = _info_repeat_badges[item_name]
		if is_instance_valid(repeat_badge):
			repeat_badge.visible = item_name == building.synced_repeat_item_name

## Right-click toggles repeat production of that unit (see ProductionBuilding.toggle_repeat).
func _on_producible_gui_input(event: InputEvent, building: ProductionBuilding, item_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		main.toggle_repeat_production(building, item_index)

## Whose face a group selection shows: its first monster, the same order the
## portrait grid below uses, so a Dark Lord leading a crowd of villagers isn't
## represented by whichever villager the drag box caught first.
func _lead_unit() -> Unit:
	for unit in main.selected_units:
		if not unit.abilities.is_empty():
			return unit
	return main.selected_units[0]

## Builds either a single unit's stat readout or a grid of portrait+health
## widgets for a multi-unit selection — structural, called once per selection
## change; _refresh_unit_info_values() updates values every frame after.
func _build_unit_info() -> void:
	if main.selected_units.size() == 1:
		var unit := main.selected_units[0]
		info_panel_name_label.text = unit.display_name
		_update_portrait(unit.team_tint, "", UnitPortrait.of_unit(unit))
		_build_unit_stat_row(unit)
		return

	info_panel_name_label.text = "%d units selected" % main.selected_units.size()
	var lead := _lead_unit()
	_update_portrait(lead.team_tint, "%d units" % main.selected_units.size(), UnitPortrait.of_unit(lead))
	var portrait_grid := GridContainer.new()
	portrait_grid.columns = SELECTION_PORTRAIT_COLUMNS
	## Shrink-to-fit, or the columns stretch across the panel and the square
	## portrait slots come out as wide rectangles.
	portrait_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait_grid.add_theme_constant_override("h_separation", 4)
	portrait_grid.add_theme_constant_override("v_separation", 4)
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
		cell.add_theme_constant_override("separation", 5)
		var portrait := Button.new()
		portrait.custom_minimum_size = Vector2(36, 36)
		portrait.tooltip_text = unit.display_name
		## A recessed well with the team colour as a wash, matching the big
		## portrait -- a solid team fill drowns the sprite sitting on it.
		portrait.add_theme_stylebox_override("normal", _tray_slot_box(unit.team_tint))
		portrait.add_theme_stylebox_override("hover", _tray_slot_box(unit.team_tint, UiStyle.LINE_STRONG))
		portrait.add_theme_stylebox_override("pressed", _tray_slot_box(unit.team_tint, UiStyle.ACCENT))
		portrait.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		## The unit's own portrait over its team colour, scaled to fit (aspect
		## kept) and kept crisp — the same image the big portrait shows.
		portrait.icon = UnitPortrait.of_unit(unit)
		portrait.expand_icon = true
		portrait.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		portrait.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.pressed.connect(main.select_only_unit.bind(unit))
		cell.add_child(portrait)
		var health_bar := ProgressBar.new()
		health_bar.custom_minimum_size = Vector2(36, 4.0)
		health_bar.max_value = 1.0
		health_bar.step = 0.0
		health_bar.show_percentage = false
		health_bar.add_theme_stylebox_override("background", _flat_bar_stylebox(UiStyle.SLOT))
		health_bar.add_theme_stylebox_override("fill", _flat_bar_stylebox(UiStyle.GOOD))
		cell.add_child(health_bar)
		portrait_grid.add_child(cell)
		_info_unit_portrait_bars.append(health_bar)
	info_panel_content.add_child(portrait_grid)

func _refresh_unit_info_values() -> void:
	_refresh_ability_buttons()
	if is_instance_valid(_hold_button):
		_hold_button.set_pressed_no_signal(main.selection_holds_position())
	if main.selected_units.size() == 1:
		var unit := main.selected_units[0]
		portrait_health_label.text = "%d / %d" % [unit.status_current_health, unit.max_health]
		_refresh_unit_stat_row(unit)
		return
	for i in _info_unit_portrait_bars.size():
		if is_instance_valid(_info_portrait_units[i]):
			var unit := _info_portrait_units[i]
			_info_unit_portrait_bars[i].value = float(unit.status_current_health) / float(maxi(unit.max_health, 1))

## Health already reads out under the portrait, and the info panel is only as
## wide as the console allows — so these stay short enough not to wrap.
## One row of caption-over-value cells, each pinned to a known height so the
## row cannot outgrow the info band. Replaces a wrapping multi-line label, which
## grew to three lines and drew over the command grid -- a Control can never be
## smaller than its content's minimum size, so the band could not hold it back.
func _build_unit_stat_row(unit: Unit) -> void:
	_info_stat_values.clear()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	info_panel_content.add_child(row)
	for entry in _unit_stat_entries(unit):
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 1)
		cell.add_child(UiTextLine.make(entry["label"], &"CaptionLabel",
				UiStyle.SIZE_LABEL, UiStyle.DIM))
		var value := UiTextLine.make(entry["value"], &"ValueLabel",
				UiStyle.SIZE_BODY, UiStyle.INK, UiStyle.SIZE_BODY)
		cell.add_child(value)
		_info_stat_values[entry["label"]] = value
		row.add_child(cell)

## Which stats a unit shows, and in what order. Health is already under the
## portrait, so it is not repeated here.
func _unit_stat_entries(unit: Unit) -> Array:
	var entries: Array = []
	if unit.can_fight:
		entries.append({"label": "Damage", "value": str(unit.attack_damage)})
		entries.append({"label": "Range", "value": "%.1f" % unit.attack_range})
		entries.append({"label": "Rate", "value": "%.1fs" % unit.attack_cooldown})
	if unit.can_gather:
		entries.append({"label": "Carries", "value": str(unit.carry_capacity)})
	entries.append({"label": "Speed", "value": "%.1f" % unit.move_speed})
	return entries

func _refresh_unit_stat_row(unit: Unit) -> void:
	for entry in _unit_stat_entries(unit):
		var line: UiTextLine = _info_stat_values.get(entry["label"])
		if line != null:
			line.set_text(entry["value"])

func _populate_unit_command_buttons() -> void:
	var buttons: Array[Control] = [
		_make_command_button(OS.get_keycode_string(Main.UNIT_MOVE_KEY), "Move", [], null, main.arm_move_mode),
		_make_command_button(OS.get_keycode_string(Main.UNIT_STOP_KEY), "Stop", [], null, main.issue_stop_order),
		_make_command_button(OS.get_keycode_string(Main.UNIT_ATTACK_KEY), "Attack", [], null, main.arm_attack_mode),
		_make_command_button(OS.get_keycode_string(Main.UNIT_PATROL_KEY), "Patrol", [], null, main.arm_patrol_mode),
	]
	_hold_button = _make_command_button(OS.get_keycode_string(Main.UNIT_HOLD_KEY), "Hold Position", [], null, main.toggle_hold_position)
	_hold_button.toggle_mode = true
	_hold_button.set_pressed_no_signal(main.selection_holds_position())
	buttons.append(_hold_button)
	if main.any_selected_can_build():
		buttons.append(_make_command_button(OS.get_keycode_string(Main.UNIT_BUILD_KEY), "Build", [], null, open_build_submenu))
	var regiment_action: Main.RegimentAction = main.selection_regiment_action()
	if regiment_action != Main.RegimentAction.NONE:
		var label: String = "Form Regiment"
		if regiment_action == Main.RegimentAction.DISBAND:
			label = "Disband"
		elif regiment_action == Main.RegimentAction.REINFORCE:
			label = "Reinforce"
		buttons.append(_make_command_button(
			OS.get_keycode_string(Main.UNIT_REGIMENT_KEY), label, [], null, main.toggle_regiment))

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
				## Shown for visibility but never actionable — a passive
				## works continuously, there's nothing to click.
				var button := _make_command_button(hotkey_label, ability.ability_name, [], ability.icon, func(): pass)
				button.disabled = true
				buttons.append(button)
			else:
				var button := _make_command_button(hotkey_label, ability.ability_name, [], ability.icon, main.arm_ability.bind(unit, i))
				_ability_buttons.append({"button": button, "unit": unit, "index": i, "sweep": _add_cooldown_sweep(button)})
				buttons.append(button)
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

## show_building rather than Main.select_building, which would break up a
## double-click group every time one of its units came out.
func _on_selected_building_item_completed(_item: ProducibleItem, building: ProductionBuilding) -> void:
	if main.selected_building == building:
		show_building(building)

func _format_construction_status(building: ProductionBuilding) -> String:
	var percent := int(building.construction_progress * 100)
	if building.synced_builder_count <= 0:
		return "Constructing... %d%% (needs a builder)" % percent
	return "Constructing... %d%% (%d building)" % [percent, building.synced_builder_count]

## Shared by the construction menu, a building's production menu, and the new
## unit-command panel: a square button showing its icon with the hotkey letter
## tucked in the corner, or just the letter when there is no icon (icons come
## from the Icon Maker dock / scenes/tools/generate_command_icons.tscn).
## A unit or an action that has real art: its sprite, with the hotkey as a
## corner badge. Anything without art goes through _make_letter_slot instead.
func _make_command_button(hotkey_label: String, display_name: String,
		costs: Array, icon: Texture2D, callback: Callable) -> Button:
	var slot := CommandSlot.new()
	slot.set_meta(&"hotkey", hotkey_label)
	if icon == null:
		slot.setup_letter(hotkey_label, display_name, costs)
	else:
		slot.setup_icon(icon, hotkey_label, display_name, costs)
	slot.pressed.connect(callback)
	slot.pressed.connect(_punch_control.bind(slot))
	return slot

## Buildings are the hotkey letter and nothing else -- no icon, no cost number.
## Whether the player can afford it is carried by the letter's colour.
func _make_letter_slot(letter: String, display_name: String, costs: Array,
		affordable: bool, callback: Callable) -> Button:
	var slot := CommandSlot.new()
	slot.set_meta(&"hotkey", letter)
	slot.setup_letter(letter, display_name, costs)
	if not affordable:
		slot.state = CommandSlot.State.UNAFFORDABLE
	slot.pressed.connect(callback)
	slot.pressed.connect(_punch_control.bind(slot))
	return slot

## Cost lines for a tooltip. No resource icons exist yet, so each line names its
## resource rather than showing a glyph.
func _tooltip_costs(costs: Array[ResourceCost]) -> Array:
	var out: Array = []
	for cost in costs:
		out.append({"label": cost.resource_type.display_name, "amount": cost.amount})
	return out

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
		if button and button.get_meta(&"hotkey", "") == hotkey_label:
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
	badge.add_theme_font_size_override("font_size", 33)
	badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	badge.add_theme_constant_override("shadow_offset_x", 2)
	badge.add_theme_constant_override("shadow_offset_y", 2)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	button.add_child(badge)
	return badge

## Top-left hotkey letter over an icon button — the other corners belong to
## the queue count and repeat badges.
func _add_repeat_badge(button: Button) -> Label:
	var badge := Label.new()
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.offset_right = -2
	badge.offset_top = -4
	badge.text = "∞"
	badge.add_theme_font_size_override("font_size", 33)
	badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	badge.add_theme_constant_override("shadow_offset_x", 2)
	badge.add_theme_constant_override("shadow_offset_y", 2)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	button.add_child(badge)
	return badge

func format_costs(costs: Array[ResourceCost]) -> String:
	var parts: Array[String] = []
	for cost in costs:
		parts.append("%d %s" % [cost.amount, cost.resource_type.display_name])
	return ", ".join(parts)

func _format_item_costs(item: ProducibleItem, building: ProductionBuilding) -> String:
	var text := format_costs(building.costs_for(item))
	if item.kind == ProducibleItem.Kind.UNIT:
		text += ", %d Pop" % item.get_population_cost()
	return text
