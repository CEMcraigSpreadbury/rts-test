class_name PowerFx
extends Node3D
## Draws the faction powers' set pieces on every peer, as PowerEffects (host)
## tells it to: relay() plays a beat here and sends it to everyone else. Each
## beat carries all it needs (where, how long, which way), so a peer draws the
## whole thing on its own clock — the Galleon's path, the knights' ride, the
## sword's fall — and only the steered Orbital Lance keeps being sent.
## Nothing here touches the game: damage and pushes are the host's.

const GALLEON_MODEL: String = "res://assets/art/Models/Powers/Galleon.glb"
const SWORD_MODEL: String = "res://assets/art/Models/Powers/GiantSword.glb"
const CHEST_MODEL: String = "res://assets/art/Models/Powers/TreasureChest.glb"
const POD_MODEL: String = "res://assets/art/Models/Powers/DropPod.glb"
const KNIGHT_MODEL: String = "res://assets/art/Models/Units/Cavalier.glb"

const KNIGHT_COUNT: int = 9
const KNIGHT_SCALE: float = 1.9
const KNIGHT_COLOR: Color = Color(0.55, 0.85, 1.0)
const KNIGHT_STAGGER: float = 1.8
const ARROW_COUNT: int = 260
const ARROW_FALL: float = 0.55
const SWORD_DROP_HEIGHT: float = 70.0
## How deep the blade is driven in, and how long it takes to sink at the end.
const SWORD_EMBED: float = 2.0
const SWORD_SINK: float = 2.5
## How far off upright it stands, in radians.
const SWORD_TILT: float = 0.18
const SWORD_LIGHT_ENERGY: float = 6.0
const SWORD_LIGHT_RANGE: float = 13.0
const GOLD: Color = Color(1.0, 0.82, 0.35)
const GHOST: Color = Color(0.45, 1.0, 0.65)
## A raised ghost's whole body: pale green, half see-through.
const GHOST_BODY: Color = Color(0.72, 1.0, 0.8)
const GHOST_ALPHA: float = 0.5
const LANCE_COLOR: Color = Color(0.45, 0.9, 1.0)
const LANCE_SCORCH_SPACING: float = 1.2
const POD_DROP_HEIGHT: float = 90.0
const GALLEON_BOB: float = 0.35
const GALLEON_WAVE_HEIGHT: float = 0.7
## The model is built full size; this is what reads on the battlefield.
const GALLEON_SCALE: float = 0.65
const CHEST_SCALE: float = 1.5
const GALLEON_BALL_SIZE: float = 0.6
## Each broadside shakes the camera this hard, from the ship.
const GALLEON_VOLLEY_SHAKE: float = 0.55
## Ghost knights leave an afterimage this often, fading over this long.
const KNIGHT_TRAIL_EVERY: float = 0.06
const KNIGHT_TRAIL_FADE: float = 0.45
## Cursed Treasure's coins: this many every this often while it lures, and a
## burst of this many when it goes up.
const TREASURE_COIN_EVERY: float = 0.05
const TREASURE_COINS_EACH: int = 3
const TREASURE_BLAST_COINS: int = 160

var main: Main

var _scenes: Dictionary = {}
## peer_id -> the Lance being drawn for them: {beam, light, target, last_scorch}.
var _lances: Dictionary = {}

## --- Relaying ---

## Host: draw `kind` here and on every other peer.
func relay(kind: StringName, data: Dictionary) -> void:
	play(kind, data)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_play.rpc(kind, data)

@rpc("authority", "call_remote", "reliable")
func _rpc_play(kind: StringName, data: Dictionary) -> void:
	play(kind, data)

func relay_lance_position(peer_id: int, pos: Vector3) -> void:
	_set_lance_target(peer_id, pos)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_lance_position.rpc(peer_id, pos)

@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_lance_position(peer_id: int, pos: Vector3) -> void:
	_set_lance_target(peer_id, pos)

func play(kind: StringName, data: Dictionary) -> void:
	if has_method("_play_" + String(kind)):
		call("_play_" + String(kind), data)

## --- Warnings ---

func _play_telegraph_circle(data: Dictionary) -> void:
	var decal: Decal = main.feedback._make_ability_decal()
	add_child(decal)
	decal.global_position = data["pos"]
	decal.size = Vector3(data["radius"] * 2.0, WorldFeedback.ABILITY_DECAL_HEIGHT, data["radius"] * 2.0)
	_pulse_and_free(decal, data["color"], data["seconds"])
	Sfx.play_at(&"storm_cast", data["pos"], 2.0, 0.7)

func _play_telegraph_line(data: Dictionary) -> void:
	var decal: Decal = main.feedback.make_line_decal()
	add_child(decal)
	main.feedback.place_line_decal(decal, data["pos"], data["end"], data["width"])
	_pulse_and_free(decal, data["color"], data["seconds"])
	Sfx.play_at(&"storm_cast", data["pos"], 2.0, 0.6)

## Throbs faster as the strike gets closer, then goes.
func _pulse_and_free(decal: Decal, color: Color, seconds: float) -> void:
	decal.modulate = Color(color, 0.0)
	var tween := create_tween()
	var beats := maxi(roundi(seconds * 2.5), 2)
	var beat := seconds / beats
	for i in beats:
		tween.tween_property(decal, "modulate", Color(color, 0.95), beat * 0.35)
		tween.tween_property(decal, "modulate", Color(color, 0.35), beat * 0.65)
	tween.tween_callback(decal.queue_free)

## --- Royal Volley ---

func _play_volley(data: Dictionary) -> void:
	var centre: Vector3 = data["pos"]
	var radius: float = data["radius"]
	var seconds: float = data["seconds"]
	var shade := _ground_disc(centre, radius * 1.1, Color(0.0, 0.0, 0.0, 0.0))
	var tween := create_tween()
	tween.tween_property(shade, "modulate", Color(0.0, 0.0, 0.0, 0.45), 0.4)
	tween.tween_interval(seconds)
	tween.tween_property(shade, "modulate", Color(0.0, 0.0, 0.0, 0.0), 1.2)
	tween.tween_callback(shade.queue_free)
	var rain := ArrowRain.new()
	rain.fx = self
	rain.centre = centre
	rain.radius = radius
	rain.seconds = seconds
	add_child(rain)
	for i in 4:
		get_tree().create_timer(i * 0.12).timeout.connect(Sfx.play_at.bind(&"bow_shot", centre, 4.0, randf_range(0.8, 1.1)))
	var hits := roundi(seconds / 0.18)
	for i in hits:
		var at := centre + _in_disc(radius)
		get_tree().create_timer(ARROW_FALL + i * 0.18).timeout.connect(Sfx.play_at.bind(&"bow_hit", at, 0.0, randf_range(0.85, 1.15)))

## Hundreds of arrows dropping out of the sky over the circle, stuck where they
## land until the volley has passed.
class ArrowRain extends MultiMeshInstance3D:
	var fx: PowerFx
	var centre: Vector3
	var radius: float
	var seconds: float
	var _t: float = 0.0
	## Per arrow: [launch time, from, to].
	var _arrows: Array = []

	func _ready() -> void:
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.035
		shaft.bottom_radius = 0.035
		shaft.height = 1.0
		shaft.radial_segments = 4
		shaft.rings = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.32, 0.22, 0.12)
		shaft.material = mat
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = shaft
		multimesh.instance_count = PowerFx.ARROW_COUNT
		var slant := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * 9.0
		for i in PowerFx.ARROW_COUNT:
			var to := fx.main.power_effects.ground_point(centre + fx._in_disc(radius))
			var from := to + Vector3.UP * 26.0 + slant + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
			_arrows.append([seconds * float(i) / PowerFx.ARROW_COUNT, from, to])
			multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), to))

	func _process(delta: float) -> void:
		_t += delta
		var fade := clampf((seconds + PowerFx.ARROW_FALL + 2.5 - _t) / 1.0, 0.0, 1.0)
		for i in _arrows.size():
			var arrow: Array = _arrows[i]
			var k: float = (_t - arrow[0]) / PowerFx.ARROW_FALL
			if k < 0.0:
				continue
			var from: Vector3 = arrow[1]
			var to: Vector3 = arrow[2]
			var along := (to - from).normalized()
			var tip: Vector3 = from.lerp(to, minf(k, 1.0))
			var basis := Basis.looking_at(along, Vector3.RIGHT if absf(along.y) > 0.99 else Vector3.UP) \
					* Basis(Vector3.RIGHT, -PI * 0.5)
			## Stuck: a little way into the ground, shaft out behind.
			var at := tip - along * (0.5 if k < 1.0 else 0.25)
			multimesh.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * (fade if k >= 1.0 else 1.0)), at))
		if _t > seconds + PowerFx.ARROW_FALL + 3.6:
			queue_free()

## --- Charge of the Old Kings ---

func _play_charge(data: Dictionary) -> void:
	var start: Vector3 = data["pos"]
	var end: Vector3 = data["end"]
	var width: float = data["width"]
	var seconds: float = data["seconds"]
	var dir := (end - start)
	dir.y = 0.0
	dir = dir.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	var mat := _ghost_material(KNIGHT_COLOR, 0.55)
	for i in KNIGHT_COUNT:
		var knight := _instance(KNIGHT_MODEL)
		if knight == null:
			break
		_override_material(knight, mat)
		add_child(knight)
		knight.scale = Vector3.ONE * KNIGHT_SCALE
		var lane: float = lerpf(-0.5, 0.5, float(i) / maxf(KNIGHT_COUNT - 1, 1)) * (width - 1.0)
		## The middle rides a little ahead, a shallow wedge.
		var lead: float = (0.5 - absf(lane) / width) * 2.0
		## Every other rider half a length back, so the row has room to gallop.
		if i % 2 == 1:
			lead -= KNIGHT_STAGGER
		var rider := GhostRider.new()
		rider.fx = self
		rider.knight = knight
		rider.from = start + side * lane - dir * 3.0 + dir * lead
		rider.to = end + side * lane + dir * 3.0 + dir * lead
		rider.seconds = seconds
		rider.phase = randf() * TAU
		add_child(rider)
	Sfx.play_at(&"unsheath", start, 6.0, 0.7)
	for i in roundi(seconds / 0.3):
		get_tree().create_timer(i * 0.3).timeout.connect(func() -> void:
			Sfx.play_at(&"earth_impact", start.lerp(end, float(i) * 0.3 / seconds), -2.0, randf_range(0.7, 0.9)))

## One ghost knight galloping its lane, kicking up dust, fading at the end.
class GhostRider extends Node:
	var fx: PowerFx
	var knight: Node3D
	var from: Vector3
	var to: Vector3
	var seconds: float
	var phase: float
	var _t: float = 0.0
	var _dust: float = 0.0
	var _trail: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		var k := clampf(_t / seconds, 0.0, 1.0)
		var flat := from.lerp(to, k)
		var ground := fx.main.power_effects.ground_point(flat)
		var gallop := absf(sin(_t * 11.0 + phase)) * 0.45
		knight.global_position = ground + Vector3.UP * gallop
		var dir := to - from
		dir.y = 0.0
		knight.global_basis = Basis.looking_at(-dir.normalized(), Vector3.UP).scaled(Vector3.ONE * PowerFx.KNIGHT_SCALE) \
				* Basis(Vector3.RIGHT, sin(_t * 11.0 + phase) * 0.12)
		_dust -= delta
		if _dust <= 0.0:
			_dust = 0.12
			fx.main.feedback._play_impact(ground, Unit.ImpactKind.CHARGE)
		_trail -= delta
		if _trail <= 0.0:
			_trail = PowerFx.KNIGHT_TRAIL_EVERY
			fx._afterimage(knight)
		if _t >= seconds:
			var tween := fx.create_tween()
			tween.tween_property(knight, "scale", knight.scale * Vector3(1.0, 1.4, 1.0), 0.35)
			tween.parallel().tween_property(knight, "position", knight.position + Vector3.UP * 2.0, 0.35)
			tween.tween_callback(knight.queue_free)
			queue_free()

## A fading copy of `figure` where it stands now: the smear a ghost knight
## leaves behind it.
func _afterimage(figure: Node3D) -> void:
	for source in figure.find_children("*", "MeshInstance3D", true, false):
		var copy := MeshInstance3D.new()
		copy.mesh = (source as MeshInstance3D).mesh
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(KNIGHT_COLOR, 0.35)
		copy.material_override = mat
		add_child(copy)
		copy.global_transform = (source as MeshInstance3D).global_transform
		var tween := create_tween()
		tween.tween_property(mat, "albedo_color", Color(KNIGHT_COLOR, 0.0), KNIGHT_TRAIL_FADE)
		tween.parallel().tween_property(copy, "scale", copy.scale * Vector3(1.0, 1.0, 1.25), KNIGHT_TRAIL_FADE)
		tween.tween_callback(copy.queue_free)

## --- The Sword of Aldmere ---

func _play_sword(data: Dictionary) -> void:
	var pos: Vector3 = data["pos"]
	var fall: float = data["fall"]
	var seconds: float = data["seconds"]
	var sword := _instance(SWORD_MODEL)
	if sword == null:
		return
	add_child(sword)
	## Driven in at a lean, and it comes down along its own blade.
	sword.global_basis = Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, SWORD_TILT)
	var along := sword.global_basis.y.normalized()
	var planted := pos - along * SWORD_EMBED
	sword.global_position = planted + along * SWORD_DROP_HEIGHT
	_glow(sword, "Rune", Color(0.5, 0.85, 1.0), 4.0)
	## A shaft of light marks where it will land.
	var shaft := _light_shaft(pos, 1.4, GOLD, 0.25)
	## Its own light, low on the blade, the way the treasure chest glows.
	var light := OmniLight3D.new()
	light.light_color = GOLD
	light.omni_range = SWORD_LIGHT_RANGE
	light.light_energy = 0.0
	light.shadow_enabled = false
	sword.add_child(light)
	light.position = Vector3.UP * 3.0
	var tween := create_tween()
	tween.tween_property(sword, "global_position", planted, fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		main.camera_rig.shake_at(pos, 1.4)
		main.feedback._play_ability_effect(pos, 10.0, GOLD, 1.4, 1.0)
		main.feedback._play_impact(pos, Unit.ImpactKind.SLAM)
		for i in 10:
			var a := TAU * i / 10.0
			main.feedback._play_impact(pos + Vector3(cos(a), 0.0, sin(a)) * 5.0, Unit.ImpactKind.SLAM)
		Sfx.play_at(&"earth_impact", pos, 6.0, 0.6)
		Sfx.play_at(&"collapse", pos, 4.0, 0.8)
		shaft.queue_free()
		light.light_energy = SWORD_LIGHT_ENERGY)
	## It stands, glowing, a ring on the ground round it.
	var aura := _ground_disc(pos, data["aura"], Color(GOLD, 0.0))
	tween.tween_property(aura, "modulate", Color(GOLD, 0.35), 0.6)
	var motes := _particles(40, 2.5, GOLD, Vector3.UP * 2.0, Vector3.ZERO, 0.12, data["aura"] * 0.8)
	tween.tween_callback(func() -> void:
		add_child(motes)
		motes.global_position = pos)
	tween.tween_interval(maxf(seconds - 0.6, 0.0))
	tween.tween_callback(func() -> void: motes.emitting = false)
	tween.tween_property(sword, "global_position", planted - along * 16.0, SWORD_SINK).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(light, "light_energy", 0.0, SWORD_SINK)
	tween.parallel().tween_property(aura, "modulate", Color(GOLD, 0.0), SWORD_SINK)
	tween.tween_callback(func() -> void:
		sword.queue_free()
		aura.queue_free()
		motes.queue_free())

## --- Cursed Treasure ---

func _play_treasure(data: Dictionary) -> void:
	var pos: Vector3 = data["pos"]
	var seconds: float = data["seconds"]
	var chest := _instance(CHEST_MODEL)
	if chest == null:
		return
	add_child(chest)
	chest.name = "TreasureChest%d" % get_child_count()
	chest.set_meta(&"at", pos)
	chest.global_position = pos + Vector3.UP * 9.0
	chest.rotation.y = randf() * TAU
	chest.scale = Vector3.ONE * CHEST_SCALE
	var lid: Node3D = chest.find_child("Lid", true, false)
	var light := OmniLight3D.new()
	light.light_color = GOLD
	light.omni_range = 7.0
	light.light_energy = 0.0
	chest.add_child(light)
	light.position = Vector3.UP * 1.2
	var lure := _ground_disc(pos, data["radius"], Color(GOLD, 0.0))
	var sparkle := _particles(30, 1.2, GOLD, Vector3.UP * 3.0, Vector3(0.0, -2.0, 0.0), 0.08, 0.6)
	var tween := create_tween()
	tween.tween_property(chest, "global_position", pos, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		Sfx.play_at(&"chest", pos, 6.0)
		main.feedback._play_impact(pos, Unit.ImpactKind.CHARGE)
		chest.add_child(sparkle)
		sparkle.position = Vector3.UP * 0.9)
	if lid != null:
		tween.tween_property(lid, "rotation:x", -1.25, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(light, "light_energy", 2.5, 0.35)
	tween.parallel().tween_property(lure, "modulate", Color(GOLD, 0.3), 0.35)
	## A fountain of coins the whole time, and it rattles harder as it goes.
	var popping := seconds - 0.8
	for i in roundi(popping / TREASURE_COIN_EVERY):
		get_tree().create_timer(0.8 + i * TREASURE_COIN_EVERY).timeout.connect(func() -> void:
			if is_instance_valid(chest):
				for k in TREASURE_COINS_EACH:
					_toss_coin(pos + Vector3.UP * 1.3, 4.5))
	tween.tween_interval(maxf(popping - 1.2, 0.0))
	for i in 6:
		tween.tween_property(chest, "rotation:z", 0.12 if i % 2 == 0 else -0.12, 0.1)
	tween.tween_property(chest, "rotation:z", 0.0, 0.05)
	tween.tween_callback(lure.queue_free)

func _play_treasure_blast(data: Dictionary) -> void:
	var pos: Vector3 = data["pos"]
	for child in get_children():
		if child.has_meta(&"at") and (child.get_meta(&"at") as Vector3).distance_to(pos) < 0.5:
			child.queue_free()
	main.camera_rig.shake_at(pos, 1.1)
	main.feedback._play_ability_effect(pos, data["radius"], Color(1.0, 0.55, 0.15), 1.2, 0.9)
	main.feedback._play_impact(pos, Unit.ImpactKind.SLAM)
	for i in 6:
		main.feedback._drop_fireball(pos + _in_disc(data["radius"] * 0.6), Color(1.0, 0.55, 0.15))
	for i in TREASURE_BLAST_COINS:
		_toss_coin(pos + Vector3.UP * 0.6, 11.0)
	Sfx.play_at(&"fire_impact", pos, 6.0, 0.8)
	Sfx.play_at(&"earth_impact", pos, 4.0, 0.9)

var _coin_mesh: CylinderMesh = null

## A gold coin flipped out in an arc that lands and is gone.
func _toss_coin(from: Vector3, spread: float) -> void:
	if _coin_mesh == null:
		_coin_mesh = CylinderMesh.new()
		_coin_mesh.top_radius = 0.12
		_coin_mesh.bottom_radius = 0.12
		_coin_mesh.height = 0.03
		_coin_mesh.radial_segments = 8
		_coin_mesh.rings = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.78, 0.2)
		mat.metallic = 0.8
		mat.roughness = 0.3
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.7, 0.2)
		mat.emission_energy_multiplier = 0.4
		_coin_mesh.material = mat
	var coin := MeshInstance3D.new()
	coin.mesh = _coin_mesh
	coin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(coin)
	coin.global_position = from
	var land := main.power_effects.ground_point(from + _in_disc(spread)) + Vector3.UP * 0.05
	var up := randf_range(2.0, 5.0)
	var time := randf_range(0.5, 0.8)
	var tween := create_tween()
	tween.tween_method(func(k: float) -> void:
		if is_instance_valid(coin):
			coin.global_position = from.lerp(land, k) + Vector3.UP * up * 4.0 * k * (1.0 - k)
			coin.rotation = Vector3(k * 14.0, k * 5.0, 0.0), 0.0, 1.0, time)
	tween.tween_interval(0.8)
	tween.tween_property(coin, "scale", Vector3.ZERO, 0.3)
	tween.tween_callback(coin.queue_free)

## --- Ghost Crew ---

func _play_ghost_zone(data: Dictionary) -> void:
	var pos: Vector3 = data["pos"]
	var seconds: float = data["seconds"]
	var zone := _ground_disc(pos, data["radius"], Color(GHOST, 0.0))
	var wisps := _particles(36, 2.2, GHOST, Vector3.UP * 1.5, Vector3.ZERO, 0.15, data["radius"])
	add_child(wisps)
	wisps.global_position = pos
	main.feedback._play_ability_effect(pos, data["radius"], GHOST, 1.2, 1.0)
	Sfx.play_at(&"arcane_cast", pos, 4.0, 0.6)
	var tween := create_tween()
	tween.tween_property(zone, "modulate", Color(GHOST, 0.3), 0.5)
	tween.tween_interval(maxf(seconds - 1.5, 0.0))
	tween.tween_callback(func() -> void: wisps.emitting = false)
	tween.tween_property(zone, "modulate", Color(GHOST, 0.0), 1.0)
	tween.tween_callback(func() -> void:
		zone.queue_free()
		wisps.queue_free())

func _play_ghost_rise(data: Dictionary) -> void:
	var unit := get_node_or_null(data["path"]) as Unit
	if unit == null:
		return
	unit.show_as_ghost(_ghost_material(GHOST_BODY, GHOST_ALPHA))
	main.feedback._play_ability_effect(unit.global_position, 1.5, GHOST, 0.8, 0.6)
	Sfx.play_at(&"arcane_impact", unit.global_position, 0.0, 0.7)
	var wisps := _particles(14, 1.2, GHOST, Vector3.UP * 1.2, Vector3.ZERO, 0.12, 0.5)
	unit.add_child(wisps)
	wisps.position = Vector3.UP * 0.8
	get_tree().create_timer(maxf(data["seconds"], 0.1)).timeout.connect(func() -> void:
		if is_instance_valid(wisps):
			wisps.queue_free())

## --- The Dread Galleon ---

func _play_galleon(data: Dictionary) -> void:
	var ship := _instance(GALLEON_MODEL)
	if ship == null:
		return
	add_child(ship)
	_team_paint(ship, data.get("tint", Color.WHITE))
	var voyage := Voyage.new()
	voyage.fx = self
	voyage.ship = ship
	var start: Vector3 = data["pos"]
	var end: Vector3 = data["end"]
	var dir := end - start
	dir.y = 0.0
	voyage.dir = dir.normalized()
	voyage.from = start - voyage.dir * data["run_in"]
	voyage.to = end + voyage.dir * data["run_in"]
	voyage.speed = data["speed"]
	add_child(voyage)
	Sfx.play_at(&"water_launch", start, 8.0, 0.5)

## The ship sailing its line on a rolling wave, spray at the bow, a wet
## trail behind it.
class Voyage extends Node:
	var fx: PowerFx
	var ship: Node3D
	var from: Vector3
	var to: Vector3
	var dir: Vector3
	var speed: float
	var _t: float = 0.0
	var _y: float = INF
	var _wave: MeshInstance3D
	var _spray: GPUParticles3D
	var _wet_left: float = 0.0
	var _splash: float = 0.0

	func _ready() -> void:
		_wave = MeshInstance3D.new()
		var hump := SphereMesh.new()
		hump.radius = 1.0
		hump.height = 2.0
		hump.radial_segments = 24
		hump.rings = 12
		var water := StandardMaterial3D.new()
		water.albedo_color = Color(0.55, 0.8, 0.95, 0.75)
		water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water.roughness = 0.1
		water.emission_enabled = true
		water.emission = Color(0.4, 0.7, 0.9)
		water.emission_energy_multiplier = 0.25
		hump.material = water
		_wave.mesh = hump
		fx.add_child(_wave)
		_spray = fx._particles(60, 0.9, Color(0.92, 0.97, 1.0), Vector3.UP * 5.0, Vector3(0.0, -9.0, 0.0), 0.35, 3.0)
		fx.add_child(_spray)

	func _process(delta: float) -> void:
		_t += delta
		var total := from.distance_to(to)
		var along := minf(_t * speed, total)
		var flat := from + dir * along
		var ground: Vector3 = fx.main.power_effects.ground_point(flat)
		## Eased over the ground's ups and downs rather than hugging them.
		_y = ground.y if _y == INF else lerpf(_y, ground.y, 1.0 - exp(-4.0 * delta))
		var bob := sin(_t * 2.3) * PowerFx.GALLEON_BOB
		ship.global_position = Vector3(flat.x, _y + PowerFx.GALLEON_WAVE_HEIGHT + bob, flat.z)
		var k := PowerFx.GALLEON_SCALE
		ship.global_basis = (Basis.looking_at(-dir, Vector3.UP) * Basis(Vector3.FORWARD, sin(_t * 1.7) * 0.06) \
				* Basis(Vector3.RIGHT, sin(_t * 2.3 + 0.8) * 0.04)).scaled(Vector3.ONE * k)
		_wave.global_position = Vector3(flat.x, _y + 0.2, flat.z) + dir * 2.0 * k
		_wave.global_basis = Basis.looking_at(-dir, Vector3.UP).scaled(Vector3(6.0 * k, 1.3 * k + bob * 0.5, 13.0 * k))
		_spray.global_position = ship.global_position + dir * 9.0 * k - Vector3.UP * 0.6
		_wet_left -= delta
		if _wet_left <= 0.0:
			_wet_left = 0.25
			fx._wet_patch(Vector3(flat.x, _y, flat.z))
		_splash -= delta
		if _splash <= 0.0:
			_splash = 0.7
			Sfx.play_at(&"water_impact", ship.global_position, 2.0, randf_range(0.6, 0.8))
		if along >= total:
			_spray.emitting = false
			var tween := fx.create_tween()
			tween.tween_property(ship, "scale", Vector3.ZERO, 0.6)
			tween.parallel().tween_property(_wave, "scale", Vector3.ZERO, 0.6)
			tween.tween_callback(func() -> void:
				ship.queue_free()
				_wave.queue_free()
				_spray.queue_free())
			queue_free()

## A dark wet stain the wave leaves, drying off.
func _wet_patch(pos: Vector3) -> void:
	var wet := _soft_disc(pos, 6.0 * GALLEON_SCALE, Color(0.05, 0.12, 0.2, 0.5))
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(wet, "modulate", Color(0.05, 0.12, 0.2, 0.0), 5.0)
	tween.tween_callback(wet.queue_free)

func _play_cannon_volley(data: Dictionary) -> void:
	var from: Array = data["from"]
	var to: Array = data["to"]
	var flight: float = data["flight"]
	if not from.is_empty():
		main.camera_rig.shake_at(from[0], GALLEON_VOLLEY_SHAKE)
	for i in from.size():
		var muzzle: Vector3 = from[i] + Vector3.UP * 2.5
		var landing: Vector3 = to[i]
		get_tree().create_timer(randf() * 0.08).timeout.connect(_fire_cannon.bind(muzzle, landing, flight))

func _fire_cannon(muzzle: Vector3, landing: Vector3, flight: float) -> void:
	var smoke := _particles(8, 1.0, Color(0.85, 0.85, 0.82), (landing - muzzle).normalized() * 2.0 + Vector3.UP, Vector3.ZERO, 0.6, 0.4)
	smoke.one_shot = true
	add_child(smoke)
	smoke.global_position = muzzle
	get_tree().create_timer(1.5).timeout.connect(smoke.queue_free)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.3)
	flash.omni_range = 5.0
	flash.light_energy = 4.0
	add_child(flash)
	flash.global_position = muzzle
	create_tween().tween_property(flash, "light_energy", 0.0, 0.15).finished.connect(flash.queue_free)
	Sfx.play_at(&"fire_launch", muzzle, 0.0, randf_range(0.5, 0.7))
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = GALLEON_BALL_SIZE
	sphere.height = GALLEON_BALL_SIZE * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.09)
	mat.metallic = 0.6
	sphere.material = mat
	ball.mesh = sphere
	add_child(ball)
	ball.global_position = muzzle
	var tween := create_tween()
	tween.tween_method(func(k: float) -> void:
		if is_instance_valid(ball):
			ball.global_position = muzzle.lerp(landing, k) + Vector3.UP * 4.5 * 4.0 * k * (1.0 - k), 0.0, 1.0, flight)
	tween.tween_callback(func() -> void:
		ball.queue_free()
		main.feedback._play_impact(landing, Unit.ImpactKind.SLAM)
		main.feedback._play_ability_effect(landing, 3.0, Color(1.0, 0.55, 0.2), 0.6, 0.5)
		main.camera_rig.shake_at(landing, 0.25)
		Sfx.play_at(&"fire_impact", landing, 0.0, randf_range(0.8, 1.1)))

## --- Overclock ---

func _play_overclock(data: Dictionary) -> void:
	var pos: Vector3 = data["pos"]
	main.feedback._play_ability_effect(pos, data["radius"], Color(1.0, 0.35, 0.15), 0.9, 0.7)
	Sfx.play_at(&"fire_cast", pos, 4.0, 1.3)
	for path in data["paths"]:
		var unit := get_node_or_null(path) as Node3D
		if unit == null:
			continue
		## A faint wisp of steam and the odd spark: the red body is the signal.
		var steam := _particles(3, 0.9, Color(0.95, 0.95, 0.95, 0.22), Vector3.UP * 2.0, Vector3.ZERO, 0.18, 0.2)
		unit.add_child(steam)
		steam.position = Vector3.UP * 1.1
		var sparks := _particles(2, 0.4, Color(1.0, 0.5, 0.15, 0.5), Vector3.UP * 3.0, Vector3(0.0, -9.0, 0.0), 0.04, 0.3)
		unit.add_child(sparks)
		sparks.position = Vector3.UP * 0.8
		get_tree().create_timer(data["seconds"]).timeout.connect(func() -> void:
			if is_instance_valid(steam):
				steam.queue_free()
			if is_instance_valid(sparks):
				sparks.queue_free())

func _play_overclock_seize(data: Dictionary) -> void:
	for path in data["paths"]:
		var unit := get_node_or_null(path) as Node3D
		if unit == null:
			continue
		main.feedback._play_impact(unit.global_position + Vector3.UP * 0.8, Unit.ImpactKind.SPARK)
		var smoke := _particles(8, 1.6, Color(0.25, 0.25, 0.27), Vector3.UP * 1.2, Vector3.ZERO, 0.35, 0.2)
		unit.add_child(smoke)
		smoke.position = Vector3.UP * 1.0
		get_tree().create_timer(data["seconds"]).timeout.connect(func() -> void:
			if is_instance_valid(smoke):
				smoke.queue_free())
	if not data["paths"].is_empty():
		var first := get_node_or_null(data["paths"][0]) as Node3D
		if first != null:
			Sfx.play_at(&"storm_impact", first.global_position, 0.0, 1.4)

## --- Orbital Lance ---

func _play_lance(data: Dictionary) -> void:
	var peer: int = data["peer"]
	_end_lance(peer)
	var pos: Vector3 = data["pos"]
	var beam := Node3D.new()
	add_child(beam)
	beam.global_position = pos
	for layer in [[1.3, Color(LANCE_COLOR, 0.35)], [0.45, Color(0.95, 1.0, 1.0, 0.95)]]:
		var column := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = layer[0]
		cylinder.bottom_radius = layer[0]
		cylinder.height = 140.0
		cylinder.radial_segments = 16
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = layer[1]
		cylinder.material = mat
		column.mesh = cylinder
		column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.add_child(column)
		column.position = Vector3.UP * 70.0
	var glow: Decal = main.feedback._make_ability_decal()
	glow.size = Vector3(data["radius"] * 2.0, WorldFeedback.ABILITY_DECAL_HEIGHT, data["radius"] * 2.0)
	glow.modulate = Color(LANCE_COLOR, 0.9)
	beam.add_child(glow)
	var sparks := _particles(40, 0.6, Color(0.7, 0.95, 1.0), Vector3.UP * 6.0, Vector3(0.0, -12.0, 0.0), 0.08, 1.5)
	beam.add_child(sparks)
	var light := OmniLight3D.new()
	light.light_color = LANCE_COLOR
	light.omni_range = 12.0
	light.light_energy = 4.0
	beam.add_child(light)
	light.position = Vector3.UP * 2.0
	beam.scale = Vector3(0.1, 1.0, 0.1)
	create_tween().tween_property(beam, "scale", Vector3.ONE, 0.25)
	main.camera_rig.shake_at(pos, 0.6)
	Sfx.play_at(&"storm_impact", pos, 6.0, 0.7)
	_lances[peer] = {"beam": beam, "target": pos, "last_scorch": pos, "hum": 0.0}
	if peer == main.my_peer_id():
		main.power_effects.listen_for_steer(data["seconds"])

func _set_lance_target(peer_id: int, pos: Vector3) -> void:
	if _lances.has(peer_id):
		_lances[peer_id]["target"] = pos

func _play_lance_end(data: Dictionary) -> void:
	_end_lance(data["peer"])

func _end_lance(peer_id: int) -> void:
	if not _lances.has(peer_id):
		return
	var beam: Node3D = _lances[peer_id]["beam"]
	_lances.erase(peer_id)
	var tween := create_tween()
	tween.tween_property(beam, "scale", Vector3(0.01, 1.0, 0.01), 0.3)
	tween.tween_callback(beam.queue_free)

func _process(delta: float) -> void:
	for peer in _lances:
		var lance: Dictionary = _lances[peer]
		var beam: Node3D = lance["beam"]
		var target: Vector3 = lance["target"]
		beam.global_position = beam.global_position.lerp(target, 1.0 - exp(-14.0 * delta))
		if beam.global_position.distance_to(lance["last_scorch"]) >= LANCE_SCORCH_SPACING:
			lance["last_scorch"] = beam.global_position
			var scorch := _soft_disc(beam.global_position, 2.0, Color(0.05, 0.03, 0.02, 0.8))
			var tween := create_tween()
			tween.tween_interval(6.0)
			tween.tween_property(scorch, "modulate", Color(0.05, 0.03, 0.02, 0.0), 6.0)
			tween.tween_callback(scorch.queue_free)
		lance["hum"] -= delta
		if lance["hum"] <= 0.0:
			lance["hum"] = 0.4
			Sfx.play_at(&"storm_impact", beam.global_position, -4.0, randf_range(1.2, 1.5))

## --- Colossus Drop ---

func _play_pod(data: Dictionary) -> void:
	var pos: Vector3 = data["pos"]
	var fall: float = data["fall"]
	var pod := _instance(POD_MODEL)
	if pod == null:
		return
	add_child(pod)
	_team_paint(pod, data.get("tint", Color.WHITE))
	var sky := pos + Vector3(8.0, POD_DROP_HEIGHT, 6.0)
	pod.global_position = sky
	var trail := _particles(50, 0.7, Color(1.0, 0.55, 0.15), Vector3.UP * 2.0, Vector3.ZERO, 0.7, 0.6)
	pod.add_child(trail)
	trail.position = Vector3.UP * 2.5
	var tween := create_tween()
	tween.tween_property(pod, "global_position", pos, fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		trail.emitting = false
		main.camera_rig.shake_at(pos, 1.5)
		main.feedback._play_ability_effect(pos, 6.0, Color(1.0, 0.55, 0.15), 1.2, 0.9)
		main.feedback._play_impact(pos, Unit.ImpactKind.SLAM)
		Sfx.play_at(&"earth_impact", pos, 6.0, 0.5)
		Sfx.play_at(&"collapse", pos, 4.0, 0.7))
	## The petals fold open and the mech steps out.
	tween.tween_interval(0.5)
	tween.tween_callback(func() -> void:
		Sfx.play_at(&"gate_open", pos, 4.0, 0.6)
		for petal in pod.find_children("Petal*", "", true, false):
			## Hinged at its foot: tipped over outward, away from the pod's middle.
			var out := Vector3(petal.position.x, 0.0, petal.position.z)
			if out.length_squared() < 0.0001:
				continue
			var hinge := Vector3.UP.cross(out.normalized()).normalized()
			var rest: Basis = petal.basis
			var open := create_tween()
			open.tween_method(func(angle: float) -> void:
				if is_instance_valid(petal):
					petal.basis = Basis(hinge, angle) * rest, 0.0, 1.7, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	tween.tween_interval(4.0)
	tween.tween_property(pod, "global_position", pos - Vector3.UP * 4.0, 2.0)
	tween.tween_callback(pod.queue_free)

func _play_colossus_blast(data: Dictionary) -> void:
	var pos: Vector3 = data["pos"]
	var radius: float = data["radius"]
	main.camera_rig.shake_at(pos, 1.6)
	main.feedback._play_ability_effect(pos, radius, Color(1.0, 0.5, 0.15), 1.4, 1.0)
	main.feedback._play_impact(pos, Unit.ImpactKind.SLAM)
	for i in 10:
		main.feedback._drop_fireball(pos + _in_disc(radius * 0.8), Color(1.0, 0.5, 0.15))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.omni_range = radius * 2.5
	light.light_energy = 8.0
	add_child(light)
	light.global_position = pos + Vector3.UP * 3.0
	create_tween().tween_property(light, "light_energy", 0.0, 0.8).finished.connect(light.queue_free)
	Sfx.play_at(&"fire_impact", pos, 8.0, 0.6)
	Sfx.play_at(&"earth_impact", pos, 6.0, 0.5)

## --- Pieces ---

func _instance(path: String) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _scenes[path]
	return scene.instantiate() as Node3D if scene != null else null

func _in_disc(radius: float) -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * radius
	return Vector3(cos(a) * r, 0.0, sin(a) * r)

## A flat disc projected on the ground, coloured (and faded) by its modulate.
func _ground_disc(pos: Vector3, radius: float, color: Color) -> Decal:
	var decal: Decal = main.feedback._make_ability_decal()
	decal.size = Vector3(radius * 2.0, WorldFeedback.ABILITY_DECAL_HEIGHT, radius * 2.0)
	decal.modulate = color
	decal.emission_energy = 0.3
	add_child(decal)
	decal.global_position = pos
	return decal

var _soft_texture: ImageTexture = null

## A stain on the ground with no rim, fading out to its edge (a wet patch, a
## scorch mark).
func _soft_disc(pos: Vector3, radius: float, color: Color) -> Decal:
	if _soft_texture == null:
		const SIZE: int = 64
		var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		for y in SIZE:
			for x in SIZE:
				var d: float = (Vector2(x + 0.5, y + 0.5) - Vector2(SIZE, SIZE) * 0.5).length() / (SIZE * 0.5)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0 - smoothstep(0.35, 1.0, d)))
		image.generate_mipmaps()
		_soft_texture = ImageTexture.create_from_image(image)
	var decal := Decal.new()
	decal.texture_albedo = _soft_texture
	decal.size = Vector3(radius * 2.0, WorldFeedback.ABILITY_DECAL_HEIGHT, radius * 2.0)
	decal.modulate = color
	decal.upper_fade = 0.15
	decal.lower_fade = 0.15
	add_child(decal)
	decal.global_position = pos
	return decal

## A soft column of light from the sky onto `pos`.
func _light_shaft(pos: Vector3, radius: float, color: Color, alpha: float) -> MeshInstance3D:
	var shaft := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius * 0.6
	cylinder.bottom_radius = radius
	cylinder.height = 80.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color, alpha)
	cylinder.material = mat
	shaft.mesh = cylinder
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shaft)
	shaft.global_position = pos + Vector3.UP * 40.0
	return shaft

## The kit surfaces made of material `material_name` lit from within.
func _glow(root: Node, material_name: String, color: Color, energy: float) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		for i in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(i)
			if source == null or source.resource_name != material_name:
				continue
			var lit := StandardMaterial3D.new()
			lit.albedo_color = color
			lit.emission_enabled = true
			lit.emission = color
			lit.emission_energy_multiplier = energy
			mesh_instance.set_surface_override_material(i, lit)
	for child in root.get_children():
		_glow(child, material_name, color, energy)

## The kit's TeamColor / TeamColorDark surfaces in the caster's colour.
func _team_paint(root: Node, tint: Color) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		for i in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(i)
			if source == null or not source.resource_name.begins_with("TeamColor"):
				continue
			var paint := StandardMaterial3D.new()
			paint.albedo_color = tint.darkened(0.35) if source.resource_name.ends_with("Dark") else tint
			paint.roughness = 0.85
			mesh_instance.set_surface_override_material(i, paint)
	for child in root.get_children():
		_team_paint(child, tint)

func _ghost_material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	## Depth pre-pass: the near side of the rider hides his far side, so he
	## reads as one glassy figure rather than a tangle of see-through parts.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	mat.albedo_color = Color(color, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6
	return mat

func _override_material(root: Node, mat: Material) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).material_override = mat
		(root as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in root.get_children():
		_override_material(child, mat)

## Soft glowing blobs: `velocity` is the push out, `gravity` what pulls them
## after, from a sphere `spread` across.
func _particles(amount: int, lifetime: float, color: Color, velocity: Vector3, gravity: Vector3, size: float,
		spread: float) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = maxf(spread, 0.01)
	process.direction = velocity.normalized() if velocity.length_squared() > 0.0 else Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = velocity.length() * 0.6
	process.initial_velocity_max = velocity.length() * 1.2
	process.gravity = gravity
	process.scale_min = 0.6
	process.scale_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	var blob := SphereMesh.new()
	blob.radius = size
	blob.height = size * 2.0
	blob.radial_segments = 6
	blob.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	blob.material = mat
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.process_material = process
	particles.draw_pass_1 = blob
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.emitting = true
	return particles
