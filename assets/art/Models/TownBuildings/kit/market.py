# Builds Market.glb: two stalls on a paved square under striped team awnings,
# counters heaped with apples, greens and gold, and sacks and barrels about.
# Kept low, as the old one was. See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(151)
plinth(1.5, 1.05, cx=0.12, cy=0.0, pz=0.16)
Z0 = 0.16


def stall(x, y, w, d, goods):
	"""A stall: a counter at the front, four posts, a striped awning sloping
	down to the front."""
	back_h, front_h = 1.45, 1.15
	for px in (x - w / 2, x + w / 2):
		box((0.12, 0.12, back_h - Z0), (px, y + d / 2, (back_h + Z0) / 2), 'Wood', bevel=0.04)
		box((0.12, 0.12, front_h - Z0), (px, y - d / 2, (front_h + Z0) / 2), 'Wood', bevel=0.04)
	box((w + 0.1, 0.12, 0.12), (x, y + d / 2, back_h - 0.04), 'Wood')
	box((w + 0.1, 0.12, 0.12), (x, y - d / 2, front_h - 0.04), 'Wood')
	# Awning: alternating strips down the slope, with a scalloped front edge.
	pitch = math.degrees(math.atan2(back_h - front_h, d))
	slope_len = math.hypot(d, back_h - front_h) + 0.3
	frame = Matrix.Translation((x, y - 0.12, (back_h + front_h) / 2 + 0.06)) @ Matrix.Rotation(math.radians(pitch), 4, 'X')
	n = 6
	sw = (w + 0.3) / n
	for i in range(n):
		box((sw + 0.005, slope_len, 0.06), (-(w + 0.3) / 2 + sw * (i + 0.5), 0, 0), 'TeamColor' if i % 2 else 'Cloth',
				bevel=0.025, segments=2, matrix=frame)
		box((sw * 0.86, 0.06, 0.16), (-(w + 0.3) / 2 + sw * (i + 0.5), -slope_len / 2, -0.07),
				'TeamColor' if i % 2 else 'Cloth', bevel=0.03, segments=2, matrix=frame)
	# The counter.
	box((w, 0.42, 0.62), (x, y - d / 2 + 0.24, Z0 + 0.31), 'Wood', bevel=0.05)
	for k in range(3):
		box((w + 0.02, 0.44, 0.05), (x, y - d / 2 + 0.24, Z0 + 0.15 + k * 0.2), 'WoodDark', bevel=0.02, segments=2)
	box((w + 0.08, 0.5, 0.07), (x, y - d / 2 + 0.24, Z0 + 0.65), 'Wood', bevel=0.03)
	# Goods in shallow crates along the counter.
	for i, g in enumerate(goods):
		cx = x - w / 2 + w * (i + 0.5) / len(goods)
		box((w / len(goods) - 0.08, 0.36, 0.08), (cx, y - d / 2 + 0.24, Z0 + 0.72), 'WoodDark', bevel=0.02)
		for j in range(6):
			gx = cx + ((j % 3) - 1) * 0.1
			gy = y - d / 2 + 0.17 + (j // 3) * 0.13
			if g == 'Gold':
				cylinder(0.05, 0.03, (gx, gy, Z0 + 0.79 + (j % 2) * 0.03), 'Gold', verts=10, bevel=0.0)
			else:
				sphere(0.065, (gx, gy, Z0 + 0.82), g)


stall(-0.62, 0.1, 1.15, 1.0, ('Apple', 'Greens', 'Apple'))
stall(0.8, 0.05, 1.05, 0.95, ('Gold', 'Sack', 'Greens'))
# Sacks, barrels, a crate of apples and a signboard.
sack(-1.2, -0.85, 0.0, 15)
sack(-0.95, -0.92, 0.0, -20)
barrel(1.45, -0.7, z=0.0, r=0.16, h=0.38)
barrel(1.5, 0.75, z=0.0, r=0.16, h=0.38)
crate(0.15, -0.95, 0.0, 0.3, 12)
for j in range(4):
	sphere(0.06, (0.08 + (j % 2) * 0.13, -0.98 + (j // 2) * 0.13, 0.33), 'Apple')
box((0.07, 0.07, 1.0), (1.55, -0.2, 0.5), 'Wood')
shield(0.36, face(1.55, -0.25, 0.85, '-y'))
export('Market')
