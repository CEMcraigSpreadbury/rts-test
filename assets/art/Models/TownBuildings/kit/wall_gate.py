# Builds WallGate.glb: two stone pillars with a round arch, a raised portcullis
# and battlements over it, and the team shield on the front. The opening stays
# inside wall_gate.tscn's walk-through gap (posts at x = +-0.85, 0.3 wide, so
# clear between +-0.7, under the lintel at 1.7). Kept light. See common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(191)
PX, PW, TOP = 0.86, 0.36, 2.25
for s in (-1, 1):
	box((PW + 0.14, 0.62, 0.3), (s * PX, 0, 0.15), 'StoneDark', bevel=0.05, segments=2)
	box((PW, 0.5, TOP - 0.3), (s * PX, 0, (TOP + 0.3) / 2), 'Stone', bevel=0.05, segments=2)
	box((PW + 0.12, 0.58, 0.12), (s * PX, 0, TOP), 'StoneDark', bevel=0.04, segments=2)
	box((0.3, 0.48, 0.3), (s * PX, 0, TOP + 0.21), 'Stone', bevel=0.06, segments=2)
	box((PW + 0.04, 0.52, 0.12), (s * PX, 0, 0.95), 'StoneDark', bevel=0.04, segments=2)
# The arch: nine voussoirs packed edge to edge round an opening springing at
# 1.15 from x = +-0.58, its crown at 1.6. Each sits outward from the opening,
# turned so its width runs along the curve.
SPRING, RX, RZ, DEPTH = 1.15, 0.58, 0.45, 0.3
for i in range(9):
	a = math.radians(180 * (i + 0.5) / 9)
	x, z = math.cos(a) * (RX + DEPTH / 2), SPRING + math.sin(a) * (RZ + DEPTH / 2)
	tilt = math.degrees(math.atan2(RZ * math.cos(a), -RX * math.sin(a)))
	box((0.25, 0.48, DEPTH), (x, 0, z), 'StoneDark' if i % 2 else 'Stone', rot=(0, -tilt, 0), bevel=0.04, segments=2)
# Spandrels: stone filling the shoulders between the curve and the wall above,
# stepped so its foot hugs the arch.
for x0, x1, z0 in ((0.5, 0.69, SPRING + 0.2), (0.25, 0.5, SPRING + 0.45)):
	for s in (-1, 1):
		box((x1 - x0 + 0.02, 0.42, 1.62 - z0), (s * (x0 + x1) / 2, 0, (1.62 + z0) / 2), 'Stone', bevel=0.03, segments=2)
# Wall over the arch, its battlements and the shield.
box((2 * PX - PW, 0.42, TOP - 1.55), (0, 0, (TOP + 1.55) / 2 + 0.05), 'Stone', bevel=0.05, segments=2)
box((2 * PX + PW + 0.12, 0.52, 0.12), (0, 0, TOP + 0.04), 'StoneDark', bevel=0.04, segments=2)
for x in (-0.3, 0.3):
	box((0.28, 0.44, 0.3), (x, 0, TOP + 0.25), 'Stone', bevel=0.06, segments=2)
shield(0.36, face(0, -0.24, 2.08, '-y'))
# The portcullis, raised: its spiked foot just shows under the crown.
box((1.2, 0.08, 0.08), (0, 0.06, 1.5), 'IronDark', bevel=0.02, segments=2)
for x in (-0.4, -0.2, 0.0, 0.2, 0.4):
	cylinder(0.04, 0.16, (x, 0.06, 1.42), 'IronDark', verts=4, bevel=0.0, radius2=0.0, rot=(180, 0, 0))
export('WallGate')
