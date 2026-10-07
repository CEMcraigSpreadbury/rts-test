"""Builds the unit figures: <Name>.glb and <Name>_LOD1.glb next to this kit,
the palette images, and (with --renders) preview stills.

	blender --background --factory-startup --python build.py -- [Name ...] [--base] [--portraits]
			[--renders DIR] [--lineup DIR] [--team-body tunic|tabard] [--out DIR]

With no names every unit units.UNITS marks ready is built. --base stands each figure
on its round tabletop base (off for now: see units.py). --portraits renders
the HUD portraits into portraits/ (see portraits()); --renders a turnaround
of one unit, --lineup every unit built, blue and red, into DIR. The kit's modules sit beside
this script. --team-body picks where the team's colour sits (parts.TEAM_BODY);
--out writes the GLBs and palettes to DIR instead of beside the kit (trial
builds that leave the game's figures alone). The modules: geo (mesh helpers), palette (colours as data), parts (the pieces
of a figure), units (which pieces make each unit), figure (finishing, baking
and export).
"""
import math
import sys
import tempfile
from pathlib import Path

import bpy

KIT = Path(__file__).resolve().parent
sys.path.insert(0, str(KIT))
# No __pycache__ left beside the kit in the repo.
sys.dont_write_bytecode = True

import figure  # noqa: E402
import palette  # noqa: E402
import parts  # noqa: E402
import units  # noqa: E402

OUT = KIT.parent
PALETTES = OUT / "palettes"


def _args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	names, renders, base = [], None, False
	i = 0
	while i < len(argv):
		if argv[i] == "--renders":
			renders = Path(argv[i + 1])
			i += 2
			continue
		if argv[i] == "--base":
			base = True
		else:
			names.append(argv[i])
		i += 1
	return names or [n for n, spec in units.UNITS.items() if spec.get("ready")], renders, base


def _clear():
	for obj in list(bpy.data.objects):
		bpy.data.objects.remove(obj)
	for mesh in list(bpy.data.meshes):
		bpy.data.meshes.remove(mesh)


def build(name, preview_png, base):
	recipe = units.UNITS[name]
	# One preview material per palette: a shared one would paint every race
	# with the last palette loaded.
	material_name = "Figure_%s" % recipe["palette"]
	made = {}
	for lod in (0, 1):
		bm = recipe["build"](lod, base)
		mesh = figure.finish(bm, name if lod == 0 else "%s_LOD1" % name)
		bm.free()
		obj = bpy.data.objects.new(mesh.name, mesh)
		bpy.context.scene.collection.objects.link(obj)
		mesh.materials.append(figure.preview_material(preview_png, material_name))
		path = OUT / ("%s.glb" % mesh.name)
		figure.export_glb(obj, path)
		dims = obj.dimensions
		print("FIGURE %s lod%d tris=%d size=%.3f x %.3f x %.3f -> %s" % (
				name, lod, figure.triangles(mesh), dims.x, dims.y, dims.z, path.name))
		made[lod] = obj
	return made


# --- previews ---------------------------------------------------------------

def _look_at(cam, target):
	direction = target - cam.location
	cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()


def _stage(scene):
	from mathutils import Vector
	scene.render.engine = 'CYCLES'
	scene.cycles.device = 'CPU'
	scene.cycles.samples = 48
	scene.cycles.use_denoising = True
	scene.render.film_transparent = False
	scene.view_settings.view_transform = 'AgX'
	scene.view_settings.look = 'AgX - Medium High Contrast'
	world = bpy.data.worlds.new("Sky")
	world.use_nodes = True
	bg = world.node_tree.nodes["Background"]
	bg.inputs[0].default_value = (0.42, 0.56, 0.78, 1.0)
	bg.inputs[1].default_value = 0.9
	scene.world = world

	sun_data = bpy.data.lights.new("Sun", 'SUN')
	sun_data.energy = 4.2
	sun_data.angle = math.radians(3.0)
	sun_data.color = (1.0, 0.95, 0.86)
	sun = bpy.data.objects.new("Sun", sun_data)
	sun.rotation_euler = (math.radians(50.0), 0.0, math.radians(-35.0))
	scene.collection.objects.link(sun)

	ground_mesh = bpy.data.meshes.new("Ground")
	s = 30.0
	ground_mesh.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
	ground = bpy.data.objects.new("Ground", ground_mesh)
	mat = bpy.data.materials.new("Grass")
	mat.use_nodes = True
	p = mat.node_tree.nodes["Principled BSDF"]
	p.inputs["Base Color"].default_value = (0.20, 0.30, 0.075, 1.0)
	p.inputs["Roughness"].default_value = 1.0
	ground_mesh.materials.append(mat)
	scene.collection.objects.link(ground)

	cam_data = bpy.data.cameras.new("Cam")
	cam = bpy.data.objects.new("Cam", cam_data)
	scene.collection.objects.link(cam)
	scene.camera = cam
	return cam


def _team_copy(src, material, location):
	"""A copy of `src` drawn with `material` (another team's preview)."""
	copy = src.copy()
	bpy.context.scene.collection.objects.link(copy)
	copy.hide_render = False
	copy.material_slots[0].link = 'OBJECT'
	copy.material_slots[0].material = material
	copy.location = location
	return copy


def renders(name, made, out_dir, red_material):
	"""Four views of the blue figure, the blue and a red one side by side,
	and blocks of them (blue LOD0 left, red LOD1 right) at the game camera."""
	from mathutils import Vector
	out_dir.mkdir(parents=True, exist_ok=True)
	scene = bpy.context.scene
	cam = _stage(scene)
	hero = made[0]
	made[1].hide_render = True
	target = Vector((0.0, 0.0, 0.45))

	scene.render.resolution_x = 900
	scene.render.resolution_y = 1100
	cam.data.lens = 85.0
	cam.data.sensor_fit = 'VERTICAL'
	views = {
		"front34": (35.0, 12.0, 4.6),
		"side": (-90.0, 6.0, 4.6),
		"back": (160.0, 14.0, 4.6),
		"pitch": (20.0, 35.0, 4.6),
	}
	for view, (azimuth, elevation, dist) in views.items():
		# Azimuth 0 is straight in front (-Y); positive swings to the figure's left (+X).
		az, el = math.radians(azimuth), math.radians(elevation)
		cam.location = target + Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el))) * dist
		_look_at(cam, target)
		scene.render.filepath = str(out_dir / ("%s_%s.png" % (name, view)))
		bpy.ops.render.render(write_still=True)
		print("RENDER", scene.render.filepath)

	# Blue and red side by side, from the front and from the game's pitch.
	red = _team_copy(hero, red_material, (0.62, 0.0, 0.0))
	hero.location = (-0.31, 0.0, 0.0)
	red.location = (0.31, 0.0, 0.0)
	scene.render.resolution_x = 1400
	for view, (azimuth, elevation, dist) in {"teams": (20.0, 12.0, 5.6), "teams_pitch": (15.0, 35.0, 5.6)}.items():
		az, el = math.radians(azimuth), math.radians(elevation)
		cam.location = target + Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el))) * dist
		_look_at(cam, target)
		scene.render.filepath = str(out_dir / ("%s_%s.png" % (name, view)))
		bpy.ops.render.render(write_still=True)
		print("RENDER", scene.render.filepath)
	bpy.data.objects.remove(red)
	hero.location = (0.0, 0.0, 0.0)

	# A block at the game's own camera (pitch 35, FOV 50, distance 22 and 12),
	# rendered at 1080p and cropped, so it shows the size the game draws it.
	block = []
	for row in range(3):
		for col in range(4):
			for lod, src in ((0, hero), (1, made[1])):
				copy = src.copy()
				copy.hide_render = False
				scene.collection.objects.link(copy)
				if lod:
					copy.material_slots[0].link = 'OBJECT'
					copy.material_slots[0].material = red_material
				copy.location = (col * 1.0 - 1.5 + (5.0 if lod else 0.0), row * 1.0 - 1.0, 0.0)
				copy.rotation_euler = (0.0, 0.0, math.radians((row * 7 + col * 13) % 11 - 5))
				block.append(copy)
	hero.hide_render = True
	scene.render.resolution_x = 1920
	scene.render.resolution_y = 1080
	cam.data.lens_unit = 'FOV'
	cam.data.angle = math.radians(50.0)
	centre = Vector((1.0, 0.0, 0.0))
	for zoom in (12.0, 22.0):
		pitch = math.radians(35.0)
		cam.location = centre + Vector((0.0, -math.cos(pitch), math.sin(pitch))) * zoom
		_look_at(cam, centre)
		scene.render.filepath = str(out_dir / ("%s_block_zoom%d.png" % (name, zoom)))
		bpy.ops.render.render(write_still=True)
		print("RENDER", scene.render.filepath)
	for copy in block:
		bpy.data.objects.remove(copy)
	hero.hide_render = False


# --- lineup and portraits ----------------------------------------------------

def _mounted(name):
	return units.UNITS[name].get("mounted", False)


def lineup(made_by_name, out_dir, red_materials):
	"""Every figure built, side by side: a blue row and a red row behind it,
	from the front and from the game's camera pitch."""
	from mathutils import Vector
	out_dir.mkdir(parents=True, exist_ok=True)
	scene = bpy.context.scene
	cam = _stage(scene)
	x = 0.0
	placed = []
	for name, made in made_by_name.items():
		hero = made[0]
		made[1].hide_render = True
		width = 1.25 if _mounted(name) else 0.85
		x += width * 0.5
		for row_y, material in ((0.0, None), (1.7, red_materials[units.UNITS[name]["palette"]])):
			copy = hero.copy()
			scene.collection.objects.link(copy)
			copy.hide_render = False
			if material is not None:
				copy.material_slots[0].link = 'OBJECT'
				copy.material_slots[0].material = material
			copy.location = (x, row_y, 0.0)
			copy.rotation_euler = (0.0, 0.0, math.radians(-18.0))
			placed.append(copy)
		hero.hide_render = True
		x += width * 0.5
	centre = Vector((x * 0.5, 0.85, 0.55))
	cam.data.type = 'ORTHO'
	cam.data.ortho_scale = x + 0.6
	scene.render.resolution_x = 3400
	scene.render.resolution_y = int(3400 * 3.4 / (x + 0.6))
	for view, azimuth, elevation in (("front", 0.0, 10.0), ("pitch", 0.0, 35.0), ("side", 50.0, 15.0)):
		el, az = math.radians(elevation), math.radians(azimuth)
		cam.location = centre + Vector((-math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el))) * 30.0
		_look_at(cam, centre)
		scene.render.filepath = str(out_dir / ("lineup_%s.png" % view))
		bpy.ops.render.render(write_still=True)
		print("RENDER", scene.render.filepath)
	for copy in placed:
		bpy.data.objects.remove(copy)
	cam.data.type = 'PERSP'


def _mask_material():
	"""Blender-only: white where a face sits on a team row, else black, as
	flat emission, for a portrait's team mask."""
	mask_png = Path(tempfile.gettempdir()) / "_figure_team_mask.png"
	palette.write_mask_png(mask_png)
	mat = bpy.data.materials.new("FigureMask")
	mat.use_nodes = True
	nt = mat.node_tree
	nt.nodes.clear()
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	emit = nt.nodes.new("ShaderNodeEmission")
	tex = nt.nodes.new("ShaderNodeTexImage")
	tex.image = bpy.data.images.load(str(mask_png), check_existing=True)
	tex.image.colorspace_settings.name = 'Non-Color'
	tex.interpolation = 'Closest'
	nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
	nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
	return mat


PORTRAIT_SIZE = 160


def portraits(made_by_name, untinted_materials):
	"""For the HUD: each figure's head and shoulders from a little to its
	left, its team rows left grey, beside a mask of where those rows are.
	One image per unit, the portrait on the left and the mask on the right
	(UnitPortrait tints it per team)."""
	import numpy as np
	from mathutils import Vector
	out_dir = OUT / "portraits"
	out_dir.mkdir(exist_ok=True)
	scene = bpy.context.scene
	cam = _stage(scene)
	bpy.data.objects["Ground"].hide_render = True
	mask_material = _mask_material()
	scene.render.film_transparent = True
	scene.render.resolution_x = PORTRAIT_SIZE
	scene.render.resolution_y = PORTRAIT_SIZE
	cam.data.type = 'PERSP'
	cam.data.lens = 85.0
	cam.data.sensor_fit = 'VERTICAL'
	for made in made_by_name.values():
		made[0].hide_render = True
		made[1].hide_render = True
	for name, made in made_by_name.items():
		spec = units.UNITS[name]
		if spec.get("portrait") is None:
			continue
		hero = made[0]
		hero.hide_render = False
		target = Vector(spec["portrait"])
		az, el = math.radians(28.0), math.radians(14.0)
		cam.location = target + Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el))) \
				* spec["portrait_distance"]
		_look_at(cam, target)
		layers = []
		untinted_material = untinted_materials[spec["palette"]]
		for material, transform in ((untinted_material, 'AgX'), (mask_material, 'Standard')):
			hero.material_slots[0].link = 'OBJECT'
			hero.material_slots[0].material = material
			scene.view_settings.view_transform = transform
			scene.view_settings.look = 'AgX - Medium High Contrast' if transform == 'AgX' else 'None'
			path = Path(tempfile.gettempdir()) / ("_portrait_%s.png" % transform)
			scene.render.filepath = str(path)
			bpy.ops.render.render(write_still=True)
			image = bpy.data.images.load(str(path))
			px = np.array(image.pixels[:], dtype=np.float32).reshape(PORTRAIT_SIZE, PORTRAIT_SIZE, 4)
			bpy.data.images.remove(image)
			layers.append(px)
		colour, mask = layers
		sheet = np.zeros((PORTRAIT_SIZE, PORTRAIT_SIZE * 2, 4), dtype=np.float32)
		sheet[:, :PORTRAIT_SIZE] = colour
		sheet[:, PORTRAIT_SIZE:, 0:3] = mask[:, :, 0:1]
		sheet[:, PORTRAIT_SIZE:, 3] = colour[:, :, 3]
		out = bpy.data.images.new("portrait_" + name, PORTRAIT_SIZE * 2, PORTRAIT_SIZE, alpha=True)
		out.pixels[:] = sheet.ravel()
		out.filepath_raw = str(out_dir / ("%s.png" % name))
		out.file_format = 'PNG'
		out.save()
		bpy.data.images.remove(out)
		hero.material_slots[0].link = 'DATA'
		hero.hide_render = True
		print("PORTRAIT", name)
	scene.render.film_transparent = False
	scene.view_settings.view_transform = 'AgX'
	scene.view_settings.look = 'AgX - Medium High Contrast'


def _pop_flag(argv, flag, takes_value=False):
	if flag not in argv:
		return None
	i = argv.index(flag)
	value = argv[i + 1] if takes_value else True
	del argv[i:i + (2 if takes_value else 1)]
	return value


def main():
	global OUT, PALETTES
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	lineup_dir = _pop_flag(argv, "--lineup", True)
	want_portraits = _pop_flag(argv, "--portraits")
	team_body = _pop_flag(argv, "--team-body", True)
	if team_body:
		assert team_body in ("tunic", "tabard"), team_body
		parts.TEAM_BODY = team_body
	out_dir = _pop_flag(argv, "--out", True)
	if out_dir:
		OUT = Path(out_dir)
		OUT.mkdir(parents=True, exist_ok=True)
		PALETTES = OUT / "palettes"
	sys.argv = sys.argv[:sys.argv.index("--") + 1] + argv if "--" in sys.argv else sys.argv
	names, render_dir, base = _args()
	PALETTES.mkdir(exist_ok=True)
	for race in palette.PALETTES:
		palette.write_png(PALETTES / ("%s.png" % race), race)
	_clear()
	scratch = render_dir or (Path(lineup_dir) if lineup_dir else Path(tempfile.gettempdir()))
	scratch.mkdir(parents=True, exist_ok=True)
	made_by_name = {}
	materials = {}
	for name in names:
		race = units.UNITS[name]["palette"]
		if race not in materials:
			blue_png = scratch / ("_preview_%s.png" % race)
			red_png = scratch / ("_preview_%s_red.png" % race)
			grey_png = scratch / ("_preview_%s_grey.png" % race)
			palette.write_png(blue_png, race, team=palette.PREVIEW_TEAM)
			palette.write_png(red_png, race, team=palette.PREVIEW_TEAM_2)
			palette.write_png(grey_png, race)
			materials[race] = (blue_png, figure.preview_material(red_png, "FigureRed_" + race),
					figure.preview_material(grey_png, "FigureGrey_" + race))
		made_by_name[name] = build(name, materials[race][0], base)
	if render_dir is not None and len(names) == 1:
		renders(names[0], made_by_name[names[0]], render_dir, materials[units.UNITS[names[0]]["palette"]][1])
	if lineup_dir:
		lineup(made_by_name, Path(lineup_dir), {race: m[1] for race, m in materials.items()})
	if want_portraits:
		portraits(made_by_name, {race: m[2] for race, m in materials.items()})


main()
