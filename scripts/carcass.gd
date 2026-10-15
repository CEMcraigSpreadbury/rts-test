class_name Carcass
extends Gatherable
## What a hunted animal leaves behind, as in Age of Empires: its figure lying
## on its side, worked by villagers for food until it is picked clean. Walkable
## (collision layer 2, like a Farm), so it never blocks a path.
##
## Made by Unit._play_death_and_remove on every peer, named after the animal's
## net id so each peer's copy sits at the same path. Hidden until the animal's
## death has played out, then shown where it fell.

## Food for each point of an animal's hunt_meat (a deer 96, a boar 128).
const FOOD_PER_MEAT: int = 8
const FOOD: ResourceType = preload("res://resources/food_resource_type.tres")
const COLLISION_RADIUS: float = 0.6
const COLLISION_HEIGHT: float = 0.5

## The carcass `animal` leaves, added to the scene, or null if it leaves none.
static func leave(animal: Unit) -> Carcass:
	if animal.hunt_meat <= 0:
		return null
	var main := animal.get_tree().current_scene
	if main == null:
		return null
	var carcass := Carcass.new()
	carcass.name = "Carcass%d" % animal.net_id if animal.net_id >= 0 else "Carcass%d" % animal.get_instance_id()
	carcass.display_name = animal.display_name
	carcass.resource_type = FOOD
	carcass.amount_remaining = animal.hunt_meat * FOOD_PER_MEAT
	carcass.gather_range = 1.4
	carcass.seek_replacement_when_depleted = true
	carcass.collision_layer = 2
	carcass.collision_mask = 0
	carcass.add_to_group(&"gatherables")
	carcass.add_to_group(&"carcasses")
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = COLLISION_RADIUS
	cylinder.height = COLLISION_HEIGHT
	shape.shape = cylinder
	shape.position.y = COLLISION_HEIGHT * 0.5
	carcass.add_child(shape)
	carcass._figure = _lying_figure(animal)
	var mesh := Unit.figure_mesh(animal.figure_model)
	if mesh != null:
		## Lying down, its height and length are what spread over the ground.
		carcass.ring_radius = 0.5 * maxf(mesh.get_aabb().size.y, mesh.get_aabb().size.z) + 0.15
	main.add_child(carcass)
	carcass.global_position = animal.global_position
	return carcass

var _figure: MultiMeshInstance3D = null
## Its hover ring's radius: round the body lying there (WorldFeedback).
var ring_radius: float = 0.8

func _ready() -> void:
	super._ready()
	if _figure != null:
		_figure.visible = false
		add_child(_figure)
		## Gatherable's harvest squash bounces whatever it calls the model.
		_model = _figure
		_model_base_scale = _figure.scale
		_model_base_quat = _figure.quaternion

## Shows the carcass once the animal's own death has finished playing.
func reveal() -> void:
	if _figure != null:
		_figure.visible = true

## The animal's figure on its side, drawn with the material FigureBatcher gives
## it so it looks the same as it did standing.
static func _lying_figure(animal: Unit) -> MultiMeshInstance3D:
	var mesh := Unit.figure_mesh(animal.figure_model)
	if mesh == null:
		return null
	## Rolled onto its side about its own length, lifted so the flank that was
	## at -X rests on the ground, and slid so the body's middle (not the feet it
	## stood on, now off to one side) sits on the carcass's own centre, where
	## its click and its hover ring are.
	var box: AABB = mesh.get_aabb()
	var lying := Basis(Vector3.UP, animal.rotation.y) * Basis(Vector3.BACK, PI * 0.5)
	var middle: Vector3 = lying * box.get_center()
	return FigureMaterials.standalone(mesh, animal.figure_palette, animal.team_tint,
			Transform3D(lying, Vector3(-middle.x, -box.position.x, -middle.z)))
