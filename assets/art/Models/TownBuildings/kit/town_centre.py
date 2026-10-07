# Builds TownCentre.glb: a chunky toy keep in the diorama style (stone plinth,
# timber-framed hall under a big tiled team-blue roof, four corner towers, an
# arched gate with the team shield). See common.py for the kit.
#
#   "C:\Program Files\Blender Foundation\Blender 5.2lender.exe" --background
#       --factory-startup --python town_centre.py [-- <out.glb>]
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
from common import _finish

new_scene(7)

# --- plinth: a base slab ringed with uneven chunky stones -------------------
PX, PY = 2.3, 1.95
box((PX * 2 - 0.1, PY * 2 - 0.1, PZ), (0, 0, PZ / 2), 'StoneDark', bevel=0.06)
box((PX * 2 - 0.3, PY * 2 - 0.3, 0.06), (0, 0, PZ + 0.02), 'Stone', bevel=0.02)
def stone_run(start, end, fixed_axis, fixed, outward):
	length = end - start
	n = max(2, round(length / 0.55))
	step = length / n
	for i in range(n):
		c = start + step * (i + 0.5) + random.uniform(-0.03, 0.03)
		w = step - 0.04
		h = PZ + random.uniform(-0.04, 0.06)
		d = 0.3 + random.uniform(-0.03, 0.03)
		mat = 'Stone' if random.random() < 0.65 else 'StoneDark'
		if fixed_axis == 'y':
			box((w, d, h), (c, fixed + outward * d * 0.3, h / 2), mat)
		else:
			box((d, w, h), (fixed + outward * d * 0.3, c, h / 2), mat)
stone_run(-PX, PX, 'y', -PY, -1)
stone_run(-PX, PX, 'y', PY, 1)
stone_run(-PY + 0.3, PY - 0.3, 'x', -PX, -1)
stone_run(-PY + 0.3, PY - 0.3, 'x', PX, 1)

# --- hall: plaster walls in a timber frame ---------------------------------
HX, HY = 1.5, 1.0
WALL_TOP = 2.1
box((HX * 2, HY * 2, WALL_TOP - PZ), (0, 0, (WALL_TOP + PZ) / 2), 'Plaster', bevel=0.04)
# Stone footing course under the plaster.
box((HX * 2 + 0.08, HY * 2 + 0.08, 0.32), (0, 0, PZ + 0.16), 'Stone', bevel=0.05)
for y in (-HY, HY):
	s = -1 if y < 0 else 1
	box((HX * 2 + 0.1, 0.16, 0.16), (0, y + s * 0.04, 1.3), 'Wood')
	box((HX * 2 + 0.1, 0.18, 0.18), (0, y + s * 0.05, WALL_TOP - 0.06), 'Wood')
	for x in (-1.05, -0.62, 0.62, 1.05):
		box((0.15, 0.14, WALL_TOP - PZ - 0.32), (x, y + s * 0.04, (WALL_TOP + PZ + 0.32) / 2), 'Wood')
	# Diagonal braces in the outer bays, below the window beam.
	for x0, a in ((-0.835, 38), (0.835, -38)):
		box((0.11, 0.12, 0.8), (x0, y + s * 0.035, 0.98), 'WoodDark', rot=(0, a, 0))
	# Upper windows, shuttered in team colour.
	for x in (-0.84, 0.84):
		box((0.34, 0.06, 0.4), (x, y + s * 0.02, 1.68), 'Window', bevel=0.02)
		box((0.46, 0.1, 0.07), (x, y + s * 0.05, 1.92), 'Wood')
		box((0.46, 0.12, 0.08), (x, y + s * 0.06, 1.45), 'Wood')
		for side in (-1, 1):
			box((0.13, 0.07, 0.42), (x + side * 0.27, y + s * 0.05, 1.68), 'TeamColorDark', bevel=0.02)

for x in (-HX, HX):
	s = -1 if x < 0 else 1
	box((0.16, HY * 2 + 0.1, 0.16), (x + s * 0.04, 0, 1.3), 'Wood')
	for y in (-0.42, 0.42):
		box((0.14, 0.15, WALL_TOP - PZ - 0.32), (x + s * 0.04, y, (WALL_TOP + PZ + 0.32) / 2), 'Wood')
	box((0.06, 0.36, 0.42), (x + s * 0.02, 0, 1.7), 'Window', bevel=0.02)
	box((0.12, 0.5, 0.08), (x + s * 0.06, 0, 1.47), 'Wood')
	for side in (-1, 1):
		box((0.07, 0.13, 0.44), (x + s * 0.05, side * 0.27, 1.7), 'TeamColorDark', bevel=0.02)

# --- roof: thick blue slabs carrying rows of chunky tiles -------------------
PITCH = 42.0
OVER_Y = 0.32
half_span = HY + OVER_Y
rise = half_span * math.tan(math.radians(PITCH))
# Lowered so the slab meets the wall tops (see common.roof_drop).
BASE = WALL_TOP - roof_drop(OVER_Y, PITCH)
RIDGE = BASE + rise
slope_len = half_span / math.cos(math.radians(PITCH))
ROOF_X = 3.05
for s in (-1, 1):
	frame = Matrix.Translation((0, s * half_span / 2, BASE + rise / 2 + 0.08)) \
		@ Matrix.Rotation(math.radians(PITCH * -s), 4, 'X')
	box((ROOF_X, slope_len + 0.06, 0.14), (0, 0, 0), 'TeamColorDark', bevel=0.05, matrix=frame)
	rows = 5
	for r in range(rows):
		# Along the slab from the eave (row 0) up to the ridge.
		v = s * (slope_len / 2 - (r + 0.5) * slope_len / rows)
		count = 7
		tw = ROOF_X / count
		offset = (tw / 2) if r % 2 else 0.0
		for i in range(count + (1 if r % 2 else 0)):
			x = -ROOF_X / 2 + tw * (i + 0.5) - offset
			lo, hi = max(x - tw / 2, -ROOF_X / 2), min(x + tw / 2, ROOF_X / 2)
			if hi - lo < 0.12:
				continue
			mat = 'TeamColor' if random.random() < 0.8 else 'TeamColorDark'
			# Each row overlaps the one below and tips out a little at its foot.
			box((hi - lo - 0.035, slope_len / rows + 0.05, 0.09),
					((lo + hi) / 2, v, 0.1 + random.uniform(0.0, 0.015)), mat,
					rot=(s * 4.0, 0, 0), bevel=0.03, segments=2, matrix=frame)
# Ridge beam and gable trim.
box((ROOF_X + 0.2, 0.22, 0.22), (0, 0, RIDGE + 0.14), 'Wood', bevel=0.05)
for x in (-ROOF_X / 2 - 0.02, ROOF_X / 2 + 0.02):
	# Plaster gable.
	mesh = bpy.data.meshes.new('gable')
	bm = bmesh.new()
	pts = [(-HY, WALL_TOP), (HY, WALL_TOP), (0, WALL_TOP + HY * math.tan(math.radians(PITCH)))]
	sign = 1 if x > 0 else -1
	vs = [bm.verts.new((sign * (HX - 0.02), py, pz)) for py, pz in pts]
	bm.faces.new(vs)
	bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
	bm.verts.ensure_lookup_table()
	for v in bm.verts[3:]:
		v.co.x += sign * 0.08
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	bm.to_mesh(mesh)
	bm.free()
	g = bpy.data.objects.new('gable', mesh)
	bpy.context.scene.collection.objects.link(g)
	_finish(g, 'Plaster', 0.02, 2)
	for s in (-1, 1):
		box((0.14, slope_len + 0.1, 0.16), (x, s * half_span / 2, BASE + rise / 2 + 0.02), 'Wood',
				rot=(PITCH * -s, 0, 0))
	box((0.1, 0.12, 0.7), (x + (0.03 if x > 0 else -0.03), 0, WALL_TOP + 0.45), 'Wood')
	box((0.1, 0.3, 0.3), (x + (0.03 if x > 0 else -0.03), 0, WALL_TOP + 0.55), 'Window', bevel=0.02)
flag(0, 0, RIDGE + 0.2, 1.2)

# --- corner towers ----------------------------------------------------------
TW = 1.0
TOWER_TOP = 2.5
for tx in (-1.85, 1.85):
	for ty in (-1.42, 1.42):
		front = ty < 0
		box((TW, TW, TOWER_TOP - PZ), (tx, ty, (TOWER_TOP + PZ) / 2), 'Stone', bevel=0.05)
		# Quoins: alternating chunky blocks up each corner.
		for k in range(6):
			z = PZ + 0.2 + k * 0.36
			long_x = k % 2 == 0
			for cx in (-1, 1):
				for cy in (-1, 1):
					sx = 0.38 if long_x else 0.24
					sy = 0.24 if long_x else 0.38
					mat = 'StoneDark' if (k + cx + cy) % 3 == 0 else 'Stone'
					box((sx, sy, 0.3), (tx + cx * (TW / 2 - sx / 2 + 0.05), ty + cy * (TW / 2 - sy / 2 + 0.05), z),
							mat, bevel=0.05)
		# Corbelled ledge.
		box((TW + 0.22, TW + 0.22, 0.14), (tx, ty, TOWER_TOP + 0.02), 'StoneDark', bevel=0.05)
		box((TW + 0.3, TW + 0.3, 0.12), (tx, ty, TOWER_TOP + 0.14), 'Stone', bevel=0.05)
		# Arrow-slit windows on the outer faces.
		ox = 1 if tx > 0 else -1
		oy = -1 if front else 1
		box((0.12, 0.06, 0.42), (tx, ty + oy * (TW / 2 + 0.01), 1.55), 'Window', bevel=0.02)
		box((0.06, 0.12, 0.42), (tx + ox * (TW / 2 + 0.01), ty, 1.55), 'Window', bevel=0.02)
		box((0.3, 0.12, 0.08), (tx, ty + oy * (TW / 2 + 0.04), 1.3), 'StoneDark', bevel=0.03)
		if front:
			# Crenellations, a blue band, and a flag.
			top = TOWER_TOP + 0.2
			for i in range(3):
				for j in range(3):
					if i == 1 and j == 1:
						continue
					off = (TW + 0.3) / 2 - 0.15
					box((0.28, 0.28, 0.3), (tx - off + i * off, ty - off + j * off, top + 0.15),
							'Stone' if (i + j) % 2 else 'StoneDark', bevel=0.05)
			box((TW + 0.12, TW + 0.12, 0.16), (tx, ty, TOWER_TOP - 0.2), 'TeamColor', bevel=0.04)
			flag(tx, ty, top, 1.1)
			banner(0.55, 0.75, face(tx, ty - TW / 2 - 0.04, TOWER_TOP - 0.36, '-y'))
		else:
			# A tall team-blue spire with a gold finial.
			pyramid(TW + 0.36, 1.25, (tx, ty, TOWER_TOP + 0.2), 'TeamColor')
			box((TW + 0.38, TW + 0.38, 0.1), (tx, ty, TOWER_TOP + 0.22), 'TeamColorDark', bevel=0.04)
			sphere(0.09, (tx, ty, TOWER_TOP + 1.5), 'Gold')

# --- gate: a deep stone arch with a planked door ----------------------------
# Its front stands clear of the roof's eave (which reaches HY + OVER_Y out),
# and its body runs back to the hall wall, so the roof meets its sides rather
# than coming out through its face.
GY = -HY - OVER_Y - 0.22
GATE_TOP = 2.45
GATE_BACK = -HY + 0.05
box((1.35, GATE_BACK - (GY - 0.2), GATE_TOP - PZ), (0, (GATE_BACK + GY - 0.2) / 2, (GATE_TOP + PZ) / 2),
		'Stone', bevel=0.05)
box((1.47, GATE_BACK - (GY - 0.26), 0.12), (0, (GATE_BACK + GY - 0.26) / 2, GATE_TOP), 'StoneDark', bevel=0.04)
for x in (-0.55, 0.0, 0.55):
	box((0.3, 0.42, 0.28), (x, GY, GATE_TOP + 0.2), 'Stone', bevel=0.05)
# The team shield over the arch, gold-rimmed.
box((0.5, 0.06, 0.48), (0, GY - 0.22, 2.06), 'Gold', bevel=0.03)
box((0.42, 0.07, 0.4), (0, GY - 0.24, 2.07), 'TeamColor', bevel=0.03)
box((0.3, 0.07, 0.2), (0, GY - 0.24, 1.82), 'TeamColor', rot=(0, 45, 0), bevel=0.03)
emblem(0.3, face(0, GY - 0.26, 2.04, '-y'))
for k, (w, z) in enumerate(((0.3, 0.55), (0.24, 0.95), (0.3, 1.35))):
	for s in (-1, 1):
		box((w, 0.46, 0.34), (s * (0.6 - w / 2 + 0.06), GY, PZ + z - 0.15), 'StoneDark' if k == 1 else 'Stone')
# Arch: voussoirs round the opening.
for i in range(7):
	a = math.radians(180 * (i + 0.5) / 7)
	box((0.2, 0.46, 0.26), (math.cos(a) * 0.5, GY, PZ + 1.2 + math.sin(a) * 0.42), 'Stone' if i % 2 else 'StoneDark',
			rot=(0, -math.degrees(a) + 90, 0), bevel=0.04)
box((0.74, 0.1, 1.35), (0, GY - 0.17, PZ + 0.68), 'WoodDark', bevel=0.03)
for x in (-0.24, 0.0, 0.24):
	box((0.2, 0.08, 1.3), (x, GY - 0.22, PZ + 0.68), 'Wood', bevel=0.025)
for z in (0.35, 0.95):
	box((0.76, 0.06, 0.08), (0, GY - 0.27, PZ + z), 'Iron', bevel=0.02)
sphere(0.05, (0.2, GY - 0.3, PZ + 0.68), 'Gold')
# Steps.
box((1.2, 0.35, 0.14), (0, GY - 0.6, 0.07), 'Stone', bevel=0.04)
box((1.0, 0.3, 0.14), (0, GY - 0.45, 0.21), 'StoneDark', bevel=0.04)

# --- props: barrels and crates at the gate ----------------------------------
barrel(-1.05, -1.45)
barrel(-0.78, -1.62)
crate(0.95, -1.5, PZ, 0.36, 12)
crate(0.95, -1.5, PZ + 0.36, 0.26, -8)

export('TownCentre')
