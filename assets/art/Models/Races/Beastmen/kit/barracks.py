# Builds Barracks.glb: the bear lodge, a long log-cabin hall under stepped
# thatch with a team hide over the ridge and crossed barge boards carrying
# antlered skulls; two bear totems flank the door, with an axe rack and a fire
# pit out front. See beastmen_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beastmen_common import *

new_scene(321)
HX, HY, CY, WALL_TOP = 1.35, 0.78, 0.2, 1.45
mound(1.9, 1.5, cy=-0.12)
log_wall_box(HX, HY, MZ - 0.02, WALL_TOP, cy=CY, r=0.11)
ridge = thatch_gable(2 * HX + 0.5, HY, WALL_TOP, cy=CY, pitch=46.0, over=0.34, hx=HX)
for side, x in (('-x', -HX - 0.48), ('+x', HX + 0.48)):
	skull(face(x, CY, ridge + 0.02, side), 0.5)
fy = CY - HY
doorway(face(0, fy - 0.1, MZ, '-y'), w=0.62, h=0.82)
hide_banner(0.44, 0.5, face(-0.82, fy - 0.12, 1.12, '-y'))
hide_banner(0.44, 0.5, face(0.82, fy - 0.12, 1.12, '-y'))
for x in (-0.62, 0.62):
	totem(x, -1.15, MZ - 0.02, ('bear', 'bear'), s=0.34, top='antlers')


def axe(x, y, z, lean):
	m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.radians(lean), 4, 'Y')
	cylinder(0.03, 0.78, (0, 0, 0.39), 'WoodDark', verts=6, bevel=0.0, matrix=m)
	box((0.24, 0.05, 0.2), (0.11, 0, 0.66), 'Steel', bevel=0.03, segments=2, matrix=m)
	box((0.07, 0.06, 0.26), (0.24, 0, 0.66), 'Steel', bevel=0.025, segments=2, matrix=m)


# Axe rack, front left.
RX, RY = -1.3, -1.02
for x in (RX - 0.32, RX + 0.32):
	post(x, RY, MZ - 0.02, 0.72, r=0.05)
cylinder(0.045, 0.8, (RX, RY, MZ + 0.6), 'Log', verts=8, rot=(0, 90, 0), bevel=0.02)
for i, x in enumerate((RX - 0.18, RX + 0.02, RX + 0.22)):
	axe(x, RY - 0.06, MZ, -8 + i * 6)
firepit(1.25, -1.0, MZ)
log_pile(0.3, CY + HY + 0.3, MZ, 1.4, rows=2, r=0.1)
export('Barracks')
