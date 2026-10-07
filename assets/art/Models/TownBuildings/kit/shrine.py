# Builds Shrine.glb: a stepped stone sanctum ringed by four pillars with fire
# braziers, team banners on the front pair, and an altar holding a red orb in
# a cradle of antlers. See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(161)
# Steps.
box((3.3, 3.3, 0.2), (0, 0.1, 0.1), 'StoneDark', bevel=0.06)
box((2.85, 2.85, 0.2), (0, 0.1, 0.3), 'Stone', bevel=0.06)
box((2.4, 2.4, 0.2), (0, 0.1, 0.5), 'StoneDark', bevel=0.06)
for i in range(6):
	x = -1.2 + 0.4 + i * 0.32
	box((0.28, 0.24, 0.06), (x, 0.1 - 1.2 + 0.14, 0.62), 'Stone', bevel=0.02, segments=2)
TOPZ = 0.6
# A worn path of slabs up the front.
for k, (w, y, z) in enumerate(((0.9, -1.6, 0.2), (0.8, -1.38, 0.4))):
	box((w, 0.3, 0.06), (0, y, z + 0.02), 'Stone', bevel=0.02)
# Pillars with capitals and braziers.
PH = 2.2
for px in (-0.95, 0.95):
	for py in (-0.85, 1.05):
		box((0.42, 0.42, 0.18), (px, py, TOPZ + 0.09), 'StoneDark', bevel=0.05)
		box((0.32, 0.32, PH), (px, py, TOPZ + 0.18 + PH / 2), 'Stone', bevel=0.05)
		for k in range(3):
			box((0.36, 0.36, 0.08), (px, py, TOPZ + 0.6 + k * 0.6), 'StoneDark', bevel=0.03, segments=2)
		cap = TOPZ + 0.18 + PH
		box((0.46, 0.46, 0.14), (px, py, cap + 0.07), 'StoneDark', bevel=0.05)
		cylinder(0.24, 0.18, (px, py, cap + 0.23), 'IronDark', verts=10, bevel=0.03, radius2=0.18)
		for j in range(4):
			sphere(0.08, (px + math.cos(j * 1.57) * 0.09, py + math.sin(j * 1.57) * 0.09, cap + 0.36), 'Ember')
		cylinder(0.11, 0.26, (px, py, cap + 0.5), 'Ember', verts=6, bevel=0.0, radius2=0.0)
		if py < 0:
			banner(0.34, 0.8, face(px, py - 0.2, cap - 0.15, '-y'))
# Lintels between the pillars, back and sides.
for py in (-0.85, 1.05):
	if py > 0:
		box((2.3, 0.3, 0.2), (0, py, TOPZ + 0.18 + PH - 0.1), 'Stone', bevel=0.05)
for px in (-0.95, 0.95):
	box((0.3, 2.2, 0.2), (px, 0.1, TOPZ + 0.18 + PH - 0.1), 'Stone', bevel=0.05)
# The altar, with a blood-red runner, and the orb in its antler cradle.
AY = 0.25
box((1.0, 0.62, 0.68), (0, AY, TOPZ + 0.34), 'Stone', bevel=0.06)
box((1.12, 0.74, 0.12), (0, AY, TOPZ + 0.72), 'StoneDark', bevel=0.04)
box((0.34, 0.76, 0.04), (0, AY, TOPZ + 0.79), 'BloodRed', bevel=0.012, segments=2)
box((0.34, 0.04, 0.4), (0, AY - 0.4, TOPZ + 0.6), 'BloodRed', bevel=0.012, segments=2)
box((0.36, 0.05, 0.08), (0, AY - 0.4, TOPZ + 0.4), 'Gold', bevel=0.015, segments=2)
for s in (-1, 1):
	f = Matrix.Translation((s * 0.13, AY, TOPZ + 0.8)) @ Matrix.Rotation(math.radians(s * 28), 4, 'Y')
	box((0.07, 0.07, 0.42), (0, 0, 0.2), 'Antler', bevel=0.025, matrix=f)
	box((0.06, 0.06, 0.2), (0, 0, 0.32), 'Antler', rot=(0, s * -45, 0), bevel=0.02, matrix=f)
	box((0.05, 0.05, 0.16), (0, 0, 0.18), 'Horn', rot=(40, 0, 0), bevel=0.02, matrix=f)
sphere(0.2, (0, AY, TOPZ + 1.1), 'Orb')
sphere(0.07, (-0.07, AY - 0.12, TOPZ + 1.18), 'Cloth')
# Offerings: candles and a bowl.
for x in (-0.38, 0.38):
	cylinder(0.045, 0.16, (x, AY - 0.18, TOPZ + 0.86), 'Cloth', verts=8, bevel=0.0)
	sphere(0.03, (x, AY - 0.18, TOPZ + 0.97), 'Ember')
cylinder(0.14, 0.08, (0.6, -0.6, TOPZ + 0.04), 'Gold', verts=10, bevel=0.02, radius2=0.1)
export('Shrine')
