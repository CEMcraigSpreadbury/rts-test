# Builds DropPod.glb: the Colossus Drop pod, a 5 m tin capsule on an
# ember-glowing heat shield, with fins and team stripes. Its four side panels
# are nodes of their own, "Petal0".."Petal3", hinged at the bottom (PowerFx
# folds them outward).
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _kit import *

new_scene(661)
R = 1.5
cylinder(R * 1.08, 0.5, (0, 0, 0.25), 'Glass', verts=16, radius2=R, bevel=0.05)
cylinder(R * 0.55, 1.2, (0, 0, 4.3), 'Pod', verts=16, radius2=0.2, bevel=0.05)
cylinder(0.8, 0.4, (0, 0, 3.8), 'TeamColor', verts=16, bevel=0.05)
sphere(0.22, (0, 0, 5.0), 'Glass')
for i in range(4):
	a = math.radians(45 + i * 90)
	box((0.14, 1.0, 2.0), (math.cos(a) * (R + 0.35), math.sin(a) * (R + 0.35), 1.4), 'IronDark',
			rot=(0, 0, math.degrees(a) + 90), bevel=0.05)
# A core the panels close round.
cylinder(R * 0.85, 3.2, (0, 0, 2.1), 'IronDark', verts=16, bevel=0.05)
for i in range(4):
	a = math.radians(i * 90)
	c, s = math.cos(a), math.sin(a)
	with moving('Petal%d' % i, (c * R * 0.95, s * R * 0.95, 0.5)) as petal:
		box((2.0, 0.22, 3.2), (c * R * 0.95, s * R * 0.95, 2.1), 'Pod', rot=(0, 0, math.degrees(a) + 90), bevel=0.08)
		box((0.4, 0.26, 2.9), (c * (R * 0.95 + 0.04), s * (R * 0.95 + 0.04), 2.1), 'TeamColor',
				rot=(0, 0, math.degrees(a) + 90), bevel=0.05)
export('DropPod')
