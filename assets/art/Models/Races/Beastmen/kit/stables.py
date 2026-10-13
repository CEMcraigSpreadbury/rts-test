# Builds Stables.glb: the beast pen, a ring of sharpened stakes lashed with
# rope round a thatched lean-to of hay, a hollow-log trough and gnawed bones;
# its gate is an arch of two great tusks under a boar skull.
# See beastmen_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beastmen_common import *

new_scene(371)
mound(1.9, 1.5, gap=(258, 282))
# Lean-to at the back right.
BACK_Y, RUN, HIGH = 1.18, 1.0, MZ + 1.2
low = thatch_shed(2.0, RUN, 0.55, BACK_Y, HIGH, '-y', pitch=22.0)
for x in (-0.38, 1.48):
	post(x, BACK_Y - 0.05, MZ - 0.02, HIGH - MZ - 0.02, r=0.08)
	post(x, BACK_Y - RUN + 0.16, MZ - 0.02, low - MZ + 0.04, r=0.08)
cylinder(0.07, 1.95, (0.55, BACK_Y - RUN + 0.16, low - 0.02), 'Log', verts=8, rot=(0, 90, 0), bevel=0.02)
hay_bale(0.3, 0.75, MZ - 0.02, rot=5)
hay_bale(0.95, 0.8, MZ - 0.02, rot=-8)
hay_bale(0.62, 0.78, MZ + 0.3, rot=80)
# The stake ring, open at the front gate.
FY, SXE, BY = -1.08, 1.55, 0.95
stakes(-SXE, FY, -0.5, FY, MZ - 0.02, 0.62)
stakes(0.5, FY, SXE, FY, MZ - 0.02, 0.62)
stakes(-SXE, FY + 0.24, -SXE, BY, MZ - 0.02, 0.62)
stakes(SXE, FY + 0.24, SXE, BY - 0.6, MZ - 0.02, 0.62)
stakes(-SXE + 0.24, BY + 0.05, -0.55, BY + 0.05, MZ - 0.02, 0.62)
# The tusk gate.
for sx in (-1, 1):
	post(sx * 0.5, FY, MZ - 0.02, 0.95, r=0.09)
	rope_band(0.11, sx * 0.5, FY, MZ + 0.75)
	tusk(Matrix.Translation((sx * 0.5, FY, MZ + 0.9)) @ Matrix.Rotation(math.radians(-sx * 40), 4, 'Y'), 2.0, -sx)
skull(face(0, FY - 0.05, MZ + 1.25, '-y'), 0.42, horns='tusks')
hide_banner(0.36, 0.4, face(0, FY - 0.04, MZ + 0.98, '-y'))
# Trough, bones, a hide on the shed post.
cylinder(0.16, 0.9, (-0.85, 0.25, MZ + 0.12), 'Log', verts=10, rot=(0, 90, 0), bevel=0.03)
box((0.78, 0.18, 0.06), (-0.85, 0.25, MZ + 0.26), 'Dirt', bevel=0.02, segments=2)
for x in (-1.27, -0.43):
	cylinder(0.13, 0.02, (x, 0.25, MZ + 0.12), 'LogEnd', verts=10, rot=(0, 90, 0), bevel=0.0)
for bx, by, a in ((-0.2, -0.45, 20), (0.35, -0.6, -40), (-0.6, -0.55, 75)):
	cylinder(0.025, 0.3, (bx, by, MZ + 0.03), 'Bone', verts=6, rot=(0, 90, a), bevel=0.0)
	for e in (-1, 1):
		sphere(0.045, (bx + e * 0.15 * math.cos(math.radians(a)), by + e * 0.15 * math.sin(math.radians(a)), MZ + 0.03), 'Bone')
totem(1.2, -0.45, MZ - 0.02, ('boar', 'bear'), s=0.32, top='antlers')
export('Stables')
