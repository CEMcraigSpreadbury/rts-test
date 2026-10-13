# Builds Lumberyard.glb: a thatched lean-to on log posts over a big log stack,
# a chopping stump with an axe bitten in, a sawhorse and a boar-and-wolf totem.
# See beastmen_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beastmen_common import *

new_scene(341)
mound(1.45, 1.12)
BACK_Y, RUN, HIGH = 0.82, 1.15, MZ + 1.3
low = thatch_shed(2.5, RUN, 0, BACK_Y, HIGH, '-y', pitch=22.0)
for x in (-1.05, 1.05):
	post(x, BACK_Y - 0.05, MZ - 0.02, HIGH - MZ - 0.02, r=0.085)
	post(x, BACK_Y - RUN + 0.18, MZ - 0.02, low - MZ + 0.04, r=0.085)
	rope_band(0.1, x, BACK_Y - RUN + 0.18, low - 0.12)
cylinder(0.08, 2.4, (0, BACK_Y - RUN + 0.18, low - 0.02), 'Log', verts=8, rot=(0, 90, 0), bevel=0.02)
log_pile(0, 0.32, MZ - 0.02, 1.85, rows=3, r=0.12)
# Chopping stump with the axe bitten in.
SX, SY = 0.72, -0.62
cylinder(0.24, 0.36, (SX, SY, MZ + 0.16), 'Log', verts=12, bevel=0.03)
cylinder(0.205, 0.03, (SX, SY, MZ + 0.345), 'LogEnd', verts=12, bevel=0.01)
m = Matrix.Translation((SX + 0.02, SY, MZ + 0.38)) @ Matrix.Rotation(math.radians(30), 4, 'Y')
cylinder(0.03, 0.62, (0, 0, 0.3), 'WoodDark', verts=6, bevel=0.0, matrix=m)
box((0.05, 0.22, 0.18), (0, 0, 0.0), 'Steel', bevel=0.025, segments=2, matrix=m)
for i in range(6):
	a = random.uniform(0, 2 * math.pi)
	d = random.uniform(0.32, 0.5)
	box((0.1, 0.06, 0.03), (SX + math.cos(a) * d, SY + math.sin(a) * d, MZ + 0.0), 'LogEnd', rot=(0, 0, random.uniform(0, 180)),
			bevel=0.012, segments=2)
# Sawhorse with a log across it.
for x in (-0.95, -0.35):
	for a in (-22, 22):
		box((0.06, 0.06, 0.55), (x, -0.62, MZ + 0.24), 'LogB', rot=(a, 0, 0), bevel=0.02, segments=2)
cylinder(0.11, 0.95, (-0.65, -0.62, MZ + 0.5), 'Log', verts=8, rot=(0, 90, 0), bevel=0.02)
cylinder(0.09, 0.02, (-0.65 - 0.48, -0.62, MZ + 0.5), 'LogEnd', verts=8, rot=(0, 90, 0), bevel=0.0)
totem(1.22, 0.05, MZ - 0.02, ('wolf', 'boar'), s=0.32, top='antlers')
export('Lumberyard')
