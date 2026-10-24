class_name RacesScreen
extends PanelContainer
## The main menu's Races screen: each playable people's playstyle, what its
## trait gives it and costs it, and its army. Picking a unit stands its
## figure on a turning display base (UnitDiorama) beside its stats.
##
## The army is read off the faction itself: every unit its capital buildings
## train, grouped by building, so it never drifts from the game.

signal closed

const PANEL_WIDTH: int = 1240
const PANEL_HEIGHT: int = 760
const LEFT_WIDTH: int = 470
const PORTRAIT_SIZE: int = 58
const DIORAMA_SIZE := Vector2(300, 300)
const STATS_WIDTH: int = 380
## Below this range a unit fights hand to hand.
const MELEE_RANGE: float = 3.0
## Shown in the first team colour.
const TINT := UnitPortrait.DEFAULT_TINT

const DAMAGE_NAMES: Array[String] = ["Plain", "Spear", "Cavalry", "Pierce", "Magic", "Blade"]
## Unit.ArmorClass, as the units wearing it.
const ARMOR_NAMES: Array[String] = ["None", "Soldiers", "Spearmen", "Archers", "Cavalry", "Siege", "Monsters"]
const SKIP_BUILDINGS: Array[String] = ["Wall", "Gate", "House", "Mine", "Storehouse", "Farm", "Mill"]

## Per RaceTraits race name: the playstyle, the trait and what it gives (+)
## and costs (-), and how to play to it.
const RACES: Dictionary = {
	"Human": {
		summary = "Disciplined regiments and the deepest armoury. Knights win by holding a line: blocks of infantry take the charge while crossbows and mages break it, and Knight-only Blacksmith gear keeps the army a step ahead in a long game.",
		trait_name = "Drilled",
		plus = [
			"Soldiers fighting in a block take 10% less damage.",
			"Shield Wall: infantry in a block take a further 25% less from arrows and bolts.",
			"The widest army: two of most unit types, plus Griffins and Manticores.",
		],
		minus = [
			"Units on their own, out of a block, don't get Drilled.",
		],
		tips = [
			"Move and fight in formation, and keep the blocks together.",
			"Spearmen in front of cavalry, crossbows behind the line.",
		],
	},
	"Pirates": {
		summary = "Raiders who get paid for fighting. Every kill and every blow against a building puts gold in the chest, so a Pirate army that keeps attacking pays for its next wave. Blunderbusses and Anchor Brutes hit hard up close.",
		trait_name = "Plunder",
		plus = [
			"Every kill pays 20% of the victim's wood and gold cost back in gold (at least 2).",
			"Hitting enemy buildings pays about 1 gold for every 8 damage.",
			"Pieces of Eight: 50% more gold from Plunder.",
			"Boarding Hooks: Tavern crews do double damage to buildings, and earn double the gold for it.",
		],
		minus = [
			"Plunder only pays while you're fighting. A Pirate player who sits back earns nothing extra.",
			"Fewer unit types: one cavalry unit and one caster.",
		],
		tips = [
			"Attack early and keep up the pressure. Raid outlying buildings with Tavern crews.",
			"Get Blunderbusses close. They shred whatever is in front of them.",
		],
	},
	"Robots": {
		summary = "Clockwork machines that are deadliest near home. Robots are tough and slow, run on oil instead of food, and fight best within reach of their own buildings, so they creep forward building as they go.",
		trait_name = "Clockwork",
		plus = [
			"Fully wound: +15% attack speed.",
			"Rewound instantly within 18 m of any of your finished buildings.",
			"Robots never go hungry. Their upkeep is oil at half the usual rate, paid from spare food first and then gold.",
			"Recruits from captured settlements still eat, but a shortage only weakens the recruits.",
			"Mainspring: a winding lasts twice as long. Repair Drones: 1 health a second out of combat.",
		],
		minus = [
			"Away from home they run down over 90 s, to 30% slower attacks.",
			"Fewer unit types: a single ranged unit, cavalry unit and caster.",
		],
		tips = [
			"Fight near your own buildings, and put up a building near the front to rewind your army.",
			"Pull a run-down army back to rewind it before the next push.",
		],
	},
}

var _shell: ModalShell
var _race_buttons: Array[Button] = []
var _summary: Label
var _trait_name: Label
var _trait_lines: VBoxContainer
var _tips: Label
var _army: VBoxContainer
var _diorama: UnitDiorama
var _unit_name: Label
var _unit_role: Label
var _stats: GridContainer
var _counters: Label
var _unit_trait: Label
var _unit_group := ButtonGroup.new()
var _race: String = ""
var _race_index: int = 0

func _init() -> void:
	name = "RacesScreen"
	_shell = ModalShell.dress(self, "Races", "Races", PANEL_WIDTH, PANEL_HEIGHT)
	_build_left()
	_build_right()
	var back := UiButton.new()
	back.text = "Back"
	back.pressed.connect(func(): closed.emit())
	_shell.footer.add_child(back)

func _build_left() -> void:
	var left := _shell.left
	left.custom_minimum_size.x = LEFT_WIDTH
	left.size_flags_horizontal = Control.SIZE_FILL
	var picker := HBoxContainer.new()
	picker.add_theme_constant_override("separation", UiStyle.SPACE_S)
	left.add_child(picker)
	for i in Faction.PLAYABLE.size():
		var button := UiButton.new()
		button.text = Faction.display_name_for(i)
		ModalShell.bound(button, 100)
		button.pressed.connect(open_race.bind(i))
		picker.add_child(button)
		_race_buttons.append(button)

	_summary = _prose(LEFT_WIDTH, 5)
	left.add_child(_summary)

	left.add_child(ModalShell.column_head("Trait"))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", UiStyle.slot_box(UiStyle.ACCENT))
	left.add_child(card)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, UiStyle.SPACE_M)
	card.add_child(pad)
	var inside := VBoxContainer.new()
	inside.add_theme_constant_override("separation", UiStyle.SPACE_XS)
	pad.add_child(inside)
	_trait_name = Label.new()
	_trait_name.add_theme_font_override("font", UiStyle.font_display())
	_trait_name.add_theme_font_size_override("font_size", UiStyle.SIZE_NAME)
	_trait_name.add_theme_color_override("font_color", UiStyle.ACCENT)
	inside.add_child(_trait_name)
	_trait_lines = VBoxContainer.new()
	_trait_lines.add_theme_constant_override("separation", UiStyle.SPACE_XS)
	_trait_lines.custom_minimum_size = Vector2(LEFT_WIDTH - 40, 300)
	inside.add_child(_trait_lines)

	left.add_child(ModalShell.column_head("How to play"))
	_tips = _prose(LEFT_WIDTH, 5)
	left.add_child(_tips)

func _build_right() -> void:
	var right := _shell.right
	right.add_child(ModalShell.column_head("Army"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_army = VBoxContainer.new()
	_army.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_army.add_theme_constant_override("separation", UiStyle.SPACE_XS)
	scroll.add_child(_army)

	right.add_child(SectionRule.new())
	var detail := HBoxContainer.new()
	detail.add_theme_constant_override("separation", UiStyle.SPACE_L)
	right.add_child(detail)
	_diorama = UnitDiorama.new()
	_diorama.custom_minimum_size = DIORAMA_SIZE
	detail.add_child(_diorama)

	var info := VBoxContainer.new()
	info.custom_minimum_size.x = STATS_WIDTH
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", UiStyle.SPACE_XS)
	detail.add_child(info)
	_unit_name = Label.new()
	_unit_name.add_theme_font_override("font", UiStyle.font_display())
	_unit_name.add_theme_font_size_override("font_size", UiStyle.SIZE_NAME)
	_unit_name.add_theme_color_override("font_color", UiStyle.INK)
	info.add_child(_unit_name)
	_unit_role = Label.new()
	_unit_role.theme_type_variation = &"CaptionLabel"
	_unit_role.add_theme_color_override("font_color", UiStyle.DIM)
	info.add_child(_unit_role)
	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", UiStyle.SPACE_M)
	_stats.add_theme_constant_override("v_separation", 2)
	info.add_child(_stats)
	_counters = _prose(STATS_WIDTH, 3)
	info.add_child(_counters)
	_unit_trait = _prose(STATS_WIDTH, 3)
	_unit_trait.add_theme_color_override("font_color", UiStyle.ACCENT)
	info.add_child(_unit_trait)

## A wrapping prose label, its height held at `lines` so the panel never
## resizes as the text changes.
func _prose(width: int, lines: int) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"ProseLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, lines * 22)
	label.max_lines_visible = lines
	label.add_theme_font_size_override("font_size", UiStyle.SIZE_LABEL)
	return label

func open() -> void:
	open_race(_race_index)

func open_race(index: int) -> void:
	var faction: Faction = Faction.for_index(index)
	_race = faction.race_name
	_race_index = index
	for i in _race_buttons.size():
		_race_buttons[i].primary = i == index
	_shell.title_label.text = Faction.display_name_for(index)
	var copy: Dictionary = RACES.get(_race, {})
	_summary.text = copy.get("summary", "")
	_trait_name.text = copy.get("trait_name", "")
	for child in _trait_lines.get_children():
		child.free()
	for line in copy.get("plus", []):
		_trait_lines.add_child(_trait_line("+", line, UiStyle.GOOD))
	for line in copy.get("minus", []):
		_trait_lines.add_child(_trait_line("−", line, UiStyle.BAD))
	_tips.text = "\n".join(copy.get("tips", []).map(func(t): return "• " + t))
	_fill_army(faction)

func _trait_line(mark: String, text: String, colour: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiStyle.SPACE_S)
	var sign := Label.new()
	sign.text = mark
	sign.custom_minimum_size.x = 18
	sign.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	sign.add_theme_font_override("font", UiStyle.font_display())
	sign.add_theme_font_size_override("font_size", UiStyle.SIZE_NAME)
	sign.add_theme_color_override("font_color", colour)
	row.add_child(sign)
	var label := Label.new()
	label.theme_type_variation = &"ProseLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = LEFT_WIDTH - 70
	label.add_theme_font_size_override("font_size", UiStyle.SIZE_LABEL)
	label.text = text
	row.add_child(label)
	return row

## One row per capital building that trains units: its name, then a portrait
## button per unit. The first unit is shown.
func _fill_army(faction: Faction) -> void:
	for child in _army.get_children():
		child.free()
	var first: Button = null
	var fallback: Array = []
	var seen: Dictionary = {}
	for type in faction.building_types:
		if type == null or type.scene == null or type.is_wall or SKIP_BUILDINGS.has(type.building_name):
			continue
		var units: Array[String] = []
		for path in _trained_at(type.scene):
			if not seen.has(path):
				seen[path] = true
				units.append(path)
		if units.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiStyle.SPACE_S)
		_army.add_child(row)
		var label := Label.new()
		label.theme_type_variation = &"CaptionLabel"
		label.add_theme_color_override("font_color", UiStyle.DIM)
		label.text = (type.display_name if type.display_name != "" else type.building_name).to_upper()
		label.custom_minimum_size.x = 150
		label.clip_text = true
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		for path in units:
			var button := Button.new()
			button.theme_type_variation = &"SquareButton"
			button.toggle_mode = true
			button.button_group = _unit_group
			button.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
			button.icon = UnitPortrait.of_scene(path, TINT)
			button.expand_icon = true
			button.texture_filter = UnitPortrait.filter_for(button.icon)
			button.pressed.connect(_show_unit.bind(path))
			row.add_child(button)
			if fallback.is_empty():
				fallback = [button, path]
			if first == null and _army.get_child_count() > 1:
				first = button
				first.button_pressed = true
				_show_unit(path)
	if first == null and not fallback.is_empty():
		fallback[0].button_pressed = true
		_show_unit(fallback[1])

## The unit scenes a building trains, read off an instance that never enters
## the tree.
static func _trained_at(scene: PackedScene) -> Array[String]:
	var out: Array[String] = []
	var building := scene.instantiate()
	if building is ProductionBuilding:
		for item: ProducibleItem in building.producibles:
			if item != null and item.kind == ProducibleItem.Kind.UNIT and item.unit_scene != null:
				out.append(item.unit_scene.resource_path)
	building.free()
	return out

func _show_unit(path: String) -> void:
	var unit := (load(path) as PackedScene).instantiate() as Unit
	if unit == null:
		return
	_diorama.show_unit(unit, TINT)
	var facts: Dictionary = _facts(unit)
	unit.free()
	_unit_name.text = facts.name
	_unit_role.text = facts.role.to_upper()
	for child in _stats.get_children():
		child.free()
	for pair in facts.stats:
		var key := Label.new()
		key.text = pair[0]
		key.add_theme_color_override("font_color", UiStyle.DIM)
		_stats.add_child(key)
		var value := Label.new()
		value.text = pair[1]
		value.add_theme_font_override("font", UiStyle.font_data_bold())
		_stats.add_child(value)
	_counters.text = facts.counters
	_unit_trait.text = _trait_for(facts.fighter, facts.worker)

## What the race's trait does for this one unit.
func _trait_for(fighter: bool, worker: bool) -> String:
	match _race:
		"Human":
			return "Drilled: takes 10% less damage while fighting in a block." if fighter and not worker else ""
		"Pirates":
			return "Plunder: its kills and its blows on buildings pay gold." if fighter else ""
		"Robots":
			return "Clockwork: attacks 15% faster near your buildings, slowing to 30% slower after 90 s away. Never goes hungry: upkeep is oil, paid from spare food, then gold."
	return ""

func _facts(unit: Unit) -> Dictionary:
	var stats: Array = [["Health", str(unit.max_health)]]
	if unit.can_fight and unit.attack_damage > 0:
		stats.append(["Attack", "%d %s every %.1f s" % [unit.attack_damage, DAMAGE_NAMES[unit.damage_type].to_lower(), unit.attack_cooldown]])
		stats.append(["Range", "Melee" if unit.attack_range < MELEE_RANGE else "%d m" % roundi(unit.attack_range)])
	stats.append(["Speed", "%.1f m/s" % unit.move_speed])
	if unit.armor_class != Unit.ArmorClass.NONE:
		stats.append(["Armour", ARMOR_NAMES[unit.armor_class]])
	var cost: Array[String] = []
	for c: ResourceCost in unit.costs:
		if c != null and c.resource_type != null and c.amount > 0:
			cost.append("%d %s" % [c.amount, c.resource_type.display_name])
	if not cost.is_empty():
		stats.append(["Cost", ", ".join(cost)])
	stats.append(["Population", str(unit.population_cost)])
	return {
		name = unit.display_name,
		role = _role(unit),
		stats = stats,
		counters = _counters_of(unit),
		fighter = unit.can_fight,
		worker = unit.can_gather,
	}

static func _role(unit: Unit) -> String:
	if unit.can_gather:
		return "Worker"
	if unit.armor_class == Unit.ArmorClass.SIEGE:
		return "Siege"
	if unit.armor_class == Unit.ArmorClass.MONSTER:
		return "Beast"
	if unit.damage_type == Unit.DamageType.MAGIC:
		return "Caster"
	if unit.attack_range >= MELEE_RANGE:
		return "Ranged"
	if unit.armor_class == Unit.ArmorClass.CAVALRY:
		return "Cavalry"
	return "Infantry"

## Who it hits hardest and who hits it hardest, off the counter table.
static func _counters_of(unit: Unit) -> String:
	if not unit.can_fight or unit.can_gather:
		return ""
	var strong: Array[String] = []
	var row: Array = CombatUtils.COUNTER_TABLE.get(unit.damage_type, [])
	for armor in range(1, row.size()):
		if row[armor] > 1.0:
			strong.append("%s ×%s" % [ARMOR_NAMES[armor], _times(row[armor])])
	var weak: Array[String] = []
	for damage in CombatUtils.COUNTER_TABLE:
		var against: float = CombatUtils.COUNTER_TABLE[damage][unit.armor_class]
		if against > 1.0:
			weak.append("%s ×%s" % [DAMAGE_NAMES[damage], _times(against)])
	var lines: Array[String] = []
	if not strong.is_empty():
		lines.append("Strong vs " + ", ".join(strong))
	if not weak.is_empty():
		lines.append("Weak to " + ", ".join(weak))
	return "\n".join(lines)

static func _times(multiplier: float) -> String:
	return str(snappedf(multiplier, 0.01)).trim_suffix(".0")
