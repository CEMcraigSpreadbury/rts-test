# Builds Mill.glb: a tapered plaster windmill on a stone footing, timber bands,
# a team-blue cap and four lattice sails with canvas; sacks of flour at the
# door. See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(111)
plinth(1.05, 1.05, pz=0.24)
Z0, TOP, R0, R1 = 0.24, 2.75, 0.86, 0.62
cylinder(R0 + 0.08, 0.42, (0, 0, Z0 + 0.21), 'Stone', verts=12, bevel=0.05)
for i in range(12):
	a = math.radians(i * 30 + 15)
	f = Matrix.Translation((math.cos(a) * (R0 + 0.08), math.sin(a) * (R0 + 0.08), Z0 + 0.21)) @ Matrix.Rotation(a + math.pi / 2, 4, 'Z')
	box((0.38, 0.12, 0.3 + random.uniform(-0.04, 0.04)), (0, 0, 0), 'StoneDark' if i % 3 == 0 else 'Stone', bevel=0.05, matrix=f)
cylinder(R0, TOP - Z0 - 0.42, (0, 0, (TOP + Z0 + 0.42) / 2), 'Plaster', verts=12, bevel=0.04, radius2=R1)
for t in (0.38, 0.72):
	r = R0 + (R1 - R0) * t + 0.03
	z = Z0 + 0.42 + (TOP - Z0 - 0.42) * t
	cylinder(r, 0.13, (0, 0, z), 'Wood', verts=12, bevel=0.03, radius2=r - 0.01)
# Door and windows.
door(face(0, -R0 - 0.02, Z0 + 0.42, '-y'), w=0.48, h=0.82)
for a_deg, z in ((-50, 1.85), (200, 1.55)):
	a = math.radians(a_deg)
	r = R0 + (R1 - R0) * ((z - Z0 - 0.42) / (TOP - Z0 - 0.42)) + 0.02
	f = Matrix.Translation((math.cos(a) * r, math.sin(a) * r, z)) @ Matrix.Rotation(a + math.pi / 2, 4, 'Z')
	window(f, w=0.26, h=0.3, shutters=True)
# The cap.
cylinder(R1 + 0.14, 0.14, (0, 0, TOP + 0.04), 'TeamColorDark', verts=12, bevel=0.04)
pyramid(2 * (R1 + 0.12), 1.05, (0, 0, TOP + 0.1), 'TeamColor', sides=12)
sphere(0.08, (0, 0, TOP + 1.18), 'Gold')
# The sails: a hub on the front of the cap, four arms with lattice and canvas.
HUB = Vector((0, -R1 - 0.32, TOP + 0.05))
cylinder(0.09, 0.5, (HUB.x, HUB.y + 0.2, HUB.z), 'WoodDark', verts=8, bevel=0.02, rot=(90, 0, 0))
cylinder(0.16, 0.14, tuple(HUB), 'Wood', verts=10, bevel=0.03, rot=(90, 0, 0))
sphere(0.08, (HUB.x, HUB.y - 0.08, HUB.z), 'Gold')
for k in range(4):
	ang = 20 + k * 90
	arm = Matrix.Translation(HUB) @ Matrix.Rotation(math.radians(ang), 4, 'Y')
	box((0.08, 0.07, 1.65), (0, -0.04, 0.95), 'Wood', bevel=0.02, matrix=arm)
	box((0.36, 0.03, 1.05), (0.22, -0.02, 1.15), 'Cloth', bevel=0.012, segments=2, matrix=arm)
	for j in range(5):
		box((0.42, 0.05, 0.04), (0.2, -0.05, 0.65 + j * 0.25), 'Wood', bevel=0.012, segments=2, matrix=arm)
	box((0.04, 0.05, 1.05), (0.42, -0.05, 1.15), 'Wood', bevel=0.012, segments=2, matrix=arm)
# Flour sacks and a cart wheel by the door.
sack(0.6, -0.95, 0.0, 20)
sack(0.88, -0.78, 0.0, -10)
sack(0.72, -0.88, 0.32, 40)
sack(-0.75, -0.9, 0.0, -25)
barrel(-1.05, -0.55, z=0.0, r=0.16, h=0.38)
export('Mill')
