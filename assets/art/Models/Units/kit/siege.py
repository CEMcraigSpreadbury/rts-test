"""Siege engines (Siege Workshop): chunky diorama-toy war machines, drawn
much bigger than any foot soldier (see docs/unit-figures.md, "Size"). Each
is designed in metres at about 2.3 m, then grown round the ground by
SIEGE_SCALE. Wood, blackened iron, brass and glossy painted panels; the
sprite's red panels are the team's paint here. Palette: `siege`
(palette.SIEGE: Aldmere's rows plus `plate_dark` for the blackened iron and
`arcane` for the cannon's glowing runes). The crewman beside each machine is
the Aldmere Soldier (the crew sprite is the swordsman), added in units.py.

  ballista: a huge bolt-thrower on a long wheeled chassis, three small iron-
    tyred wheels a side as in the sprite; the team's painted side boards
    with brass trim; a turret drum carrying a long stock tilted up, iron
    banded; at its front a wooden bow frame with two rope torsion skeins
    and great blue-steel arms swept back to brass tips, the string drawn
    back to the nock; an oversized bolt loaded: a pale shaft, a big steel
    head, the team's fletching; a winch with crank handles at the back and
    a tall swallow-tailed team pennant.
  magic_cannon: an arcane field cannon: two huge iron-tyred wheels, the
    team's painted carriage cheeks edged in brass, a trail to the ground; a
    fat brass barrel (its breech half painted in the team's colour) with
    glowing cyan rune rings and a glowing bore, raised a little, and on its
    breech a brass cage holding a big glowing cyan crystal core, two small
    shards floating beside it.
"""
import math

from mathutils import Matrix, Vector

import geo
from beasts import _grow
from geo import HARD, SMOOTH
from palette import row
from parts import seg

SIEGE_SCALE = 1.15


def _cyl_x(x0, x1, r, y, z, swatch, lod, segs=(16, 10)):
	"""A capped cylinder along X."""
	return geo.tube([(x0, y, z), (x1, y, z)], [r, r], seg(lod, *segs), row(swatch), sharp=SMOOTH,
			cap_start=row(swatch), cap_end=row(swatch))


def _cyl(a, b, r, swatch, lod, segs=(14, 8)):
	return geo.tube([a, b], [r, r], seg(lod, *segs), row(swatch), sharp=SMOOTH, cap_start=row(swatch),
			cap_end=row(swatch))


def _beam(a, b, w, h, swatch, bevel=0.012):
	"""A box beam from `a` to `b`, `w` wide and `h` deep (its top kept up)."""
	a, b = Vector(a), Vector(b)
	bm = geo.box(w, h, (b - a).length, row(swatch), sharp=HARD, bevel=bevel)
	return geo.transform(bm, geo.frame((a + b) * 0.5, b - a, (0.0, 0.0, 1.0)))


def _ring(r, z, half, swatch, lod, proud=0.035):
	"""A raised band round local Z at `z` (a barrel ring)."""
	return geo.lathe([(r - 0.01, z - half), (r + proud, z - half * 0.8), (r + proud, z + half * 0.8),
			(r - 0.01, z + half)], seg(lod, 20, 12), row(swatch), sharp=40)


def _wheel(lod, x, y, z, r, w, side, spokes=6, segs=(20, 12)):
	"""A chunky toy wheel along X: a wooden disc in a blackened iron tyre, a
	brass hub boss, raised spoke ribs on the outer face (LOD1 keeps them,
	unbevelled, so the spokes don't pop in and out at the LOD switch)."""
	bm = geo.new_bm()
	geo.merge(bm, _cyl_x(x - w * 0.5, x + w * 0.5, r, y, z, "plate_dark", lod, segs))
	geo.merge(bm, _cyl_x(x - w * 0.5 - 0.02, x + w * 0.5 + 0.02, r - 0.07, y, z, "wood", lod, segs))
	geo.merge(bm, _cyl_x(x - w * 0.5 - 0.09, x + w * 0.5 + 0.09, r * 0.28, y, z, "brass", lod, (12, 8)))
	cap = geo.ellipsoid(0.04 + r * 0.06, r * 0.16, r * 0.16, seg(lod, 10, 6), seg(lod, 5, 3), row("brass"))
	geo.translate(cap, (x + side * (w * 0.5 + 0.09), y, z))
	geo.merge(bm, cap)
	face = x + side * (w * 0.5 + 0.03)
	for k in range(spokes):
		a = 2.0 * math.pi * k / spokes
		d = Vector((0.0, math.cos(a), math.sin(a)))
		mid = Vector((face, y, z)) + d * (r * 0.28 + (r - 0.07 - r * 0.28) * 0.5)
		rib = geo.box(0.07, 0.03, r - 0.07 - r * 0.28, row("wood_light"), sharp=HARD, bevel=0.008 if lod == 0 else 0.0)
		geo.merge(bm, rib, geo.frame(mid, d, (1.0, 0.0, 0.0)))
	return bm


def _pennant(lod, x, y, z_base, z_top):
	"""A tall pole with a brass finial and a swallow-tailed team pennant
	streaming back, turned a little so it never shows only its edge."""
	bm = geo.new_bm()
	geo.merge(bm, _cyl((x, y, z_base), (x, y, z_top), 0.035, "wood", lod, (8, 6)))
	knob = geo.ellipsoid(0.065, 0.065, 0.065, seg(lod, 10, 6), seg(lod, 5, 3), row("brass"))
	geo.translate(knob, (x, y, z_top + 0.04))
	geo.merge(bm, knob)
	flag = geo.plate([(0.0, 0.0), (0.80, -0.03), (0.56, -0.24), (0.80, -0.46), (0.0, -0.44)], 0.03,
			row("team_cloth"), row("team_cloth"), row("team_cloth_dark"), sharp=40, bend=0.12)
	geo.rotate(flag, 90.0, 'Z')
	geo.rotate(flag, -28.0, 'Z')
	geo.translate(flag, (x, y, z_top - 0.06))
	geo.merge(bm, flag)
	return bm


# --- ballista -----------------------------------------------------------------

## The upper works (stock, bow, bolt) tilt nose-up round this point.
BALLISTA_PIVOT = Vector((0.0, -0.05, 1.42))
BALLISTA_TILT = 6.0


def _ballista_upper(lod):
	bm = geo.new_bm()
	# The stock: a long wooden rail, iron banded.
	geo.merge(bm, _beam((0.0, 1.20, 1.56), (0.0, -1.30, 1.56), 0.34, 0.20, "wood"))
	for y in (-1.10, -0.35, 0.40, 1.00):
		geo.merge(bm, _beam((0.0, y + 0.05, 1.56), (0.0, y - 0.05, 1.56), 0.37, 0.23, "plate_dark",
				0.006 if lod == 0 else 0.0))
	# The bow frame and its two rope torsion skeins with brass washers.
	frame = geo.box(0.92, 0.26, 0.44, row("wood"), sharp=HARD, bevel=0.03)
	geo.translate(frame, (0.0, -0.98, 1.58))
	geo.merge(bm, frame)
	plate = geo.box(0.50, 0.04, 0.30, row("team_paint"), sharp=HARD, bevel=0.012)
	geo.translate(plate, (0.0, -1.12, 1.58))
	geo.merge(bm, plate)
	for side in (-1.0, 1.0):
		geo.merge(bm, _cyl((side * 0.31, -0.98, 1.24), (side * 0.31, -0.98, 1.92), 0.10, "string", lod, (10, 6)))
		for z in (1.26, 1.90):
			geo.merge(bm, _cyl((side * 0.31, -0.98, z - 0.03), (side * 0.31, -0.98, z + 0.03), 0.135, "brass", lod,
					(10, 6)))
		# The great arms, swept back to brass tips, and the string drawn back.
		arm = geo.tube([(side * 0.36, -1.00, 1.58), (side * 0.80, -0.96, 1.60), (side * 1.20, -0.78, 1.62),
				(side * 1.48, -0.48, 1.64)], [0.090, 0.078, 0.062, 0.048], seg(lod, 10, 6), row("steel"),
				sharp=SMOOTH, flatten=0.75, cap_start=row("steel"))
		geo.merge(bm, arm)
		tip = geo.ellipsoid(0.075, 0.075, 0.075, seg(lod, 10, 6), seg(lod, 5, 3), row("brass"))
		geo.translate(tip, (side * 1.50, -0.46, 1.64))
		geo.merge(bm, tip)
		geo.merge(bm, geo.tube([(side * 1.50, -0.46, 1.64), (0.0, 0.62, 1.74)], [0.020, 0.020], 6, row("string"),
				sharp=SMOOTH))
	# The bolt: a pale shaft, a big steel head, the team's fletching.
	geo.merge(bm, geo.tube([(0.0, 0.64, 1.74), (0.0, -1.86, 1.74)], [0.072, 0.072], seg(lod, 10, 6),
			row("wood_light"), sharp=SMOOTH, cap_start=row("wood_light")))
	geo.merge(bm, _cyl((0.0, -1.80, 1.74), (0.0, -1.94, 1.74), 0.095, "plate_dark", lod, (10, 6)))
	head = geo.lathe([(0.17, 0.0), (0.12, 0.20), (0.0, 0.50)], 4, row("blade"), sharp=30, phase=0.0,
			cap_start=row("blade"))
	geo.merge(bm, head, geo.frame((0.0, -1.92, 1.74), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
	for angle in (0.0, 90.0, -90.0):
		vane = geo.plate([(0.0, 0.0), (0.50, 0.0), (0.40, 0.23), (0.04, 0.23)], 0.026, row("team_cloth"),
				sharp=40)
		geo.rotate(vane, 90.0, 'Z')
		geo.rotate(vane, angle, 'Y')
		geo.translate(vane, (0.0, 0.14, 1.74))
		geo.merge(bm, vane)
	return geo.transform(bm, Matrix.Translation(BALLISTA_PIVOT) @ Matrix.Rotation(math.radians(-BALLISTA_TILT), 4, 'X')
			@ Matrix.Translation(-BALLISTA_PIVOT))


def ballista(lod):
	bm = geo.new_bm()
	# The chassis, on three small wheels a side.
	chassis = geo.box(1.24, 2.50, 0.42, row("wood"), sharp=HARD, bevel=0.035)
	geo.translate(chassis, (0.0, 0.10, 0.84))
	geo.merge(bm, chassis)
	for y in (-0.80, 0.10, 1.00):
		geo.merge(bm, _cyl_x(-0.80, 0.80, 0.07, y, 0.40, "plate_dark", lod, (8, 6)))
		for side in (-1.0, 1.0):
			geo.merge(bm, _wheel(lod, side * 0.75, y, 0.40, 0.40, 0.20, side, segs=(14, 9)))
	# The team's painted side boards, rising into a gunwale, brass trimmed.
	for side in (-1.0, 1.0):
		board = geo.box(0.05, 2.36, 0.40, row("team_paint"), sharp=HARD, bevel=0.015)
		geo.translate(board, (side * 0.635, 0.10, 0.96))
		geo.merge(bm, board)
		geo.merge(bm, geo.tube([(side * 0.64, -1.10, 1.17), (side * 0.64, 1.30, 1.17)], [0.026, 0.026],
				seg(lod, 8, 5), row("brass"), sharp=SMOOTH, cap_start=row("brass"), cap_end=row("brass")))
		for y in (-1.08, 1.28):
			corner = geo.box(0.08, 0.10, 0.42, row("brass"), sharp=HARD, bevel=0.012)
			geo.translate(corner, (side * 0.64, y, 0.96))
			geo.merge(bm, corner)
	front = geo.box(1.30, 0.05, 0.40, row("team_paint"), sharp=HARD, bevel=0.015)
	geo.translate(front, (0.0, -1.15, 0.96))
	geo.merge(bm, front)
	# The turret drum and cradle the upper works turn on.
	geo.merge(bm, _cyl((0.0, -0.05, 1.04), (0.0, -0.05, 1.26), 0.34, "plate_dark", lod, (16, 10)))
	geo.merge(bm, _cyl((0.0, -0.05, 1.20), (0.0, -0.05, 1.25), 0.37, "brass", lod, (16, 10)))
	cradle = geo.box(0.46, 0.66, 0.24, row("wood"), sharp=HARD, bevel=0.025)
	geo.translate(cradle, (0.0, -0.05, 1.36))
	geo.merge(bm, cradle)
	geo.merge(bm, _ballista_upper(lod))
	# The winch at the back: a rope drum between two cheeks, crank handles.
	for side in (-1.0, 1.0):
		cheek = geo.box(0.08, 0.26, 0.40, row("wood"), sharp=HARD, bevel=0.015)
		geo.translate(cheek, (side * 0.42, 1.02, 1.22))
		geo.merge(bm, cheek)
		geo.merge(bm, _beam((side * 0.52, 1.02, 1.36), (side * 0.52, 1.02, 1.06), 0.04, 0.05, "steel", 0.008))
		geo.merge(bm, _cyl((side * 0.50, 1.02, 1.07), (side * 0.62, 1.02, 1.07), 0.03, "leather_dark", lod, (6, 4)))
	geo.merge(bm, _cyl_x(-0.50, 0.50, 0.035, 1.02, 1.36, "steel", lod, (8, 6)))
	geo.merge(bm, _cyl_x(-0.38, 0.38, 0.13, 1.02, 1.36, "wood", lod, (12, 8)))
	geo.merge(bm, _cyl_x(-0.24, 0.24, 0.15, 1.02, 1.36, "string", lod, (12, 8)))
	geo.merge(bm, _pennant(lod, 0.52, 1.24, 1.10, 2.62))
	return _grow(bm, 0.0, SIEGE_SCALE)


# --- magic cannon -------------------------------------------------------------

CANNON_TRUNNION = Vector((0.0, 0.02, 1.28))
CANNON_ELEVATION = 10.0


def _cannon_barrel(lod):
	"""Built along local +Z (the bore), local +Y up, trunnion at the origin."""
	bm = geo.new_bm()
	profile = [(0.0, -1.00), (0.24, -0.99), (0.37, -0.90), (0.39, -0.72), (0.38, -0.02), (0.37, 0.02),
			(0.31, 0.95), (0.29, 1.32), (0.37, 1.42), (0.41, 1.60), (0.36, 1.70), (0.23, 1.70), (0.21, 1.50)]
	paint = ["brass", "brass", "team_paint", "team_paint", "brass", "brass", "brass", "brass", "brass", "brass",
			"brass", "brass"]
	barrel = geo.lathe(profile, seg(lod, 22, 12), row("brass"), sharp=40, cap_end=row("arcane"),
			ring_swatches=[row(s) for s in paint])
	geo.merge(bm, barrel)
	knob = geo.ellipsoid(0.15, 0.15, 0.15, seg(lod, 12, 8), seg(lod, 6, 4), row("brass"))
	geo.translate(knob, (0.0, 0.0, -1.12))
	geo.merge(bm, knob)
	# Rune rings: brass at the breech and muzzle, glowing cyan between.
	geo.merge(bm, _ring(0.39, -0.70, 0.05, "brass", lod))
	geo.merge(bm, _ring(0.38, 0.00, 0.07, "arcane", lod, proud=0.045))
	geo.merge(bm, _ring(0.335, 0.55, 0.06, "arcane", lod, proud=0.045))
	geo.merge(bm, _ring(0.30, 1.22, 0.05, "brass", lod))
	# Glowing rune marks on the brass between the rings (kept at LOD1 too:
	# near-only parts pop at the LOD switch).
	for k in range(4):
		a = math.pi * 0.5 * k + math.pi * 0.25
		n = Vector((math.cos(a), math.sin(a), 0.0))
		rune = geo.plate([(0.0, -0.07), (0.05, 0.0), (0.0, 0.07), (-0.05, 0.0)], 0.02, row("arcane"), sharp=40)
		geo.merge(bm, rune, geo.orient(n * 0.36 + Vector((0.0, 0.0, 0.28)), n, (0.0, 0.0, 1.0)))
	# The crystal core on the breech, in a brass cage.
	seat = Vector((0.0, 0.38, -0.36))
	cup = geo.lathe([(0.10, 0.0), (0.22, 0.04), (0.24, 0.12), (0.20, 0.16)], seg(lod, 14, 8), row("brass"), sharp=40,
			cap_start=row("brass"))
	geo.merge(bm, cup, geo.frame(seat - Vector((0.0, 0.04, 0.0)), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)))
	core = seat + Vector((0.0, 0.48, 0.0))
	crystal = geo.lathe([(0.0, -0.36), (0.22, 0.0), (0.0, 0.40)], 6, row("crystal"), sharp=30, phase=0.0)
	geo.merge(bm, crystal, geo.frame(core, (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)))
	for k in range(4):
		a = math.pi * 0.5 * k + math.pi * 0.25
		out = Vector((math.cos(a), 0.0, math.sin(a)))
		prong = geo.tube([seat + Vector((0.0, 0.12, 0.0)) + out * 0.21, core - Vector((0.0, 0.10, 0.0)) + out * 0.27,
				core + Vector((0.0, 0.16, 0.0)) + out * 0.16], [0.030, 0.026, 0.0], seg(lod, 6, 4), row("brass"),
				sharp=SMOOTH)
		geo.merge(bm, prong)
	geo.merge(bm, _ring(0.10, 0.0, 0.03, "brass", lod), geo.frame(core + Vector((0.0, 0.30, 0.0)), (0.0, 1.0, 0.0),
			(0.0, 0.0, 1.0)))
	for side in (-1.0, 1.0):
		shard = geo.lathe([(0.0, -0.10), (0.06, 0.0), (0.0, 0.12)], 5, row("crystal"), sharp=30, phase=0.0)
		geo.merge(bm, shard, geo.frame(core + Vector((side * 0.46, 0.10, 0.05 * side)), (side * 0.3, 1.0, 0.0),
				(0.0, 0.0, 1.0)))
	return bm


def magic_cannon(lod):
	bm = geo.new_bm()
	# Two huge wheels on an iron axle.
	geo.merge(bm, _cyl_x(-0.95, 0.95, 0.09, 0.10, 0.72, "plate_dark", lod, (10, 6)))
	for side in (-1.0, 1.0):
		geo.merge(bm, _wheel(lod, side * 0.80, 0.10, 0.72, 0.72, 0.22, side, spokes=8))
	# The team's painted carriage cheeks edged in brass, a transom, a trail.
	for side in (-1.0, 1.0):
		cheek = geo.plate([(-0.66, 0.50), (-0.66, 1.08), (-0.25, 1.30), (0.42, 1.30), (0.78, 1.00), (1.05, 0.62),
				(0.78, 0.50)], 0.09, row("team_paint"), row("team_paint"), row("brass"), sharp=40)
		geo.rotate(cheek, 90.0, 'Z')
		geo.translate(cheek, (side * 0.48, 0.0, 0.0))
		geo.merge(bm, cheek)
		geo.merge(bm, _cyl_x(side * 0.38, side * 0.60, 0.13, CANNON_TRUNNION.y, CANNON_TRUNNION.z, "brass", lod,
				(12, 8)))
	geo.merge(bm, _beam((0.0, -0.40, 0.62), (0.0, 0.30, 0.62), 0.90, 0.20, "wood"))
	geo.merge(bm, _beam((0.0, 0.55, 0.68), (0.0, 2.00, 0.10), 0.38, 0.22, "wood"))
	spade = geo.box(0.52, 0.10, 0.22, row("plate_dark"), sharp=HARD, bevel=0.015)
	geo.translate(spade, (0.0, 2.02, 0.12))
	geo.merge(bm, spade)
	for y, z in ((1.05, 0.50), (1.55, 0.30)):
		geo.merge(bm, _beam((0.0, y - 0.04, z + 0.016), (0.0, y + 0.04, z - 0.016), 0.41, 0.25, "plate_dark",
				0.006 if lod == 0 else 0.0))
	# The barrel, raised a little, with its crystal core.
	c, s = math.cos(math.radians(CANNON_ELEVATION)), math.sin(math.radians(CANNON_ELEVATION))
	geo.merge(bm, _cannon_barrel(lod), geo.frame(CANNON_TRUNNION, (0.0, -c, s), (0.0, s, c)))
	return _grow(bm, 0.0, SIEGE_SCALE)
