# Builds every Robots building (Races/Robots/*.glb) on top of the Aldmere kit
# (TownBuildings/kit/common.py): a clockwork tin-toy factory town. Everything
# stands on a riveted steel plate edged in hazard stripes; buildings are tin
# boxes and drums in silver and cream enamel, banded with rivets, domed and
# roofed in the team's enamel, with brass gears and wind-up keys, chimneys,
# pipes, amber lamp portholes and antennae.
#
#	blender --background --factory-startup --python robots_buildings.py [-- Name ...]
#
# With no names every building is built.
import sys, os
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(_HERE, '..', '..', '..', 'TownBuildings', 'kit')))
import common
from common import *
from common import _finish, _placed, _rot
import bmesh


def _out_path(name):
	return os.path.join(os.path.dirname(_HERE), name + '.glb')


common.out_path = _out_path

# Linear colours. TeamColor stays the kit's blue and alone in the team
# shader's hue window: no other blue or cyan here (the Tesla glow is violet).
common.COLOURS.update({
	'Tin': (0.52, 0.54, 0.58), 'TinLight': (0.75, 0.76, 0.79), 'TinDark': (0.2, 0.21, 0.24),
	'Enamel': (0.8, 0.72, 0.55), 'Orange': (0.9, 0.24, 0.03), 'Hazard': (0.86, 0.58, 0.02),
	'Black': (0.025, 0.025, 0.03), 'Rubber': (0.03, 0.03, 0.035), 'Lamp': (1.0, 0.52, 0.06),
	'Volt': (0.42, 0.16, 0.95), 'Glass': (0.03, 0.03, 0.04),
})
common.GLOSSY = common.GLOSSY + ('Tin', 'TinLight', 'TinDark', 'Enamel', 'Orange', 'Lamp', 'Volt', 'Hazard')

PZ = 0.26


def _t(x, y, z):
	return Matrix.Translation((x, y, z))


def _rz(d):
	return Matrix.Rotation(math.radians(d), 4, 'Z')


# --- ground ----------------------------------------------------------------

def plate(px, py, cx=0.0, cy=0.0):
	"""A riveted steel plate, edged all round in yellow-and-black hazard
	stripes, rivets at its corners."""
	box((px * 2 + 0.2, py * 2 + 0.2, 0.12), (cx, cy, 0.06), 'TinDark', bevel=0.05)
	for side in ('-y', '+y', '-x', '+x'):
		half = px if side in ('-y', '+y') else py
		f = face(cx + (px + 0.02 if side == '+x' else -px - 0.02 if side == '-x' else 0),
				cy + (py + 0.02 if side == '+y' else -py - 0.02 if side == '-y' else 0), 0, side)
		n = max(2, round(half * 2 / 0.32))
		w = half * 2 / n
		for i in range(n):
			box((w - 0.02, 0.1, 0.1), (-half + w * (i + 0.5), 0.0, 0.17), 'Hazard' if i % 2 else 'Black', bevel=0.02,
					segments=2, matrix=f)
	box((px * 2 - 0.1, py * 2 - 0.1, 0.1), (cx, cy, PZ - 0.05), 'Tin', bevel=0.03)
	for sx in (-1, 1):
		for sy in (-1, 1):
			cylinder(0.07, 0.05, (cx + sx * (px - 0.15), cy + sy * (py - 0.15), PZ + 0.01), 'Gold', verts=8, bevel=0.01)
	return PZ


# --- parts -------------------------------------------------------------------

def rivets(x0, x1, y, z, frame=None, step=0.22):
	n = max(1, round((x1 - x0) / step))
	for i in range(n + 1):
		sphere(0.035, (x0 + (x1 - x0) * i / n, y, z), 'Gold', matrix=frame)


def tin_box(hx, hy, z0, top, cx=0.0, cy=0.0, mat='TinLight', band='TinDark'):
	"""A rounded tin box with a dark band at its foot and its top, rivets
	along each band on every face."""
	box((hx * 2, hy * 2, top - z0), (cx, cy, (top + z0) / 2), mat, bevel=0.1)
	for z in (z0 + 0.08, top - 0.08):
		box((hx * 2 + 0.06, hy * 2 + 0.06, 0.12), (cx, cy, z), band, bevel=0.04)
	for side in ('-y', '+y', '-x', '+x'):
		half = hx if side in ('-y', '+y') else hy
		f = face(cx + (hx + 0.04 if side == '+x' else -hx - 0.04 if side == '-x' else 0),
				cy + (hy + 0.04 if side == '+y' else -hy - 0.04 if side == '-y' else 0), 0, side)
		rivets(-half + 0.15, half - 0.15, 0.0, top - 0.08, frame=f)


def drum(r, z0, top, cx=0.0, cy=0.0, mat='TinLight', band='TinDark', verts=20):
	cylinder(r, top - z0, (cx, cy, (top + z0) / 2), mat, verts=verts, bevel=0.08)
	for z in (z0 + 0.07, top - 0.07):
		cylinder(r + 0.04, 0.1, (cx, cy, z), band, verts=verts, bevel=0.03)
	for k in range(12):
		a = math.radians(k * 30)
		sphere(0.03, (cx + math.cos(a) * (r + 0.04), cy + math.sin(a) * (r + 0.04), top - 0.07), 'Gold')


def dome(r, cx, cy, z, mat='TeamColor', squash=1.0):
	bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=r)
	obj = bpy.context.active_object
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.001], context='VERTS')
	bm.to_mesh(obj.data)
	bm.free()
	_placed(obj, (cx, cy, z), (0, 0, 0), None)
	obj.scale = (1, 1, squash)
	_finish(obj, mat, 0.0, 0)
	cylinder(r + 0.03, 0.08, (cx, cy, z + 0.02), 'Gold', verts=20, bevel=0.02)


def lamp_window(frame, r=0.16):
	"""A round porthole lit amber from inside, in a thick brass ring."""
	torus(r, 0.045, (0, -0.04, 0), 'Gold', rot=(90, 0, 0), matrix=frame)
	cylinder(r, 0.06, (0, 0.0, 0), 'Lamp', verts=14, rot=(90, 0, 0), bevel=0.0, matrix=frame)


def tin_door(frame, w=0.62, h=0.95):
	"""A rounded-top hatch with a wheel lock."""
	box((w + 0.14, 0.08, h + 0.07), (0, 0.0, h / 2), 'TinDark', bevel=0.05, matrix=frame)
	box((w, 0.08, h - 0.05), (0, -0.04, h / 2), 'Enamel', bevel=0.08, matrix=frame)
	torus(0.12, 0.025, (0, -0.1, h * 0.55), 'Gold', rot=(90, 0, 0), matrix=frame)
	for a in (0, 60, 120):
		box((0.22, 0.03, 0.03), (0, -0.1, h * 0.55), 'Gold', rot=(0, a, 0), bevel=0.005, matrix=frame)


def gear(r, frame, teeth=10, mat='Gold', depth=0.08):
	"""A brass cog flat on a wall (frame faces out along -Y)."""
	cylinder(r, depth, (0, -depth / 2, 0), mat, verts=24, rot=(90, 0, 0), bevel=0.02, matrix=frame)
	for k in range(teeth):
		a = 360.0 * k / teeth
		f = frame @ Matrix.Rotation(math.radians(a), 4, 'Y')
		box((r * 0.32, depth, r * 0.32), (0, -depth / 2, r + r * 0.1), mat, bevel=0.02, segments=2, matrix=f)
	cylinder(r * 0.3, depth + 0.04, (0, -depth / 2 - 0.02, 0), 'TinDark', verts=12, rot=(90, 0, 0), bevel=0.01,
			matrix=frame)


def wind_key(x, y, z, size=1.0, rot=0.0):
	"""A giant brass wind-up key standing up out of a roof."""
	s = size
	f = _t(x, y, z) @ _rz(rot)
	cylinder(0.08 * s, 0.5 * s, (0, 0, 0.25 * s), 'Gold', verts=10, bevel=0.01, matrix=f)
	cylinder(0.16 * s, 0.08 * s, (0, 0, 0.06 * s), 'Gold', verts=12, bevel=0.02, matrix=f)
	for side in (-1, 1):
		torus(0.24 * s, 0.09 * s, (side * 0.26 * s, 0, 0.62 * s), 'Gold', rot=(90, 0, 0), matrix=f)
		cylinder(0.2 * s, 0.1 * s, (side * 0.26 * s, 0, 0.62 * s), 'Gold', verts=14, rot=(90, 0, 0), bevel=0.02,
				matrix=f)


def stack(x, y, z0, top, r=0.18):
	"""A chimney stack banded in brass with a flared black top."""
	cylinder(r, top - z0, (x, y, (top + z0) / 2), 'TinDark', verts=12, bevel=0.03)
	for z in (z0 + (top - z0) * 0.35, z0 + (top - z0) * 0.7):
		cylinder(r + 0.03, 0.07, (x, y, z), 'Gold', verts=12, bevel=0.01)
	cylinder(r + 0.08, 0.14, (x, y, top + 0.05), 'Black', verts=12, radius2=r + 0.02, bevel=0.02)


def antenna(x, y, z, h=0.9, ball='TeamColor'):
	cylinder(0.035, h, (x, y, z + h / 2), 'TinLight', verts=8, bevel=0.0)
	for k in range(3):
		torus(0.08 - k * 0.015, 0.02, (x, y, z + h * (0.3 + k * 0.2)), 'Gold')
	sphere(0.12, (x, y, z + h + 0.08), ball)


def pipe(points, r=0.07, mat='TinDark'):
	for a, b in zip(points, points[1:]):
		a, b = Vector(a), Vector(b)
		d = b - a
		mid = (a + b) / 2
		obj_len = d.length
		rot = d.to_track_quat('Z', 'Y').to_euler()
		cylinder(r, obj_len, mid, mat, verts=10, bevel=0.0, rot=tuple(math.degrees(v) for v in rot))
	for p in points[1:-1]:
		sphere(r * 1.25, p, 'Gold')


def coil(x, y, z0, h, r=0.28):
	"""A tesla coil: brass rings tapering up a cream post to a violet ball."""
	cylinder(r * 0.6, 0.3, (x, y, z0 + 0.15), 'TinDark', verts=12, bevel=0.03)
	cylinder(0.08, h, (x, y, z0 + h / 2), 'Enamel', verts=10, bevel=0.01)
	n = 5
	for k in range(n):
		t = k / (n - 1)
		torus(r * (1.0 - 0.45 * t), 0.045, (x, y, z0 + 0.4 + (h - 0.6) * t), 'Gold')
	sphere(r * 0.75, (x, y, z0 + h + r * 0.4), 'Volt')
	for k in range(4):
		a = math.radians(k * 90 + 20)
		cx, cy, cz = x + math.cos(a) * r, y + math.sin(a) * r, z0 + h + r * 0.4
		box((0.05, 0.05, 0.35), (cx, cy, cz + 0.12), 'Volt', rot=(25, 0, k * 90 + 20), bevel=0.01)


def dial(frame, r=0.2):
	cylinder(r, 0.06, (0, -0.03, 0), 'Enamel', verts=18, rot=(90, 0, 0), bevel=0.01, matrix=frame)
	torus(r, 0.03, (0, -0.06, 0), 'Gold', rot=(90, 0, 0), matrix=frame)
	box((0.025, 0.03, r * 0.8), (r * 0.2, -0.08, r * 0.3), 'Black', rot=(0, 30, 0), bevel=0.005, matrix=frame)


def oil_can(x, y, z, s=1.0):
	cylinder(0.14 * s, 0.32 * s, (x, y, z + 0.16 * s), 'Orange', verts=12, bevel=0.03)
	cylinder(0.15 * s, 0.04 * s, (x, y, z + 0.3 * s), 'TinDark', verts=12, bevel=0.01)
	cylinder(0.03 * s, 0.3 * s, (x + 0.12 * s, y, z + 0.38 * s), 'TinLight', verts=6, rot=(0, 45, 0), bevel=0.0)


def bolt_crate(x, y, z, s=0.36, rot=0.0):
	box((s, s, s), (x, y, z + s / 2), 'Tin', rot=(0, 0, rot), bevel=0.04)
	box((s + 0.02, s + 0.02, 0.05), (x, y, z + s / 2), 'Orange', rot=(0, 0, rot), bevel=0.015)


def hazard_sign(frame, w=0.5):
	box((w, 0.05, w * 0.5), (0, 0, 0), 'Hazard', bevel=0.02, matrix=frame)
	for i in range(3):
		box((w * 0.12, 0.06, w * 0.6), (-w * 0.3 + i * w * 0.3, -0.01, 0), 'Black', rot=(0, 35, 0), bevel=0.005,
				matrix=frame)


# --- buildings ---------------------------------------------------------------

def town_centre():
	new_scene(51)
	plate(2.3, 2.1)
	# The Central Core: a great tin drum with a team dome and a giant key.
	drum(1.45, PZ, 2.5)
	dome(1.5, 0, 0, 2.5, squash=0.6)
	wind_key(0, 0, 3.3, size=1.0)
	for a in (-50, 50, 180):
		f = _rz(a) @ _t(0, -1.48, 1.45) @ _rz(0)
		lamp_window(f, r=0.2)
	tin_door(face(0, -1.47, PZ, '-y'), w=0.8, h=1.1)
	hazard_sign(face(0, -1.5, 1.55, '-y'), w=0.6)
	# Two side towers with gears turning on their faces.
	for side in (-1, 1):
		tin_box(0.55, 0.55, PZ, 2.0, cx=side * 1.55, cy=0.6, mat='Enamel')
		box((1.2, 1.2, 0.18), (side * 1.55, 0.6, 2.05), 'TeamColor', bevel=0.06)
		gear(0.38, face(side * 1.55, 0.04, 1.2, '-y'), teeth=9)
		antenna(side * 1.55, 0.6, 2.14, h=0.8 if side < 0 else 1.1, ball='Lamp' if side < 0 else 'TeamColor')
	stack(1.2, 1.3, 1.0, 3.4)
	pipe([(1.2, 1.3, 1.6), (0.8, 1.1, 1.6), (0.8, 0.9, 2.0)])
	for x in (-1.7, 1.7):
		bolt_crate(x, -1.55, PZ, 0.36, 15)
	oil_can(-1.2, -1.75, PZ)
	export('TownCentre')


def house():
	new_scene(52)
	plate(1.2, 0.95)
	# A charging pod: a squat capsule with a battery on its back.
	drum(0.72, PZ, 1.45, mat='Enamel')
	dome(0.75, 0, 0, 1.45, squash=0.7)
	lamp_window(face(0, -0.73, 1.0, '-y'), r=0.16)
	tin_door(face(0.0, -0.74, PZ, '-y'), w=0.45, h=0.6)
	cylinder(0.24, 0.8, (0.72, 0.35, PZ + 0.4), 'Orange', verts=12, bevel=0.04)
	cylinder(0.12, 0.12, (0.72, 0.35, PZ + 0.86), 'TinLight', verts=10, bevel=0.02)
	cylinder(0.25, 0.1, (0.72, 0.35, PZ + 0.5), 'Black', verts=12, bevel=0.02)
	antenna(-0.3, 0.2, 1.85, h=0.7, ball='Lamp')
	bolt_crate(-0.85, -0.65, PZ, 0.3, 20)
	export('House')


def barracks():
	new_scene(53)
	CY = 0.15
	plate(1.85, 1.15, cy=CY)
	# The Assembly Line: a long tin factory with a sawtooth team roof and a
	# conveyor carrying robot heads out of its front.
	tin_box(1.45, 0.8, PZ, 1.8, cy=CY + 0.05)
	for i in range(3):
		x = -0.97 + i * 0.97
		mesh_f = _t(x, CY + 0.05, 1.86)
		box((0.92, 1.66, 0.12), (0, 0, 0.32), 'TeamColor', rot=(0, 34, 0), bevel=0.04, matrix=mesh_f)
		box((0.08, 1.66, 0.62), (0.4, 0, 0.3), 'Lamp', bevel=0.02, matrix=mesh_f)
	stack(-1.1, CY + 0.45, 1.8, 3.6, r=0.16)
	stack(-0.6, CY + 0.45, 1.8, 3.2, r=0.13)
	tin_door(face(0.55, CY - 0.79, PZ, '-y'), w=0.8, h=0.95)
	gear(0.32, face(-0.6, CY - 0.79, 1.15, '-y'), teeth=9)
	# The conveyor out the front, heads riding it.
	box((1.1, 0.42, 0.12), (-0.55, CY - 1.12, PZ + 0.32), 'Rubber', bevel=0.04)
	for x in (-0.95, -0.15):
		box((0.08, 0.4, 0.32), (x, CY - 1.12, PZ + 0.16), 'TinDark')
	for i, x in enumerate((-0.85, -0.5, -0.15)):
		box((0.24, 0.22, 0.2), (x, CY - 1.12, PZ + 0.5), 'TinLight', bevel=0.06)
		for side in (-1, 1):
			sphere(0.035, (x + side * 0.05, CY - 1.24, PZ + 0.52), 'Black')
	for x in (1.2, 1.55):
		bolt_crate(x, CY - 1.0, PZ, 0.3, x * 40)
	hazard_sign(face(1.45 + 0.05, CY, 1.3, '+x'))
	export('Barracks')


def archery_range():
	new_scene(54)
	plate(2.0, 1.6, cy=-0.15)
	# The Ray Works: a low tin block under a huge ray dish, a target range.
	tin_box(0.9, 0.7, PZ, 1.35, cx=-0.8, cy=0.3, mat='Enamel')
	tin_door(face(-0.8, -0.41, PZ, '-y'), w=0.55, h=0.8)
	cylinder(0.12, 0.6, (-0.8, 0.3, 1.65), 'TinDark', verts=10, bevel=0.02)
	f = _t(-0.8, 0.3, 1.95) @ Matrix.Rotation(math.radians(-40), 4, 'X')
	bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=0.85)
	obj = bpy.context.active_object
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > -0.45], context='VERTS')
	bm.to_mesh(obj.data)
	bm.free()
	obj.matrix_world = f @ _t(0, 0, 0.85)
	_finish(obj, 'TinLight', 0.0, 0)
	cylinder(0.05, 0.75, (0, 0, 0.42), 'Gold', verts=8, bevel=0.0, matrix=f)
	sphere(0.14, (0, 0, 0.82), 'Lamp', matrix=f)
	torus(0.6, 0.05, (0, 0, 0.42), 'TeamColor', matrix=f)
	# The target range: three tin targets on posts with team rings.
	for i, x in enumerate((0.6, 1.2, 1.8)):
		fr = face(x, -1.0 + i * 0.6, PZ + 0.7, '-y')
		box((0.06, 0.06, 0.7), (0, 0.04, -0.35), 'TinDark', matrix=fr)
		for k, (r, m) in enumerate(((0.3, 'TinLight'), (0.22, 'TeamColor'), (0.12, 'Orange'))):
			cylinder(r, 0.05 + k * 0.02, (0, -k * 0.012, 0), m, verts=18, rot=(90, 0, 0), bevel=0.0, matrix=fr)
	for x in (-1.7, -1.4):
		oil_can(x, -1.4, PZ)
	export('ArcheryRange')


def stables():
	new_scene(55)
	plate(2.15, 1.3, cy=0.1)
	# The Garage: a tin shed with a ribbed roll door, a spanner over it.
	tin_box(1.5, 0.85, PZ, 1.9, cx=-0.5, cy=0.25)
	box((3.1, 1.8, 0.16), (-0.5, 0.25, 1.95), 'TeamColor', bevel=0.06)
	for i in range(6):
		box((1.3, 0.08, 0.16), (-0.5, -0.62, PZ + 0.12 + i * 0.2), 'TinDark' if i % 2 else 'Tin', bevel=0.03)
	f = face(-0.5, -0.64, 1.75, '-y')
	box((0.9, 0.06, 0.14), (0, -0.05, 0), 'Gold', bevel=0.03, matrix=f)
	for side in (-1, 1):
		torus(0.14, 0.05, (side * 0.48, -0.05, 0), 'Gold', rot=(90, 0, 0), matrix=f)
	# A kennel for the hounds, with a bone-shaped sign.
	tin_box(0.5, 0.45, PZ, 1.0, cx=1.55, cy=0.4, mat='Enamel')
	box((1.1, 1.0, 0.1), (1.55, 0.4, 1.05), 'TeamColor', bevel=0.04)
	box((0.36, 0.1, 0.45), (1.55, -0.07, PZ + 0.25), 'Black', bevel=0.1)
	for x in (1.2, 1.9):
		oil_can(x, -0.95, PZ, 0.9)
	wind_key(-1.4, 0.25, 2.03, size=0.7)
	export('Stables')


def arcane_sanctum():
	new_scene(56)
	plate(1.8, 1.5, cx=0.25, cy=-0.15)
	# The Tesla Lab: a tall riveted tower, a dome, two crackling coils.
	drum(0.85, PZ, 2.8, mat='TinLight')
	dome(0.88, 0, 0, 2.8, squash=0.75)
	coil(0, 0, 3.4, 1.5, r=0.32)
	for side in (-1, 1):
		coil(side * 1.3 + 0.25, -0.9, PZ, 1.6, r=0.24)
	tin_door(face(0, -0.86, PZ, '-y'), w=0.55, h=0.9)
	for z in (1.6, 2.3):
		lamp_window(face(0, -0.86, z, '-y'), r=0.14)
	pipe([(0.6, 0.6, 1.0), (1.3, 0.8, 1.0), (1.3, 0.8, PZ + 0.1)], r=0.06)
	hazard_sign(face(0.86, 0, 1.4, '+x'), w=0.5)
	export('ArcaneSanctum')


def siege_workshop():
	new_scene(57)
	plate(2.15, 1.7, cy=0.08)
	# The Foundry: a smelter with two great stacks, a glowing crucible, a
	# crane over a rocket on its rack.
	tin_box(1.0, 0.8, PZ, 1.7, cx=-1.0, cy=0.7, mat='TinLight')
	box((2.2, 1.8, 0.14), (-1.0, 0.7, 1.75), 'TeamColor', bevel=0.05)
	stack(-1.5, 1.0, 1.7, 3.0, r=0.2)
	stack(-0.6, 1.0, 1.7, 2.6, r=0.16)
	tin_door(face(-1.0, -0.11, PZ, '-y'), w=0.7, h=0.95)
	cylinder(0.38, 0.5, (0.4, -0.9, PZ + 0.25), 'TinDark', verts=16, bevel=0.04)
	cylinder(0.32, 0.06, (0.4, -0.9, PZ + 0.5), 'Lamp', verts=16, bevel=0.0)
	for x in (0.9, 1.9):
		cylinder(0.08, 2.4, (x, 0.7, PZ + 1.2), 'TinDark', verts=8, bevel=0.0)
	cylinder(0.07, 1.3, (1.4, 0.7, PZ + 2.4), 'Hazard', verts=8, rot=(0, 90, 0), bevel=0.0)
	cylinder(0.015, 0.8, (1.4, 0.7, PZ + 1.95), 'Black', verts=4, bevel=0.0)
	f = _t(1.4, 0.4, PZ + 0.6) @ Matrix.Rotation(math.radians(-20), 4, 'X')
	cylinder(0.16, 1.1, (0, 0, 0), 'Enamel', verts=12, rot=(90, 0, 0), bevel=0.03, matrix=f)
	bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.16, radius2=0.0, depth=0.35)
	o = bpy.context.active_object
	o.matrix_world = f @ Matrix.Rotation(math.radians(90), 4, 'X') @ _t(0, 0, 0.72)
	_finish(o, 'Orange', 0.02, 2, angle=50)
	cylinder(0.17, 0.12, (0, 0.1, 0), 'TeamColor', verts=12, rot=(90, 0, 0), bevel=0.02, matrix=f)
	for side in (-1, 1):
		box((0.05, 0.4, 0.4), (side * 0.18, 0.45, 0), 'Orange', bevel=0.01, matrix=f)
	for x in (1.6, 1.9):
		bolt_crate(x, -1.3, PZ, 0.3, x * 30)
	export('SiegeWorkshop')


def blacksmith():
	new_scene(58)
	plate(1.65, 1.15, cx=0.4)
	# The Machine Shop: a tin workshop with a big gear on its face and a
	# steam hammer out the side.
	tin_box(1.0, 0.8, PZ, 1.75, mat='Enamel')
	box((2.2, 1.8, 0.16), (0, 0, 1.8), 'TeamColor', bevel=0.06)
	gear(0.45, face(0.35, -0.82, 1.15, '-y'), teeth=10)
	gear(0.25, face(-0.25, -0.82, 1.4, '-y'), teeth=8, mat='TinLight')
	tin_door(face(-0.45, -0.82, PZ, '-y'), w=0.55, h=0.85)
	stack(0.6, 0.45, 1.8, 3.0, r=0.15)
	# The steam hammer: a frame, a piston and an anvil block.
	for y in (-0.45, 0.45):
		box((0.12, 0.12, 1.5), (1.55, y, PZ + 0.75), 'TinDark', bevel=0.02)
	box((0.3, 1.05, 0.2), (1.55, 0, PZ + 1.5), 'Hazard', bevel=0.04)
	cylinder(0.12, 0.6, (1.55, 0, PZ + 1.05), 'TinLight', verts=10, bevel=0.02)
	box((0.36, 0.36, 0.2), (1.55, 0, PZ + 0.72), 'TinDark', bevel=0.04)
	box((0.5, 0.42, 0.3), (1.55, 0, PZ + 0.15), 'TinDark', bevel=0.04)
	box((0.36, 0.3, 0.06), (1.55, 0, PZ + 0.33), 'Lamp', bevel=0.02)
	oil_can(2.05, 0.75, PZ)
	export('Blacksmith')


def library():
	new_scene(59)
	plate(1.9, 1.35)
	# The Data Bank: a tall cabinet of tape reels and blinking lamps, a
	# radar dish on top.
	tin_box(1.3, 0.85, PZ, 2.6, mat='Enamel')
	box((2.8, 1.9, 0.16), (0, 0, 2.65), 'TeamColor', bevel=0.06)
	for x in (-0.8, 0.8):
		for k, r in enumerate((0.32, 0.22)):
			cylinder(r, 0.06 + k * 0.03, (x, -0.88 - k * 0.02, 1.75), 'TinDark' if k == 0 else 'TinLight', verts=18,
					rot=(90, 0, 0), bevel=0.01)
		sphere(0.06, (x, -0.95, 1.75), 'Gold')
	for i in range(4):
		for j in range(3):
			box((0.12, 0.05, 0.12), (-0.3 + i * 0.2, -0.88, 1.0 + j * 0.2), ('Lamp', 'Orange', 'TeamColor', 'TinLight')[(i + j) % 4],
					bevel=0.02)
	tin_door(face(0, -0.86, PZ, '-y'), w=0.5, h=0.7)
	cylinder(0.08, 0.5, (0.5, 0, 2.95), 'TinDark', verts=8, bevel=0.0)
	f = _t(0.5, 0, 3.25) @ Matrix.Rotation(math.radians(-35), 4, 'X')
	bpy.ops.mesh.primitive_uv_sphere_add(segments=18, ring_count=9, radius=0.6)
	obj = bpy.context.active_object
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > -0.3], context='VERTS')
	bm.to_mesh(obj.data)
	bm.free()
	obj.matrix_world = f @ _t(0, 0, 0.6)
	_finish(obj, 'TinLight', 0.0, 0)
	sphere(0.1, (0, 0, 0.5), 'Lamp', matrix=f)
	antenna(-0.8, 0.3, 2.73, h=1.0)
	export('Library')


def mill():
	new_scene(60)
	plate(1.5, 1.15)
	# The Fuel Depot: two tall tanks, a pump and pipes.
	drum(0.6, PZ, 3.2, cx=-0.6, cy=0.25, mat='TinLight')
	dome(0.62, -0.6, 0.25, 3.2, squash=0.6)
	drum(0.5, PZ, 2.2, cx=0.75, cy=0.35, mat='Enamel')
	dome(0.52, 0.75, 0.35, 2.2, squash=0.6)
	for k in range(9):
		box((0.3, 0.05, 0.04), (-0.6, -0.42, PZ + 0.3 + k * 0.3), 'TinDark', bevel=0.01)
	for x in (-0.75, -0.45):
		box((0.04, 0.05, 2.8), (x, -0.42, PZ + 1.4), 'TinDark')
	cylinder(0.64, 0.25, (-0.6, 0.25, 2.0), 'TeamColor', verts=20, bevel=0.04)
	cylinder(0.54, 0.22, (0.75, 0.35, 1.4), 'TeamColor', verts=20, bevel=0.04)
	pipe([(-0.0, 0.25, 0.8), (0.3, 0.25, 0.8), (0.3, -0.6, 0.8), (0.3, -0.6, PZ + 0.1)], r=0.07)
	box((0.4, 0.4, 0.5), (0.3, -0.75, PZ + 0.25), 'Orange', bevel=0.06)
	dial(face(0.3, -0.96, PZ + 0.32, '-y'), r=0.13)
	oil_can(-1.2, -0.8, PZ)
	export('Mill')


def mine():
	new_scene(61)
	# In front of the gold deposit (at the origin): a drill rig, its derrick
	# over a bore hole, an ore cart on rails.
	box((2.5, 2.3, 0.12), (0.1, -1.5, 0.06), 'TinDark', bevel=0.05)
	for x in (-0.65, 0.45):
		for y in (-1.9, -0.9):
			cylinder(0.05, 1.5, (x, y, 0.85), 'Hazard', verts=6, bevel=0.0, rot=(0, (1 if x < 0 else -1) * 10, 0))
	box((0.85, 0.85, 0.1), (-0.1, -1.4, 1.55), 'TinDark', bevel=0.03)
	cylinder(0.08, 1.4, (-0.1, -1.4, 0.75), 'TinLight', verts=10, bevel=0.02)
	bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.12, radius2=0.0, depth=0.3)
	_placed(bpy.context.active_object, (-0.1, -1.4, 0.18), (180, 0, 0), None)
	_finish(bpy.context.active_object, 'TinLight', 0.02, 2, angle=50)
	box((0.4, 0.4, 0.3), (-0.1, -1.4, 1.35), 'Orange', bevel=0.06)
	antenna(-0.1, -1.4, 1.6, h=0.5, ball='Lamp')
	for x in (-0.9, 0.9):
		box((0.06, 2.2, 0.05), (0.85 + x * 0.12, -1.5, 0.15), 'TinLight', bevel=0.01)
	box((0.5, 0.6, 0.35), (0.85, -0.9, 0.42), 'Tin', bevel=0.05)
	for k in range(4):
		sphere(0.1, (0.75 + (k % 2) * 0.2, -0.95 + (k // 2) * 0.15, 0.62), 'Gold')
	for y in (-1.1, -0.7):
		for x in (0.6, 1.1):
			cylinder(0.08, 0.06, (x, y, 0.22), 'Rubber', verts=10, rot=(0, 90, 0), bevel=0.0)
	export('Mine')


def storehouse():
	new_scene(62)
	plate(1.7, 1.2, cx=0.1, cy=0.15)
	# The Depot: a tin warehouse, a crane arm over stacked crates.
	tin_box(1.05, 0.8, PZ, 1.6, cx=0.1, cy=0.3)
	box((2.3, 1.8, 0.16), (0.1, 0.3, 1.65), 'TeamColor', bevel=0.06)
	for i in range(5):
		box((1.0, 0.08, 0.15), (0.1, -0.52, PZ + 0.12 + i * 0.2), 'TinDark' if i % 2 else 'Tin', bevel=0.03)
	bolt_crate(-1.15, -0.7, PZ, 0.38, 10)
	bolt_crate(-1.1, -0.65, PZ + 0.38, 0.3, -15)
	bolt_crate(-0.6, -0.85, PZ, 0.3, 30)
	cylinder(0.07, 1.6, (1.45, -0.6, PZ + 0.8), 'Hazard', verts=8, bevel=0.0)
	cylinder(0.05, 1.0, (1.1, -0.6, PZ + 1.55), 'Hazard', verts=8, rot=(0, 75, 0), bevel=0.0)
	cylinder(0.012, 0.5, (0.65, -0.6, PZ + 1.35), 'Black', verts=4, bevel=0.0)
	bolt_crate(0.65, -0.6, PZ + 0.6, 0.28, 0)
	oil_can(1.6, 0.8, PZ)
	export('Storehouse')


def watchtower():
	new_scene(63)
	plate(0.9, 0.9)
	# The Zap Tower: a lattice mast to a tin lookout with a tesla ball.
	for sx in (-1, 1):
		for sy in (-1, 1):
			x, y = sx * 0.5, sy * 0.5
			cylinder(0.06, 4.0, (x * 0.8, y * 0.8, PZ + 2.0), 'TinDark', verts=6, bevel=0.0,
					rot=(sy * -4, sx * 4, 0))
	for k in range(5):
		z = PZ + 0.5 + k * 0.75
		r = 0.42 - k * 0.03
		for a in (0, 90):
			box((r * 2, 0.05, 0.05), (0, 0, z), 'Hazard', rot=(0, 0, a + 45 * (k % 2)), bevel=0.01)
	drum(0.6, 4.1, 4.75, mat='TinLight')
	box((1.5, 1.5, 0.1), (0, 0, 4.82), 'TeamColor', bevel=0.04)
	for a in (0, 90, 180, 270):
		lamp_window(_rz(a) @ _t(0, -0.62, 4.45), r=0.12)
	coil(0, 0, 4.85, 0.6, r=0.2)
	export('Watchtower')


def wall_segment():
	new_scene(64)
	# A tin fence panel: a riveted plate between posts, a hazard stripe.
	box((1.9, 0.18, 1.3), (0, 0, 0.75), 'Tin', bevel=0.05)
	for x in (-0.95, 0.95):
		box((0.18, 0.26, 1.6), (x, 0, 0.8), 'TinDark', bevel=0.04)
	for i in range(6):
		box((0.3, 0.2, 0.14), (-0.75 + i * 0.3, 0, 1.35), 'Hazard' if i % 2 else 'Black', bevel=0.02)
	for z in (0.3, 0.75):
		rivets(-0.75, 0.75, -0.1, z, step=0.25)
	box((2.0, 0.24, 0.1), (0, 0, 0.08), 'TinDark', bevel=0.03)
	export('WallSegment')


def wall_corner():
	new_scene(65)
	cylinder(0.4, 2.3, (0, 0, 1.15), 'TinDark', verts=12, bevel=0.04)
	for z in (0.6, 1.5):
		cylinder(0.44, 0.1, (0, 0, z), 'Hazard', verts=12, bevel=0.02)
	cylinder(0.3, 0.3, (0, 0, 2.45), 'Lamp', verts=12, bevel=0.04)
	dome(0.34, 0, 0, 2.6, mat='TeamColor', squash=0.8)
	export('WallCorner')


def wall_gate():
	new_scene(66)
	for side in (-1, 1):
		box((0.38, 0.5, 2.3), (side * 0.92, 0, 1.15), 'TinDark', bevel=0.05)
		for z in (0.6, 1.4):
			box((0.42, 0.54, 0.1), (side * 0.92, 0, z), 'Hazard', bevel=0.02)
		sphere(0.14, (side * 0.92, 0, 2.42), 'Lamp')
	box((2.3, 0.4, 0.3), (0, 0, 2.1), 'Tin', bevel=0.05)
	gear(0.32, face(0, -0.2, 2.1, '-y'), teeth=9)
	export('WallGate')


def charge_pad():
	"""The Robots' field: a tin pad of battery cells charging in rows. The game
	squashes it flat and tints it while the cells are drained (FarmField), so it
	grows like a crop: grey stubs, amber, then full cells standing tall."""
	new_scene(67)
	box((3.0, 3.0, 0.1), (0, 0, 0.05), 'TinDark', bevel=0.04)
	for side in ('-y', '+y', '-x', '+x'):
		f = face(1.5 if side == '+x' else -1.5 if side == '-x' else 0, 1.5 if side == '+y' else -1.5 if side == '-y' else 0,
				0, side)
		for i in range(8):
			box((0.34, 0.08, 0.08), (-1.31 + i * 0.375, 0.0, 0.12), 'Hazard' if i % 2 else 'Black', bevel=0.02, matrix=f)
	for i in range(4):
		for j in range(4):
			x, y = -1.05 + i * 0.7, -1.05 + j * 0.7
			cylinder(0.2, 0.75, (x, y, 0.47), 'Enamel', verts=12, bevel=0.05)
			cylinder(0.21, 0.16, (x, y, 0.52), 'Orange', verts=12, bevel=0.02)
			cylinder(0.08, 0.1, (x, y, 0.88), 'Gold', verts=10, bevel=0.02)
			cylinder(0.22, 0.06, (x, y, 0.13), 'TinDark', verts=12, bevel=0.01)
	for j in range(4):
		box((2.4, 0.05, 0.05), (0, -1.05 + j * 0.7, 0.17), 'Black', bevel=0.01)
	export('ChargePad')


BUILDINGS = {
	'TownCentre': town_centre, 'House': house, 'Barracks': barracks, 'ArcheryRange': archery_range,
	'Stables': stables, 'ArcaneSanctum': arcane_sanctum, 'SiegeWorkshop': siege_workshop,
	'Blacksmith': blacksmith, 'Library': library, 'Mill': mill, 'Mine': mine, 'Storehouse': storehouse,
	'Watchtower': watchtower, 'WallSegment': wall_segment, 'WallCorner': wall_corner, 'WallGate': wall_gate,
	'ChargePad': charge_pad,
}

if __name__ == '__main__':
	names = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
	for name in names or list(BUILDINGS):
		BUILDINGS[name]()
