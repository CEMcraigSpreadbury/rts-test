class_name FarmField
extends Gatherable
## One of the fields a Mill lays out around itself (see BuildingType.companion_*).
## It never runs out: it goes round a cycle, and the farmers assigned to it stay
## on it the whole way round rather than being sent anywhere else.
##
##   SOWING   the farmers' work sows it (sow_work, in gather ticks)
##   GROWING  it grows on its own for grow_seconds; the farmers tend it
##   RIPE     ripe_yield food to harvest; emptied, it goes back to SOWING
##
## Only RIPE gives anything (see is_yielding), so a farmer works the field in
## every stage but only walks to the Mill with a load. The host runs the cycle;
## every peer is told of each stage change and animates the crop itself.

enum Stage { SOWING, GROWING, RIPE }

## Gather ticks of work to sow it. Two farmers take half as long.
@export var sow_work: int = 8
@export var grow_seconds: float = 60.0
@export var ripe_yield: int = 120

## How the crop looks through the cycle: what stands above the field's bed is
## squashed flat for bare soil and rises as it grows (see crop_base), tinted from earth to green to its own ripe
## colour (the tint multiplies the baked texture, so white is as exported).
const SOIL_HEIGHT: float = 0.06
const SHOOT_HEIGHT: float = 0.15
## A people's own field can colour its cycle its own way (the Robots' Charge
## Pad: drained grey cells, charging amber, full).
@export var soil_tint: Color = Color(0.62, 0.45, 0.3)
@export var shoot_tint: Color = Color(0.5, 0.95, 0.4)
## The top of the field's bed in its model's space: only what stands above it
## is squashed for the crop's height (plastic_prop.gdshader's crop_height), so
## the bed itself never sinks into the ground.
@export var crop_base: float = 0.16
const RIPE_TINT: Color = Color(1.0, 1.0, 1.0)

var stage: Stage = Stage.SOWING
var _sown: int = 0
var _ripe_left: int = 0
## Seconds into the current stage, kept on every peer for the growing crop.
var _stage_time: float = 0.0
var _meshes: Array[GeometryInstance3D] = []

func _ready() -> void:
	super()
	## Never runs out, so never depletes (Gatherable.gather is not used here).
	amount_remaining = 1
	if _model != null:
		_collect_meshes(_model)
	_show_stage()
	## Bare earth under and round the field, as under a building, so no grass
	## grows up through the crop.
	var obstacle := get_node_or_null(^"NavigationObstacle3D") as NavigationObstacle3D
	if obstacle != null:
		(func(): GroundStamps.stamp_building(self, obstacle.radius)).call_deferred()

func _collect_meshes(node: Node) -> void:
	if node is GeometryInstance3D:
		_meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child)

## A field doesn't give under a farmer's blows.
func play_harvest_squash(_from: Vector3 = Vector3.INF, _strength: float = 1.0) -> void:
	pass

func is_yielding() -> bool:
	return stage == Stage.RIPE

## Food ready to harvest: shown in the info panel in place of a remaining total.
func display_remaining() -> int:
	return _ripe_left if stage == Stage.RIPE else 0

## Host only (gathering runs there). Sowing and tending take work but give
## nothing; only a ripe field gives food.
func gather(amount: int) -> int:
	match stage:
		Stage.SOWING:
			_sown += amount
			if _sown >= sow_work:
				_set_stage(Stage.GROWING)
			return 0
		Stage.RIPE:
			var taken: int = mini(amount, _ripe_left)
			_ripe_left -= taken
			if _ripe_left <= 0:
				_set_stage(Stage.SOWING)
			return taken
	return 0

func _process(delta: float) -> void:
	_stage_time += delta
	if stage == Stage.GROWING:
		if multiplayer.is_server() and _stage_time >= grow_seconds:
			_set_stage(Stage.RIPE)
		else:
			_show_stage()

func _set_stage(next: Stage) -> void:
	_enter_stage(next)
	if multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_rpc_stage.rpc(int(next))

@rpc("authority", "call_remote", "reliable")
func _rpc_stage(next: int) -> void:
	_enter_stage(next as Stage)

func _enter_stage(next: Stage) -> void:
	stage = next
	_stage_time = 0.0
	_sown = 0
	if next == Stage.RIPE:
		_ripe_left = ripe_yield
	_show_stage()

func _show_stage() -> void:
	if _model == null:
		return
	var height := 1.0
	var tint := RIPE_TINT
	match stage:
		Stage.SOWING:
			height = SOIL_HEIGHT
			tint = soil_tint
		Stage.GROWING:
			var grown: float = clampf(_stage_time / maxf(grow_seconds, 0.01), 0.0, 1.0)
			height = lerpf(SHOOT_HEIGHT, 1.0, grown)
			tint = shoot_tint.lerp(RIPE_TINT, grown * grown)
	for mesh in _meshes:
		mesh.set_instance_shader_parameter(&"tint", tint)
		mesh.set_instance_shader_parameter(&"crop_height", height)
		mesh.set_instance_shader_parameter(&"crop_base", crop_base)
