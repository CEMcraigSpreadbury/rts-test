# Builds Range.glb: the hunters' lodge, a thatched lean-to with a bow rack,
# two stretched-hide targets on log hoops stuck with arrows, a straw stag to
# shoot at and a stag-and-wolf totem. See beastmen_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from beastmen_common import *

new_scene(361)
CY = -0.2
mound(1.8, 1.36, cy=CY)
# Lean-to along the back.
BACK_Y, RUN, HIGH = 0.82, 1.0, MZ + 1.3
low = thatch_shed(2.3, RUN, -0.45, BACK_Y, HIGH, '-y', pitch=24.0)
for x in (-1.5, 0.6):
	post(x, BACK_Y - 0.05, MZ - 0.02, HIGH - MZ - 0.02, r=0.08)
	post(x, BACK_Y - RUN + 0.16, MZ - 0.02, low - MZ + 0.04, r=0.08)
cylinder(0.07, 2.25, (-0.45, BACK_Y - RUN + 0.16, low - 0.02), 'Log', verts=8, rot=(0, 90, 0), bevel=0.02)
# Bow rack under it.
for x in (-1.2, -0.3):
	post(x, 0.5, MZ - 0.02, 0.8, r=0.045)
cylinder(0.04, 1.0, (-0.75, 0.5, MZ + 0.72), 'Log', verts=8, rot=(0, 90, 0), bevel=0.02)
for i in range(4):
	x = -1.08 + i * 0.22
	m = Matrix.Translation((x, 0.44, MZ + 0.1)) @ Matrix.Rotation(math.radians(-8), 4, 'X')
	for k in range(5):
		a = math.radians(-50 + 25 * k)
		th = -math.degrees(math.atan2(0.12 * math.sin(a), 0.4 * math.cos(a)))
		box((0.04, 0.04, 0.2), (0, -0.12 * math.cos(a), 0.4 + 0.4 * math.sin(a)), 'WoodDark', rot=(th, 0, 0),
				bevel=0.012, segments=2, matrix=m)
	box((0.014, 0.014, 0.62), (0, -0.04, 0.4), 'Rope', bevel=0.0, matrix=m)
basket(-1.3, -0.1, MZ - 0.02, r=0.16, h=0.3, fill=None)
for k in range(5):
	a = 2 * math.pi * k / 5
	cylinder(0.012, 0.5, (-1.3 + math.cos(a) * 0.06, -0.1 + math.sin(a) * 0.06, MZ + 0.4), 'WoodDark', verts=4, bevel=0.0)
	box((0.02, 0.06, 0.08), (-1.3 + math.cos(a) * 0.06, -0.1 + math.sin(a) * 0.06, MZ + 0.62), 'Bone', bevel=0.008, segments=1)


def target(x, y, turn):
	"""A hide stretched in a log hoop on a tripod, a red bullseye, arrows in."""
	f = Matrix.Translation((x, y, MZ)) @ Matrix.Rotation(math.radians(turn), 4, 'Z')
	for a in (-25, 25):
		box((0.06, 0.06, 1.0), (math.sin(math.radians(a)) * 0.22, 0.05, 0.46), 'LogB', rot=(0, a, 0), bevel=0.02, segments=2, matrix=f)
	box((0.06, 0.06, 0.8), (0, 0.24, 0.36), 'LogB', rot=(-25, 0, 0), bevel=0.02, segments=2, matrix=f)
	c = f @ Matrix.Translation((0, 0, 0.72)) @ Matrix.Rotation(math.radians(90), 4, 'X')
	torus(0.33, 0.055, (0, 0, 0), 'Log', matrix=c)
	cylinder(0.31, 0.04, (0, 0, 0), 'Hide', verts=14, bevel=0.01, matrix=c)
	cylinder(0.2, 0.05, (0, 0, 0.005), 'Red', verts=14, bevel=0.01, matrix=c)
	cylinder(0.1, 0.06, (0, 0, 0.01), 'TeamColor', verts=12, bevel=0.01, matrix=c)
	for ax, az in ((0.08, 0.05), (-0.12, -0.1), (0.15, -0.14)):
		m = f @ Matrix.Translation((ax, -0.18, 0.72 + az)) @ Matrix.Rotation(math.radians(80), 4, 'X')
		cylinder(0.014, 0.36, (0, 0, 0), 'WoodDark', verts=4, bevel=0.0, matrix=m)
		box((0.06, 0.02, 0.08), (0, 0, -0.16), 'Bone', bevel=0.008, segments=1, matrix=m)


target(0.75, -0.25, 15)
target(1.35, 0.25, 30)
# The straw stag.
SX, SY = 0.45, -1.0
for dx in (-0.2, 0.2):
	for dy in (-0.08, 0.08):
		box((0.06, 0.06, 0.44), (SX + dx, SY + dy, MZ + 0.2), 'LogB', bevel=0.02, segments=2)
box((0.62, 0.3, 0.3), (SX, SY, MZ + 0.55), 'Hay', bevel=0.1, segments=2)
box((0.18, 0.16, 0.36), (SX - 0.3, SY, MZ + 0.82), 'Hay', rot=(0, -25, 0), bevel=0.06, segments=2)
box((0.26, 0.15, 0.15), (SX - 0.42, SY, MZ + 1.0), 'Hay', bevel=0.05, segments=2)
antlers(Matrix.Translation((SX - 0.38, SY, MZ + 1.05)) @ Matrix.Rotation(math.radians(90), 4, 'Z'), 0.42)
for dx in (-0.12, 0.12):
	box((0.03, 0.32, 0.06), (SX + dx, SY, MZ + 0.55), 'Rope', bevel=0.01, segments=1)
cylinder(0.014, 0.4, (SX + 0.05, SY - 0.2, MZ + 0.6), 'WoodDark', verts=4, bevel=0.0, rot=(80, 0, 0))
totem(-0.95, -1.05, MZ - 0.02, ('wolf', 'stag'), s=0.32)
hide_banner(0.4, 0.46, face(-1.5, BACK_Y - RUN + 0.08, low - 0.1, '-y') @ Matrix.Translation((0.3, 0, 0)), claws=True)
export('Range')
