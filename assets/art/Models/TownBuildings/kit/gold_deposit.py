# Builds GoldDeposit.glb: a heap of chunky rounded boulders, half sunk into
# the ground, studded with faceted gold nuggets and a few veins of gold. See
# common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
from common import _finish

new_scene(211)
# Boulders: (x, y, width, height); the tallest in the middle.
ROCKS = ((0.0, 0.05, 1.3, 1.9), (-0.75, 0.35, 1.0, 1.25), (0.75, 0.4, 0.95, 1.4), (-0.55, -0.6, 0.9, 1.0),
		(0.6, -0.55, 0.85, 1.1), (-1.15, -0.2, 0.7, 0.75), (1.2, -0.05, 0.7, 0.85), (0.1, 0.95, 0.9, 1.05),
		(0.05, -1.05, 0.65, 0.6))
tops = []
for i, (x, y, w, h) in enumerate(ROCKS):
	m = ('RockA', 'RockB', 'RockC')[i % 3]
	rz = random.uniform(0, 90)
	tilt = (random.uniform(-8, 8), random.uniform(-8, 8), rz)
	box((w, w * random.uniform(0.8, 0.95), h + 0.6), (x, y, (h + 0.6) / 2 - 0.6), m, rot=tilt,
			bevel=min(0.3, w * 0.3), segments=3)
	tops.append((x, y, h - 0.05, w))


def nugget(x, y, z, r, mat='Gold'):
	bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=r)
	obj = bpy.context.active_object
	obj.matrix_world = Matrix.Translation((x, y, z)) @ Matrix.Rotation(random.uniform(0, 3.1), 4, 'Z') \
		@ Matrix.Rotation(random.uniform(0, 3.1), 4, 'X') @ Matrix.Diagonal((1.0, 1.0, random.uniform(0.75, 1.1), 1.0))
	# Faceted, like cut gold: smooth=False keeps each face flat.
	_finish(obj, mat, 0.0, 0)
	for p in obj.data.polygons:
		p.use_smooth = False


# Clusters of big nuggets sitting proud on the boulders' tops and shoulders,
# so the gold reads from gameplay distance.
for x, y, top, w in tops:
	for k in range(random.randint(2, 4)):
		a = random.uniform(0, math.tau)
		d = random.uniform(0.0, w * 0.3)
		r = random.uniform(0.18, 0.32)
		nugget(x + math.cos(a) * d, y + math.sin(a) * d, top + r * 0.3 - d * 0.35,
				r, 'Gold' if random.random() < 0.7 else 'GoldDeep')
# Loose nuggets at the foot.
for k in range(7):
	a = random.uniform(0, math.tau)
	d = random.uniform(1.15, 1.5)
	nugget(math.cos(a) * d, math.sin(a) * d, 0.06, random.uniform(0.1, 0.18))
# Veins: gold bands across the big middle boulder's faces.
for a_deg, z in ((-80, 0.7), (-20, 1.15), (200, 0.5)):
	a = math.radians(a_deg)
	f = Matrix.Translation((math.cos(a) * 0.62, 0.05 + math.sin(a) * 0.6, z)) @ Matrix.Rotation(a + math.pi / 2, 4, 'Z')
	box((0.6, 0.1, 0.14), (0, 0, 0), 'Gold', rot=(0, random.uniform(-25, 25), 0), bevel=0.04, segments=2, matrix=f)
export('GoldDeposit')
