class_name Sfx
extends Node
## Positional world sounds from the Fantasy SFX pack: blows, arrows, spells,
## chopping and mining, gates, collapsing buildings. Played through a small
## shared pool like UnitVoices, so a battle of hundreds is a handful of voices
## rather than one per soldier: each set has a minimum gap between plays and a
## cap on how many of it sound at once, and anything the pool can't fit is
## simply dropped. Purely local — every peer reaches the same calls through
## WorldFeedback's relays — and silent in fog, so a fight can't be heard
## through it.

## The match's pool (every peer has one; Main creates it).
static var current: Sfx = null
## Host only, set by Unit.take_damage while it reports an ability's damage.
static var ability_hit: bool = false

const DIR: String = "res://assets/sfx/Fantasy SFX/SFX/"
const SWORD: String = "Attacks/Sword Attacks Hits and Blocks/"
const BOW: String = "Attacks/Bow Attacks Hits and Blocks/"

## Set -> clips, relative to DIR.
const SETS: Dictionary = {
	&"sword_hit": [SWORD + "Sword Impact Hit 1.wav", SWORD + "Sword Impact Hit 2.wav", SWORD + "Sword Impact Hit 3.wav"],
	&"sword_block": [SWORD + "Sword Blocked 1.wav", SWORD + "Sword Blocked 2.wav", SWORD + "Sword Blocked 3.wav",
			SWORD + "Sword Parry 1.wav", SWORD + "Sword Parry 2.wav", SWORD + "Sword Parry 3.wav"],
	&"unsheath": [SWORD + "Sword Unsheath 1.wav", SWORD + "Sword Unsheath 2.wav"],
	&"beast_hit": ["Torch/Torch Impact 1.wav", "Torch/Torch Impact 2.wav", "Spells/Rock Meteor Throw 1.wav", "Spells/Rock Meteor Throw 2.wav"],
	&"bow_shot": [BOW + "Bow Attack 1.wav", BOW + "Bow Attack 2.wav"],
	&"bow_hit": [BOW + "Bow Impact Hit 1.wav", BOW + "Bow Impact Hit 2.wav", BOW + "Bow Impact Hit 3.wav"],
	&"bow_block": [BOW + "Bow Blocked 1.wav", BOW + "Bow Blocked 2.wav", BOW + "Bow Blocked 3.wav"],
	&"bow_ready": [BOW + "Bow Take Out 1.wav"],
	&"magic_shot": ["Spells/Fireball 1.wav", "Spells/Fireball 2.wav", "Spells/Fireball 3.wav"],
	&"magic_hit": ["Spells/Spell Impact 1.wav", "Spells/Spell Impact 2.wav", "Spells/Spell Impact 3.wav"],
	&"fire_cast": ["Spells/Firebuff 1.wav", "Spells/Firebuff 2.wav"],
	&"fire_launch": ["Spells/Fireball 1.wav", "Spells/Fireball 2.wav", "Spells/Fireball 3.wav"],
	&"fire_impact": ["Spells/Firespray 1.wav", "Spells/Firespray 2.wav"],
	&"ice_cast": ["Spells/Ice Freeze 1.wav", "Spells/Ice Freeze 2.wav"],
	&"ice_launch": ["Spells/Ice Throw 1.wav", "Spells/Ice Throw 2.wav"],
	&"ice_impact": ["Spells/Ice Barrage 1.wav", "Spells/Ice Barrage 2.wav"],
	&"earth_cast": ["Spells/Rock Wall 1.wav", "Spells/Rock Wall 2.wav"],
	&"earth_launch": ["Spells/Rock Meteor Throw 1.wav", "Spells/Rock Meteor Throw 2.wav"],
	&"earth_impact": ["Spells/Rock Meteor Swarm 1.wav", "Spells/Rock Meteor Swarm 2.wav"],
	&"water_launch": ["Spells/Waterspray 1.wav", "Spells/Waterspray 2.wav"],
	&"water_impact": ["Spells/Wave Attack 1.wav", "Spells/Wave Attack 2.wav"],
	&"arcane_cast": ["Spells/Firebuff 1.wav", "Spells/Firebuff 2.wav"],
	&"arcane_launch": ["Spells/Ice Throw 1.wav", "Spells/Ice Throw 2.wav"],
	&"arcane_impact": ["Spells/Spell Impact 1.wav", "Spells/Spell Impact 2.wav", "Spells/Spell Impact 3.wav"],
	&"storm_cast": ["Spells/Firebuff 1.wav", "Spells/Firebuff 2.wav"],
	&"storm_launch": ["Spells/Ice Throw 1.wav", "Spells/Ice Throw 2.wav"],
	&"storm_impact": ["Spells/Rock Meteor Swarm 1.wav", "Spells/Rock Meteor Swarm 2.wav"],
	&"chop": ["Chopping and Mining/chop 1.wav", "Chopping and Mining/chop 2.wav", "Chopping and Mining/chop 3.wav", "Chopping and Mining/chop 4.wav"],
	&"mine": ["Chopping and Mining/mine 1.wav", "Chopping and Mining/mine 2.wav", "Chopping and Mining/mine 3.wav",
			"Chopping and Mining/mine 4.wav", "Chopping and Mining/mine 5.wav"],
	&"collapse": ["Spells/Rock Wall 1.wav", "Spells/Rock Wall 2.wav"],
	&"gate_open": ["Doors Gates and Chests/Gate Open.wav"],
	&"gate_close": ["Doors Gates and Chests/Gate Close.wav"],
	&"torch": ["Torch/Light Torch 1.wav", "Torch/Light Torch 2.wav"],
	&"chest": ["Doors Gates and Chests/Chest Open 1.wav", "Doors Gates and Chests/Chest Open 2.wav"],
}
## [seconds between two plays of a set, how many of it at once, volume dB].
## Sets not listed use DEFAULT_LIMIT.
const LIMITS: Dictionary = {
	&"sword_hit": [0.07, 4, -6.0],
	&"sword_block": [0.1, 3, -7.0],
	&"beast_hit": [0.15, 2, -3.0],
	&"bow_shot": [0.08, 3, -9.0],
	&"bow_hit": [0.1, 3, -9.0],
	&"bow_block": [0.12, 2, -10.0],
	&"magic_shot": [0.25, 2, -14.0],
	&"magic_hit": [0.12, 3, -8.0],
	&"chop": [0.12, 3, -8.0],
	&"mine": [0.12, 3, -9.0],
	&"collapse": [0.5, 2, 0.0],
	&"unsheath": [0.3, 1, -10.0],
	&"bow_ready": [0.3, 1, -8.0],
}
const DEFAULT_LIMIT: Array = [0.2, 2, -4.0]
const PLAYERS: int = 20
## How far from the middle of the screen (the camera's ground pivot) a sound
## carries: this at the closest zoom, growing with zoom so the whole view stays
## audible, up to HEARING_MAX.
const HEARING_MIN: float = 35.0
const HEARING_PER_ZOOM: float = 1.4
const HEARING_MAX: float = 160.0
## The players stand this far from the listener at the edge of hearing, so a
## sound's loudness depends on where it is on screen, not on how high the
## camera is.
const LISTEN_SPAN: float = 30.0
## Quieter as the camera pulls out: 0 dB up to FADE_FROM_ZOOM, this much by
## the overview zoom.
const FADE_FROM_ZOOM: float = 25.0
const OVERVIEW_FADE_DB: float = -9.0
const PITCH_JITTER: float = 0.07

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
## Set -> msec it last played.
var _last_played: Dictionary = {}
## Player -> the set it is playing.
var _playing_set: Dictionary = {}
## Set -> index of the clip it last played, so a set never repeats itself.
var _last_clip: Dictionary = {}
var _main: Main

func _enter_tree() -> void:
	current = self

func _exit_tree() -> void:
	if current == self:
		current = null

func _ready() -> void:
	_main = get_parent() as Main
	for set_name in SETS:
		var loaded: Array[AudioStream] = []
		for clip in SETS[set_name]:
			var stream := load(DIR + clip) as AudioStream
			if stream != null:
				loaded.append(stream)
		_streams[set_name] = loaded
	for i in PLAYERS:
		var player := AudioStreamPlayer3D.new()
		player.bus = &"SFX"
		player.unit_size = 12.0
		player.max_distance = LISTEN_SPAN * 1.5
		add_child(player)
		_players.append(player)
	for i in 2:
		var flat := AudioStreamPlayer.new()
		flat.bus = &"SFX"
		add_child(flat)
		_flat.append(flat)

## `set_name` from SETS at `pos`, if it can be heard there and the set has room.
static func play_at(set_name: StringName, pos: Vector3, volume_offset_db: float = 0.0, pitch: float = 1.0) -> void:
	if current != null:
		current._play(set_name, pos, volume_offset_db, pitch)

## Interface flourish (selecting a unit): not placed in the world.
static func play_flat(set_name: StringName) -> void:
	if current == null or not current._may_play(set_name):
		return
	var player: AudioStreamPlayer = current._flat[0] if not current._flat[0].playing else current._flat[1]
	current._start(player, set_name, 1.0)

func _play(set_name: StringName, pos: Vector3, volume_offset_db: float, pitch: float) -> void:
	if _main == null or not _may_play(set_name):
		return
	var camera: Camera3D = _main.camera
	var rig := _main.camera_rig as RtsCamera
	if camera == null or rig == null:
		return
	var zoom: float = rig.zoom_distance
	var hearing: float = clampf(zoom * HEARING_PER_ZOOM, HEARING_MIN, HEARING_MAX)
	var offset: Vector3 = pos - rig.global_position
	offset.y = 0.0
	if offset.length() > hearing:
		return
	if _main.fog_of_war != null and not _main.fog_of_war.is_visible_at(pos):
		return
	var limit: Array = LIMITS.get(set_name, DEFAULT_LIMIT)
	var at_once := 0
	var free_player: AudioStreamPlayer3D = null
	for player in _players:
		if not player.playing:
			if free_player == null:
				free_player = player
		elif _playing_set.get(player) == set_name:
			at_once += 1
	if free_player == null or at_once >= int(limit[1]):
		return
	## Kept on the same side of the listener as on screen, so panning still
	## follows the picture.
	free_player.global_position = camera.global_position + offset * (LISTEN_SPAN / hearing)
	var fade: float = clampf((zoom - FADE_FROM_ZOOM) / maxf(rig.overview_zoom - FADE_FROM_ZOOM, 1.0), 0.0, 1.0)
	free_player.volume_db = float(limit[2]) + volume_offset_db + OVERVIEW_FADE_DB * fade
	_start(free_player, set_name, pitch)

func _may_play(set_name: StringName) -> bool:
	var clips: Array = _streams.get(set_name, [])
	if clips.is_empty():
		return false
	var limit: Array = LIMITS.get(set_name, DEFAULT_LIMIT)
	var now := Time.get_ticks_msec()
	return now - int(_last_played.get(set_name, -100000)) >= int(float(limit[0]) * 1000.0)

func _start(player: Node, set_name: StringName, pitch: float) -> void:
	var clips: Array = _streams[set_name]
	var index: int = randi() % clips.size()
	if clips.size() > 1 and index == _last_clip.get(set_name, -1):
		index = (index + 1) % clips.size()
	_last_clip[set_name] = index
	_last_played[set_name] = Time.get_ticks_msec()
	_playing_set[player] = set_name
	player.stream = clips[index]
	player.pitch_scale = pitch * randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	if player is AudioStreamPlayer:
		player.volume_db = float((LIMITS.get(set_name, DEFAULT_LIMIT) as Array)[2])
	player.play()

## --- What each event sounds like ---

## A blow or shot landing on `target` from `attacker` for `amount` (after
## armour): a clean hit, or a clang when most of it was turned aside.
static func hit(attacker: Node, target: Node3D, amount: int) -> void:
	if current == null or attacker == null or not is_instance_valid(attacker) or not is_instance_valid(target):
		return
	var pos: Vector3 = target.global_position + Vector3(0.0, 0.8, 0.0)
	var on_building: bool = target is ProductionBuilding
	if attacker is ProductionBuilding:
		play_at(&"bow_block" if on_building else &"bow_hit", pos)
		return
	var unit := attacker as Unit
	if unit == null:
		return
	var turned: bool = amount < unit.attack_damage * 0.6
	if unit.projectile_scene != null:
		if unit.damage_type == Unit.DamageType.MAGIC or _is_magic_projectile(unit):
			play_at(&"magic_hit", pos)
		else:
			play_at(&"bow_block" if on_building or turned else &"bow_hit", pos)
	elif is_beast(unit):
		play_at(&"beast_hit", pos)
	else:
		play_at(&"sword_block" if on_building or turned else &"sword_hit", pos)

## A unit or tower loosing a shot.
static func shot(shooter: Node3D) -> void:
	if current == null or not is_instance_valid(shooter):
		return
	var unit := shooter as Unit
	if unit != null and (unit.damage_type == Unit.DamageType.MAGIC or _is_magic_projectile(unit)):
		play_at(&"magic_shot", shooter.global_position)
		return
	## A bolt thrower's string is heavier than a bow's.
	var heavy: bool = unit != null and unit.armor_class == Unit.ArmorClass.SIEGE
	play_at(&"bow_shot", shooter.global_position, 2.0 if heavy else 0.0, 0.7 if heavy else 1.0)

static func _is_magic_projectile(unit: Unit) -> bool:
	return unit.projectile_scene != null and unit.projectile_scene.resource_path.contains("magic")

## The big creatures (Bestiary beasts, monsters): they land blows, not cuts.
static func is_beast(unit: Unit) -> bool:
	return unit.armor_class == Unit.ArmorClass.MONSTER or unit.population_cost >= 3

## Which family of spell sounds an ability uses: from its name, else its colour.
static func element_of(ability: Ability) -> String:
	var text := ability.ability_name.to_lower()
	for pair in [["fire", ["fire", "flame", "burn", "inferno", "breath"]],
			["storm", ["lightning", "thunder", "storm", "heaven", "wrath"]],
			["ice", ["ice", "frost", "freeze", "snow", "cold"]],
			["earth", ["slam", "sand", "rock", "stone", "quake", "ground", "meteor"]],
			["water", ["water", "wave", "tide", "acid", "venom", "bile", "spit", "plague"]]]:
		for word in pair[1]:
			if text.contains(word):
				return pair[0]
	var c: Color = ability.effect_color
	if c.s > 0.35:
		if c.h < 0.12 or c.h > 0.92:
			return "fire"
		if c.h > 0.45 and c.h < 0.62:
			return "ice"
		if c.h >= 0.12 and c.h < 0.2:
			return "earth"
	return "arcane"

static func ability_cast(ability: Ability, pos: Vector3) -> void:
	var element := element_of(ability)
	if element == "water":
		return
	play_at(StringName(element + "_cast"), pos, -6.0)

static func ability_launch(ability: Ability, pos: Vector3) -> void:
	if ability.projectile_style == Ability.ProjectileStyle.NONE:
		return
	play_at(StringName(element_of(ability) + "_launch"), pos, -2.0)

static func ability_impact(ability: Ability, pos: Vector3) -> void:
	play_at(StringName(element_of(ability) + "_impact"), pos)

## A worker's stroke on a tree or a vein.
static func harvest(node: Gatherable) -> void:
	if current == null or not is_instance_valid(node):
		return
	if node.trunk_radius > 0.0:
		play_at(&"chop", node.global_position + Vector3(0.0, 1.0, 0.0))
	elif node.resource_type == Objective.GOLD_COST:
		play_at(&"mine", node.global_position + Vector3(0.0, 0.5, 0.0))

## A soldier answering selection: a blade drawn, or a bow readied.
static func select_flourish(unit: Unit) -> void:
	if unit == null or unit.can_gather or not unit.can_fight or is_beast(unit) or unit.is_lord:
		return
	if unit.projectile_scene != null:
		if not _is_magic_projectile(unit):
			play_flat(&"bow_ready")
	else:
		play_flat(&"unsheath")
