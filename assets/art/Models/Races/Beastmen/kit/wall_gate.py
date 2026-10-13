# Builds WallGate.glb: two sharpened gate logs carved with a bear over a boar,
# a double log lintel lashed across them and a great antlered skull on top,
# with claw-marked team hides on the posts. The opening stays inside
# wall_gate.tscn's walk-through gap (posts at x = +-0.85, clear between +-0.7,
# under the lintel at 1.7). Kept light. See beastmen_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beastmen_common import *

new_scene(421)
PX = 0.86
for s in (-1, 1):
	box((0.5, 0.56, 0.18), (s * PX, 0, 0.07), 'Dirt', bevel=0.06, segments=2)
	boulder(s * (PX + 0.16), -0.2, 0.0, (0.24, 0.2, 0.18), 'Stone', tilt=False)
	post(s * PX, 0, 0.05, 2.25, r=0.15, mat_name='LogB', tip=True, verts=10)
	z = 0.32
	for kind in ('boar', 'bear'):
		z += head(kind, face(s * PX, -0.05, z, '-y'), 0.3) + 0.06
	hide_banner(0.24, 0.34, face(s * PX, -0.17, 1.62, '-y'), claws=False)
	for zz in (1.75, 2.08):
		rope_band(0.17, s * PX, 0, zz, h=0.07, n=10)
for z, r in ((1.86, 0.13), (2.1, 0.11)):
	cylinder(r, 2.2, (0, 0.04, z), 'Log', verts=10, rot=(0, 90, 0), bevel=0.03)
	for e in (-1, 1):
		cylinder(r * 0.82, 0.02, (e * 1.105, 0.04, z), 'LogEnd', verts=10, rot=(0, 90, 0), bevel=0.0)
skull(face(0, -0.08, 2.42, '-y'), 0.6)
claw_marks(face(0, -0.1, 1.86, '-y'), h=0.24, mat_name='Bone')
export('WallGate')
