# Builds Watchtower.glb: a stone tower with an overhanging timber watch room
# and a tall team-blue spire with a flag. See common.py for the kit.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

new_scene(81)
plinth(0.82, 0.82, pz=0.22)
Z0 = 0.22
TW, STONE_TOP = 1.15, 2.55
box((TW, TW, STONE_TOP - Z0), (0, 0, (STONE_TOP + Z0) / 2), 'Stone', bevel=0.06)
# A batter at the foot.
box((TW + 0.18, TW + 0.18, 0.34), (0, 0, Z0 + 0.17), 'StoneDark', bevel=0.06)
for cx in (-1, 1):
	for cy in (-1, 1):
		quoins(cx * TW / 2, cy * TW / 2, Z0 + 0.34, STONE_TOP - 0.05, size=0.26)
door(face(0, -TW / 2 - 0.05, Z0, '-y'), w=0.48, h=0.85, arch='stone')
box((0.7, 0.3, 0.1), (0, -TW / 2 - 0.3, Z0 - 0.05), 'Stone', bevel=0.04)
for side in ('-x', '+x', '+y'):
	ox = {'-x': -1, '+x': 1, '+y': 0}[side]
	oy = 1 if side == '+y' else 0
	f = face(ox * (TW / 2 + 0.01), oy * (TW / 2 + 0.01), 1.35, side)
	box((0.12, 0.06, 0.4), (0, 0, 0), 'Window', bevel=0.02, matrix=f)
	box((0.3, 0.12, 0.08), (0, -0.03, -0.25), 'StoneDark', bevel=0.03, matrix=f)
banner(0.46, 0.62, face(0, -TW / 2 - 0.04, 2.25, '-y'))
# Corbels, then the watch room overhanging the stone.
RW, RZ0, RZ1 = 1.5, STONE_TOP + 0.1, 3.55
for cx in (-1, 1):
	for k in (-0.3, 0.3):
		box((0.16, 0.3, 0.16), (cx * (TW / 2 + 0.1), k, STONE_TOP), 'Wood', bevel=0.04)
		box((0.3, 0.16, 0.16), (k, cx * (TW / 2 + 0.1), STONE_TOP), 'Wood', bevel=0.04)
box((RW + 0.1, RW + 0.1, 0.14), (0, 0, RZ0), 'Wood', bevel=0.05)
box((RW, RW, RZ1 - RZ0), (0, 0, (RZ0 + RZ1) / 2), 'Plaster', bevel=0.04)
for side in ('-y', '+y', '-x', '+x'):
	ox = {'-x': -1, '+x': 1}.get(side, 0)
	oy = {'-y': -1, '+y': 1}.get(side, 0)
	f = face(ox * RW / 2, oy * RW / 2, 0, side)
	for x in (-RW / 2 + 0.07, RW / 2 - 0.07):
		box((0.14, 0.14, RZ1 - RZ0), (x, -0.04, (RZ0 + RZ1) / 2), 'Wood', matrix=f)
	box((RW + 0.08, 0.16, 0.16), (0, -0.05, RZ1 - 0.05), 'Wood', matrix=f)
	window(face(ox * (RW / 2 + 0.03), oy * (RW / 2 + 0.03), (RZ0 + RZ1) / 2 + 0.02, side), w=0.42, h=0.4)
# The spire.
box((RW + 0.4, RW + 0.4, 0.14), (0, 0, RZ1 + 0.04), 'TeamColorDark', bevel=0.05)
pyramid(RW + 0.38, 1.45, (0, 0, RZ1 + 0.08), 'TeamColor')
flag(0, 0, RZ1 + 1.4, 0.75)
export('Watchtower')
