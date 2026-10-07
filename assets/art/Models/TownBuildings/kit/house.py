# Builds House.glb: a snug cottage on a stone plinth, steep tiled roof and a
# chimney. See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(11)
HX, HY, WALL_TOP = 1.0, 0.72, 1.6
plinth(1.22, 0.95)
mid = hall(HX, HY, WALL_TOP, braces=False, mid_z=1.22)
gable_roof(2.3, HY, WALL_TOP, pitch=46.0, over=0.28, hx=HX, tile_rows=4)
chimney(0.62, 0.36, 1.6, 2.85)
door_x, window_x = bay_centres(HX)
door(face(door_x, -HY - 0.07, PZ, '-y'), w=0.52, h=0.86)
box((0.8, 0.3, 0.1), (door_x, -HY - 0.28, 0.05 + PZ - 0.06), 'Stone', bevel=0.04)
window(face(window_x, -HY - 0.03, 0.88, '-y'), w=0.36, h=0.36)
# A flower box under the front window.
box((0.5, 0.14, 0.12), (window_x, -HY - 0.12, 0.62), 'Wood', bevel=0.03)
for i, c in enumerate(('Red', 'Gold', 'Red')):
	sphere(0.06, (window_x - 0.14 + i * 0.14, -HY - 0.12, 0.71), c)
for side in ('-x', '+x'):
	x = -HX - 0.03 if side == '-x' else HX + 0.03
	window(face(x, 0, 0.9, side), w=0.32, h=0.34)
for y in (-HY, HY):
	for x in (-HX, HX):
		quoins(x, y, PZ + 0.3, mid - 0.1, size=0.22)
barrel(-0.95, -1.0, z=0.0, r=0.17, h=0.4)
crate(0.98, -0.92, 0.0, 0.3, 14)
export('House')
