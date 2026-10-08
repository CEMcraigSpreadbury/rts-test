"""Bestiary beasts (scenes/units/beasts): each race's two great creatures,
drawn as big chunky chibi toys. They are race units, so each carries the
team's colour on its harness, and each is built on its race's palette:

  griffin (Aldmere): an eagle-headed lion, wings raised high over its back,
    a white feathered head, neck and chest ruff, a big hooked golden beak,
    tawny lion haunches and a tufted tail, yellow scaled eagle forelegs with
    dark talons; the team's saddle cloth with a brass edge on its back and
    the team's breast collar with a brass boss.
  sand_worm (Gnolls): a fat segmented worm rearing out of its own coil, a
    round head bent forward over a ringed maw of bone teeth, bone spikes down
    its back, the team's collar band under the head and a tall gnoll war
    banner in the team's colour with a horned skull, lashed to its back.
  manticore (Aldmere): a low, prowling russet-orange lion with a round,
    near-human face in a huge spiky dark amber mane, ivory ram horns, half-
    spread charcoal bat wings with dusky violet membranes leaning back to
    the sky, and a black scorpion tail
    arched over its back to an ivory stinger; the team's saddle cloth and
    two team wraps round the tail.
  kitsune (Dark Elves): a slender silver-white fox on black-violet socks,
    tall ears lined in black-violet, violet markings and a silver circlet,
    and a fan of seven fat tails, each tipped in a violet foxfire flame;
    the team's collar and chest bib with a silver bell, a team saddle cloth.
  wind_tiger (Dark Elves): a heavy, low white tiger in black stripes, a big
    round head with white cheek ruffs, mint wind gusts streaming back from
    its shoulders and haunches, wind swirls round its paws and a vortex at
    its tail tip; the team's collar with a long scarf streaming back, a
    team saddle cloth edged in silver under a black-violet saddle.
  skeleton_dragon (Gnolls): a bone drake (the Bestiary one; the monster is
    a bigger, separate figure): a vertebra spine, an open rib cage with a
    green soul fire inside, a horned skull with green eye sparks and ochre
    war paint, torn grey hide wings raised high; a hide saddle on the
    team's blanket with ochre dags, team rags tied to its horns, a bead
    necklace and a skull trophy.

Beasts are MUCH bigger than infantry and cavalry (see docs/unit-figures.md,
"Size"): each is designed at about a horse's scale, then grown round the
ground under its middle (`_grow`) by its *_SCALE. Built in a figure's
standing space (the ground at Body.base_height, facing -Y), like animals.py.
Colours: the race palettes' Bestiary rows (palette.py).
"""
import math

from mathutils import Matrix, Vector

import animals
import geo
import gnoll
import star_wanderers
from geo import SMOOTH
from palette import row
from parts import seg


def _grow(bm, g, k):
	geo.transform(bm, Matrix.Translation((0.0, 0.0, g)) @ Matrix.Scale(k, 4) @ Matrix.Translation((0.0, 0.0, -g)))
	return bm


def _band(radius, half, lod, segments=(14, 9)):
	"""A cloth band (a collar or girth) round local Z, team-coloured."""
	return geo.lathe([(radius - 0.012, -half), (radius, -half * 0.6), (radius + 0.004, 0.0), (radius, half * 0.6),
			(radius - 0.012, half)], seg(lod, *segments), sharp=50,
			ring_swatches=[row("team_cloth_dark"), row("team_cloth"), row("team_cloth"), row("team_cloth_dark")])


def _cone(radius, length, swatch, segments=5):
	return geo.lathe([(radius, 0.0), (radius * 0.7, length * 0.45), (0.0, length)], segments, row(swatch), sharp=40,
			phase=0.0, cap_start=row(swatch))


# --- griffin -----------------------------------------------------------------

GRIFFIN_SCALE = 1.8
GRIFFIN_SPINE = [(-0.300, 0.400, 0.020), (-0.260, 0.410, 0.150), (-0.140, 0.420, 0.185), (0.020, 0.400, 0.175),
		(0.160, 0.385, 0.165), (0.260, 0.380, 0.135), (0.310, 0.380, 0.0)]
GRIFFIN_HEAD = Vector((0.0, -0.370, 0.780))


def _griffin_head(lod, g):
	H = GRIFFIN_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.150, 0.145, 0.140, seg(lod, 14, 9), seg(lod, 7, 5), row("fletch"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	# Cheek feathers, a little wider than the crown.
	for side in (-1.0, 1.0):
		cheek = geo.ellipsoid(0.070, 0.080, 0.070, seg(lod, 9, 6), 4, row("fletch"), sharp=SMOOTH)
		geo.translate(cheek, H + Vector((side * 0.100, 0.030, -0.060)))
		geo.merge(bm, cheek)
	# A big hooked golden beak: the upper hooks down over a short lower.
	upper = geo.tube([H + Vector((0.0, -0.100, 0.010)), H + Vector((0.0, -0.185, 0.000)),
			H + Vector((0.0, -0.240, -0.040)), H + Vector((0.0, -0.236, -0.100))], [0.066, 0.050, 0.030, 0.0],
			seg(lod, 10, 7), row("ochre"), sharp=SMOOTH, flatten=1.25)
	geo.merge(bm, upper)
	lower = geo.tube([H + Vector((0.0, -0.100, -0.050)), H + Vector((0.0, -0.170, -0.066)),
			H + Vector((0.0, -0.200, -0.080))], [0.046, 0.030, 0.0], seg(lod, 8, 6), row("ochre"), sharp=SMOOTH)
	geo.merge(bm, lower)
	# Swept-back ear tufts and a short crest.
	for side in (-1.0, 1.0):
		tuft = geo.tube([H + Vector((side * 0.080, 0.040, 0.090)), H + Vector((side * 0.120, 0.150, 0.150)),
				H + Vector((side * 0.140, 0.240, 0.230))], [0.050, 0.034, 0.0], seg(lod, 7, 5), row("fletch"),
				sharp=SMOOTH, flatten=0.45)
		geo.merge(bm, tuft)
	for k, (dy, dz) in enumerate(((0.060, 0.130), (0.130, 0.110))):
		crest = geo.tube([H + Vector((0.0, dy, dz)), H + Vector((0.0, dy + 0.110, dz + 0.060))], [0.040, 0.0],
				seg(lod, 6, 4), row("fur_red"), sharp=SMOOTH, flatten=0.45, up=(1.0, 0.0, 0.0))
		geo.merge(bm, crest)
	geo.merge(bm, animals._eyes(lod, skull, H, 0.088, 0.040, rx=0.032, ry=0.040))
	if lod == 0:
		# A dark brow over each eye, so it reads fierce rather than owlish.
		for side in (-1.0, 1.0):
			brow = geo.tube([H + Vector((side * 0.050, -0.128, 0.090)), H + Vector((side * 0.125, -0.100, 0.100))],
					[0.016, 0.010], 5, row("fur_red"), sharp=SMOOTH)
			geo.merge(bm, brow)
	return bm


def _wing_matrix(side, root, span, lead):
	"""Places a wing built with its span along +X and its leading edge up
	(+Z) at `root`, the span turned along `span` (x mirrored by `side`)."""
	span = Vector((side * span[0], span[1], span[2])).normalized()
	lead = Vector(lead)
	lead = (lead - span * lead.dot(span)).normalized()
	thick = lead.cross(span).normalized()
	return Matrix((
		(span.x, thick.x, lead.x, root[0]),
		(span.y, thick.y, lead.y, root[1]),
		(span.z, thick.z, lead.z, root[2]),
		(0.0, 0.0, 0.0, 1.0),
	))


def _feather(length, width, swatch, round_tip=False, bend=0.0):
	"""One feather along +X in the XZ plane: narrow at the quill, widest a
	third of the way out, tapering to a point (or a rounded tip)."""
	L, w = length, width
	if round_tip:
		outline = [(0.0, -w * 0.30), (L * 0.5, -w * 0.5), (L * 0.88, -w * 0.32), (L, 0.0), (L * 0.88, w * 0.32),
				(L * 0.5, w * 0.5), (0.0, w * 0.30)]
	else:
		outline = [(0.0, -w * 0.20), (L * 0.35, -w * 0.5), (L * 0.74, -w * 0.40), (L, 0.0), (L * 0.74, w * 0.40),
				(L * 0.35, w * 0.5), (0.0, w * 0.20)]
	return geo.plate(outline, 0.014, row(swatch), sharp=40, bend=bend)


def _feather_row(bm, count, x0, x1, z0, z1, a0, a1, l0, l1, width, swatch, depth, step=0.0, round_tip=False,
		bend=0.0):
	"""A row of overlapping feathers along the wing, each turned from `a0`
	to `a1` degrees (90 hangs straight back off the leading edge) and set
	`step` further forward than the last, so they lie like shingles."""
	for i in range(count):
		t = i / max(count - 1, 1)
		f = _feather(l0 + (l1 - l0) * t, width, swatch, round_tip, bend)
		geo.rotate(f, a0 + (a1 - a0) * t, 'Y')
		geo.translate(f, (x0 + (x1 - x0) * t, depth - step * i, z0 + (z1 - z0) * t))
		geo.merge(bm, f)


def _wing(lod, side, root):
	"""A raised wing in layers: a leading-edge arm, two rows of short tawny
	coverts over brown secondaries, and long brown primaries fanned out from
	the wrist, each feather tapered and overlapping the next. Built with
	its span along +X and its leading edge up (+Z), then turned up, out and
	back from `root`."""
	bm = geo.new_bm()
	arm = geo.tube([(0.0, 0.0, 0.0), (0.160, 0.0, 0.080), (0.330, 0.0, 0.105), (0.540, 0.0, 0.070)],
			[0.046, 0.040, 0.030, 0.012], seg(lod, 8, 5), row("fur"), sharp=SMOOTH, flatten=0.7, up=(0.0, 1.0, 0.0))
	geo.merge(bm, arm)
	# Primaries: long, fanned from the wrist out toward the tip.
	_feather_row(bm, seg(lod, 6, 4), 0.300, 0.500, 0.070, 0.085, 92.0, 30.0, 0.300, 0.360, 0.090, "fur_red",
			0.010, step=0.004, bend=0.18)
	# Secondaries: shorter, hanging straight back off the inner arm.
	_feather_row(bm, seg(lod, 6, 4), 0.030, 0.290, 0.020, 0.070, 104.0, 94.0, 0.250, 0.290, 0.095, "fur_red",
			0.004, step=0.003, bend=0.12)
	# Greater and lesser coverts over the feather roots, tawny.
	_feather_row(bm, seg(lod, 7, 5), 0.010, 0.470, 0.030, 0.090, 98.0, 58.0, 0.150, 0.130, 0.090, "fur",
			-0.012, step=0.002, round_tip=True)
	if lod == 0:
		_feather_row(bm, 6, 0.0, 0.380, 0.050, 0.100, 96.0, 70.0, 0.085, 0.075, 0.070, "fur", -0.024,
				step=0.002, round_tip=True)
	geo.transform(bm, _wing_matrix(side, root, (0.62, 0.36, 0.70), (0.0, -1.0, 0.25)))
	return bm


def _saddle_cloth(lod, cz, y0=-0.030, y1=0.250, r=0.200, drop=0.105, edge="brass"):
	"""The team's cloth over a beast's back (a tube cut off below `drop`
	under its crown at height `cz`), lined, with an `edge` trim along each
	side and three dags hanging under it."""
	bm = geo.new_bm()
	cloth = geo.tube([(0.0, y0, cz), (0.0, (y0 + y1) * 0.5, cz), (0.0, y1, cz - 0.004)], [r, r + 0.002, r * 0.93],
			seg(lod, 16, 10), row("team_cloth"), sharp=SMOOTH)
	geo.delete_faces(cloth, lambda f: f.calc_center_median().z < cz - drop)
	geo.merge(bm, cloth)
	geo.merge(bm, geo.flipped(cloth, row("team_cloth_dark"), inset=0.008))
	edge_x = math.sqrt(max((r + 0.001) ** 2 - drop ** 2, 0.0))
	for side in (-1.0, 1.0):
		trim = geo.tube([(side * edge_x, y0, cz - drop + 0.005), (side * edge_x, y1, cz - drop + 0.005)],
				[0.014, 0.014], seg(lod, 6, 4), row(edge), sharp=40)
		geo.merge(bm, trim)
		if lod == 0:
			for k in range(3):
				y = y0 + (y1 - y0) * (0.15 + 0.35 * k)
				dag = geo.plate([(-0.040, 0.0), (0.040, 0.0), (0.0, -0.060)], 0.010, row("team_cloth"), sharp=40)
				geo.rotate(dag, 90.0, 'Z')
				geo.translate(dag, (side * (edge_x + 0.006), y, cz - drop + 0.005))
				geo.merge(bm, dag)
	return bm


def _griffin_team(lod, g):
	"""The team's saddle cloth over the back with a brass edge and a leather
	saddle, and the team's breast collar with a brass boss."""
	bm = geo.new_bm()
	cz = g + 0.400
	geo.merge(bm, _saddle_cloth(lod, cz))
	saddle = geo.ellipsoid(0.105, 0.120, 0.040, seg(lod, 10, 7), 4, row("leather"), sharp=SMOOTH)
	geo.translate(saddle, (0.0, 0.110, cz + 0.200))
	geo.merge(bm, saddle)
	for y, h in ((0.010, 0.050), (0.215, 0.040)):
		lip = geo.ellipsoid(0.080, 0.022, h, seg(lod, 8, 6), 3, row("leather_dark"), sharp=SMOOTH)
		geo.translate(lip, (0.0, y, cz + 0.215))
		geo.merge(bm, lip)
	at = Vector((0.0, -0.250, g + 0.470))
	axis = Vector((0.0, -0.80, 0.60)).normalized()
	geo.merge(bm, _band(0.150, 0.034, lod), geo.frame(at, axis, (0.0, 0.0, 1.0)))
	boss = geo.lathe([(0.046, 0.0), (0.040, 0.018), (0.0, 0.026)], seg(lod, 10, 7), row("brass"), sharp=40, phase=0.0)
	geo.merge(bm, boss, geo.frame(at + Vector((0.0, -0.140, -0.080)), (0.0, -0.75, -0.66), (0.0, 0.0, 1.0)))
	return bm


def griffin(b, lod):
	g = b.base_height
	bm = animals._body(GRIFFIN_SPINE, lod, "fur", g=g)
	# The white feathered chest ruff over the front of the lion body.
	ruff = geo.ellipsoid(0.175, 0.160, 0.195, seg(lod, 12, 8), seg(lod, 6, 4), row("fletch"), sharp=SMOOTH)
	geo.translate(ruff, (0.0, -0.230, g + 0.430))
	geo.merge(bm, ruff)
	if lod == 0:
		for k in range(7):
			a = math.radians(-150.0 + 50.0 * k)
			tip = geo.lathe([(0.040, 0.0), (0.026, 0.040), (0.0, 0.070)], 5, row("fletch"), sharp=40, phase=0.0,
					sy=0.45)
			base = Vector((math.cos(a) * 0.150, -0.110, g + 0.430 + math.sin(a) * 0.170))
			geo.merge(bm, tip, geo.frame(base, (math.cos(a) * 0.3, 1.0, math.sin(a) * 0.3), (0.0, 0.0, 1.0)))
	belly = geo.ellipsoid(0.130, 0.220, 0.090, seg(lod, 10, 7), 4, row("fur_light"), sharp=SMOOTH)
	geo.translate(belly, (0.0, 0.040, g + 0.270))
	geo.merge(bm, belly)
	neck = geo.tube([Vector((0.0, -0.220, g + 0.480)), Vector((0.0, -0.300, g + 0.610)),
			Vector((0.0, -0.345, g + 0.710))], [0.135, 0.115, 0.100], seg(lod, 12, 8), row("fletch"), sharp=SMOOTH)
	geo.merge(bm, neck)
	segs = seg(lod, 9, 6)
	for side in (-1.0, 1.0):
		x = side * 0.115
		# Lion hind legs under round haunches.
		haunch = geo.ellipsoid(0.095, 0.150, 0.150, seg(lod, 10, 7), 5, row("fur"), sharp=SMOOTH)
		geo.translate(haunch, (side * 0.125, 0.200, g + 0.360))
		geo.merge(bm, haunch)
		leg = geo.tube([Vector((x * 1.1, 0.230, g + 0.300)), Vector((x * 1.12, 0.270, g + 0.150)),
				Vector((x * 1.1, 0.210, g + 0.050))], [0.075, 0.056, 0.050], segs, row("fur"), sharp=SMOOTH)
		geo.merge(bm, leg)
		paw = geo.ellipsoid(0.060, 0.080, 0.040, seg(lod, 9, 6), 3, row("fur_light"), sharp=SMOOTH, squash_bottom=0.3)
		geo.translate(paw, (x * 1.1, 0.180, g + 0.025))
		geo.merge(bm, paw)
		# Eagle forelegs: feathered thighs, scaled yellow shins, talons.
		thigh = geo.tube([Vector((x, -0.210, g + 0.350)), Vector((x * 1.04, -0.230, g + 0.260)),
				Vector((x * 1.04, -0.245, g + 0.190))], [0.078, 0.066, 0.0], segs, row("fletch"), sharp=SMOOTH)
		geo.merge(bm, thigh)
		ankle = Vector((x * 1.04, -0.265, g + 0.035))
		shin = geo.tube([Vector((x * 1.04, -0.245, g + 0.220)), ankle], [0.036, 0.032], segs, row("ochre"),
				sharp=SMOOTH)
		geo.merge(bm, shin)
		for k in (-1.0, 0.0, 1.0, None):
			if k is None:
				d = Vector((0.0, 1.0, -0.15)).normalized()
				length = 0.060
			else:
				d = Vector((math.sin(math.radians(28.0 * k)), -math.cos(math.radians(28.0 * k)), -0.12)).normalized()
				length = 0.095
			end = ankle + d * length
			toe = geo.tube([ankle, end], [0.024, 0.016], seg(lod, 6, 4), row("ochre"), sharp=SMOOTH,
					cap_end=row("ochre"))
			geo.merge(bm, toe)
			claw = _cone(0.016, 0.045, "nose", seg(lod, 5, 4))
			geo.merge(bm, claw, geo.frame(end - d * 0.006, (d.x, d.y, -0.6), (0.0, 0.0, 1.0)))
	# A lion's tail curling up behind, a dark tuft at its end.
	tail = geo.tube([Vector((0.0, 0.300, g + 0.420)), Vector((0.0, 0.420, g + 0.440)), Vector((0.0, 0.500, g + 0.530)),
			Vector((0.0, 0.520, g + 0.640))], [0.036, 0.030, 0.026, 0.022], seg(lod, 7, 5), row("fur"), sharp=SMOOTH)
	geo.merge(bm, tail)
	tuft = geo.ellipsoid(0.052, 0.052, 0.075, seg(lod, 8, 5), 4, row("fur_dark"), sharp=SMOOTH)
	geo.translate(tuft, (0.0, 0.515, g + 0.690))
	geo.merge(bm, tuft)
	for side in (-1.0, 1.0):
		geo.merge(bm, _wing(lod, side, Vector((side * 0.130, -0.090, g + 0.540))))
	geo.merge(bm, _griffin_team(lod, g))
	geo.merge(bm, _griffin_head(lod, g))
	return _grow(bm, g, GRIFFIN_SCALE)


# --- sand worm ---------------------------------------------------------------

WORM_SCALE = 2.0
## The worm's path, tail tip to the back of its head: (x, y, z, radius).
WORM_PATH = [(0.060, 0.500, 0.040, 0.030), (0.230, 0.420, 0.065, 0.075), (0.310, 0.240, 0.095, 0.110),
		(0.240, 0.070, 0.120, 0.135), (0.080, 0.010, 0.140, 0.150), (-0.040, 0.060, 0.220, 0.160),
		(-0.060, 0.100, 0.380, 0.165), (-0.030, 0.080, 0.540, 0.165), (0.0, 0.010, 0.670, 0.168),
		(0.0, -0.090, 0.740, 0.172)]
WORM_HEAD = Vector((0.0, -0.170, 0.740))
## The maw looks forward and down.
WORM_MAW = Vector((0.0, -0.80, -0.60)).normalized()


def _catmull(points, steps):
	"""A smooth curve through `points` (Vectors or floats), `steps` per span."""
	out = []
	n = len(points)
	for i in range(n - 1):
		p0 = points[max(i - 1, 0)]
		p1, p2 = points[i], points[i + 1]
		p3 = points[min(i + 2, n - 1)]
		for s in range(steps):
			t = s / steps
			t2, t3 = t * t, t * t * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(points[-1])
	return out


def _worm_curve(g):
	pts = _catmull([Vector((x, y, g + z)) for x, y, z, _r in WORM_PATH], 4)
	radii = _catmull([r for _x, _y, _z, r in WORM_PATH], 4)
	return pts, radii


def _worm_frame(pts, i):
	t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
	back = Vector((0.0, 0.8, 0.6))
	back = (back - t * back.dot(t)).normalized()
	return t, back


def _worm_body(lod, g):
	pts, radii = _worm_curve(g)
	# Ringed segments: two hide bands, then a narrow dark crease.
	bands = []
	rr = []
	for i in range(len(pts) - 1):
		bands.append(row("coat_dark") if i % 3 == 2 else row("coat"))
	for i, r in enumerate(radii):
		rr.append(r * (0.92 if i % 3 in (0, 2) and 0 < i < len(radii) - 1 else 1.0))
	body = geo.tube(pts, rr, seg(lod, 14, 9), sharp=SMOOTH, ring_swatches=bands, cap_start=row("coat"))
	bm = geo.new_bm()
	geo.merge(bm, body)
	# Bone spikes down its back.
	for i in range(3, len(pts) - 2, seg(lod, 3, 4)):
		t, back = _worm_frame(pts, i)
		r = rr[i]
		spike = _cone(0.040 * (0.6 + r / 0.17 * 0.6), 0.070 + r * 0.45, "bone", seg(lod, 6, 4))
		geo.merge(bm, spike, geo.frame(pts[i] + back * r * 0.85, back - t * 0.35, t))
	return bm


def _worm_head(lod, g):
	H = WORM_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.205, 0.200, 0.195, seg(lod, 14, 9), seg(lod, 7, 5), row("coat"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	# A heavy brow ridge in bone over the eyes.
	brow = geo.tube([H + Vector((-0.140, -0.110, 0.120)), H + Vector((0.0, -0.150, 0.150)),
			H + Vector((0.140, -0.110, 0.120))], [0.026, 0.034, 0.026], seg(lod, 7, 5), row("coat_dark"), sharp=SMOOTH,
			cap_start=row("coat_dark"), cap_end=row("coat_dark"))
	geo.merge(bm, brow)
	# The maw: a thick pink lip round a dark throat ringed with bone teeth.
	at = H + WORM_MAW * 0.150
	maw = geo.new_bm()
	geo.merge(maw, geo.lathe([(0.120, -0.040), (0.150, -0.005), (0.142, 0.030), (0.112, 0.040), (0.092, 0.018)],
			seg(lod, 14, 9), row("coat_grey"), sharp=SMOOTH))
	geo.merge(maw, geo.lathe([(0.092, 0.018), (0.070, -0.030), (0.0, -0.060)], seg(lod, 14, 9), row("mouth"),
			sharp=SMOOTH))
	for ring, (count, radius, size) in enumerate(((seg(lod, 10, 7), 0.098, 1.0), (seg(lod, 7, 0), 0.062, 0.75))):
		for k in range(count):
			a = 2.0 * math.pi * (k + 0.5 * ring) / count
			radial = Vector((math.cos(a), math.sin(a), 0.0))
			tooth = _cone(0.020 * size, 0.060 * size, "bone", 4)
			geo.merge(maw, tooth, geo.frame(radial * radius + Vector((0.0, 0.0, 0.020 - 0.025 * ring)),
					-radial + Vector((0.0, 0.0, 0.45)), (0.0, 0.0, 1.0)))
	geo.merge(bm, maw, geo.frame(at, WORM_MAW, (0.0, 0.0, 1.0)))
	geo.merge(bm, animals._eyes(lod, skull, H, 0.082, 0.072, rx=0.036, ry=0.044, cheek=0.030))
	return bm


def _worm_team(lod, g):
	"""The team's collar band under the head, and a gnoll war banner lashed
	to its back: a pole, a ragged flag in the team's colour, a horned skull."""
	pts, radii = _worm_curve(g)
	bm = geo.new_bm()
	i = len(pts) - 7
	t, back = _worm_frame(pts, i)
	geo.merge(bm, _band(radii[i] + 0.020, 0.040, lod), geo.frame(pts[i], t, back))
	if lod == 0:
		for k in range(5):
			a = 2.0 * math.pi * k / 5
			side = t.cross(back)
			d = (back * math.cos(a) + side * math.sin(a)).normalized()
			bead = geo.ellipsoid(0.016, 0.016, 0.016, 6, 4, row("ochre"), sharp=SMOOTH)
			geo.translate(bead, pts[i] + d * (radii[i] + 0.030) - t * 0.045)
			geo.merge(bm, bead)
	# The banner pole stands in a hide harness on the back of the column.
	j = len(pts) - 15
	t, back = _worm_frame(pts, j)
	harness = gnoll.recolour(_band(radii[j] + 0.012, 0.030, lod), "team_cloth", "leather")
	gnoll.recolour(harness, "team_cloth_dark", "leather_dark")
	geo.merge(bm, harness, geo.frame(pts[j], t, back))
	foot = pts[j] + back * (radii[j] + 0.010)
	tip = Vector((foot.x + 0.020, foot.y + 0.060, g + 1.120))
	pole = geo.tube([foot, tip], [0.018, 0.016], seg(lod, 6, 4), row("wood"), sharp=40)
	geo.merge(bm, pole)
	skull = gnoll.beast_skull(lod)
	geo.transform(skull, Matrix.Translation(tip + Vector((0.0, 0.0, 0.030))) @ Matrix.Scale(1.5, 4))
	geo.merge(bm, skull)
	bar = geo.tube([tip + Vector((-0.020, 0.0, -0.040)), tip + Vector((0.300, 0.0, -0.040))], [0.012, 0.012], 4,
			row("wood"), sharp=40)
	geo.merge(bm, bar)
	flag = geo.plate([(0.0, 0.0), (0.280, 0.0), (0.280, -0.300), (0.215, -0.240), (0.150, -0.330), (0.085, -0.250),
			(0.0, -0.310)], 0.012, row("team_cloth"), sharp=40, bend=-0.4)
	if lod == 0:
		for face in (-1.0, 1.0):
			mark = geo.plate([(0.110, -0.080), (0.170, -0.080), (0.140, -0.190)], 0.004, row("ochre"), sharp=40,
					bend=-0.4)
			geo.translate(mark, (0.0, face * 0.007, 0.0))
			geo.merge(flag, mark)
	geo.translate(flag, tip + Vector((0.0, 0.0, -0.045)))
	geo.merge(bm, flag)
	return bm


def sand_worm(b, lod):
	g = b.base_height
	bm = geo.new_bm()
	for piece in (_worm_body(lod, g), _worm_head(lod, g), _worm_team(lod, g)):
		geo.merge(bm, piece)
	return _grow(bm, g, WORM_SCALE)


# --- manticore ---------------------------------------------------------------

MANTICORE_SCALE = 1.75
MANTICORE_SPINE = [(-0.320, 0.360, 0.020), (-0.280, 0.370, 0.160), (-0.150, 0.380, 0.200), (0.020, 0.370, 0.190),
		(0.180, 0.360, 0.175), (0.280, 0.360, 0.140), (0.330, 0.360, 0.0)]
MANTICORE_HEAD = Vector((0.0, -0.440, 0.600))
## The scorpion tail, rump to stinger: up and over the back, (y, z, radius).
MANTICORE_TAIL = [(0.300, 0.420, 0.060), (0.430, 0.520, 0.056), (0.530, 0.700, 0.052), (0.540, 0.880, 0.050),
		(0.460, 1.020, 0.048), (0.330, 1.070, 0.046), (0.220, 1.030, 0.044)]


def _manticore_head(lod, g):
	"""A round, near-human chibi face in a huge spiky dark amber mane, ivory
	ram horns curling back, a fierce dark brow and a fanged grin."""
	H = MANTICORE_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	mane = geo.ellipsoid(0.235, 0.170, 0.235, seg(lod, 14, 9), seg(lod, 7, 5), row("warpaint"), sharp=SMOOTH)
	geo.translate(mane, H + Vector((0.0, 0.070, 0.0)))
	geo.merge(bm, mane)
	count = seg(lod, 12, 7)
	for k in range(count):
		a = 2.0 * math.pi * (k + 0.5) / count
		radial = Vector((math.cos(a), 0.0, math.sin(a)))
		spike = _cone(0.070, 0.130, "warpaint", seg(lod, 6, 4))
		geo.merge(bm, spike, geo.frame(H + Vector((0.0, 0.050, 0.0)) + radial * 0.190,
				radial + Vector((0.0, 0.35, 0.0)), (0.0, 1.0, 0.0)))
	face = geo.ellipsoid(0.150, 0.120, 0.142, seg(lod, 14, 9), seg(lod, 7, 5), row("skin"), sharp=SMOOTH)
	F = H + Vector((0.0, -0.075, -0.010))
	geo.translate(face, F)
	geo.merge(bm, face)
	# A small round lion nose and a dark grin with two ivory fangs.
	nose = geo.ellipsoid(0.034, 0.024, 0.024, seg(lod, 8, 5), 3, row("blush"), sharp=SMOOTH)
	geo.translate(nose, F + Vector((0.0, -0.118, -0.040)))
	geo.merge(bm, nose)
	tree = geo.bvh(face)
	loc, nrm = geo.project(tree, (0.0, F.y - 1.0, F.z - 0.082), (0.0, 1.0, 0.0))
	if loc is not None:
		geo.merge(bm, geo.disc(0.050, 0.020, seg(lod, 10, 6), row("mouth"), dome=0.002, depth=0.004),
				geo.frame(loc + nrm * 0.001, nrm, (0.0, 0.0, 1.0)))
		for side in (-1.0, 1.0):
			fang = _cone(0.011, 0.034, "bone", 4)
			geo.merge(bm, fang, geo.frame(loc + nrm * 0.006 + Vector((side * 0.026, 0.0, 0.008)), (0.0, -0.25, -1.0),
					(0.0, -1.0, 0.0)))
	geo.merge(bm, animals._eyes(lod, face, F, 0.060, 0.022, rx=0.030, ry=0.036))
	for side in (-1.0, 1.0):
		brow = geo.tube([F + Vector((side * 0.030, -0.120, 0.070)), F + Vector((side * 0.105, -0.095, 0.092))],
				[0.017, 0.012], 5, row("robe_dark"), sharp=SMOOTH)
		geo.merge(bm, brow)
		# Ivory ram horns curling back and down out of the mane.
		horn = geo.tube([H + Vector((side * 0.100, -0.020, 0.110)), H + Vector((side * 0.165, 0.040, 0.215)),
				H + Vector((side * 0.240, 0.150, 0.220)), H + Vector((side * 0.265, 0.215, 0.110)),
				H + Vector((side * 0.230, 0.160, 0.035))], [0.048, 0.042, 0.034, 0.024, 0.0], seg(lod, 8, 5),
				row("bone"), sharp=SMOOTH)
		geo.merge(bm, horn)
		ear = geo.ellipsoid(0.042, 0.022, 0.044, seg(lod, 8, 5), 4, row("beard_dark"), sharp=SMOOTH)
		geo.translate(ear, H + Vector((side * 0.150, -0.030, 0.165)))
		geo.merge(bm, ear)
	return bm


def _bat_wing(lod, side, root, span=(0.80, 0.30, 0.60), lead=(0.0, 0.30, 1.0), size=1.15, bone="robe_dark",
		skin="tuft", tattered=False, stars=None):
	"""A half-spread bat wing: `bone` arm and finger bones, a `skin`
	membrane scalloped between the fingers, an ivory claw at the wrist.
	Turned so the membrane leans back and faces up toward the game's camera
	rather than standing edge-on. `tattered` cuts the scallops deep and
	tears holes in the outer panels (the skeleton dragon). `stars` (a swatch)
	scatters little four-point stars over both faces of the membrane (the
	Star Wanderers' sun dragon)."""
	bm = geo.new_bm()
	shoulder, elbow, wrist = Vector((0.0, 0.0, 0.0)), Vector((0.220, 0.0, 0.120)), Vector((0.420, 0.0, 0.130))
	arm = geo.tube([shoulder, elbow, wrist], [0.042, 0.034, 0.026], seg(lod, 8, 5), row(bone), sharp=SMOOTH)
	geo.merge(bm, arm)
	if tattered and lod == 0:
		for joint, r in ((elbow, 0.040), (wrist, 0.034)):
			knob = geo.ellipsoid(r, r, r, 8, 5, row(bone), sharp=SMOOTH)
			geo.translate(knob, joint)
			geo.merge(bm, knob)
	tips = [Vector((0.700, 0.0, 0.040)), Vector((0.680, 0.0, -0.170)), Vector((0.560, 0.0, -0.340)),
			Vector((0.360, 0.0, -0.420))]
	root_back = Vector((0.020, 0.0, -0.300))
	for tip in tips:
		finger = geo.tube([wrist, wrist.lerp(tip, 0.5) + Vector((0.0, 0.0, 0.02)), tip], [0.020, 0.015, 0.006],
				seg(lod, 6, 4), row(bone), sharp=SMOOTH)
		geo.merge(bm, finger)

	def panel(a, b, c):
		tri = geo.plate([(a.x, a.z), (b.x, b.z), (c.x, c.z)], 0.012, row(skin), sharp=40)
		geo.merge(bm, tri)

	edge = tips + [root_back]
	for i in range(len(edge) - 1):
		a, b = edge[i], edge[i + 1]
		hub = wrist if i < len(tips) - 1 else shoulder
		scallop = a.lerp(b, 0.5).lerp(hub, 0.42 if tattered else 0.22)
		if tattered:
			# Torn: the membrane hangs in ragged strips from each finger,
			# a tear through the middle of every other panel.
			mid = hub.lerp(scallop, 0.55)
			panel(hub, a, mid)
			panel(mid, a, a.lerp(scallop, 0.6))
			panel(hub, mid, b)
			if i % 2 == 0:
				panel(mid, scallop.lerp(b, 0.3), b)
		else:
			panel(hub, a, scallop)
			panel(hub, scallop, b)
	# The inner panel from the shoulder to the wrist and the last finger.
	panel(shoulder, wrist, tips[-1])
	panel(shoulder, elbow, wrist)
	claw = _cone(0.020, 0.070, "bone", seg(lod, 5, 4))
	geo.merge(bm, claw, geo.frame(wrist + Vector((0.010, 0.0, 0.010)), (0.3, 0.0, 1.0), (1.0, 0.0, 0.0)))
	if stars is not None:
		spots = ((0.300, -0.080, 0.034), (0.520, -0.120, 0.026), (0.430, -0.270, 0.030), (0.200, -0.230, 0.022),
				(0.600, -0.020, 0.020), (0.320, -0.360, 0.020))
		for x, z, r in spots[:seg(lod, 6, 3)]:
			for face in (-1.0, 1.0):
				st = geo.plate(star_wanderers._star(r, r, r * 0.34), 0.004, row(stars), sharp=40)
				geo.translate(st, (x, face * 0.008, z))
				geo.merge(bm, st)
	geo.transform(bm, _wing_matrix(side, root, span, lead) @ Matrix.Scale(size, 4))
	return bm


def _manticore_tail(lod, g):
	"""A black scorpion tail in swelling plates, arched over the back, a
	bulb and an ivory stinger aimed forward; two team wraps at its root."""
	pts = _catmull([Vector((0.0, y, g + z)) for y, z, _r in MANTICORE_TAIL], 3)
	radii = _catmull([r for _y, _z, r in MANTICORE_TAIL], 3)
	rr = [r * (1.0 if i % 3 == 1 else 0.82) for i, r in enumerate(radii)]
	bm = geo.new_bm()
	geo.merge(bm, geo.tube(pts, rr, seg(lod, 9, 6), row("robe_dark"), sharp=SMOOTH))
	end = pts[-1]
	d = (pts[-1] - pts[-2]).normalized()
	bulb = geo.ellipsoid(0.072, 0.072, 0.072, seg(lod, 10, 6), 5, row("robe_dark"), sharp=SMOOTH)
	geo.translate(bulb, end + d * 0.040)
	geo.merge(bm, bulb)
	sting_dir = Vector((0.0, -0.75, -0.65)).normalized()
	sting = _cone(0.034, 0.140, "bone", seg(lod, 7, 5))
	geo.merge(bm, sting, geo.frame(end + d * 0.040 + sting_dir * 0.050, sting_dir, (0.0, 0.0, 1.0)))
	for i in (2, 5):
		t = (pts[i + 1] - pts[i - 1]).normalized()
		geo.merge(bm, _band(rr[i] + 0.016, 0.034, lod, (10, 7)), geo.frame(pts[i], t, (0.0, 0.0, 1.0)))
	return bm


def manticore(b, lod):
	g = b.base_height
	bm = animals._body(MANTICORE_SPINE, lod, "beard_dark", g=g)
	belly = geo.ellipsoid(0.130, 0.230, 0.090, seg(lod, 10, 7), 4, row("cream"), sharp=SMOOTH)
	geo.translate(belly, (0.0, 0.020, g + 0.255))
	geo.merge(bm, belly)
	neck = geo.tube([Vector((0.0, -0.200, g + 0.420)), Vector((0.0, -0.330, g + 0.540)),
			Vector((0.0, -0.400, g + 0.590))], [0.140, 0.125, 0.110], seg(lod, 12, 8), row("beard_dark"),
			sharp=SMOOTH)
	geo.merge(bm, neck)
	segs = seg(lod, 9, 6)
	for side in (-1.0, 1.0):
		x = side * 0.120
		# Thick lion forelegs, low and set wide, and round haunches behind.
		shoulder = geo.ellipsoid(0.090, 0.130, 0.130, seg(lod, 10, 7), 5, row("beard_dark"), sharp=SMOOTH)
		geo.translate(shoulder, (side * 0.120, -0.220, g + 0.350))
		geo.merge(bm, shoulder)
		haunch = geo.ellipsoid(0.095, 0.150, 0.150, seg(lod, 10, 7), 5, row("beard_dark"), sharp=SMOOTH)
		geo.translate(haunch, (side * 0.125, 0.200, g + 0.340))
		geo.merge(bm, haunch)
		for y0, y1, y2, r0 in ((-0.230, -0.260, -0.280, 0.080), (0.230, 0.270, 0.210, 0.075)):
			leg = geo.tube([Vector((x * 1.08, y0, g + 0.300)), Vector((x * 1.10, y1, g + 0.150)),
					Vector((x * 1.10, y2, g + 0.050))], [r0, r0 * 0.75, r0 * 0.70], segs, row("beard_dark"),
					sharp=SMOOTH)
			geo.merge(bm, leg)
			py = y2 - 0.020
			paw = geo.ellipsoid(0.066, 0.086, 0.044, seg(lod, 9, 6), 3, row("beard_dark"), sharp=SMOOTH,
					squash_bottom=0.3)
			geo.translate(paw, (x * 1.10, py, g + 0.028))
			geo.merge(bm, paw)
			if lod == 0:
				for k in (-1.0, 0.0, 1.0):
					claw = _cone(0.012, 0.034, "bone", 4)
					geo.merge(bm, claw, geo.frame(Vector((x * 1.10 + k * 0.030, py - 0.078, g + 0.020)),
							(k * 0.2, -1.0, -0.3), (0.0, 0.0, 1.0)))
	geo.merge(bm, _saddle_cloth(lod, g + 0.380, y0=-0.060, y1=0.240, r=0.205, drop=0.120))
	for side in (-1.0, 1.0):
		geo.merge(bm, _bat_wing(lod, side, Vector((side * 0.120, -0.100, g + 0.500))))
	geo.merge(bm, _manticore_tail(lod, g))
	geo.merge(bm, _manticore_head(lod, g))
	return _grow(bm, g, MANTICORE_SCALE)


# --- kitsune -----------------------------------------------------------------

KITSUNE_SCALE = 1.6
KITSUNE_SPINE = [(-0.270, 0.440, 0.020), (-0.240, 0.450, 0.125), (-0.120, 0.445, 0.150), (0.030, 0.435, 0.140),
		(0.160, 0.425, 0.135), (0.240, 0.425, 0.105), (0.280, 0.425, 0.0)]
KITSUNE_HEAD = Vector((0.0, -0.340, 0.820))
## The tails fan out from the rump, this many degrees either side of upright.
KITSUNE_FAN = 70.0


def _wisp(size, swatch="arcane"):
	"""A foxfire flame along local +Z: a teardrop with a pointed top."""
	return geo.lathe([(0.0, 0.0), (size * 0.55, size * 0.35), (size * 0.48, size * 0.85), (size * 0.18, size * 1.4),
			(0.0, size * 1.9)], 7, row(swatch), sharp=SMOOTH, phase=0.0)


def _kitsune_head(lod, g):
	"""A silver fox head: tall pointed ears lined in black-violet, white
	cheek tufts, a long tapering snout, violet markings, and a silver
	circlet with a violet gem across the brow."""
	H = KITSUNE_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.165, 0.150, 0.145, seg(lod, 14, 9), seg(lod, 7, 5), row("fur"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	snout = geo.tube([H + Vector((0.0, -0.090, -0.045)), H + Vector((0.0, -0.170, -0.062)),
			H + Vector((0.0, -0.222, -0.070))], [0.085, 0.060, 0.030], seg(lod, 10, 7), row("fur"), sharp=SMOOTH,
			flatten=0.80, cap_end=row("fur"))
	geo.merge(bm, snout)
	jaw = geo.tube([H + Vector((0.0, -0.080, -0.085)), H + Vector((0.0, -0.160, -0.098)),
			H + Vector((0.0, -0.200, -0.098))], [0.062, 0.042, 0.016], seg(lod, 9, 6), row("fur_light"),
			sharp=SMOOTH, flatten=0.7)
	geo.merge(bm, jaw)
	nose = geo.ellipsoid(0.026, 0.020, 0.018, seg(lod, 8, 5), 3, row("nose"), sharp=SMOOTH)
	geo.translate(nose, H + Vector((0.0, -0.232, -0.060)))
	geo.merge(bm, nose)
	for side in (-1.0, 1.0):
		# White cheek tufts flaring out and back.
		tuft = geo.tube([H + Vector((side * 0.090, -0.020, -0.050)), H + Vector((side * 0.165, 0.030, -0.075)),
				H + Vector((side * 0.215, 0.080, -0.060))], [0.060, 0.040, 0.0], seg(lod, 8, 5), row("fur_light"),
				sharp=SMOOTH, flatten=0.6)
		geo.merge(bm, tuft)
		# Tall pointed ears, lined in black-violet.
		ear_at = H + Vector((side * 0.085, 0.030, 0.090))
		ear_dir = Vector((side * 0.32, 0.12, 1.0)).normalized()
		ear = geo.lathe([(0.068, 0.0), (0.050, 0.110), (0.0, 0.240)], seg(lod, 8, 5), row("fur"), sharp=40,
				phase=0.0, sy=0.42)
		geo.merge(bm, ear, geo.frame(ear_at, ear_dir, (0.0, 1.0, 0.0)))
		inner = geo.lathe([(0.044, 0.0), (0.030, 0.090), (0.0, 0.185)], seg(lod, 7, 4), row("fur_dark"), sharp=40,
				phase=0.0, sy=0.30)
		geo.merge(bm, inner, geo.frame(ear_at + Vector((0.0, -0.022, 0.020)), ear_dir, (0.0, 1.0, 0.0)))
	geo.merge(bm, animals._eyes(lod, skull, H, 0.068, 0.020, rx=0.028, ry=0.034))
	tree = geo.bvh(skull)
	# Violet markings: a stripe under each eye, a teardrop on the brow.
	for x, dz, rx, ry, tilt in ((-0.085, -0.040, 0.034, 0.010, -0.35), (0.085, -0.040, 0.034, 0.010, 0.35),
			(0.0, 0.088, 0.014, 0.030, 0.0)):
		loc, nrm = geo.project(tree, (x, H.y - 1.0, H.z + dz), (0.0, 1.0, 0.0))
		if loc is not None:
			geo.merge(bm, geo.disc(rx, ry, seg(lod, 8, 5), row("arcane"), dome=0.002, depth=0.003),
					geo.frame(loc + nrm * 0.001, nrm, (tilt, 0.0, 1.0)))
	# A silver circlet across the brow, a violet gem at its front.
	circ = geo.tube([H + Vector((-0.150, -0.010, 0.064)), H + Vector((-0.090, -0.115, 0.112)),
			H + Vector((0.0, -0.144, 0.126)), H + Vector((0.090, -0.115, 0.112)),
			H + Vector((0.150, -0.010, 0.064))], [0.011] * 5, seg(lod, 6, 4), row("brass"), sharp=SMOOTH)
	geo.merge(bm, circ)
	gem = geo.ellipsoid(0.022, 0.014, 0.030, seg(lod, 8, 5), 4, row("arcane"), sharp=SMOOTH)
	geo.translate(gem, H + Vector((0.0, -0.152, 0.148)))
	geo.merge(bm, gem)
	return bm


def _kitsune_tails(lod, g):
	"""The signature: a fan of fat silver tails rising from the rump, white
	towards their tips, each ending in a violet foxfire flame."""
	bm = geo.new_bm()
	R = Vector((0.0, 0.400, g + 0.470))
	back = Vector((0.0, 1.0, 0.0))
	count = seg(lod, 7, 5)
	for i in range(count):
		a = math.radians(-KITSUNE_FAN + 2.0 * KITSUNE_FAN * i / (count - 1))
		out = Vector((math.sin(a), 0.0, math.cos(a)))
		k = 1.0 - 0.18 * abs(a) / math.radians(KITSUNE_FAN)
		pts = [R, R + back * 0.090 + out * 0.060 * k, R + back * 0.170 + out * 0.220 * k,
				R + back * 0.180 + out * 0.400 * k, R + back * 0.120 + out * 0.540 * k]
		tip_dir = (pts[-1] - pts[-2]).normalized()
		pts.append(pts[-1] + tip_dir * 0.060)
		radii = [0.040, 0.072, 0.092, 0.084, 0.050, 0.0]
		bands = [row("fur"), row("fur"), row("fur"), row("fur_light"), row("fur_light")]
		geo.merge(bm, geo.tube(pts, radii, seg(lod, 9, 6), sharp=SMOOTH, ring_swatches=bands))
		geo.merge(bm, _wisp(0.060), geo.frame(pts[-2] + tip_dir * 0.020, tip_dir, (0.0, -1.0, 0.0)))
	return bm


def _kitsune_team(lod, g):
	"""The team's thick collar round the neck with a team bib on the chest
	and a silver bell, and the team's light saddle cloth edged in silver."""
	bm = geo.new_bm()
	at = Vector((0.0, -0.270, g + 0.660))
	axis = Vector((0.0, -0.45, 0.89)).normalized()
	geo.merge(bm, _band(0.112, 0.042, lod), geo.frame(at, axis, (0.0, -1.0, 0.0)))
	bib = geo.plate([(-0.120, 0.0), (0.120, 0.0), (0.080, -0.090), (0.0, -0.165), (-0.080, -0.090)], 0.012,
			row("team_cloth"), back=row("team_cloth_dark"), sharp=40, bend=0.9)
	geo.rotate(bib, -18.0, 'X')
	geo.translate(bib, (0.0, -0.355, g + 0.640))
	geo.merge(bm, bib)
	bell = geo.ellipsoid(0.030, 0.030, 0.032, seg(lod, 8, 5), 4, row("brass"), sharp=SMOOTH)
	geo.translate(bell, (0.0, -0.405, g + 0.470))
	geo.merge(bm, bell)
	geo.merge(bm, _saddle_cloth(lod, g + 0.445, y0=-0.080, y1=0.200, r=0.162, drop=0.100))
	return bm


def kitsune(b, lod):
	g = b.base_height
	bm = animals._body(KITSUNE_SPINE, lod, "fur", g=g)
	ruff = geo.ellipsoid(0.125, 0.120, 0.165, seg(lod, 12, 8), seg(lod, 6, 4), row("fur_light"), sharp=SMOOTH)
	geo.translate(ruff, (0.0, -0.215, g + 0.500))
	geo.merge(bm, ruff)
	belly = geo.ellipsoid(0.100, 0.200, 0.070, seg(lod, 10, 7), 4, row("fur_light"), sharp=SMOOTH)
	geo.translate(belly, (0.0, 0.030, g + 0.335))
	geo.merge(bm, belly)
	neck = geo.tube([Vector((0.0, -0.180, g + 0.500)), Vector((0.0, -0.260, g + 0.640)),
			Vector((0.0, -0.320, g + 0.760))], [0.115, 0.098, 0.090], seg(lod, 12, 8), row("fur"), sharp=SMOOTH)
	geo.merge(bm, neck)
	segs = seg(lod, 8, 6)
	for side in (-1.0, 1.0):
		x = side * 0.085
		haunch = geo.ellipsoid(0.075, 0.130, 0.130, seg(lod, 10, 7), 5, row("fur"), sharp=SMOOTH)
		geo.translate(haunch, (side * 0.095, 0.220, g + 0.400))
		geo.merge(bm, haunch)
		# Long slender legs in black-violet socks.
		for top, knee, foot, r0 in (((x, -0.220, 0.380), (x * 1.05, -0.225, 0.200), (x * 1.05, -0.240, 0.040), 0.055),
				((x * 1.1, 0.250, 0.360), (x * 1.15, 0.305, 0.200), (x * 1.15, 0.255, 0.040), 0.058)):
			p0, p1, p2 = (Vector((p[0], p[1], g + p[2])) for p in (top, knee, foot))
			geo.merge(bm, geo.tube([p0, p1], [r0, r0 * 0.70], segs, row("fur"), sharp=SMOOTH))
			geo.merge(bm, geo.tube([p1 + (p1 - p0).normalized() * 0.010, p2], [r0 * 0.74, r0 * 0.66], segs,
					row("fur_dark"), sharp=SMOOTH))
			paw = geo.ellipsoid(0.044, 0.064, 0.032, seg(lod, 8, 5), 3, row("fur_dark"), sharp=SMOOTH,
					squash_bottom=0.3)
			geo.translate(paw, (p2.x, p2.y - 0.018, g + 0.022))
			geo.merge(bm, paw)
	geo.merge(bm, _kitsune_tails(lod, g))
	geo.merge(bm, _kitsune_team(lod, g))
	geo.merge(bm, _kitsune_head(lod, g))
	if lod == 0:
		# Three foxfire wisps floating over the head.
		for x, y, z, s in ((-0.200, -0.300, 1.120, 0.040), (0.0, -0.420, 1.200, 0.046), (0.200, -0.300, 1.120, 0.040)):
			geo.merge(bm, _wisp(s), geo.frame(Vector((x, y, g + z)), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0)))
	return _grow(bm, g, KITSUNE_SCALE)


# --- shared: wind and stripes -------------------------------------------------

def _curl(points, radii, lod, swatch, flatten=1.0, up=(0.0, 0.0, 1.0), steps=3):
	"""A smooth tapering tube through `points`: gusts, scarves, rags."""
	pts = _catmull([Vector(p) for p in points], steps)
	rr = _catmull(list(radii), steps)
	return geo.tube(pts, [max(r, 0.0) for r in rr], seg(lod, 8, 5), row(swatch), sharp=SMOOTH, flatten=flatten, up=up)


def _spiral(origin, axis, r0, r1, turns, rise, thick, swatch, lod, phase=0.0, y_hint=(0.0, 0.0, 1.0)):
	"""A tapering coil round `axis` at `origin`: a wind swirl."""
	n = max(int(seg(lod, 12, 7) * turns), 4)
	pts, radii = [], []
	for i in range(n + 1):
		t = i / n
		a = phase + 2.0 * math.pi * turns * t
		r = r0 + (r1 - r0) * t
		pts.append(Vector((math.cos(a) * r, math.sin(a) * r, rise * t)))
		radii.append(thick * (1.0 - 0.85 * t))
	bm = geo.tube(pts, radii, seg(lod, 6, 4), row(swatch), sharp=SMOOTH)
	geo.transform(bm, geo.frame(origin, axis, y_hint))
	return bm


def _stripe(bm, tree, y, zc, side, a0, a1, width, swatch, sweep=0.040, lod=0):
	"""A tapering stripe laid round a body from `a0` to `a1` degrees off the
	top (90 is the flank), found by casting rays in at the axis (0, y, zc)."""
	n = seg(lod, 7, 4)
	pts, nrms, widths = [], [], []
	for i in range(n):
		t = i / (n - 1)
		a = math.radians(a0 + (a1 - a0) * t)
		yy = y + sweep * t
		origin = Vector((side * math.sin(a), yy, zc + math.cos(a)))
		loc, nrm = geo.project(tree, origin, Vector((0.0, yy, zc)) - origin)
		if loc is None:
			continue
		pts.append(loc)
		nrms.append(nrm)
		widths.append(max(width * (1.0 - t) ** 0.8, 0.004))
	if len(pts) > 1:
		geo.merge(bm, geo.ribbon(pts, nrms, width, 0.006, row(swatch), sharp=SMOOTH, embed=0.004, widths=widths))


def _decal(bm, tree, origin, direction, rx, ry, swatch, y_hint=(0.0, 0.0, 1.0), lod=0):
	loc, nrm = geo.project(tree, origin, direction)
	if loc is not None:
		geo.merge(bm, geo.disc(rx, ry, seg(lod, 8, 5), row(swatch), dome=0.002, depth=0.004),
				geo.frame(loc + nrm * 0.001, nrm, y_hint))


# --- wind tiger --------------------------------------------------------------

TIGER_SCALE = 1.95
TIGER_SPINE = [(-0.340, 0.400, 0.020), (-0.300, 0.405, 0.170), (-0.160, 0.410, 0.215), (0.010, 0.400, 0.200),
		(0.170, 0.395, 0.192), (0.285, 0.395, 0.150), (0.335, 0.395, 0.0)]
TIGER_HEAD = Vector((0.0, -0.455, 0.640))


def _tiger_head(lod, g):
	"""A big round tiger head: white cheek ruffs flaring back, a broad white
	muzzle on puffy whisker pads, short round ears, black stripes on the
	brow and cheeks."""
	H = TIGER_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.190, 0.165, 0.165, seg(lod, 14, 9), seg(lod, 7, 5), row("beard"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	for side in (-1.0, 1.0):
		# Rounded-triangle ears set out to the sides, black at the back,
		# white inside (a cat's, not the bear's round ones).
		ear_at = H + Vector((side * 0.120, 0.030, 0.110))
		ear_dir = Vector((side * 0.55, 0.10, 1.0)).normalized()
		ear = geo.lathe([(0.066, 0.0), (0.054, 0.060), (0.026, 0.105), (0.0, 0.118)], seg(lod, 8, 5), row("beard_dark"),
				sharp=SMOOTH, phase=0.0, sy=0.40)
		geo.merge(bm, ear, geo.frame(ear_at, ear_dir, (0.0, 1.0, 0.0)))
		inner = geo.lathe([(0.046, 0.0), (0.036, 0.050), (0.0, 0.092)], seg(lod, 7, 4), row("fur_light"), sharp=SMOOTH,
				phase=0.0, sy=0.28)
		geo.merge(bm, inner, geo.frame(ear_at + Vector((0.0, -0.016, 0.010)), ear_dir, (0.0, 1.0, 0.0)))
		# White cheek ruffs flaring out and back, two tufts a side.
		for dz, k in ((-0.040, 1.0), (-0.100, 0.8)):
			tuft = geo.tube([H + Vector((side * 0.120, 0.000, dz)), H + Vector((side * 0.200, 0.040, dz - 0.020 * k)),
					H + Vector((side * 0.265 * k, 0.100, dz - 0.010))], [0.070 * k, 0.050 * k, 0.0], seg(lod, 8, 5),
					row("fur_light"), sharp=SMOOTH, flatten=0.6)
			geo.merge(bm, tuft)
		# Puffy white whisker pads.
		pad = geo.ellipsoid(0.058, 0.050, 0.046, seg(lod, 9, 6), 5, row("fur_light"), sharp=SMOOTH)
		geo.translate(pad, H + Vector((side * 0.048, -0.150, -0.070)))
		geo.merge(bm, pad)
	bridge = geo.tube([H + Vector((0.0, -0.100, -0.010)), H + Vector((0.0, -0.170, -0.035))], [0.060, 0.048],
			seg(lod, 9, 6), row("beard"), sharp=SMOOTH, cap_end=row("beard"))
	geo.merge(bm, bridge)
	chin = geo.ellipsoid(0.050, 0.044, 0.032, seg(lod, 8, 5), 4, row("fur_light"), sharp=SMOOTH)
	geo.translate(chin, H + Vector((0.0, -0.140, -0.118)))
	geo.merge(bm, chin)
	nose = geo.ellipsoid(0.036, 0.022, 0.024, seg(lod, 8, 5), 3, row("blush"), sharp=SMOOTH)
	geo.translate(nose, H + Vector((0.0, -0.200, -0.036)))
	geo.merge(bm, nose)
	geo.merge(bm, animals._eyes(lod, skull, H, 0.072, 0.025, rx=0.030, ry=0.036))
	tree = geo.bvh(skull)
	fwd = Vector((0.0, 1.0, 0.0))
	# Brow stripes: one down the middle, two either side fanning out.
	for x, dz, rx, ry, tilt in ((0.0, 0.120, 0.016, 0.050, 0.0), (-0.055, 0.105, 0.015, 0.044, 0.45),
			(0.055, 0.105, 0.015, 0.044, -0.45), (-0.105, 0.075, 0.014, 0.040, 0.8), (0.105, 0.075, 0.014, 0.040, -0.8),
			(-0.075, 0.062, 0.040, 0.011, 0.25), (0.075, 0.062, 0.040, 0.011, -0.25)):
		_decal(bm, tree, (x, H.y - 1.0, H.z + dz), fwd, rx, ry, "beard_dark", (tilt, 0.0, 1.0), lod)
	if lod == 0:
		# Cheek stripes, cast in from the sides.
		for side in (-1.0, 1.0):
			for dy, dz, tilt in ((-0.030, -0.010, 0.3), (0.030, 0.035, 0.2), (0.060, -0.050, 0.3)):
				_decal(bm, tree, (side * 1.0, H.y + dy, H.z + dz), (-side, 0.0, 0.0), 0.040, 0.010, "beard_dark",
						(0.0, tilt, 1.0), lod)
	return bm


def _tiger_wind(lod, g):
	"""Mint wind: gusts streaming back off the shoulders and haunches, each
	ending in a curl."""
	bm = geo.new_bm()
	for side in (-1.0, 1.0):
		for y0, z0, k in ((-0.230, 0.560, 1.0), (0.170, 0.540, 0.8)):
			x = side * 0.170
			pts = [(x, y0, g + z0), (x + side * 0.060, y0 + 0.140 * k, g + z0 + 0.090 * k),
					(x + side * 0.080, y0 + 0.300 * k, g + z0 + 0.110 * k),
					(x + side * 0.060, y0 + 0.420 * k, g + z0 + 0.050 * k)]
			geo.merge(bm, _curl(pts, [0.006, 0.030 * k, 0.028 * k, 0.020 * k], lod, "tuft", flatten=0.40,
					up=(side, 0.0, 0.4)))
			end = Vector(pts[-1])
			geo.merge(bm, _spiral(end + Vector((0.0, 0.010, -0.050 * k)), (side, 0.0, 0.0), 0.050 * k, 0.012, 0.85, 0.0,
					0.020 * k, "tuft", lod, phase=math.pi * 0.5, y_hint=(0.0, 1.0, 0.0)))
	return bm


def _tiger_team(lod, g):
	"""The team's collar with a silver crescent and a long scarf streaming
	back over each shoulder, and the team's saddle cloth edged in silver
	under a black-violet lacquered saddle."""
	bm = geo.new_bm()
	at = Vector((0.0, -0.320, g + 0.540))
	axis = Vector((0.0, -0.60, 0.80)).normalized()
	geo.merge(bm, _band(0.168, 0.048, lod), geo.frame(at, axis, (0.0, 0.0, 1.0)))
	crescent = geo.plate([(-0.060, 0.030), (-0.030, -0.020), (0.0, -0.034), (0.030, -0.020), (0.060, 0.030),
			(0.025, 0.000), (0.0, -0.008), (-0.025, 0.000)], 0.016, row("brass"), sharp=40)
	geo.rotate(crescent, -30.0, 'X')
	geo.translate(crescent, (0.0, -0.468, g + 0.475))
	geo.merge(bm, crescent)
	for side in (-1.0, 1.0):
		pts = [(side * 0.100, -0.300, g + 0.640), (side * 0.150, -0.170, g + 0.690), (side * 0.175, -0.020, g + 0.660),
				(side * 0.190, 0.120, g + 0.720), (side * 0.220, 0.250, g + 0.690)]
		geo.merge(bm, _curl(pts, [0.050, 0.058, 0.056, 0.050, 0.030], lod, "team_cloth", flatten=0.22,
				up=(side * 0.3, 0.0, 1.0)))
	geo.merge(bm, _saddle_cloth(lod, g + 0.400, y0=-0.100, y1=0.250, r=0.225, drop=0.135))
	saddle = geo.ellipsoid(0.110, 0.130, 0.040, seg(lod, 10, 7), 4, row("plate_dark"), sharp=SMOOTH)
	geo.translate(saddle, (0.0, 0.080, g + 0.625))
	geo.merge(bm, saddle)
	for y, h in ((-0.030, 0.055), (0.195, 0.042)):
		lip = geo.ellipsoid(0.090, 0.024, h, seg(lod, 8, 6), 3, row("brass"), sharp=SMOOTH)
		geo.translate(lip, (0.0, y, g + 0.640))
		geo.merge(bm, lip)
	gem = geo.ellipsoid(0.022, 0.016, 0.028, seg(lod, 8, 5), 4, row("arcane"), sharp=SMOOTH)
	geo.translate(gem, (0.0, -0.058, g + 0.690))
	geo.merge(bm, gem)
	return bm


def wind_tiger(b, lod):
	g = b.base_height
	torso = animals._body(TIGER_SPINE, lod, "beard", g=g)
	for side in (-1.0, 1.0):
		shoulder = geo.ellipsoid(0.105, 0.150, 0.165, seg(lod, 10, 7), 5, row("beard"), sharp=SMOOTH)
		geo.translate(shoulder, (side * 0.130, -0.205, g + 0.400))
		geo.merge(torso, shoulder)
		haunch = geo.ellipsoid(0.105, 0.165, 0.160, seg(lod, 10, 7), 5, row("beard"), sharp=SMOOTH)
		geo.translate(haunch, (side * 0.130, 0.200, g + 0.395))
		geo.merge(torso, haunch)
	tree = geo.bvh(torso)
	bm = geo.new_bm()
	geo.merge(bm, torso)
	# Black stripes over the back and down the flanks, full and half ones.
	for k, y in enumerate((-0.250, -0.165, -0.080, 0.005, 0.090, 0.175, 0.255, 0.320)):
		if lod == 1 and k % 2:
			continue
		for side in (-1.0, 1.0):
			if k % 2 == 0:
				_stripe(bm, tree, y, g + 0.400, side, 0.0, 112.0, 0.040, "beard_dark", lod=lod)
			else:
				_stripe(bm, tree, y + 0.010, g + 0.400, side, 28.0, 96.0, 0.034, "beard_dark", sweep=-0.030, lod=lod)
	belly = geo.ellipsoid(0.150, 0.260, 0.090, seg(lod, 10, 7), 4, row("fur_light"), sharp=SMOOTH)
	geo.translate(belly, (0.0, 0.0, g + 0.225))
	geo.merge(bm, belly)
	chest = geo.ellipsoid(0.140, 0.110, 0.160, seg(lod, 12, 8), seg(lod, 6, 4), row("fur_light"), sharp=SMOOTH)
	geo.translate(chest, (0.0, -0.300, g + 0.410))
	geo.merge(bm, chest)
	neck = geo.tube([Vector((0.0, -0.240, g + 0.460)), Vector((0.0, -0.330, g + 0.560)),
			Vector((0.0, -0.385, g + 0.610))], [0.160, 0.150, 0.140], seg(lod, 12, 8), row("beard"), sharp=SMOOTH)
	geo.merge(bm, neck)
	segs = seg(lod, 9, 6)
	for side in (-1.0, 1.0):
		x = side * 0.135
		for p0, p1, p2, r0 in (((x, -0.215, 0.340), (x * 1.06, -0.245, 0.170), (x * 1.06, -0.270, 0.055), 0.088),
				((x, 0.225, 0.340), (x * 1.08, 0.285, 0.175), (x * 1.08, 0.235, 0.055), 0.084)):
			a, b_, c = (Vector((p[0], p[1], g + p[2])) for p in (p0, p1, p2))
			geo.merge(bm, geo.tube([a, b_, c], [r0, r0 * 0.80, r0 * 0.74], segs, row("beard"), sharp=SMOOTH))
			band = geo.tube([b_.lerp(c, 0.30), b_.lerp(c, 0.42)], [r0 * 0.80, r0 * 0.78], segs, row("beard_dark"),
					sharp=SMOOTH)
			geo.merge(bm, band)
			# Big white paws.
			paw = geo.ellipsoid(0.078, 0.098, 0.050, seg(lod, 9, 6), 3, row("fur_light"), sharp=SMOOTH,
					squash_bottom=0.3)
			geo.translate(paw, (c.x, c.y - 0.022, g + 0.034))
			geo.merge(bm, paw)
			if lod == 0:
				for t in (-1.0, 0.0, 1.0):
					claw = _cone(0.011, 0.030, "bone", 4)
					geo.merge(bm, claw, geo.frame(Vector((c.x + t * 0.034, c.y - 0.112, g + 0.026)),
							(t * 0.2, -1.0, -0.3), (0.0, 0.0, 1.0)))
			# A wind swirl round the paw.
			geo.merge(bm, _spiral(Vector((c.x, c.y - 0.010, g + 0.040)), (0.0, 0.0, 1.0), 0.120, 0.090, 0.80, 0.090,
					0.016, "tuft", lod, phase=math.radians(-90.0 + side * 60.0)))
	# A long ringed tail rising behind, its tip spun into a wind vortex.
	tail_pts = [(0.0, 0.320, g + 0.440), (0.0, 0.450, g + 0.470), (0.0, 0.560, g + 0.560), (0.0, 0.610, g + 0.700),
			(0.0, 0.580, g + 0.820)]
	pts = _catmull([Vector(p) for p in tail_pts], 3)
	radii = _catmull([0.058, 0.052, 0.048, 0.044, 0.040], 3)
	bands = [row("beard_dark") if i % 3 == 1 else row("beard") for i in range(len(pts) - 1)]
	geo.merge(bm, geo.tube(pts, radii, seg(lod, 8, 6), sharp=SMOOTH, ring_swatches=bands, cap_end=row("beard_dark")))
	tip = pts[-1]
	tip_dir = (pts[-1] - pts[-2]).normalized()
	geo.merge(bm, _spiral(tip - tip_dir * 0.040, tip_dir, 0.110, 0.030, 1.4, 0.150, 0.022, "tuft", lod))
	geo.merge(bm, _tiger_wind(lod, g))
	geo.merge(bm, _tiger_team(lod, g))
	geo.merge(bm, _tiger_head(lod, g))
	return _grow(bm, g, TIGER_SCALE)


# --- skeleton dragon -----------------------------------------------------------

## The Bestiary drake. The monster (scenes/units/monsters) is a much bigger,
## separate figure; this one leaves it room.
BONE_DRAGON_SCALE = 1.75
## The spine, tail tip to the back of the skull: (x, y, z, vertebra radius).
BONE_DRAGON_SPINE = [(0.300, 0.540, 0.060, 0.016), (0.230, 0.600, 0.130, 0.020), (0.120, 0.540, 0.230, 0.026),
		(0.030, 0.420, 0.340, 0.032), (0.0, 0.290, 0.430, 0.040), (0.0, 0.130, 0.470, 0.044),
		(0.0, -0.030, 0.480, 0.046), (0.0, -0.150, 0.520, 0.046), (0.0, -0.250, 0.640, 0.042),
		(0.0, -0.300, 0.780, 0.038), (0.0, -0.340, 0.880, 0.034)]
BONE_DRAGON_HEAD = Vector((0.0, -0.420, 0.930))


def _dragon_spine(lod, g):
	"""A chain of knobbed vertebrae on a thin cord, with dorsal spikes, and
	an open rib cage hanging from the back round a green soul fire."""
	pts = _catmull([Vector((x, y, g + z)) for x, y, z, _r in BONE_DRAGON_SPINE], seg(lod, 3, 2))
	radii = _catmull([r for _x, _y, _z, r in BONE_DRAGON_SPINE], seg(lod, 3, 2))
	bm = geo.new_bm()
	geo.merge(bm, geo.tube(pts, [r * 0.55 for r in radii], seg(lod, 7, 5), row("bone"), sharp=SMOOTH))
	for i, (p, r) in enumerate(zip(pts, radii)):
		t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
		knob = geo.ellipsoid(r * 1.15, r * 1.15, r * 0.70, seg(lod, 8, 6), 4, row("bone"), sharp=SMOOTH)
		geo.merge(bm, knob, geo.frame(p, t, (0.0, 0.0, 1.0)))
		if i % 2 == 0 and r > 0.022:
			up = (Vector((0.0, 0.0, 1.0)) - t * t.z).normalized()
			spike = _cone(r * 0.55, r * 1.9, "bone", seg(lod, 5, 4))
			geo.merge(bm, spike, geo.frame(p + up * r * 0.6, up + Vector((0.0, 0.35, 0.0)), t))
	# Ribs: pairs arcing out and down from the back to a keel of breastbone.
	for k, y in enumerate((-0.110, -0.040, 0.030, 0.100, 0.170)):
		if lod == 1 and k % 2:
			continue
		zs = g + 0.475
		depth = 0.330 - 0.035 * k
		for side in (-1.0, 1.0):
			rib = geo.tube([Vector((side * 0.030, y, zs)), Vector((side * 0.150, y + 0.012, zs - 0.040)),
					Vector((side * 0.200, y + 0.030, zs - depth * 0.50)),
					Vector((side * 0.140, y + 0.040, zs - depth * 0.86)), Vector((side * 0.030, y + 0.045, zs - depth))],
					[0.020, 0.019, 0.017, 0.014, 0.012], seg(lod, 6, 4), row("bone"), sharp=SMOOTH)
			geo.merge(bm, rib)
	keel = geo.tube([Vector((0.0, -0.090, g + 0.150)), Vector((0.0, 0.050, g + 0.155)), Vector((0.0, 0.215, g + 0.300))],
			[0.024, 0.026, 0.016], seg(lod, 6, 4), row("bone"), sharp=SMOOTH)
	geo.merge(bm, keel)
	heart = geo.ellipsoid(0.075, 0.075, 0.085, seg(lod, 9, 6), 5, row("crystal"), sharp=SMOOTH)
	geo.translate(heart, (0.0, 0.010, g + 0.310))
	geo.merge(bm, heart)
	if lod == 0:
		for dx, dy, h in ((-0.030, 0.0, 0.120), (0.035, 0.020, 0.100), (0.0, -0.030, 0.150)):
			flame = _wisp(h * 0.45, "crystal")
			geo.merge(bm, flame, geo.frame(Vector((dx, 0.010 + dy, g + 0.350)), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0)))
	# Pelvis and shoulder blades.
	pelvis = geo.ellipsoid(0.130, 0.090, 0.045, seg(lod, 10, 7), 4, row("bone"), sharp=SMOOTH)
	geo.translate(pelvis, (0.0, 0.290, g + 0.410))
	geo.merge(bm, pelvis)
	for side in (-1.0, 1.0):
		blade = geo.plate([(-0.050, 0.0), (0.060, 0.0), (0.030, -0.140), (-0.020, -0.130)], 0.020, row("bone"), sharp=40)
		geo.rotate(blade, side * 18.0, 'Z')
		geo.merge(bm, blade, geo.frame(Vector((side * 0.110, -0.110, g + 0.520)), (side * 1.0, 0.0, 0.3), (0.0, 0.0, 1.0)))
	return bm


def _bone_limb(bm, joints, radii, lod):
	"""A bone leg: a thin shaft between each pair of joints, a knob at each."""
	geo.merge(bm, geo.tube(joints, radii, seg(lod, 6, 4), row("bone"), sharp=SMOOTH))
	for p, r in zip(joints[:-1], radii):
		knob = geo.ellipsoid(r * 1.6, r * 1.6, r * 1.6, seg(lod, 7, 5), 4, row("bone"), sharp=SMOOTH)
		geo.translate(knob, p)
		geo.merge(bm, knob)


def _dragon_legs(lod, g):
	bm = geo.new_bm()
	for side in (-1.0, 1.0):
		front = [Vector((side * 0.150, -0.120, g + 0.420)), Vector((side * 0.185, -0.080, g + 0.250)),
				Vector((side * 0.170, -0.200, g + 0.100)), Vector((side * 0.170, -0.230, g + 0.030))]
		hind = [Vector((side * 0.140, 0.300, g + 0.400)), Vector((side * 0.180, 0.170, g + 0.250)),
				Vector((side * 0.175, 0.320, g + 0.120)), Vector((side * 0.175, 0.250, g + 0.030))]
		for joints in (front, hind):
			_bone_limb(bm, joints, [0.032, 0.026, 0.022, 0.020], lod)
			foot = joints[-1]
			for k in (-1.0, 0.0, 1.0):
				d = Vector((math.sin(math.radians(30.0 * k)), -math.cos(math.radians(30.0 * k)), -0.10)).normalized()
				end = foot + d * 0.080
				geo.merge(bm, geo.tube([foot, end], [0.016, 0.012], seg(lod, 5, 4), row("bone"), sharp=SMOOTH))
				claw = _cone(0.014, 0.045, "fur_dark", seg(lod, 5, 4))
				geo.merge(bm, claw, geo.frame(end - d * 0.006, (d.x, d.y, -0.6), (0.0, 0.0, 1.0)))
	return bm


def _dragon_head(lod, g):
	"""A long horned dragon skull: green sparks in dark sockets, a toothed
	jaw hanging a little open, ochre war paint down the snout, the team's
	rags tied to its horns."""
	H = BONE_DRAGON_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	cranium = geo.ellipsoid(0.115, 0.120, 0.100, seg(lod, 12, 8), seg(lod, 6, 5), row("bone"), sharp=SMOOTH)
	geo.translate(cranium, H)
	geo.merge(bm, cranium)
	snout = geo.tube([H + Vector((0.0, -0.070, -0.010)), H + Vector((0.0, -0.190, -0.040)),
			H + Vector((0.0, -0.275, -0.052))], [0.082, 0.064, 0.044], seg(lod, 10, 7), row("bone"), sharp=SMOOTH,
			flatten=0.72, cap_end=row("bone"))
	geo.merge(bm, snout)
	jaw = geo.tube([H + Vector((0.0, -0.020, -0.085)), H + Vector((0.0, -0.160, -0.125)),
			H + Vector((0.0, -0.250, -0.120))], [0.056, 0.042, 0.026], seg(lod, 9, 6), row("bone"), sharp=SMOOTH,
			flatten=0.6)
	geo.merge(bm, jaw)
	mouth = geo.ellipsoid(0.040, 0.100, 0.020, seg(lod, 8, 5), 3, row("fur_dark"), sharp=SMOOTH)
	geo.translate(mouth, H + Vector((0.0, -0.150, -0.085)))
	geo.merge(bm, mouth)
	for side in (-1.0, 1.0):
		for k in range(seg(lod, 4, 2)):
			y = -0.120 - 0.045 * k
			tooth = _cone(0.010, 0.034, "bone", 4)
			geo.merge(bm, tooth, geo.frame(H + Vector((side * 0.042, y, -0.060 - 0.010 * k)), (0.0, 0.0, -1.0),
					(0.0, -1.0, 0.0)))
		# Long horns swept back off the crown, a shorter pair under them.
		horn = geo.tube([H + Vector((side * 0.060, 0.040, 0.070)), H + Vector((side * 0.100, 0.140, 0.130)),
				H + Vector((side * 0.130, 0.260, 0.150)), H + Vector((side * 0.140, 0.370, 0.110))],
				[0.034, 0.027, 0.017, 0.0], seg(lod, 7, 5), row("bone"), sharp=SMOOTH)
		geo.merge(bm, horn)
		spur = geo.tube([H + Vector((side * 0.090, 0.050, -0.020)), H + Vector((side * 0.150, 0.130, -0.010)),
				H + Vector((side * 0.180, 0.200, 0.020))], [0.024, 0.015, 0.0], seg(lod, 6, 4), row("bone"), sharp=SMOOTH)
		geo.merge(bm, spur)
		# The team's rag tied round each horn, its ends streaming back.
		knot = H + Vector((side * 0.112, 0.180, 0.142))
		geo.merge(bm, _band(0.030, 0.020, lod, (8, 6)), geo.frame(knot, (side * 0.25, 1.0, 0.3), (0.0, 0.0, 1.0)))
		rag = [knot, knot + Vector((side * 0.030, 0.080, -0.040)), knot + Vector((side * 0.050, 0.170, -0.050)),
				knot + Vector((side * 0.070, 0.250, -0.110))]
		geo.merge(bm, _curl(rag, [0.034, 0.040, 0.036, 0.020], lod, "team_cloth", flatten=0.25, up=(side, 0.0, 0.3)))
	tree = geo.bvh(cranium)
	for side in (-1.0, 1.0):
		loc, nrm = geo.project(tree, (side * 0.062, H.y - 1.0, H.z + 0.020), (0.0, 1.0, 0.0))
		if loc is None:
			continue
		geo.merge(bm, geo.disc(0.034, 0.030, seg(lod, 10, 6), row("eye"), dome=-0.004, depth=0.003),
				geo.frame(loc + nrm * 0.002, nrm, (0.0, 0.0, 1.0)))
		geo.merge(bm, geo.disc(0.014, 0.014, seg(lod, 7, 5), row("crystal"), dome=0.006, depth=0.002),
				geo.frame(loc + nrm * 0.006, nrm, (0.0, 0.0, 1.0)))
	# Ochre war paint: a stripe down the snout and a bar over each eye.
	stree = geo.bvh(snout)
	_decal(bm, stree, (0.0, H.y - 0.170, H.z + 1.0), (0.0, 0.0, -1.0), 0.016, 0.075, "ochre", (0.0, 1.0, 0.0), lod)
	for side in (-1.0, 1.0):
		_decal(bm, tree, (side * 0.060, H.y - 0.020, H.z + 1.0), (0.0, 0.0, -1.0), 0.040, 0.012, "ochre",
				(0.0, 1.0, 0.0), lod)
	return bm


def _dragon_team(lod, g):
	"""The team's blanket over the ribs with ochre edges and dags, a raw
	hide saddle with a bone cantle, a bead necklace and a horned skull
	trophy hung at the flank."""
	bm = geo.new_bm()
	geo.merge(bm, _saddle_cloth(lod, g + 0.300, y0=-0.100, y1=0.210, r=0.235, drop=0.140, edge="ochre"))
	saddle = geo.ellipsoid(0.100, 0.120, 0.040, seg(lod, 10, 7), 4, row("leather"), sharp=SMOOTH)
	geo.translate(saddle, (0.0, 0.050, g + 0.545))
	geo.merge(bm, saddle)
	cantle = geo.tube([Vector((-0.070, 0.165, g + 0.560)), Vector((0.0, 0.175, g + 0.620)),
			Vector((0.070, 0.165, g + 0.560))], [0.016, 0.020, 0.016], seg(lod, 6, 4), row("bone"), sharp=SMOOTH)
	geo.merge(bm, cantle)
	if lod == 0:
		# Beads round the base of the neck.
		for k in range(9):
			a = math.radians(-150.0 + 300.0 * k / 8)
			bead = geo.ellipsoid(0.020, 0.020, 0.020, 6, 4, row("ochre" if k % 2 else "bone"), sharp=SMOOTH)
			geo.translate(bead, (math.sin(a) * 0.080, -0.230 - math.cos(a) * 0.050, g + 0.600 - math.cos(a) * 0.050))
			geo.merge(bm, bead)
	skull = gnoll.beast_skull(lod)
	geo.transform(skull, Matrix.Translation((0.275, 0.120, g + 0.250)) @ Matrix.Rotation(math.radians(90.0), 4, 'Z')
			@ Matrix.Scale(1.4, 4))
	geo.merge(bm, skull)
	return bm


def skeleton_dragon(b, lod):
	g = b.base_height
	bm = geo.new_bm()
	for piece in (_dragon_spine(lod, g), _dragon_legs(lod, g), _dragon_team(lod, g), _dragon_head(lod, g)):
		geo.merge(bm, piece)
	for side in (-1.0, 1.0):
		geo.merge(bm, _bat_wing(lod, side, Vector((side * 0.100, -0.080, g + 0.520)), span=(0.50, 0.45, 0.75),
				lead=(0.0, 0.45, 1.0), size=1.05, bone="bone", skin="mane", tattered=True))
	return _grow(bm, g, BONE_DRAGON_SCALE)


# --- star wanderers: sun dragon ------------------------------------------------

## The Star Wanderers' Bestiary dragon. The monster dragons are much bigger,
## separate figures; this one leaves them room.
SUN_DRAGON_SCALE = 1.8
SUN_DRAGON_SPINE = [(-0.330, 0.440, 0.020), (-0.290, 0.445, 0.170), (-0.150, 0.435, 0.220), (0.020, 0.415, 0.222),
		(0.180, 0.400, 0.195), (0.300, 0.390, 0.120), (0.340, 0.385, 0.0)]
SUN_DRAGON_HEAD = Vector((0.0, -0.430, 0.840))


def _sun_ring(centre, normal, radius, thick, rays, lod, ray_len=0.060):
	"""A floating gold sun: a ring with pointed rays, facing `normal`."""
	bm = geo.new_bm()
	n = seg(lod, 20, 12)
	pts = [Vector((math.cos(2.0 * math.pi * i / n) * radius, math.sin(2.0 * math.pi * i / n) * radius, 0.0))
			for i in range(n + 1)]
	geo.merge(bm, geo.tube(pts, [thick] * len(pts), seg(lod, 6, 4), row("brass"), sharp=SMOOTH))
	for k in range(rays):
		a = 2.0 * math.pi * k / rays
		ray = geo.plate([(-0.020, 0.0), (0.020, 0.0), (0.0, ray_len)], 0.014, row("brass"), sharp=40)
		geo.rotate(ray, 90.0, 'X')
		geo.rotate(ray, math.degrees(a) + 90.0, 'Z')
		geo.translate(ray, (math.cos(a) * (radius + thick * 0.6), math.sin(a) * (radius + thick * 0.6), 0.0))
		geo.merge(bm, ray)
	geo.transform(bm, geo.frame(centre, normal, (0.0, 0.0, 1.0)))
	return bm


def _brow_star(bm, skull, x, y, z, r):
	"""The race's cyan four-point star on a beast's brow."""
	tree = geo.bvh(skull)
	loc, nrm = geo.project(tree, (x, y - 1.0, z), (0.0, 1.0, 0.0))
	if loc is not None:
		geo.merge(bm, geo.plate(star_wanderers._star(r, r * 0.72, r * 0.28), 0.012, row("crystal"), sharp=40),
				geo.orient(loc + nrm * 0.002, nrm, (0.0, 0.0, 1.0)))


def _sun_dragon_head(lod, g):
	"""A big round chibi dragon head in gold scales: an ivory jaw, porcelain
	horns swept back and tipped in gold, amber fins at the cheeks, a cyan
	star on the brow, and a floating gold sun ring behind the horns."""
	H = SUN_DRAGON_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.150, 0.145, 0.128, seg(lod, 14, 9), seg(lod, 7, 5), row("fur"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	snout = geo.tube([H + Vector((0.0, -0.080, -0.020)), H + Vector((0.0, -0.170, -0.040)),
			H + Vector((0.0, -0.235, -0.050))], [0.100, 0.086, 0.070], seg(lod, 11, 7), row("fur"), sharp=SMOOTH,
			flatten=0.78, cap_end=row("fur"))
	geo.merge(bm, snout)
	jaw = geo.tube([H + Vector((0.0, -0.030, -0.090)), H + Vector((0.0, -0.150, -0.112)),
			H + Vector((0.0, -0.215, -0.104))], [0.080, 0.064, 0.046], seg(lod, 10, 6), row("fur_light"), sharp=SMOOTH,
			flatten=0.6, cap_end=row("fur_light"))
	geo.merge(bm, jaw)
	for side in (-1.0, 1.0):
		nostril = geo.ellipsoid(0.014, 0.012, 0.010, 6, 4, row("fur_dark"), sharp=SMOOTH)
		geo.translate(nostril, H + Vector((side * 0.036, -0.268, -0.018)))
		geo.merge(bm, nostril)
		fang = _cone(0.014, 0.040, "bone", 4)
		geo.merge(bm, fang, geo.frame(H + Vector((side * 0.046, -0.200, -0.070)), (0.0, -0.1, -1.0), (0.0, -1.0, 0.0)))
		horn = geo.tube([H + Vector((side * 0.070, 0.020, 0.085)), H + Vector((side * 0.115, 0.120, 0.150)),
				H + Vector((side * 0.140, 0.230, 0.160)), H + Vector((side * 0.135, 0.320, 0.120))],
				[0.044, 0.032, 0.020, 0.0], seg(lod, 8, 5), sharp=SMOOTH,
				ring_swatches=[row("steel"), row("steel"), row("brass")])
		geo.merge(bm, horn)
		fin_at = H + Vector((side * 0.135, 0.030, -0.010))
		fin = geo.lathe([(0.060, 0.0), (0.046, 0.050), (0.020, 0.100), (0.0, 0.125)], seg(lod, 8, 5), row("fur_dark"),
				sharp=SMOOTH, phase=0.0, sy=0.30)
		geo.merge(bm, fin, geo.frame(fin_at, (side * 1.0, 0.45, 0.25), (0.0, 0.0, 1.0)))
	geo.merge(bm, animals._eyes(lod, skull, H, 0.068, 0.018, rx=0.034, ry=0.042))
	_brow_star(bm, skull, 0.0, H.y, H.z + 0.092, 0.040)
	geo.merge(bm, _sun_ring(H + Vector((0.0, 0.130, 0.160)), (0.0, -0.75, 0.66), 0.175, 0.018, seg(lod, 12, 8), lod))
	return bm


def _sun_dragon_team(lod, g):
	"""The team's saddle cloth edged in gold under a porcelain saddle with a
	cyan star, and the team's collar at the base of the neck with a gold
	sun medallion on the chest."""
	bm = geo.new_bm()
	geo.merge(bm, _saddle_cloth(lod, g + 0.425, y0=-0.130, y1=0.240, r=0.240, drop=0.170))
	saddle = geo.ellipsoid(0.115, 0.135, 0.042, seg(lod, 10, 7), 4, row("steel"), sharp=SMOOTH)
	geo.translate(saddle, (0.0, 0.050, g + 0.660))
	geo.merge(bm, saddle)
	for y, h in ((-0.065, 0.060), (0.170, 0.046)):
		lip = geo.ellipsoid(0.094, 0.026, h, seg(lod, 8, 6), 3, row("brass"), sharp=SMOOTH)
		geo.translate(lip, (0.0, y, g + 0.676))
		geo.merge(bm, lip)
	star = geo.plate(star_wanderers._star(0.040, 0.030, 0.012), 0.014, row("crystal"), sharp=40)
	geo.merge(bm, star, geo.orient(Vector((0.0, -0.088, g + 0.700)), (0.0, -1.0, 0.25), (0.0, 0.0, 1.0)))
	at = Vector((0.0, -0.290, g + 0.580))
	axis = Vector((0.0, -0.45, 0.89)).normalized()
	geo.merge(bm, _band(0.158, 0.050, lod), geo.frame(at, axis, (0.0, 0.0, 1.0)))
	medal_at = Vector((0.0, -0.445, g + 0.505))
	geo.merge(bm, _sun_ring(medal_at, (0.0, -1.0, -0.15), 0.045, 0.012, 8, lod, ray_len=0.030))
	disc = geo.ellipsoid(0.040, 0.012, 0.040, seg(lod, 10, 6), 4, row("brass"), sharp=SMOOTH)
	geo.translate(disc, medal_at)
	geo.merge(bm, disc)
	return bm


def sun_dragon(b, lod):
	g = b.base_height
	bm = animals._body(SUN_DRAGON_SPINE, lod, "fur", g=g)
	belly = geo.ellipsoid(0.160, 0.280, 0.100, seg(lod, 10, 7), 4, row("fur_light"), sharp=SMOOTH)
	geo.translate(belly, (0.0, 0.010, g + 0.255))
	geo.merge(bm, belly)
	chest = geo.ellipsoid(0.155, 0.120, 0.175, seg(lod, 12, 8), seg(lod, 6, 4), row("fur_light"), sharp=SMOOTH)
	geo.translate(chest, (0.0, -0.300, g + 0.440))
	geo.merge(bm, chest)
	neck_pts = [Vector((0.0, -0.250, g + 0.500)), Vector((0.0, -0.345, g + 0.640)), Vector((0.0, -0.395, g + 0.770))]
	geo.merge(bm, geo.tube(neck_pts, [0.150, 0.124, 0.108], seg(lod, 12, 8), row("fur"), sharp=SMOOTH))
	# Ivory scutes down the front of the neck.
	for k in range(seg(lod, 4, 2)):
		t = 0.15 + 0.75 * k / 3.0
		p = neck_pts[0].lerp(neck_pts[2], t) + Vector((0.0, -0.090 - 0.015 * t, -0.020))
		scute = geo.ellipsoid(0.085 - 0.012 * t, 0.040, 0.040, seg(lod, 9, 6), 4, row("fur_light"), sharp=SMOOTH)
		geo.merge(bm, scute, geo.frame(p, (0.0, -0.89, 0.45), (0.0, 0.0, 1.0)))
	segs = seg(lod, 9, 6)
	for side in (-1.0, 1.0):
		x = side * 0.150
		haunch = geo.ellipsoid(0.112, 0.175, 0.175, seg(lod, 10, 7), 5, row("fur"), sharp=SMOOTH)
		geo.translate(haunch, (side * 0.140, 0.200, g + 0.390))
		geo.merge(bm, haunch)
		shoulder = geo.ellipsoid(0.105, 0.140, 0.150, seg(lod, 10, 7), 5, row("fur"), sharp=SMOOTH)
		geo.translate(shoulder, (side * 0.140, -0.200, g + 0.400))
		geo.merge(bm, shoulder)
		for p0, p1, p2, r0 in (((x, -0.210, 0.360), (x * 1.06, -0.240, 0.180), (x * 1.06, -0.265, 0.060), 0.096),
				((x, 0.230, 0.330), (x * 1.08, 0.295, 0.170), (x * 1.08, 0.245, 0.060), 0.094)):
			a, b_, c = (Vector((p[0], p[1], g + p[2])) for p in (p0, p1, p2))
			geo.merge(bm, geo.tube([a, b_, c], [r0, r0 * 0.80, r0 * 0.74], segs, row("fur"), sharp=SMOOTH))
			foot = geo.ellipsoid(0.084, 0.100, 0.050, seg(lod, 9, 6), 3, row("fur"), sharp=SMOOTH, squash_bottom=0.3)
			geo.translate(foot, (c.x, c.y - 0.022, g + 0.034))
			geo.merge(bm, foot)
			for t in (-1.0, 0.0, 1.0):
				claw = _cone(0.016, 0.042, "bone", seg(lod, 5, 4))
				geo.merge(bm, claw, geo.frame(Vector((c.x + t * 0.040, c.y - 0.110, g + 0.030)), (t * 0.2, -1.0, -0.3),
						(0.0, 0.0, 1.0)))
	# A thick tail sweeping back and round to one side on the ground, ending
	# in a gold sun.
	tail = _catmull([Vector((0.0, 0.300, g + 0.400)), Vector((0.0, 0.460, g + 0.320)),
			Vector((0.090, 0.600, g + 0.190)), Vector((0.220, 0.660, g + 0.100)), Vector((0.360, 0.630, g + 0.070))], 3)
	radii = _catmull([0.120, 0.095, 0.072, 0.050, 0.026], 3)
	geo.merge(bm, geo.tube(tail, radii, seg(lod, 10, 6), row("fur"), sharp=SMOOTH, cap_end=row("fur")))
	sun = geo.plate(star_wanderers._star(0.075, 0.075, 0.034, points=8), 0.020, row("brass"), sharp=40)
	geo.merge(bm, sun, geo.orient(tail[-1] + Vector((0.030, -0.010, 0.040)), (0.0, -1.0, 0.35), (0.0, 0.0, 1.0)))
	# Porcelain dorsal spikes: neck, back and tail.
	ridge = [(neck_pts[2] + Vector((0.0, 0.070, 0.070)), Vector((0.0, 0.6, 0.8)), 0.050),
			(neck_pts[1] + Vector((0.0, 0.090, 0.090)), Vector((0.0, 0.5, 0.85)), 0.058),
			(neck_pts[0] + Vector((0.0, 0.090, 0.125)), Vector((0.0, 0.4, 0.9)), 0.064)]
	for y in (-0.150, -0.050, 0.050, 0.150, 0.250):
		ridge.append((Vector((0.0, y, g + 0.420 - 0.060 * y + 0.200)), Vector((0.0, 0.35, 1.0)), 0.070))
	for i in (2, 5, 8):
		t = (tail[i + 1] - tail[i - 1]).normalized()
		up = (Vector((0.0, 0.0, 1.0)) - t * t.z).normalized()
		ridge.append((tail[i] + up * radii[i] * 0.85, up + t * 0.5, radii[i] * 0.70))
	for p, d, h in ridge:
		spike = _cone(h * 0.42, h, "steel", seg(lod, 5, 4))
		geo.merge(bm, spike, geo.frame(p, d, (0.0, 1.0, 0.0)))
	for side in (-1.0, 1.0):
		geo.merge(bm, _bat_wing(lod, side, Vector((side * 0.130, -0.110, g + 0.620)), span=(0.55, 0.45, 0.75),
				lead=(0.0, 0.45, 1.0), size=1.10, bone="fur", skin="plate_dark", stars="brass"))
	geo.merge(bm, _sun_dragon_team(lod, g))
	geo.merge(bm, _sun_dragon_head(lod, g))
	return _grow(bm, g, SUN_DRAGON_SCALE)


# --- star wanderers: lightning dragon -------------------------------------------

LIGHTNING_DRAGON_SCALE = 1.9
## The serpent's path, tail tip to the back of its head: (x, y, z, radius).
## The tail lies on the ground; the body rises from it in an S.
LIGHTNING_PATH = [(0.320, 0.430, 0.030, 0.018), (0.340, 0.290, 0.050, 0.044), (0.240, 0.160, 0.074, 0.068),
		(0.070, 0.130, 0.094, 0.086), (-0.110, 0.090, 0.110, 0.098), (-0.160, -0.040, 0.180, 0.104),
		(-0.070, -0.080, 0.320, 0.106), (0.060, -0.030, 0.450, 0.104), (0.075, 0.030, 0.580, 0.096),
		(0.010, 0.020, 0.690, 0.088), (0.0, -0.050, 0.775, 0.082)]
LIGHTNING_HEAD = Vector((0.0, -0.110, 0.830))
LIGHTNING_HEAD_SCALE = 1.25


def _bolt(h):
	"""A zigzag lightning bolt outline along local +Z, `h` tall."""
	k = h / 0.110
	return [(-0.018 * k, 0.0), (0.016 * k, 0.0), (0.010 * k, 0.040 * k), (0.032 * k, 0.040 * k), (-0.004 * k, h),
			(0.002 * k, 0.060 * k), (-0.024 * k, 0.060 * k)]


def _bolt_plate(h, swatch="crystal", thick=0.014):
	return geo.plate(_bolt(h), thick, row(swatch), sharp=40)


def _lightning_head(lod, g):
	"""A long eastern dragon head: storm-blue with a navy brow, an ivory
	jaw, branching gold antlers, pearl-white cheek manes, long whiskers
	curling back to cyan tips, a cyan star on the brow."""
	H = LIGHTNING_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.112, 0.118, 0.098, seg(lod, 13, 8), seg(lod, 7, 5), row("beard"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	snout = geo.tube([H + Vector((0.0, -0.060, -0.015)), H + Vector((0.0, -0.160, -0.032)),
			H + Vector((0.0, -0.225, -0.034))], [0.080, 0.064, 0.056], seg(lod, 10, 7), row("beard"), sharp=SMOOTH,
			flatten=0.78, cap_end=row("beard"))
	geo.merge(bm, snout)
	nose = geo.ellipsoid(0.060, 0.040, 0.040, seg(lod, 9, 6), 4, row("beard"), sharp=SMOOTH)
	geo.translate(nose, H + Vector((0.0, -0.228, -0.012)))
	geo.merge(bm, nose)
	jaw = geo.tube([H + Vector((0.0, -0.020, -0.075)), H + Vector((0.0, -0.140, -0.092)),
			H + Vector((0.0, -0.205, -0.084))], [0.060, 0.048, 0.034], seg(lod, 9, 6), row("fur_light"), sharp=SMOOTH,
			flatten=0.6, cap_end=row("fur_light"))
	geo.merge(bm, jaw)
	brow = geo.ellipsoid(0.100, 0.050, 0.030, seg(lod, 10, 6), 4, row("beard_dark"), sharp=SMOOTH)
	geo.translate(brow, H + Vector((0.0, -0.050, 0.068)))
	geo.merge(bm, brow)
	wsteps = seg(lod, 3, 2)
	for side in (-1.0, 1.0):
		# Branching gold antlers.
		base = H + Vector((side * 0.055, 0.030, 0.075))
		mid = H + Vector((side * 0.085, 0.090, 0.170))
		top = H + Vector((side * 0.100, 0.170, 0.250))
		geo.merge(bm, geo.tube([base, mid, top], [0.028, 0.020, 0.0], seg(lod, 7, 5), row("brass"), sharp=SMOOTH))
		tine = geo.tube([mid, mid + Vector((side * 0.060, -0.030, 0.070)), mid + Vector((side * 0.075, -0.040, 0.110))],
				[0.017, 0.012, 0.0], seg(lod, 6, 4), row("brass"), sharp=SMOOTH)
		geo.merge(bm, tine)
		# Pearl-white cheek manes flaring back.
		for dz, k in ((-0.010, 1.0), (-0.065, 0.8)):
			tuft = geo.tube([H + Vector((side * 0.085, 0.010, dz)), H + Vector((side * 0.150, 0.070, dz - 0.010 * k)),
					H + Vector((side * 0.200 * k, 0.150, dz + 0.020))], [0.050 * k, 0.038 * k, 0.0], seg(lod, 8, 5),
					row("mane"), sharp=SMOOTH, flatten=0.55)
			geo.merge(bm, tuft)
		# Long whiskers from the snout tip, curling out and back, cyan ends.
		w = [H + Vector((side * 0.050, -0.235, -0.030)), H + Vector((side * 0.120, -0.250, -0.020)),
				H + Vector((side * 0.200, -0.200, 0.010)), H + Vector((side * 0.230, -0.120, 0.050)),
				H + Vector((side * 0.200, -0.080, 0.080))]
		wp = _catmull(w, wsteps)
		n = len(wp)
		geo.merge(bm, geo.tube(wp, [0.012] * (n - 1) + [0.005], seg(lod, 6, 4), sharp=SMOOTH,
				ring_swatches=[row("mane")] * (n - 1 - wsteps) + [row("crystal")] * wsteps))
		nostril = geo.ellipsoid(0.012, 0.010, 0.009, 6, 4, row("beard_dark"), sharp=SMOOTH)
		geo.translate(nostril, H + Vector((side * 0.026, -0.264, -0.004)))
		geo.merge(bm, nostril)
	geo.merge(bm, animals._eyes(lod, skull, H, 0.052, 0.012, rx=0.028, ry=0.034))
	_brow_star(bm, skull, 0.0, H.y, H.z + 0.085, 0.032)
	# Drawn big, chibi-style, round the back of the skull.
	pivot = H + Vector((0.0, 0.060, -0.040))
	geo.transform(bm, Matrix.Translation(pivot) @ Matrix.Scale(LIGHTNING_HEAD_SCALE, 4) @ Matrix.Translation(-pivot))
	return bm


def _lightning_body(lod, g):
	"""The serpent: a storm-blue tube with an ivory belly down its front,
	dark navy fins and cyan lightning bolts down its back, pearl tufts on
	the nape and a pearl tail plume round a cyan bolt. Returns the mesh and
	the curve (points, radii, (tangent, back) per point) for the harness."""
	pts = _catmull([Vector((x, y, g + z)) for x, y, z, _r in LIGHTNING_PATH], 3)
	radii = _catmull([r for _x, _y, _z, r in LIGHTNING_PATH], 3)
	bm = geo.tube(pts, radii, seg(lod, 12, 8), row("beard"), sharp=SMOOTH, cap_end=row("beard"))
	b_pts, b_nrm, b_w, frames = [], [], [], []
	for i, (p, r) in enumerate(zip(pts, radii)):
		t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
		belly = Vector((0.0, -1.0, -0.8))
		belly = (belly - t * belly.dot(t)).normalized()
		frames.append((t, -belly))
		if i >= 2:
			b_pts.append(p + belly * r * 0.92)
			b_nrm.append(belly)
			b_w.append(r * 0.85)
	geo.merge(bm, geo.ribbon(b_pts, b_nrm, 0.1, 0.012, row("fur_light"), sharp=SMOOTH, embed=0.010, widths=b_w))
	for i in range(3, len(pts) - 2):
		t, back = frames[i]
		r = radii[i]
		if i % 3 == 0:
			fin = _bolt_plate(r * 1.30)
		elif i % 3 == 1 and lod == 0:
			fin = geo.plate([(-0.034, 0.0), (0.030, 0.0), (0.020, r * 0.75)], 0.014, row("beard_dark"), sharp=40)
		else:
			continue
		geo.merge(bm, fin, geo.frame(pts[i] + back * r * 0.80, back, t.cross(back)))
	if lod == 0:
		for i in (len(pts) - 3, len(pts) - 5):
			t, back = frames[i]
			for side in (-1.0, 1.0):
				d = back - t * 0.8 + Vector((side * 0.5, 0.0, 0.0))
				geo.merge(bm, _cone(0.034, 0.090, "mane", 6), geo.frame(pts[i] + back * radii[i] * 0.7, d, (0.0, 0.0, 1.0)))
	# The tail plume: pearl tufts round a cyan bolt at the tip.
	tip, prev = pts[0], pts[2]
	d = (tip - prev).normalized()
	for a in range(seg(lod, 5, 3)):
		ang = math.radians(-60.0 + 30.0 * a)
		dd = (d + Vector((0.0, 0.0, 0.6)) + Vector((math.cos(ang), math.sin(ang), 0.0)) * 0.6).normalized()
		geo.merge(bm, _cone(0.040, 0.130, "mane", 6), geo.frame(tip - d * 0.020, dd, (0.0, 0.0, 1.0)))
	geo.merge(bm, _bolt_plate(0.190), geo.frame(tip, (d + Vector((0.0, 0.0, 0.9))).normalized(), (1.0, 0.0, 0.0)))
	return bm, pts, radii, frames


def _lightning_limbs(lod, g):
	"""Short legs: a hind pair on the ground coil, a front pair on the
	rising chest clutching a crackling cyan pearl."""
	bm = geo.new_bm()
	segs = seg(lod, 8, 5)
	for hip, foot in ((Vector((-0.020, 0.040, g + 0.100)), Vector((0.000, -0.070, g + 0.030))),
			(Vector((-0.060, 0.130, g + 0.100)), Vector((-0.120, 0.220, g + 0.030)))):
		knee = hip.lerp(foot, 0.5) + Vector((0.0, 0.0, 0.040))
		geo.merge(bm, geo.tube([hip, knee, foot], [0.050, 0.040, 0.034], segs, row("beard"), sharp=SMOOTH))
		paw = geo.ellipsoid(0.044, 0.054, 0.028, seg(lod, 8, 5), 3, row("beard_dark"), sharp=SMOOTH, squash_bottom=0.3)
		geo.translate(paw, (foot.x, foot.y - 0.010, g + 0.020))
		geo.merge(bm, paw)
		for t in (-1.0, 0.0, 1.0):
			claw = _cone(0.010, 0.030, "brass", 4)
			geo.merge(bm, claw, geo.frame(Vector((foot.x + t * 0.022, foot.y - 0.060, g + 0.016)), (t * 0.2, -1.0, -0.3),
					(0.0, 0.0, 1.0)))
	pearl_at = Vector((0.0, -0.250, g + 0.330))
	for side in (-1.0, 1.0):
		sh = Vector((side * 0.070, -0.110, g + 0.430))
		el = Vector((side * 0.120, -0.200, g + 0.390))
		hand = Vector((side * 0.055, -0.250, g + 0.340))
		geo.merge(bm, geo.tube([sh, el, hand], [0.042, 0.034, 0.028], segs, row("beard"), sharp=SMOOTH))
		for t in (-1.0, 0.0, 1.0):
			claw = _cone(0.009, 0.032, "brass", 4)
			geo.merge(bm, claw, geo.frame(hand + Vector((0.0, t * 0.016, 0.012)), (-side, 0.0, -0.4), (0.0, 0.0, 1.0)))
	pearl = geo.ellipsoid(0.060, 0.060, 0.060, seg(lod, 12, 8), seg(lod, 6, 4), row("crystal"), sharp=SMOOTH)
	geo.translate(pearl, pearl_at)
	geo.merge(bm, pearl)
	for k in range(seg(lod, 5, 3)):
		a = math.radians(30.0 + 72.0 * k)
		d = Vector((math.cos(a), -0.35, math.sin(a))).normalized()
		geo.merge(bm, _bolt_plate(0.085, thick=0.010), geo.frame(pearl_at + d * 0.050, d, (0.0, -1.0, 0.0)))
	return bm


def _lightning_team(lod, pts, radii, frames):
	"""The team's bands round the neck and the coil, each between gold
	rings, and the team's scarf knotted at the neck with two long tails
	streaming back, a gold star at each end."""
	bm = geo.new_bm()
	neck = len(pts) - 6
	for i in (neck, 13, 7):
		t, back = frames[i]
		r = radii[i]
		geo.merge(bm, _band(r + 0.016, 0.040, lod), geo.frame(pts[i], t, back))
		for off in (-0.046, 0.046):
			ring = geo.tube([Vector((0.0, 0.0, -0.007)), Vector((0.0, 0.0, 0.007))], [r + 0.020, r + 0.020],
					seg(lod, 14, 9), row("brass"), sharp=40)
			geo.merge(bm, ring, geo.frame(pts[i] + t * off, t, back))
	t, back = frames[neck]
	knot = pts[neck] + back * (radii[neck] + 0.020)
	side_v = t.cross(back).normalized()
	for side in (-1.0, 1.0):
		tail = [knot, knot + side_v * side * 0.060 + back * 0.050 + Vector((0.0, 0.040, -0.020)),
				knot + side_v * side * 0.130 + back * 0.090 + Vector((0.0, 0.140, -0.080)),
				knot + side_v * side * 0.160 + back * 0.110 + Vector((0.0, 0.250, -0.180))]
		geo.merge(bm, _curl(tail, [0.040, 0.060, 0.058, 0.040], lod, "team_cloth", flatten=0.22,
				up=side_v * side * 0.3 + Vector((0.0, 0.0, 1.0))))
		star = geo.plate(star_wanderers._star(0.034, 0.026, 0.011), 0.012, row("brass"), sharp=40)
		geo.merge(bm, star, geo.orient(tail[-1] + Vector((0.0, 0.010, -0.030)), (0.0, -1.0, 0.3), (0.0, 0.0, 1.0)))
	return bm


def lightning_dragon(b, lod):
	g = b.base_height
	bm, pts, radii, frames = _lightning_body(lod, g)
	for piece in (_lightning_limbs(lod, g), _lightning_team(lod, pts, radii, frames), _lightning_head(lod, g)):
		geo.merge(bm, piece)
	return _grow(bm, g, LIGHTNING_DRAGON_SCALE)
