"""Monsters (scenes/units/monsters): the great creatures any race can raise
at the neutral Shrine, drawn as huge chunky chibi toys. They must TOWER over
infantry (see docs/unit-figures.md, "Size"): each is designed at about a
horse's scale, like the beasts, then grown round the ground under its middle
(`beasts._grow`) by its *_SCALE, two to three times a Bestiary beast. Each
carries its owner's team colour on a harness. Palette: `monsters`
(palette.MONSTERS).

  black_dragon: a hulking charcoal dragon reared up on planted forelegs, its
    chest high and its neck curving up to a big horned head held forward;
    molten ember scutes down the throat, chest and belly and an ember glow in
    its half-open maw; a crown of four ivory horns swept back, heavy black
    brows; huge raised bat wings in dark oxblood membrane; a long tail low
    along the ground ending in a spade, black spikes from crown to spade.
    The team's saddle cloth on its back under a dark iron saddle, the team's
    collar at the base of the neck with an iron ring, team rags tied to its
    big horns.
  hydra: a squat, heavy sea-teal body low on four short thick legs, a tan
    belly, a fat tail curling low behind; five long necks fanning up and out
    from the shoulders like a hand, the middle one tallest, each ending in a
    round chibi head with a tan jaw, angry dark brows, fangs and a fan of
    gold crest fins. A team band round the base of every neck and the
    team's saddle cloth edged in gold on its back.
  skeleton_dragon: the great undead dragon, a step up from the Gnolls'
    Bestiary drake: reared like the black dragon on thick knobbed bone legs,
    a heavy vertebra spine with tall dorsal blades, a deep rib cage round a
    roaring jade soul fire, a massive horned skull with angry bone brows,
    jade fire burning in its sockets and trailing back from them, a jade
    glow in its open jaws; huge torn slate wings; a vertebra tail to a bone
    blade. The team's tattered caparison over its back, a ragged team war
    banner on a bone pole, a team collar with an iron ring, team rags tied
    to its horns.
  giant_bear: a colossal chestnut war-bear on all fours, a huge roaring head
    held low and forward under a dark iron war cap with a spike and cheek
    guards, angry dark brows, rust war-paint claw stripes on the shoulders,
    iron plates over the shoulders and an iron chain slung across the chest.
    The team's caparison over its back carries a wooden war-howdah with
    iron-capped posts, the team's round shields on its sides and a tall team
    war banner; the team's breast collar round the neck.
  yeti: a towering hunched white ape on short legs, huge shoulder mounds
    crusted with ice crystals, a blue-grey face, hands and feet, angry slate
    brows, a roaring underbite with ivory tusks, a crest of white shag; the
    left fist knuckling the ground, the right dragging a mammoth-bone club
    with a frozen boulder head bristling with ice spikes; icicles hanging
    off the arms. The team's fur-wrap kilt with flaps, a wide team sash
    across the chest and a team rag on the club.
  orc_mutant: a hunched, lopsided olive-grey brute on short thick legs, a
    huge swollen shoulder and arm of raw mauve flesh stitched onto the right
    side, bone spikes bursting out of it, bile pustules; the big fist raises
    a door-sized butcher's cleaver up and back, ready to chop (chipped
    bright edge turned forward), an iron pauldron with spikes on the small left arm, a manacle
    with a broken chain, a chain across the chest; an underbite with tusks,
    angry dark brows, one great bone horn out of the right of the skull, a
    stitched scar. The team's loincloth and a tattered team banner on a
    pole strapped to the back, a horned skull on top.
  dark_lord: a towering sorcerer-king in black-violet plate edged in gold,
    huge layered spiked pauldrons, a horned helm with a gold spiked crown, a
    dark T-visor with glowing violet eyes under gold brows in an angry V; a
    runed greatsword held point-down in the right hand (bright edges, a
    violet rune channel, a gold spiked guard), violet sorcery burning in the
    raised left hand. The team's huge cape to the ground (lined a darker
    team shade), a team mantle over the shoulders and the team's tabard.
  phoenix: a great fire bird standing tall on long charcoal legs bent back
    at the ankle, flame-orange plumage over an amber breast with a white-hot
    core, huge raised wings of flame feathers (orange primaries, amber
    coverts, white-hot at the root, deep ember undersides), a long trailing
    flame tail low along the ground curling up at its end, a hooked bronze
    beak open in a screech, the shared eyes under dark angry brows, a crest
    of flame tongues, white-hot embers off its back. Kept on orange, amber
    and white-hot so it never reads as the red or yellow team. The team's
    collar with an iron boss, a swallow-tailed team pennant down the
    breast, the team's jesses with ribbons on both shins.
"""
import math

import bmesh
from mathutils import Matrix, Vector

import animals
import geo
from beasts import _band, _bat_wing, _catmull, _cone, _curl, _grow, _saddle_cloth, _stripe, _wing_matrix, _wisp
from geo import HARD, SMOOTH
from palette import row
from parts import seg


# --- black dragon ----------------------------------------------------------------

BLACK_DRAGON_SCALE = 2.35
## (y, z, r): rump low behind, chest raised high in front.
BLACK_DRAGON_SPINE = [(-0.420, 0.700, 0.020), (-0.390, 0.700, 0.170), (-0.270, 0.660, 0.255), (-0.080, 0.580, 0.272),
		(0.120, 0.490, 0.250), (0.280, 0.440, 0.200), (0.360, 0.420, 0.0)]
BLACK_DRAGON_HEAD = Vector((0.0, -0.560, 1.230))


def _black_dragon_head(lod, g):
	"""A big round chibi head held forward: a long blunt snout over a half-
	open jaw with an ember glow inside and ivory fangs, heavy black brows, the
	shared eyes, and a crown of four ivory horns swept back."""
	H = BLACK_DRAGON_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.175, 0.170, 0.150, seg(lod, 14, 9), seg(lod, 7, 5), row("coat"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	# A long wedge of a snout, flat on top, tapering to a blunt tip.
	snout = geo.tube([H + Vector((0.0, -0.080, 0.000)), H + Vector((0.0, -0.220, -0.025)),
			H + Vector((0.0, -0.350, -0.040)), H + Vector((0.0, -0.395, -0.042))], [0.120, 0.092, 0.066, 0.040],
			seg(lod, 11, 7), row("coat"), sharp=SMOOTH, flatten=0.62, cap_end=row("coat"))
	geo.merge(bm, snout)
	jaw = geo.tube([H + Vector((0.0, -0.040, -0.105)), H + Vector((0.0, -0.200, -0.140)),
			H + Vector((0.0, -0.330, -0.140))], [0.090, 0.066, 0.040], seg(lod, 10, 6), row("coat"), sharp=SMOOTH,
			flatten=0.55, cap_end=row("coat"))
	geo.merge(bm, jaw)
	# The ember glow between the jaws.
	maw = geo.ellipsoid(0.066, 0.150, 0.036, seg(lod, 10, 6), 4, row("fur_red"), sharp=SMOOTH)
	geo.translate(maw, H + Vector((0.0, -0.210, -0.090)))
	geo.merge(bm, maw)
	for side in (-1.0, 1.0):
		nostril = geo.ellipsoid(0.016, 0.020, 0.010, 6, 4, row("coat_dark"), sharp=SMOOTH)
		geo.translate(nostril, H + Vector((side * 0.030, -0.385, -0.008)))
		geo.merge(bm, nostril)
		for y, h in ((-0.300, 0.052), (-0.200, 0.042)):
			fang = _cone(0.016, h, "bone", 4)
			geo.merge(bm, fang, geo.frame(H + Vector((side * 0.056, y, -0.070)), (0.0, -0.1, -1.0),
					(0.0, -1.0, 0.0)))
		low = _cone(0.014, 0.036, "bone", 4)
		geo.merge(bm, low, geo.frame(H + Vector((side * 0.044, -0.270, -0.120)), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0)))
		# Angry: the inner end low by the snout, the outer end raised.
		brow = geo.ellipsoid(0.050, 0.030, 0.072, seg(lod, 9, 6), 4, row("coat_dark"), sharp=SMOOTH)
		geo.merge(bm, brow, geo.frame(H + Vector((side * 0.084, -0.112, 0.100)), (side * 1.0, 0.22, 0.50),
				(0.0, -0.45, 1.0)))
		# The great horns, swept back from the crown, and a smaller pair
		# under them from the back of the jaw.
		horn = geo.tube([H + Vector((side * 0.090, 0.010, 0.110)), H + Vector((side * 0.150, 0.130, 0.190)),
				H + Vector((side * 0.180, 0.270, 0.210)), H + Vector((side * 0.165, 0.400, 0.165))],
				[0.054, 0.040, 0.024, 0.0], seg(lod, 8, 5), row("bone"), sharp=SMOOTH)
		geo.merge(bm, horn)
		small = geo.tube([H + Vector((side * 0.140, 0.060, -0.020)), H + Vector((side * 0.215, 0.160, 0.000)),
				H + Vector((side * 0.250, 0.250, -0.030))], [0.034, 0.022, 0.0], seg(lod, 7, 5), row("bone"),
				sharp=SMOOTH)
		geo.merge(bm, small)
		# The team's rag knotted round each great horn.
		rag_at = H + Vector((side * 0.152, 0.140, 0.188))
		axis = Vector((side * 0.30, 0.85, 0.40)).normalized()
		geo.merge(bm, _band(0.046, 0.028, lod, (10, 7)), geo.frame(rag_at, axis, (0.0, 0.0, 1.0)))
		if lod == 0:
			tail = geo.plate([(-0.030, 0.0), (0.030, 0.0), (0.022, -0.150), (0.0, -0.120), (-0.020, -0.160)], 0.010,
					row("team_cloth"), sharp=40, bend=0.2)
			geo.merge(bm, tail, geo.orient(rag_at + Vector((side * 0.030, 0.030, -0.020)), (side * 1.0, -0.3, 0.0),
					(0.0, 0.35, 1.0)))
	geo.merge(bm, animals._eyes(lod, skull, H, 0.078, 0.030, rx=0.034, ry=0.040))
	return bm


def _black_dragon_team(lod, g):
	"""The team's saddle cloth over the back under a dark iron saddle, and
	the team's collar at the base of the neck with an iron ring at the
	throat."""
	bm = geo.new_bm()
	geo.merge(bm, _saddle_cloth(lod, g + 0.600, y0=-0.200, y1=0.200, r=0.270, drop=0.190, edge="steel"))
	saddle = geo.ellipsoid(0.125, 0.145, 0.046, seg(lod, 10, 7), 4, row("steel"), sharp=SMOOTH)
	geo.translate(saddle, (0.0, 0.000, g + 0.865))
	geo.merge(bm, saddle)
	for y, h in ((-0.125, 0.066), (0.130, 0.050)):
		lip = geo.ellipsoid(0.100, 0.028, h, seg(lod, 8, 6), 3, row("leather_dark"), sharp=SMOOTH)
		geo.translate(lip, (0.0, y, g + 0.885))
		geo.merge(bm, lip)
	at = Vector((0.0, -0.440, g + 0.880))
	axis = Vector((0.0, -0.30, 0.95)).normalized()
	geo.merge(bm, _band(0.170, 0.058, lod), geo.frame(at, axis, (0.0, 0.0, 1.0)))
	ring_at = at + Vector((0.0, -0.175, -0.060))
	n = seg(lod, 14, 9)
	pts = [Vector((math.cos(2.0 * math.pi * i / n) * 0.050, 0.0, math.sin(2.0 * math.pi * i / n) * 0.050 - 0.050))
			for i in range(n + 1)]
	ring = geo.tube(pts, [0.013] * len(pts), seg(lod, 6, 4), row("steel"), sharp=SMOOTH)
	geo.translate(ring, ring_at)
	geo.merge(bm, ring)
	return bm


def _black_dragon_legs(lod, g):
	"""Thick forelegs planted forward under the raised chest, and big
	crouched haunches behind; ivory claws on round feet."""
	bm = geo.new_bm()
	segs = seg(lod, 9, 6)
	for side in (-1.0, 1.0):
		x = side * 0.180
		shoulder = geo.ellipsoid(0.120, 0.160, 0.180, seg(lod, 10, 7), 5, row("coat"), sharp=SMOOTH)
		geo.translate(shoulder, (side * 0.170, -0.300, g + 0.600))
		geo.merge(bm, shoulder)
		haunch = geo.ellipsoid(0.140, 0.220, 0.210, seg(lod, 10, 7), 5, row("coat"), sharp=SMOOTH)
		geo.translate(haunch, (side * 0.180, 0.190, g + 0.360))
		geo.merge(bm, haunch)
		legs = (((x * 1.05, -0.330, 0.560), (x * 1.10, -0.380, 0.300), (x * 1.10, -0.400, 0.070), 0.110),
				((x * 1.05, 0.160, 0.300), (x * 1.12, 0.020, 0.170), (x * 1.12, 0.060, 0.065), 0.112))
		for p0, p1, p2, r0 in legs:
			a, b_, c = (Vector((p[0], p[1], g + p[2])) for p in (p0, p1, p2))
			geo.merge(bm, geo.tube([a, b_, c], [r0, r0 * 0.80, r0 * 0.74], segs, row("coat"), sharp=SMOOTH))
			foot = geo.ellipsoid(0.098, 0.118, 0.056, seg(lod, 9, 6), 3, row("coat"), sharp=SMOOTH, squash_bottom=0.3)
			geo.translate(foot, (c.x, c.y - 0.028, g + 0.038))
			geo.merge(bm, foot)
			for t in (-1.0, 0.0, 1.0):
				claw = _cone(0.020, 0.054, "bone", seg(lod, 5, 4))
				geo.merge(bm, claw, geo.frame(Vector((c.x + t * 0.048, c.y - 0.130, g + 0.034)),
						(t * 0.2, -1.0, -0.3), (0.0, 0.0, 1.0)))
	return bm


def black_dragon(b, lod):
	g = b.base_height
	bm = animals._body(BLACK_DRAGON_SPINE, lod, "coat", g=g)
	# Molten ember: a big plate over the front of the chest, and scutes on
	# down the belly.
	chest = geo.ellipsoid(0.170, 0.090, 0.200, seg(lod, 12, 8), seg(lod, 6, 4), row("fur_red"), sharp=SMOOTH)
	geo.merge(bm, chest, geo.frame(Vector((0.0, -0.500, g + 0.640)), (0.0, 0.25, 1.0), (0.0, -1.0, 0.0)))
	belly = [(-0.330, 0.475, 0.150), (-0.200, 0.400, 0.150), (-0.060, 0.320, 0.150), (0.090, 0.265, 0.130)]
	for y, z, rx in (belly if lod == 0 else belly[::2]):
		scute = geo.ellipsoid(rx, 0.080, 0.050, seg(lod, 10, 7), 4, row("fur_red"), sharp=SMOOTH)
		geo.translate(scute, (0.0, y, g + z))
		geo.merge(bm, scute)
	neck_pts = [Vector((0.0, -0.360, g + 0.720)), Vector((0.0, -0.440, g + 0.900)), Vector((0.0, -0.430, g + 1.040)),
			Vector((0.0, -0.500, g + 1.150))]
	geo.merge(bm, geo.tube(neck_pts, [0.190, 0.155, 0.135, 0.125], seg(lod, 12, 8), row("coat"), sharp=SMOOTH))
	for k in range(seg(lod, 4, 2)):
		t = 0.10 + 0.80 * k / 3.0
		i = min(int(t * 3.0), 2)
		p = neck_pts[i].lerp(neck_pts[i + 1], t * 3.0 - i)
		d = (neck_pts[i + 1] - neck_pts[i]).normalized()
		front = (Vector((0.0, -1.0, 0.0)) - d * Vector((0.0, -1.0, 0.0)).dot(d)).normalized()
		scute = geo.ellipsoid(0.125 - 0.020 * t, 0.050, 0.056, seg(lod, 9, 6), 4, row("fur_red"), sharp=SMOOTH)
		geo.merge(bm, scute, geo.frame(p + front * (0.120 - 0.020 * t), front, d))
	geo.merge(bm, _black_dragon_legs(lod, g))
	# A long tail low along the ground, curling round to one side, ending in
	# a black spade.
	tail = _catmull([Vector((0.0, 0.320, g + 0.420)), Vector((0.0, 0.520, g + 0.260)),
			Vector((0.060, 0.760, g + 0.120)), Vector((0.220, 0.940, g + 0.070)), Vector((0.440, 1.000, g + 0.060)),
			Vector((0.600, 0.920, g + 0.070))], 3)
	radii = _catmull([0.170, 0.130, 0.095, 0.068, 0.046, 0.024], 3)
	geo.merge(bm, geo.tube(tail, radii, seg(lod, 10, 6), row("coat"), sharp=SMOOTH, cap_end=row("coat")))
	d = (tail[-1] - tail[-3]).normalized()
	spade = geo.plate([(0.0, 0.0), (0.080, 0.060), (0.060, 0.150), (0.0, 0.210), (-0.060, 0.150), (-0.080, 0.060)],
			0.026, row("coat_dark"), sharp=40)
	geo.rotate(spade, -90.0, 'X')
	geo.merge(bm, spade, geo.orient(tail[-1] - d * 0.010, -d, (0.0, 0.0, 1.0)))
	# Black spikes from the back of the neck down the back and tail.
	ridge = [(neck_pts[3] + Vector((0.0, 0.110, 0.070)), Vector((0.0, 0.7, 0.7)), 0.070),
			(neck_pts[2] + Vector((0.0, 0.125, 0.040)), Vector((0.0, 0.8, 0.6)), 0.080),
			(neck_pts[1] + Vector((0.0, 0.140, 0.060)), Vector((0.0, 0.6, 0.8)), 0.090)]
	for y in (-0.300, 0.230, 0.330):
		z = 0.660 - (y + 0.300) * 0.40
		ridge.append((Vector((0.0, y, g + z + 0.240)), Vector((0.0, 0.35, 1.0)), 0.100))
	for i in (2, 5, 8, 11):
		t = (tail[i + 1] - tail[i - 1]).normalized()
		up = (Vector((0.0, 0.0, 1.0)) - t * t.z).normalized()
		ridge.append((tail[i] + up * radii[i] * 0.85, up + t * 0.5, radii[i] * 0.75))
	for p, dd, h in ridge:
		spike = _cone(h * 0.42, h, "coat_dark", seg(lod, 5, 4))
		geo.merge(bm, spike, geo.frame(p, dd, (0.0, 1.0, 0.0)))
	# Huge raised wings, leaning back so their membranes face the camera.
	for side in (-1.0, 1.0):
		geo.merge(bm, _bat_wing(lod, side, Vector((side * 0.170, -0.150, g + 0.800)), span=(0.42, 0.55, 0.85),
				lead=(0.0, 0.40, 1.0), size=1.45, bone="coat", skin="coat_grey"))
	geo.merge(bm, _black_dragon_team(lod, g))
	geo.merge(bm, _black_dragon_head(lod, g))
	return _grow(bm, g, BLACK_DRAGON_SCALE)


# --- hydra ---------------------------------------------------------------------

HYDRA_SCALE = 2.35
## (y, z, r): a squat barrel, the front a little higher than the rump.
HYDRA_SPINE = [(-0.330, 0.460, 0.020), (-0.300, 0.455, 0.190), (-0.190, 0.440, 0.285), (-0.020, 0.430, 0.305),
		(0.140, 0.420, 0.285), (0.260, 0.410, 0.210), (0.310, 0.405, 0.0)]
## The five necks: fan angle in degrees (toward +X when positive) and the
## head's height. The middle one is tallest, the outer pair lowest.
HYDRA_NECKS = [(0.0, 1.480), (-31.0, 1.300), (31.0, 1.300), (-62.0, 1.060), (62.0, 1.060)]
## The heads are drawn this much bigger than the neck tips (chibi).
HYDRA_HEAD_SCALE = 1.22


def _hydra_head(lod):
	"""A round chibi head at the origin facing -Y: a blunt snout over a tan
	jaw, a half-open mouth with fangs, the shared eyes under angry dark
	brows, and a fan of gold crest fins swept back."""
	H = Vector((0.0, 0.0, 0.0))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.112, 0.115, 0.098, seg(lod, 10, 8), seg(lod, 6, 5), row("fur"), sharp=SMOOTH)
	geo.merge(bm, skull)
	snout = geo.tube([H + Vector((0.0, -0.060, -0.010)), H + Vector((0.0, -0.160, -0.030)),
			H + Vector((0.0, -0.215, -0.036))], [0.076, 0.060, 0.034], seg(lod, 8, 7), row("fur"), sharp=SMOOTH,
			flatten=0.66, cap_end=row("fur"))
	geo.merge(bm, snout)
	jaw = geo.tube([H + Vector((0.0, -0.020, -0.070)), H + Vector((0.0, -0.130, -0.092)),
			H + Vector((0.0, -0.190, -0.090))], [0.062, 0.046, 0.026], seg(lod, 7, 6), row("fur_light"), sharp=SMOOTH,
			flatten=0.6, cap_end=row("fur_light"))
	geo.merge(bm, jaw)
	mouth = geo.ellipsoid(0.044, 0.085, 0.020, seg(lod, 8, 6), 3, row("mouth"), sharp=SMOOTH)
	geo.translate(mouth, H + Vector((0.0, -0.120, -0.060)))
	geo.merge(bm, mouth)
	for side in (-1.0, 1.0):
		fang = _cone(0.012, 0.036, "bone", 4)
		geo.merge(bm, fang, geo.frame(H + Vector((side * 0.034, -0.170, -0.048)), (0.0, -0.1, -1.0), (0.0, -1.0, 0.0)))
		nostril = geo.ellipsoid(0.011, 0.013, 0.007, 6, 4, row("fur_dark"), sharp=SMOOTH)
		geo.translate(nostril, H + Vector((side * 0.022, -0.208, -0.010)))
		geo.merge(bm, nostril)
		# Angry: the inner end low over the snout, the outer end raised.
		brow = geo.ellipsoid(0.034, 0.020, 0.050, seg(lod, 8, 5), 4, row("fur_dark"), sharp=SMOOTH)
		geo.merge(bm, brow, geo.frame(H + Vector((side * 0.052, -0.090, 0.066)), (side * 1.0, 0.22, 0.55),
				(0.0, -0.45, 1.0)))
	# The gold crest: three fins fanned back over the crown, the middle tallest.
	# They face the front, so the crown reads from the camera.
	for dx, h in ((0.0, 0.150), (-0.050, 0.115), (0.050, 0.115)):
		fin = geo.plate([(-0.034, 0.0), (0.034, 0.0), (0.016, h * 0.55), (0.0, h), (-0.016, h * 0.55)], 0.018,
				row("brass"), sharp=40)
		lean = Vector((dx * 9.0, 0.40, 1.0))
		geo.merge(bm, fin, geo.frame(H + Vector((dx, 0.030 + abs(dx) * 0.4, 0.068)), lean, (0.0, 1.0, 0.0)))
	geo.merge(bm, animals._eyes(lod, skull, H, 0.050, 0.020, rx=0.025, ry=0.031))
	return bm


def _hydra_neck(lod, g, ang, top):
	"""One long neck from the shoulders curving up and out to its head: a
	tan throat strip, the team's band at its base between gold rims."""
	a = math.radians(ang)
	sx, fy = math.sin(a), math.cos(a)
	head = Vector((sx * 0.780, -0.400 - fy * 0.110, g + top))
	ctrl = [Vector((sx * 0.150, -0.200, g + 0.560)), Vector((sx * 0.300, -0.190, g + 0.800)),
			Vector((sx * 0.560, -0.170, g + top - 0.260)), Vector((sx * 0.720, -0.270 - fy * 0.080, g + top - 0.080)),
			head + Vector((0.0, 0.050, -0.030))]
	pts = _catmull(ctrl, 2)
	radii = _catmull([0.110, 0.088, 0.074, 0.068, 0.064], 2)
	bm = geo.new_bm()
	geo.merge(bm, geo.tube(pts, radii, seg(lod, 9, 7), row("fur"), sharp=SMOOTH))
	look = Vector((sx * 0.45, -1.0, 0.0)).normalized()
	n = len(pts)
	for k in range(seg(lod, 4, 3)):
		i = int((0.20 + 0.65 * k / 3.0) * (n - 1))
		t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
		front = (look - t * look.dot(t)).normalized()
		scute = geo.ellipsoid(radii[i] * 0.80, 0.030, radii[i] * 0.70, seg(lod, 7, 5), 3, row("fur_light"),
				sharp=SMOOTH)
		geo.merge(bm, scute, geo.frame(pts[i] + front * radii[i] * 0.72, front, t))
	i = max(1, int(0.34 * (n - 1)))
	t = (pts[i + 1] - pts[i - 1]).normalized()
	geo.merge(bm, _band(radii[i] + 0.012, 0.036, lod, (12, 8)), geo.frame(pts[i], t, (0.0, -1.0, 0.0)))
	for d in (-1.0, 1.0):
		rim = geo.lathe([(radii[i] + 0.004, -0.006), (radii[i] + 0.016, 0.0), (radii[i] + 0.004, 0.006)],
				seg(lod, 10, 8), row("brass"), sharp=40)
		geo.merge(bm, rim, geo.frame(pts[i] + t * d * 0.040, t, (0.0, -1.0, 0.0)))
	geo.merge(bm, _hydra_head(lod), geo.orient(head, look, (0.0, 0.0, 1.0)) @ Matrix.Scale(HYDRA_HEAD_SCALE, 4))
	return bm


def _hydra_legs(lod, g):
	"""Four short, thick pillar legs set wide, bone claws on round feet."""
	bm = geo.new_bm()
	for side in (-1.0, 1.0):
		for y, z in ((-0.170, 0.340), (0.170, 0.320)):
			top = Vector((side * 0.230, y, g + z))
			foot = Vector((side * 0.290, y - 0.020, g + 0.060))
			upper = geo.ellipsoid(0.120, 0.140, 0.140, seg(lod, 9, 6), 5, row("fur"), sharp=SMOOTH)
			geo.translate(upper, top)
			geo.merge(bm, upper)
			geo.merge(bm, geo.tube([top, top.lerp(foot, 0.55) + Vector((side * 0.020, 0.0, 0.0)), foot],
					[0.110, 0.092, 0.086], seg(lod, 9, 6), row("fur"), sharp=SMOOTH))
			pad = geo.ellipsoid(0.100, 0.115, 0.055, seg(lod, 9, 6), 3, row("fur"), sharp=SMOOTH, squash_bottom=0.3)
			geo.translate(pad, (foot.x, foot.y - 0.020, g + 0.040))
			geo.merge(bm, pad)
			for t in (-1.0, 0.0, 1.0):
				claw = _cone(0.020, 0.050, "bone", seg(lod, 5, 4))
				geo.merge(bm, claw, geo.frame(Vector((foot.x + t * 0.050, foot.y - 0.120, g + 0.032)),
						(t * 0.2, -1.0, -0.3), (0.0, 0.0, 1.0)))
	return bm


def hydra(b, lod):
	g = b.base_height
	bm = animals._body(HYDRA_SPINE, lod, "fur", g=g)
	belly = geo.ellipsoid(0.215, 0.300, 0.130, seg(lod, 12, 8), 5, row("fur_light"), sharp=SMOOTH)
	geo.translate(belly, (0.0, -0.020, g + 0.235))
	geo.merge(bm, belly)
	chest = geo.ellipsoid(0.200, 0.120, 0.170, seg(lod, 11, 7), 5, row("fur_light"), sharp=SMOOTH)
	geo.translate(chest, (0.0, -0.250, g + 0.390))
	geo.merge(bm, chest)
	geo.merge(bm, _hydra_legs(lod, g))
	# A fat tail low behind, curling round to one side.
	tail = _catmull([Vector((0.0, 0.250, g + 0.420)), Vector((0.0, 0.470, g + 0.290)),
			Vector((-0.060, 0.700, g + 0.130)), Vector((-0.240, 0.860, g + 0.070)), Vector((-0.450, 0.880, g + 0.060)),
			Vector((-0.580, 0.800, g + 0.060))], 3)
	radii = _catmull([0.210, 0.160, 0.115, 0.080, 0.050, 0.020], 3)
	geo.merge(bm, geo.tube(tail, radii, seg(lod, 10, 6), row("fur"), sharp=SMOOTH, cap_end=row("fur")))
	# Dark ridge plates down the rump and tail.
	ridge = [(Vector((0.0, 0.215, g + 0.680)), 0.090), (Vector((0.0, 0.275, g + 0.620)), 0.080)]
	for i in (2, 5, 8, 11):
		t = (tail[i + 1] - tail[i - 1]).normalized()
		up = (Vector((0.0, 0.0, 1.0)) - t * t.z).normalized()
		ridge.append((tail[i] + up * radii[i] * 0.85, radii[i] * 0.70))
	for p, h in ridge:
		spike = _cone(h * 0.48, h, "fur_dark", seg(lod, 5, 4))
		geo.merge(bm, spike, geo.frame(p, (0.0, 0.45, 1.0), (0.0, 1.0, 0.0)))
	geo.merge(bm, _saddle_cloth(lod, g + 0.430, y0=-0.120, y1=0.170, r=0.312, drop=0.190, edge="brass"))
	for ang, top in HYDRA_NECKS:
		geo.merge(bm, _hydra_neck(lod, g, ang, top))
	return _grow(bm, g, HYDRA_SCALE)


# --- skeleton dragon (the monster) ---------------------------------------------

## Much bigger and heavier than the Gnolls' Bestiary drake (beasts.py).
SKELETON_DRAGON_SCALE = 2.35
## The spine, tail tip to the base of the skull: (x, y, z, vertebra radius).
SKELETON_DRAGON_SPINE = [(0.560, 0.900, 0.060, 0.020), (0.330, 0.960, 0.070, 0.026), (0.120, 0.840, 0.120, 0.034),
		(0.020, 0.640, 0.250, 0.044), (0.0, 0.440, 0.430, 0.054), (0.0, 0.250, 0.560, 0.060),
		(0.0, 0.050, 0.640, 0.064), (0.0, -0.150, 0.720, 0.066), (0.0, -0.300, 0.800, 0.064),
		(0.0, -0.400, 0.940, 0.058), (0.0, -0.420, 1.080, 0.052), (0.0, -0.470, 1.180, 0.048)]
SKELETON_DRAGON_HEAD = Vector((0.0, -0.590, 1.250))
## The back's slope under the caparison (the front high).
SKELETON_DRAGON_TILT = 22.0


def _skel_spine(lod, g):
	"""Heavy knobbed vertebrae on a cord with tall dorsal blades, a deep rib
	cage hanging from the back round a roaring jade soul fire, the pelvis and
	shoulder blades, and a bone blade at the tail tip."""
	pts = _catmull([Vector((x, y, g + z)) for x, y, z, _r in SKELETON_DRAGON_SPINE], 2)
	radii = _catmull([r for _x, _y, _z, r in SKELETON_DRAGON_SPINE], 2)
	bm = geo.new_bm()
	geo.merge(bm, geo.tube(pts, [r * 0.55 for r in radii], seg(lod, 8, 5), row("bone"), sharp=SMOOTH))
	for i, (p, r) in enumerate(zip(pts, radii)):
		t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
		knob = geo.ellipsoid(r * 1.15, r * 1.15, r * 0.72, seg(lod, 7, 6), 4, row("bone"), sharp=SMOOTH)
		geo.merge(bm, knob, geo.frame(p, t, (0.0, 0.0, 1.0)))
		# Dorsal blades, left off under the caparison.
		under_cloth = -0.110 < p.y < 0.210 and abs(p.x) < 0.05
		if i % 2 == 0 and r > 0.028 and not under_cloth:
			up = (Vector((0.0, 0.0, 1.0)) - t * t.z).normalized()
			spike = _cone(r * 0.60, r * 2.3, "bone", seg(lod, 5, 4))
			geo.merge(bm, spike, geo.frame(p + up * r * 0.6, up - t * 0.45, t))
	# Ribs: deep pairs arcing out and down from the back to a keel.
	for k, y in enumerate((-0.260, -0.170, -0.080, 0.010, 0.100, 0.190)):
		if lod == 1 and k % 2:
			continue
		zs = g + 0.740 - (y + 0.260) * 0.36
		depth = 0.430 - 0.040 * k
		w = 0.270 - 0.012 * k
		for side in (-1.0, 1.0):
			rib = geo.tube([Vector((side * 0.040, y, zs)), Vector((side * w * 0.80, y + 0.012, zs - 0.050)),
					Vector((side * w, y + 0.030, zs - depth * 0.50)),
					Vector((side * w * 0.70, y + 0.045, zs - depth * 0.86)), Vector((side * 0.040, y + 0.050, zs - depth))],
					[0.034, 0.032, 0.029, 0.024, 0.020], seg(lod, 6, 5), row("bone"), sharp=SMOOTH)
			geo.merge(bm, rib)
	keel = geo.tube([Vector((0.0, -0.290, g + 0.320)), Vector((0.0, -0.050, g + 0.290)),
			Vector((0.0, 0.250, g + 0.390))], [0.040, 0.042, 0.026], seg(lod, 7, 5), row("bone"), sharp=SMOOTH)
	geo.merge(bm, keel)
	heart = geo.ellipsoid(0.125, 0.130, 0.140, seg(lod, 10, 7), 6, row("crystal"), sharp=SMOOTH)
	geo.translate(heart, (0.0, -0.060, g + 0.490))
	geo.merge(bm, heart)
	flames = ((-0.060, 0.010, 0.230), (0.065, 0.040, 0.190), (0.0, -0.060, 0.280), (0.030, -0.120, 0.170),
			(-0.040, 0.090, 0.150))
	for dx, dy, h in flames[:seg(lod, 5, 2)]:
		flame = _wisp(h * 0.45, "crystal")
		geo.merge(bm, flame, geo.frame(Vector((dx, -0.060 + dy, g + 0.560)), (dx, dy * 0.5 + 0.10, 1.0),
				(0.0, -1.0, 0.0)))
	pelvis = geo.ellipsoid(0.180, 0.130, 0.066, seg(lod, 10, 7), 4, row("bone"), sharp=SMOOTH)
	geo.translate(pelvis, (0.0, 0.420, g + 0.450))
	geo.merge(bm, pelvis)
	for side in (-1.0, 1.0):
		blade = geo.plate([(-0.070, 0.0), (0.085, 0.0), (0.045, -0.200), (-0.030, -0.185)], 0.028, row("bone"),
				sharp=40)
		geo.rotate(blade, side * 18.0, 'Z')
		geo.merge(bm, blade, geo.frame(Vector((side * 0.150, -0.310, g + 0.820)), (side * 1.0, 0.0, 0.3),
				(0.0, 0.0, 1.0)))
	# A bone blade at the tail tip.
	d = (pts[0] - pts[2]).normalized()
	tip = geo.plate([(0.0, 0.0), (0.070, 0.050), (0.090, 0.150), (0.0, 0.260), (-0.090, 0.150), (-0.070, 0.050)],
			0.030, row("bone"), sharp=40)
	geo.rotate(tip, -90.0, 'X')
	geo.merge(bm, tip, geo.orient(pts[0] - d * 0.020, -d, (0.0, 0.0, 1.0)))
	return bm


def _skel_limb(bm, joints, radii, lod):
	geo.merge(bm, geo.tube(joints, radii, seg(lod, 7, 5), row("bone"), sharp=SMOOTH))
	for p, r in zip(joints[:-1], radii):
		knob = geo.ellipsoid(r * 1.5, r * 1.5, r * 1.5, seg(lod, 7, 5), 4, row("bone"), sharp=SMOOTH)
		geo.translate(knob, p)
		geo.merge(bm, knob)


def _skel_legs(lod, g):
	"""Thick bone forelegs planted forward under the raised chest, crouched
	hind legs; long bone toes with black claws."""
	bm = geo.new_bm()
	for side in (-1.0, 1.0):
		front = [Vector((side * 0.200, -0.300, g + 0.720)), Vector((side * 0.250, -0.260, g + 0.420)),
				Vector((side * 0.230, -0.380, g + 0.150)), Vector((side * 0.230, -0.400, g + 0.045))]
		hind = [Vector((side * 0.190, 0.400, g + 0.450)), Vector((side * 0.250, 0.220, g + 0.290)),
				Vector((side * 0.240, 0.400, g + 0.130)), Vector((side * 0.240, 0.320, g + 0.045))]
		for joints in (front, hind):
			_skel_limb(bm, joints, [0.058, 0.050, 0.044, 0.040], lod)
			foot = joints[-1]
			for k in (-1.0, 0.0, 1.0):
				d = Vector((math.sin(math.radians(28.0 * k)), -math.cos(math.radians(28.0 * k)), -0.15)).normalized()
				end = foot + d * 0.120
				geo.merge(bm, geo.tube([foot, end], [0.030, 0.022], seg(lod, 6, 4), row("bone"), sharp=SMOOTH))
				claw = _cone(0.024, 0.070, "coat_dark", seg(lod, 5, 4))
				geo.merge(bm, claw, geo.frame(end - d * 0.008, (d.x, d.y, -0.6), (0.0, 0.0, 1.0)))
	return bm


def _skel_head(lod, g):
	"""A massive horned skull: a heavy cranium, a long toothed snout over an
	open jaw with a jade glow, dark sockets with jade fire burning in them
	and trailing back, angry bone brows (inner ends low), a crown of great
	horns and a frill of spikes behind, team rags on the great horns."""
	H = SKELETON_DRAGON_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	cranium = geo.ellipsoid(0.165, 0.165, 0.140, seg(lod, 13, 9), seg(lod, 7, 5), row("bone"), sharp=SMOOTH)
	geo.translate(cranium, H)
	geo.merge(bm, cranium)
	snout = geo.tube([H + Vector((0.0, -0.090, -0.005)), H + Vector((0.0, -0.240, -0.040)),
			H + Vector((0.0, -0.370, -0.055)), H + Vector((0.0, -0.405, -0.058))], [0.112, 0.088, 0.062, 0.040],
			seg(lod, 11, 7), row("bone"), sharp=SMOOTH, flatten=0.68, cap_end=row("bone"))
	geo.merge(bm, snout)
	jaw = geo.tube([H + Vector((0.0, -0.030, -0.120)), H + Vector((0.0, -0.200, -0.185)),
			H + Vector((0.0, -0.340, -0.190))], [0.078, 0.058, 0.036], seg(lod, 10, 6), row("bone"), sharp=SMOOTH,
			flatten=0.58, cap_end=row("bone"))
	geo.merge(bm, jaw)
	glow = geo.ellipsoid(0.060, 0.150, 0.040, seg(lod, 10, 6), 4, row("crystal"), sharp=SMOOTH)
	geo.translate(glow, H + Vector((0.0, -0.200, -0.115)))
	geo.merge(bm, glow)
	for side in (-1.0, 1.0):
		for k in range(seg(lod, 5, 3)):
			y = -0.140 - 0.050 * k
			tooth = _cone(0.014, 0.046, "bone", 4)
			geo.merge(bm, tooth, geo.frame(H + Vector((side * 0.058, y, -0.075 - 0.008 * k)), (0.0, 0.0, -1.0),
					(0.0, -1.0, 0.0)))
			low = _cone(0.012, 0.036, "bone", 4)
			geo.merge(bm, low, geo.frame(H + Vector((side * 0.046, y - 0.020, -0.165 - 0.004 * k)), (0.0, 0.0, 1.0),
					(0.0, -1.0, 0.0)))
		nostril = geo.ellipsoid(0.020, 0.026, 0.012, 6, 4, row("coat_dark"), sharp=SMOOTH)
		geo.translate(nostril, H + Vector((side * 0.034, -0.385, -0.018)))
		geo.merge(bm, nostril)
		# Angry bone brows: the inner end low by the snout, the outer raised.
		brow = geo.ellipsoid(0.050, 0.034, 0.080, seg(lod, 9, 6), 4, row("bone"), sharp=SMOOTH)
		geo.merge(bm, brow, geo.frame(H + Vector((side * 0.080, -0.120, 0.098)), (side * 1.0, 0.22, 0.50),
				(0.0, -0.45, 1.0)))
		# The great horns swept back off the crown, a lower pair, a cheek spur.
		horn = geo.tube([H + Vector((side * 0.085, 0.020, 0.110)), H + Vector((side * 0.150, 0.150, 0.210)),
				H + Vector((side * 0.190, 0.300, 0.250)), H + Vector((side * 0.180, 0.450, 0.200))],
				[0.056, 0.042, 0.026, 0.0], seg(lod, 8, 5), row("bone"), sharp=SMOOTH)
		geo.merge(bm, horn)
		mid = geo.tube([H + Vector((side * 0.130, 0.060, 0.020)), H + Vector((side * 0.220, 0.170, 0.050)),
				H + Vector((side * 0.270, 0.280, 0.010))], [0.038, 0.026, 0.0], seg(lod, 7, 5), row("bone"),
				sharp=SMOOTH)
		geo.merge(bm, mid)
		spur = geo.tube([H + Vector((side * 0.120, -0.040, -0.100)), H + Vector((side * 0.190, 0.040, -0.120)),
				H + Vector((side * 0.230, 0.110, -0.100))], [0.026, 0.017, 0.0], seg(lod, 6, 4), row("bone"),
				sharp=SMOOTH)
		geo.merge(bm, spur)
		# The team's rag tied round each great horn, its ends streaming back.
		knot = H + Vector((side * 0.155, 0.165, 0.215))
		geo.merge(bm, _band(0.044, 0.028, lod, (10, 7)), geo.frame(knot, (side * 0.30, 0.85, 0.40), (0.0, 0.0, 1.0)))
		rag = [knot, knot + Vector((side * 0.040, 0.100, -0.050)), knot + Vector((side * 0.070, 0.210, -0.060)),
				knot + Vector((side * 0.090, 0.310, -0.140))]
		geo.merge(bm, _curl(rag, [0.048, 0.056, 0.050, 0.026], lod, "team_cloth", flatten=0.25, up=(side, 0.0, 0.3)))
	# A frill of short spikes round the back of the skull.
	count = seg(lod, 5, 3)
	for k in range(count):
		a = math.radians(-50.0 + 100.0 * k / (count - 1))
		d = Vector((math.sin(a) * 0.9, 0.7, math.cos(a) * 0.6)).normalized()
		spike = _cone(0.026, 0.090, "bone", seg(lod, 5, 4))
		geo.merge(bm, spike, geo.frame(H + Vector((math.sin(a) * 0.110, 0.120, math.cos(a) * 0.060)), d,
				(0.0, 0.0, 1.0)))
	# Dark sockets with jade fire in them, trailing back over the crown.
	tree = geo.bvh(cranium)
	for side in (-1.0, 1.0):
		loc, nrm = geo.project(tree, (side * 0.074, H.y - 1.0, H.z + 0.030), (0.0, 1.0, 0.0))
		if loc is None:
			continue
		geo.merge(bm, geo.disc(0.046, 0.040, seg(lod, 10, 6), row("coat_dark"), dome=-0.004, depth=0.003),
				geo.frame(loc + nrm * 0.002, nrm, (0.0, 0.0, 1.0)))
		geo.merge(bm, geo.disc(0.022, 0.024, seg(lod, 8, 5), row("crystal"), dome=0.008, depth=0.002),
				geo.frame(loc + nrm * 0.007, nrm, (0.0, 0.0, 1.0)))
		if lod == 0:
			trail = _wisp(0.050, "crystal")
			geo.merge(bm, trail, geo.frame(loc + Vector((side * 0.020, 0.010, 0.020)), (side * 0.35, 0.80, 0.55),
					(0.0, 0.0, 1.0)))
	return bm


def _skel_team(lod, g):
	"""The team's tattered caparison over the back (tilted with it), a ragged
	team war banner on a bone pole behind it, the team's collar at the base
	of the neck with an iron ring."""
	bm = geo.new_bm()
	cloth = _saddle_cloth(lod, 0.0, y0=-0.150, y1=0.150, r=0.215, drop=0.055, edge="steel")
	geo.transform(cloth, Matrix.Translation((0.0, 0.050, g + 0.610))
			@ Matrix.Rotation(math.radians(-SKELETON_DRAGON_TILT), 4, 'X'))
	geo.merge(bm, cloth)
	if lod == 0:
		# Ragged tatters hanging off the cloth's sides.
		for side in (-1.0, 1.0):
			for y in (-0.060, 0.050, 0.160):
				z = 0.610 - (y - 0.050) * math.tan(math.radians(SKELETON_DRAGON_TILT)) - 0.055
				tat = geo.plate([(-0.045, 0.0), (0.045, 0.0), (0.030, -0.110), (0.0, -0.070), (-0.025, -0.140)],
						0.010, row("team_cloth"), sharp=40)
				geo.rotate(tat, 90.0, 'Z')
				geo.translate(tat, (side * 0.210, y, g + z + 0.010))
				geo.merge(bm, tat)
	# The war banner on a bone pole, planted on the pelvis behind the wings.
	base = Vector((0.0, 0.400, g + 0.460))
	top = Vector((0.0, 0.460, g + 1.300))
	geo.merge(bm, geo.tube([base, top], [0.022, 0.018], seg(lod, 7, 5), row("bone"), sharp=SMOOTH))
	cross = geo.tube([top + Vector((-0.175, 0.0, -0.050)), top + Vector((0.175, 0.0, -0.050))], [0.016, 0.016],
			seg(lod, 6, 4), row("bone"), sharp=SMOOTH)
	geo.merge(bm, cross)
	for side in (-1.0, 1.0):
		knob = geo.ellipsoid(0.026, 0.026, 0.026, 6, 4, row("bone"), sharp=SMOOTH)
		geo.translate(knob, top + Vector((side * 0.180, 0.0, -0.050)))
		geo.merge(bm, knob)
	finial = _cone(0.034, 0.110, "steel", seg(lod, 6, 4))
	geo.merge(bm, finial, geo.frame(top, (0.0, 0.0, 1.0), (0.0, 1.0, 0.0)))
	flag = geo.plate([(-0.165, 0.0), (0.165, 0.0), (0.165, -0.360), (0.100, -0.300), (0.050, -0.420), (0.0, -0.330),
			(-0.060, -0.440), (-0.110, -0.310), (-0.165, -0.380)], 0.014, row("team_cloth"), row("team_cloth_dark"),
			sharp=40, bend=0.15)
	geo.translate(flag, top + Vector((0.0, 0.016, -0.065)))
	geo.merge(bm, flag)
	# The collar round the base of the neck, an iron ring at the throat.
	at = Vector((0.0, -0.395, g + 0.900))
	axis = Vector((0.0, -0.20, 0.98)).normalized()
	geo.merge(bm, _band(0.105, 0.050, lod, (12, 8)), geo.frame(at, axis, (0.0, 0.0, 1.0)))
	n = seg(lod, 12, 8)
	pts = [Vector((math.cos(2.0 * math.pi * i / n) * 0.050, 0.0, math.sin(2.0 * math.pi * i / n) * 0.050 - 0.050))
			for i in range(n + 1)]
	ring = geo.tube(pts, [0.013] * len(pts), seg(lod, 6, 4), row("steel"), sharp=SMOOTH)
	geo.translate(ring, at + Vector((0.0, -0.105, -0.040)))
	geo.merge(bm, ring)
	return bm


def skeleton_dragon(b, lod):
	g = b.base_height
	bm = geo.new_bm()
	for piece in (_skel_spine(lod, g), _skel_legs(lod, g), _skel_team(lod, g), _skel_head(lod, g)):
		geo.merge(bm, piece)
	for side in (-1.0, 1.0):
		geo.merge(bm, _bat_wing(lod, side, Vector((side * 0.150, -0.200, g + 0.840)), span=(0.42, 0.55, 0.85),
				lead=(0.0, 0.40, 1.0), size=1.55, bone="bone", skin="mane", tattered=True))
	return _grow(bm, g, SKELETON_DRAGON_SCALE)


# --- giant bear --------------------------------------------------------------

GIANT_BEAR_SCALE = 2.35
## (y, z, r): a long heavy barrel, the shoulders a little higher than the rump.
GIANT_BEAR_SPINE = [(-0.460, 0.560, 0.020), (-0.420, 0.575, 0.220), (-0.280, 0.590, 0.305), (-0.060, 0.565, 0.320),
		(0.160, 0.530, 0.300), (0.320, 0.505, 0.235), (0.400, 0.495, 0.0)]
GIANT_BEAR_HEAD = Vector((0.0, -0.640, 0.660))
## The war-howdah's floor: its centre (y), height (z), half width, half depth.
GIANT_BEAR_HOWDAH = (0.110, 0.880, 0.205, 0.165)


def _ring(centre, axis, radius, thick, lod, swatch="steel", up=(0.0, 0.0, 1.0)):
	"""A closed ring (a chain link, an iron ring) round `axis`."""
	n = seg(lod, 8, 6)
	pts = [Vector((math.cos(2.0 * math.pi * i / n) * radius, math.sin(2.0 * math.pi * i / n) * radius, 0.0))
			for i in range(n + 1)]
	bm = geo.tube(pts, [thick] * len(pts), seg(lod, 5, 4), row(swatch), sharp=SMOOTH)
	geo.transform(bm, geo.frame(centre, axis, up))
	return bm


def _brow(H, side, inner, mid, outer, radii, swatch, lod):
	"""An angry brow: a flattened bar from `inner` (low, by the nose) through
	`mid` to `outer` (high, over the outer corner of the eye), each (x, y, z)
	from the head's centre `H` for the +X side, mirrored by `side`."""
	pts = [H + Vector((side * p[0], p[1], p[2])) for p in (inner, mid, outer)]
	return geo.tube(pts, list(radii), seg(lod, 8, 6), row(swatch), sharp=SMOOTH, flatten=0.55,
			up=(0.0, -1.0, 0.25), cap_start=row(swatch), cap_end=row(swatch))


def _giant_bear_head(lod, g):
	"""A huge round head held low and forward, roaring: a cream muzzle over
	an open mouth with ivory fangs, heavy dark brows in an angry frown, round
	ears, the shared eyes; a dark iron war cap on the crown with a spike."""
	H = GIANT_BEAR_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.225, 0.195, 0.195, seg(lod, 14, 9), seg(lod, 7, 5), row("beard"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	for side in (-1.0, 1.0):
		cheek = geo.ellipsoid(0.105, 0.100, 0.092, seg(lod, 9, 6), 4, row("beard"), sharp=SMOOTH)
		geo.translate(cheek, H + Vector((side * 0.140, 0.015, -0.072)))
		geo.merge(bm, cheek)
	muzzle = geo.tube([H + Vector((0.0, -0.110, -0.052)), H + Vector((0.0, -0.225, -0.060)),
			H + Vector((0.0, -0.280, -0.064))], [0.110, 0.088, 0.054], seg(lod, 10, 7), row("cream"),
			sharp=SMOOTH, flatten=0.70, cap_end=row("cream"))
	geo.merge(bm, muzzle)
	nose = geo.ellipsoid(0.052, 0.034, 0.034, seg(lod, 8, 5), 3, row("nose"), sharp=SMOOTH)
	geo.translate(nose, H + Vector((0.0, -0.282, -0.026)))
	geo.merge(bm, nose)
	# The roar: a dark open mouth under the muzzle, a lowered cream jaw.
	mouth = geo.ellipsoid(0.072, 0.090, 0.040, seg(lod, 9, 6), 4, row("mouth"), sharp=SMOOTH)
	geo.translate(mouth, H + Vector((0.0, -0.190, -0.118)))
	geo.merge(bm, mouth)
	jaw = geo.tube([H + Vector((0.0, -0.060, -0.140)), H + Vector((0.0, -0.170, -0.168)),
			H + Vector((0.0, -0.236, -0.168))], [0.080, 0.064, 0.036], seg(lod, 9, 6), row("cream"), sharp=SMOOTH,
			flatten=0.55, cap_end=row("cream"))
	geo.merge(bm, jaw)
	for side in (-1.0, 1.0):
		fang = _cone(0.018, 0.058, "bone", 4)
		geo.merge(bm, fang, geo.frame(H + Vector((side * 0.050, -0.236, -0.088)), (0.0, -0.1, -1.0), (0.0, -1.0, 0.0)))
		low = _cone(0.016, 0.046, "bone", 4)
		geo.merge(bm, low, geo.frame(H + Vector((side * 0.044, -0.214, -0.150)), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0)))
		# Angry: a flat bar from the inner end, low on the bridge of the
		# muzzle, up to the outer end raised over the eye. (A tilted
		# ellipsoid half-sunk in the skull showed only its outer half, which
		# read as drooping, sad brows.)
		geo.merge(bm, _brow(H, side, (0.030, -0.194, 0.036), (0.086, -0.180, 0.084), (0.142, -0.128, 0.128),
				(0.026, 0.034, 0.024), "beard_dark", lod))
		ear = geo.ellipsoid(0.074, 0.034, 0.068, seg(lod, 10, 7), seg(lod, 5, 4), row("beard"), sharp=SMOOTH)
		inner = geo.disc(0.042, 0.040, seg(lod, 8, 6), row("beard_dark"), dome=0.003, depth=0.004)
		geo.merge(ear, inner, geo.frame((0.0, -0.030, -0.004), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
		geo.rotate(ear, side * 32.0, 'Y')
		geo.translate(ear, H + Vector((side * 0.165, 0.040, 0.150)))
		geo.merge(bm, ear)
	# The iron war cap: a dome on the crown between the ears, a rim and a
	# short spike.
	cap = geo.ellipsoid(0.175, 0.170, 0.105, seg(lod, 12, 8), seg(lod, 5, 3), row("steel"), sharp=SMOOTH,
			squash_bottom=0.2)
	geo.translate(cap, H + Vector((0.0, 0.030, 0.130)))
	geo.merge(bm, cap)
	rim = geo.lathe([(0.168, -0.012), (0.180, 0.0), (0.168, 0.012)], seg(lod, 12, 8), row("steel"), sharp=40)
	geo.merge(bm, rim, geo.frame(H + Vector((0.0, 0.030, 0.128)), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0)))
	spike = _cone(0.040, 0.130, "steel", seg(lod, 6, 4))
	geo.merge(bm, spike, geo.frame(H + Vector((0.0, 0.010, 0.225)), (0.0, -0.25, 1.0), (0.0, 1.0, 0.0)))
	geo.merge(bm, animals._eyes(lod, skull, H, 0.092, 0.040, rx=0.034, ry=0.042))
	return bm


def _giant_bear_legs(lod, g):
	"""Four short, massive pillar legs, dark paws with ivory claws; two iron
	plates over each shoulder."""
	bm = geo.new_bm()
	for side in (-1.0, 1.0):
		for y, top, x in ((-0.300, 0.560, 0.205), (0.255, 0.520, 0.215)):
			p0 = Vector((side * x, y, g + top))
			p2 = Vector((side * x * 1.06, y - 0.020, g + 0.070))
			leg = geo.tube([p0, p0.lerp(p2, 0.55) + Vector((side * 0.012, 0.0, 0.0)), p2], [0.150, 0.122, 0.112],
					seg(lod, 10, 7), row("beard"), sharp=SMOOTH)
			geo.merge(bm, leg)
			paw = geo.ellipsoid(0.118, 0.140, 0.064, seg(lod, 10, 6), seg(lod, 4, 3), row("beard_dark"), sharp=SMOOTH,
					squash_bottom=0.3)
			geo.translate(paw, (p2.x, p2.y - 0.040, g + 0.040))
			geo.merge(bm, paw)
			if lod == 0:
				for k in (-1.0, 0.0, 1.0):
					claw = _cone(0.018, 0.058, "bone", 4)
					geo.merge(bm, claw, geo.frame(Vector((p2.x + k * 0.050, p2.y - 0.165, g + 0.030)),
							(k * 0.2, -1.0, -0.35), (0.0, 0.0, 1.0)))
		haunch = geo.ellipsoid(0.150, 0.210, 0.200, seg(lod, 10, 7), 5, row("beard"), sharp=SMOOTH)
		geo.translate(haunch, (side * 0.190, 0.240, g + 0.520))
		geo.merge(bm, haunch)
		for k, (dz, r) in enumerate(((0.0, 1.0), (-0.090, 0.86))):
			plate = geo.ellipsoid(0.175 * r, 0.215 * r, 0.090, seg(lod, 10, 7), seg(lod, 4, 3), row("steel"),
					sharp=HARD, squash_bottom=0.25)
			geo.merge(bm, plate, geo.frame(Vector((side * (0.235 + 0.035 * k), -0.290, g + 0.800 + dz)),
					(side * 0.70, 0.0, 0.72), (0.0, -1.0, 0.0)))
	return bm


def _giant_bear_harness(lod, g):
	"""The team's war caparison over the back, a wooden war-howdah on it with
	iron-capped corner posts and iron bands, the team's round shields hung
	on its sides and a tall team war banner at its back; the team's breast
	collar and an iron chain slung across the chest."""
	bm = geo.new_bm()
	geo.merge(bm, _saddle_cloth(lod, g + 0.545, y0=-0.140, y1=0.380, r=0.338, drop=0.290, edge="steel"))
	hy, hz, hx, hd = GIANT_BEAR_HOWDAH
	floor = geo.box(hx * 2.0 + 0.030, hd * 2.0 + 0.030, 0.040, row("wood"), bevel=0.008)
	geo.translate(floor, (0.0, hy, g + hz))
	geo.merge(bm, floor)
	wall_h = 0.170
	for side in (-1.0, 1.0):
		wall = geo.box(0.030, hd * 2.0, wall_h, row("wood"))
		geo.translate(wall, (side * hx, hy, g + hz + wall_h * 0.5))
		geo.merge(bm, wall)
		end = geo.box(hx * 2.0, 0.030, wall_h, row("wood"))
		geo.translate(end, (0.0, hy + side * hd, g + hz + wall_h * 0.5))
		geo.merge(bm, end)
		for s2 in (-1.0, 1.0):
			post = geo.box(0.060, 0.060, wall_h + 0.080, row("wood"))
			geo.translate(post, (side * hx, hy + s2 * hd, g + hz + (wall_h + 0.080) * 0.5))
			geo.merge(bm, post)
			top = _cone(0.046, 0.070, "steel", 4)
			geo.merge(bm, top, geo.frame(Vector((side * hx, hy + s2 * hd, g + hz + wall_h + 0.080)), (0.0, 0.0, 1.0),
					(0.0, 1.0, 0.0)))
		for dz in (0.030, wall_h - 0.020):
			band = geo.box(0.040, hd * 2.0 + 0.010, 0.020, row("steel"))
			geo.translate(band, (side * hx, hy, g + hz + dz))
			geo.merge(bm, band)
		# The team's round shield on each side, an iron rim and boss.
		at = Vector((side * (hx + 0.024), hy, g + hz + 0.085))
		face = geo.disc(0.110, 0.110, seg(lod, 14, 9), row("team_paint"), dome=0.014, depth=0.018)
		geo.merge(bm, face, geo.frame(at, (side, 0.0, 0.0), (0.0, 0.0, 1.0)))
		rim = geo.lathe([(0.102, -0.010), (0.116, 0.0), (0.102, 0.010)], seg(lod, 14, 9), row("steel"), sharp=40)
		geo.merge(bm, rim, geo.frame(at + Vector((side * 0.008, 0.0, 0.0)), (side, 0.0, 0.0), (0.0, 0.0, 1.0)))
		boss = geo.ellipsoid(0.034, 0.034, 0.022, seg(lod, 8, 5), 3, row("steel"), sharp=SMOOTH)
		geo.merge(bm, boss, geo.frame(at + Vector((side * 0.026, 0.0, 0.0)), (side, 0.0, 0.0), (0.0, 0.0, 1.0)))
	# The war banner at the back of the howdah.
	base = Vector((0.0, hy + hd - 0.040, g + hz))
	top = Vector((0.0, hy + hd - 0.010, g + 1.640))
	geo.merge(bm, geo.tube([base, top], [0.022, 0.018], seg(lod, 7, 5), row("wood"), sharp=SMOOTH))
	finial = _cone(0.036, 0.110, "steel", seg(lod, 6, 4))
	geo.merge(bm, finial, geo.frame(top, (0.0, 0.0, 1.0), (0.0, 1.0, 0.0)))
	cross = geo.tube([top + Vector((-0.170, 0.0, -0.040)), top + Vector((0.170, 0.0, -0.040))], [0.014, 0.014],
			seg(lod, 6, 4), row("wood"), sharp=SMOOTH)
	geo.merge(bm, cross)
	flag = geo.plate([(-0.160, 0.0), (0.160, 0.0), (0.160, -0.400), (0.0, -0.310), (-0.160, -0.400)], 0.014,
			row("team_cloth"), row("team_cloth_dark"), sharp=40, bend=0.15)
	geo.translate(flag, top + Vector((0.0, 0.014, -0.052)))
	geo.merge(bm, flag)
	paw = geo.plate([(-0.060, 0.0), (0.060, 0.0), (0.050, -0.090), (0.0, -0.120), (-0.050, -0.090)], 0.006,
			row("steel"), sharp=40)
	geo.translate(paw, top + Vector((0.0, 0.002, -0.130)))
	geo.merge(bm, paw)
	# The team's breast collar round the base of the neck.
	at = Vector((0.0, -0.470, g + 0.640))
	geo.merge(bm, _band(0.270, 0.060, lod, (14, 9)), geo.frame(at, (0.0, -0.80, 0.60), (0.0, 0.0, 1.0)))
	# An iron chain slung across the chest from plate to plate.
	n = seg(lod, 9, 5)
	for i in range(n):
		t = i / (n - 1)
		sag = math.sin(math.pi * t)
		p = Vector((-0.250 + 0.500 * t, -0.540 - 0.050 * sag, g + 0.640 - 0.160 * sag))
		if i % 2 == 0:
			geo.merge(bm, _ring(p, (0.0, -1.0, 0.0), 0.034, 0.011, lod, up=(0.0, 0.0, 1.0)))
		else:
			geo.merge(bm, _ring(p, (0.0, 0.0, 1.0), 0.034, 0.011, lod, up=(0.0, 1.0, 0.0)))
	return bm


def giant_bear(b, lod):
	g = b.base_height
	bm = animals._body(GIANT_BEAR_SPINE, lod, "beard", g=g)
	# The great shoulder hump and a shaggy chest.
	hump = geo.ellipsoid(0.240, 0.230, 0.170, seg(lod, 11, 7), seg(lod, 5, 4), row("beard"), sharp=SMOOTH)
	geo.translate(hump, (0.0, -0.230, g + 0.780))
	geo.merge(bm, hump)
	chest = geo.ellipsoid(0.250, 0.170, 0.250, seg(lod, 11, 7), seg(lod, 5, 4), row("beard"), sharp=SMOOTH)
	geo.translate(chest, (0.0, -0.420, g + 0.520))
	geo.merge(bm, chest)
	# Rust war paint: claw stripes down each flank in front of the cloth.
	if lod == 0:
		tree = geo.bvh(bm)
		for side in (-1.0, 1.0):
			for y in (-0.330, -0.230):
				_stripe(bm, tree, y, g + 0.570, side, 45.0, 110.0, 0.036, "warpaint", sweep=0.050, lod=lod)
	tail = geo.ellipsoid(0.060, 0.055, 0.055, seg(lod, 7, 5), 3, row("beard_dark"), sharp=SMOOTH)
	geo.translate(tail, (0.0, 0.430, g + 0.560))
	geo.merge(bm, tail)
	geo.merge(bm, _giant_bear_legs(lod, g))
	geo.merge(bm, _giant_bear_harness(lod, g))
	head = _giant_bear_head(lod, g)
	H = GIANT_BEAR_HEAD + Vector((0.0, 0.0, g))
	geo.transform(head, Matrix.Translation(H) @ Matrix.Scale(1.12, 4) @ Matrix.Translation(-H))
	geo.merge(bm, head)
	return _grow(bm, g, GIANT_BEAR_SCALE)


# --- yeti --------------------------------------------------------------------

YETI_SCALE = 2.35
YETI_HEAD = Vector((0.0, -0.250, 1.230))


def _yeti_head(lod, g):
	"""A big shaggy white head sunk between the shoulders: a blue-grey face,
	heavy slate brows in an angry frown, the shared eyes, a wide roaring mouth
	over an underbite with two ivory tusks, a crest of white shag."""
	H = YETI_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.215, 0.195, 0.200, seg(lod, 13, 8), seg(lod, 7, 5), row("hair"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	face = geo.ellipsoid(0.160, 0.100, 0.150, seg(lod, 12, 8), seg(lod, 6, 4), row("skin"), sharp=SMOOTH)
	geo.translate(face, H + Vector((0.0, -0.118, -0.030)))
	geo.merge(bm, face)
	mouth = geo.ellipsoid(0.100, 0.050, 0.044, seg(lod, 10, 6), 4, row("mouth"), sharp=SMOOTH)
	geo.translate(mouth, H + Vector((0.0, -0.200, -0.098)))
	geo.merge(bm, mouth)
	jaw = geo.ellipsoid(0.125, 0.090, 0.060, seg(lod, 10, 6), 4, row("skin"), sharp=SMOOTH)
	geo.translate(jaw, H + Vector((0.0, -0.170, -0.150)))
	geo.merge(bm, jaw)
	nose = geo.ellipsoid(0.040, 0.030, 0.026, seg(lod, 7, 5), 3, row("hair_dark"), sharp=SMOOTH)
	geo.translate(nose, H + Vector((0.0, -0.222, -0.030)))
	geo.merge(bm, nose)
	for side in (-1.0, 1.0):
		tusk = geo.tube([H + Vector((side * 0.070, -0.218, -0.135)), H + Vector((side * 0.084, -0.232, -0.080)),
				H + Vector((side * 0.096, -0.222, -0.040))], [0.020, 0.014, 0.0], seg(lod, 6, 4), row("bone"),
				sharp=SMOOTH, cap_start=row("bone"))
		geo.merge(bm, tusk)
		fang = _cone(0.012, 0.030, "bone", 4)
		geo.merge(bm, fang, geo.frame(H + Vector((side * 0.035, -0.228, -0.068)), (0.0, -0.1, -1.0),
				(0.0, -1.0, 0.0)))
		# Angry: the inner end low over the nose, the outer end raised.
		brow = geo.ellipsoid(0.048, 0.030, 0.070, seg(lod, 9, 6), 4, row("hair_dark"), sharp=SMOOTH)
		geo.merge(bm, brow, geo.frame(H + Vector((side * 0.074, -0.190, 0.080)), (side * 1.0, 0.22, 0.50),
				(0.0, -0.45, 1.0)))
		whisk = geo.ellipsoid(0.070, 0.080, 0.120, seg(lod, 8, 6), 4, row("hair"), sharp=SMOOTH)
		geo.merge(bm, whisk, geo.frame(H + Vector((side * 0.170, -0.090, -0.070)), (side * 0.3, 0.0, 1.0),
				(0.0, -1.0, 0.0)))
	# The crest of shag: points swept up and back over the crown.
	tufts = ((0.0, -0.090, 0.150, 0.0, 0.18, 0.150), (-0.090, -0.060, 0.140, -0.45, 0.20, 0.120),
			(0.090, -0.060, 0.140, 0.45, 0.20, 0.120), (-0.055, 0.030, 0.180, -0.25, 0.55, 0.140),
			(0.055, 0.030, 0.180, 0.25, 0.55, 0.140), (-0.150, 0.010, 0.080, -0.85, 0.30, 0.110),
			(0.150, 0.010, 0.080, 0.85, 0.30, 0.110), (0.0, 0.090, 0.150, 0.0, 0.85, 0.130))
	for x, y, z, dx, dy, h in (tufts if lod == 0 else tufts[:5]):
		tuft = _cone(h * 0.55, h, "hair", seg(lod, 6, 4))
		geo.merge(bm, tuft, geo.frame(H + Vector((x, y, z)), (dx, dy, 1.0), (0.0, 1.0, 0.0)))
	geo.merge(bm, animals._eyes(lod, face, H, 0.066, 0.016, rx=0.032, ry=0.038))
	return bm


def _icicles(bm, pts, lod):
	"""Ice hanging off the fur: (point, length) pairs, cones pointing down."""
	for p, h in (pts if lod == 0 else pts[::2]):
		ice = _cone(h * 0.30, h, "arcane", seg(lod, 5, 4))
		geo.merge(bm, ice, geo.frame(p, (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)))


def _yeti_arm(lod, joints, radii, fist_r):
	"""A huge shaggy arm through `joints` (shoulder, elbow, wrist, fist), a
	white fur cuff at the wrist, a big blue-grey fist with slate nails."""
	bm = geo.new_bm()
	geo.merge(bm, geo.tube(joints[:3], radii, seg(lod, 10, 7), row("hair"), sharp=SMOOTH))
	elbow = geo.ellipsoid(radii[1] * 1.15, radii[1] * 1.15, radii[1] * 1.15, seg(lod, 8, 6), 4, row("hair"),
			sharp=SMOOTH)
	geo.translate(elbow, joints[1])
	geo.merge(bm, elbow)
	d = (joints[2] - joints[1]).normalized()
	cuff = geo.ellipsoid(radii[2] * 1.35, radii[2] * 1.35, 0.060, seg(lod, 10, 7), 4, row("hair"), sharp=SMOOTH)
	geo.merge(bm, cuff, geo.frame(joints[2] - d * 0.030, d, (0.0, -1.0, 0.0)))
	fist = geo.ellipsoid(fist_r, fist_r * 1.05, fist_r * 0.92, seg(lod, 10, 7), seg(lod, 5, 4), row("skin"),
			sharp=SMOOTH)
	geo.translate(fist, joints[3])
	geo.merge(bm, fist)
	if lod == 0:
		for k in (-1.0, 0.0, 1.0):
			nail = geo.ellipsoid(0.024, 0.020, 0.016, 6, 3, row("hair_dark"), sharp=SMOOTH)
			geo.translate(nail, joints[3] + Vector((k * fist_r * 0.48, -fist_r * 0.90, -fist_r * 0.20)))
			geo.merge(bm, nail)
	return bm


def _yeti_club(lod, g):
	"""A mammoth thighbone club dragged by its end: a frozen boulder of blue
	ice for a head bristling with ice spikes, the team's rag tied below the
	fist."""
	bm = geo.new_bm()
	grip = Vector((0.520, -0.360, g + 0.470))
	head = Vector((0.600, -0.700, g + 0.200))
	d = (head - grip).normalized()
	shaft = geo.tube([grip - d * 0.080, grip.lerp(head, 0.5), head], [0.042, 0.036, 0.052], seg(lod, 8, 6),
			row("bone"), sharp=SMOOTH)
	geo.merge(bm, shaft)
	knob = geo.ellipsoid(0.058, 0.058, 0.058, seg(lod, 8, 5), 4, row("bone"), sharp=SMOOTH)
	geo.translate(knob, grip - d * 0.090)
	geo.merge(bm, knob)
	rock = geo.ellipsoid(0.165, 0.150, 0.140, seg(lod, 7, 6), seg(lod, 4, 3), row("arcane"), sharp=HARD)
	geo.merge(bm, rock, geo.frame(head, d, (0.0, 0.0, 1.0)))
	spikes = ((1.0, 0.2, 0.3), (-1.0, 0.1, 0.4), (0.1, -0.2, 1.0), (0.5, 0.6, 0.7), (-0.5, 0.7, 0.5),
			(0.2, 1.0, -0.2), (-0.6, -0.3, -0.5))
	for v in (spikes if lod == 0 else spikes[:4]):
		v = Vector(v).normalized()
		spike = _cone(0.050, 0.150, "arcane", seg(lod, 5, 4))
		geo.merge(bm, spike, geo.frame(head + v * 0.120, v, (0.0, 0.0, 1.0)))
	at = grip.lerp(head, 0.30)
	geo.merge(bm, _band(0.050, 0.034, lod, (10, 7)), geo.frame(at, d, (0.0, 0.0, 1.0)))
	if lod == 0:
		rag = [at, at + Vector((0.050, 0.030, -0.060)), at + Vector((0.080, 0.090, -0.140)),
				at + Vector((0.070, 0.150, -0.210))]
		geo.merge(bm, _curl(rag, [0.040, 0.046, 0.040, 0.020], lod, "team_cloth", flatten=0.25, up=(1.0, 0.0, 0.0)))
	return bm


def _yeti_team(lod, g):
	"""The team's fur-wrap kilt round the hips under a dark belt, dagged
	flaps front and back, and a wide team sash slung over the left shoulder
	across the chest."""
	bm = geo.new_bm()
	kilt = geo.lathe([(0.300, -0.130), (0.335, -0.050), (0.330, 0.040), (0.300, 0.070)], seg(lod, 16, 10),
			row("team_cloth"), sharp=SMOOTH)
	geo.translate(kilt, (0.0, 0.020, g + 0.470))
	geo.merge(bm, kilt)
	geo.merge(bm, geo.flipped(kilt, row("team_cloth_dark"), inset=0.008))
	belt = geo.lathe([(0.305, -0.020), (0.318, 0.0), (0.305, 0.020)], seg(lod, 16, 10), row("leather_dark"),
			sharp=40)
	geo.translate(belt, (0.0, 0.020, g + 0.530))
	geo.merge(bm, belt)
	for y, d in ((-0.330, -1.0), (0.360, 1.0)):
		flap = geo.plate([(-0.120, 0.0), (0.120, 0.0), (0.100, -0.250), (0.040, -0.210), (0.0, -0.280),
				(-0.040, -0.210), (-0.100, -0.250)], 0.020, row("team_cloth"), row("team_cloth_dark"), sharp=40)
		geo.rotate(flap, d * 8.0, 'X')
		geo.translate(flap, (0.0, y, g + 0.520))
		geo.merge(bm, flap)
	sash = [Vector((-0.330, -0.160, g + 1.080)), Vector((-0.170, -0.400, g + 0.950)),
			Vector((0.050, -0.450, g + 0.780)), Vector((0.230, -0.390, g + 0.620)), Vector((0.320, -0.230, g + 0.540))]
	geo.merge(bm, _curl(sash, [0.080, 0.085, 0.085, 0.080, 0.070], lod, "team_cloth", flatten=0.28,
			up=(0.0, -1.0, 0.3)))
	return bm


def yeti(b, lod):
	g = b.base_height
	bm = geo.new_bm()
	# A hunched white barrel of a body on short thick legs.
	torso = geo.tube([Vector((0.0, 0.040, g + 0.380)), Vector((0.0, 0.010, g + 0.620)),
			Vector((0.0, -0.050, g + 0.860)), Vector((0.0, -0.100, g + 1.060)), Vector((0.0, -0.130, g + 1.160))],
			[0.250, 0.330, 0.360, 0.300, 0.150], seg(lod, 14, 9), row("hair"), sharp=SMOOTH, cap_start=row("hair"))
	geo.merge(bm, torso)
	belly = geo.ellipsoid(0.250, 0.120, 0.260, seg(lod, 11, 7), seg(lod, 5, 4), row("hair"), sharp=SMOOTH)
	geo.translate(belly, (0.0, -0.250, g + 0.760))
	geo.merge(bm, belly)
	for side in (-1.0, 1.0):
		hip = Vector((side * 0.170, 0.030, g + 0.440))
		knee = Vector((side * 0.215, -0.040, g + 0.250))
		ankle = Vector((side * 0.215, 0.000, g + 0.080))
		geo.merge(bm, geo.tube([hip, knee, ankle], [0.150, 0.125, 0.100], seg(lod, 10, 7), row("hair"),
				sharp=SMOOTH))
		foot = geo.ellipsoid(0.115, 0.165, 0.062, seg(lod, 10, 7), seg(lod, 4, 3), row("skin"), sharp=SMOOTH,
				squash_bottom=0.3)
		geo.translate(foot, (ankle.x, ankle.y - 0.060, g + 0.045))
		geo.merge(bm, foot)
		if lod == 0:
			for k in (-1.0, 0.0, 1.0):
				nail = geo.ellipsoid(0.026, 0.022, 0.018, 6, 3, row("hair_dark"), sharp=SMOOTH)
				geo.translate(nail, (ankle.x + k * 0.055, ankle.y - 0.215, g + 0.040))
				geo.merge(bm, nail)
		# Huge shoulder mounds crusted with frost crystals.
		mound = geo.ellipsoid(0.215, 0.205, 0.190, seg(lod, 11, 7), seg(lod, 5, 4), row("hair"), sharp=SMOOTH)
		geo.translate(mound, (side * 0.360, -0.080, g + 1.040))
		geo.merge(bm, mound)
		for k, (dx, dy, h, lean) in enumerate(((0.000, 0.020, 0.160, 0.2), (0.080, 0.070, 0.110, 0.6),
				(-0.060, 0.090, 0.095, -0.4))):
			if lod == 1 and k:
				continue
			crystal = _cone(h * 0.32, h, "arcane", seg(lod, 5, 4))
			geo.merge(bm, crystal, geo.frame(Vector((side * (0.380 + dx), -0.080 + dy, g + 1.200)),
					(side * lean, 0.25, 1.0), (0.0, 1.0, 0.0)))
	# The arms: the left knuckling the ground, the right dragging the club.
	geo.merge(bm, _yeti_arm(lod, [Vector((-0.420, -0.080, g + 1.000)), Vector((-0.560, -0.200, g + 0.640)),
			Vector((-0.540, -0.330, g + 0.250)), Vector((-0.540, -0.360, g + 0.115))], [0.150, 0.125, 0.105], 0.120))
	geo.merge(bm, _yeti_arm(lod, [Vector((0.420, -0.080, g + 1.000)), Vector((0.570, -0.180, g + 0.700)),
			Vector((0.530, -0.310, g + 0.500)), Vector((0.520, -0.360, g + 0.470))], [0.150, 0.125, 0.105], 0.115))
	_icicles(bm, [(Vector((-0.590, -0.210, g + 0.560)), 0.110), (Vector((-0.600, -0.260, g + 0.420)), 0.090),
			(Vector((0.600, -0.200, g + 0.640)), 0.110), (Vector((0.590, -0.250, g + 0.560)), 0.080),
			(Vector((-0.450, -0.100, g + 0.880)), 0.100), (Vector((0.450, -0.100, g + 0.880)), 0.100),
			(Vector((-0.300, -0.160, g + 0.880)), 0.070), (Vector((0.300, -0.160, g + 0.880)), 0.070)], lod)
	geo.merge(bm, _yeti_team(lod, g))
	geo.merge(bm, _yeti_club(lod, g))
	geo.merge(bm, _yeti_head(lod, g))
	return _grow(bm, g, YETI_SCALE)


# --- orc mutant --------------------------------------------------------------

ORC_MUTANT_SCALE = 2.35
ORC_MUTANT_HEAD = Vector((-0.070, -0.250, 1.150))


def _stitches(bm, centre, axis, radius, lod, a0=0.0, a1=360.0, up=(0.0, 0.0, 1.0)):
	"""A stitched seam: a dark thread ring of `radius` round `axis` at
	`centre` (from `a0` to `a1` degrees), crossed by short stitches."""
	n = seg(lod, 9, 5)
	m = geo.frame(centre, axis, up)
	pts = []
	for i in range(n + 1):
		a = math.radians(a0 + (a1 - a0) * i / n)
		pts.append(m @ Vector((math.cos(a) * radius, math.sin(a) * radius, 0.0)))
	geo.merge(bm, geo.tube(pts, [0.010] * len(pts), seg(lod, 5, 4), row("string"), sharp=SMOOTH))
	ax = (m.to_3x3() @ Vector((0.0, 0.0, 1.0))).normalized()
	for i in range(n):
		p = pts[i].lerp(pts[i + 1], 0.5)
		out = (p - Vector(centre)).normalized() * 0.006
		geo.merge(bm, geo.tube([p + out - ax * 0.034, p + out * 2.0, p + out + ax * 0.034], [0.009, 0.010, 0.009],
				4, row("string"), sharp=SMOOTH))


def _bumps(bm, part, pts, lod, swatch="fruit"):
	"""Pustules on `part`: (from, toward, radius), each cast onto its surface."""
	tree = geo.bvh(part)
	for origin, d, r in (pts if lod == 0 else pts[::2]):
		loc, nrm = geo.project(tree, origin, d)
		if loc is None:
			continue
		blob = geo.ellipsoid(r, r, r * 0.75, seg(lod, 7, 5), 3, row(swatch), sharp=SMOOTH)
		geo.merge(bm, blob, geo.frame(loc, nrm, (0.0, 0.0, 1.0)))


def _chain(bm, a, b, sag, lod, links=None, tree=None, lift=0.026):
	"""A chain of iron links from `a` to `b`, sagging `sag` in the middle,
	each link turned a quarter from the last. With `tree`, each link is laid
	on that surface seen from the front (-Y), `lift` proud of it."""
	n = links or seg(lod, 8, 5)
	a, b = Vector(a), Vector(b)
	d = (b - a).normalized()
	across = Vector((0.0, 0.0, 1.0)).cross(d)
	if across.length < 1e-4:
		across = Vector((1.0, 0.0, 0.0))
	across.normalize()
	flat = d.cross(across).normalized()
	for i in range(n):
		t = i / max(n - 1, 1)
		p = a.lerp(b, t) + Vector((0.0, 0.0, -sag * math.sin(math.pi * t)))
		if tree is not None:
			loc, nrm = geo.project(tree, (p.x, p.y - 1.0, p.z), (0.0, 1.0, 0.0))
			if loc is not None:
				p = loc + nrm * lift
		geo.merge(bm, _ring(p, across if i % 2 else flat, 0.030, 0.010, lod, up=d))


def _orc_head(lod, g):
	"""A lumpy olive head sunk low between lopsided shoulders: a great
	underbite jaw with two ivory tusks, a flat pig nose, small pointed ears,
	heavy dark brows in an angry V, the shared eyes; one big bone horn
	bursting out of the right side of the skull and a broken stub on the
	left, a stitched scar across the crown, an iron ring in the left ear."""
	H = ORC_MUTANT_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.195, 0.180, 0.175, seg(lod, 13, 8), seg(lod, 7, 5), row("hood"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	jaw = geo.ellipsoid(0.180, 0.125, 0.090, seg(lod, 11, 7), seg(lod, 5, 4), row("hood"), sharp=SMOOTH)
	geo.translate(jaw, H + Vector((0.0, -0.090, -0.125)))
	geo.merge(bm, jaw)
	mouth = geo.ellipsoid(0.120, 0.040, 0.024, seg(lod, 9, 6), 3, row("mouth"), sharp=SMOOTH)
	geo.translate(mouth, H + Vector((0.0, -0.188, -0.080)))
	geo.merge(bm, mouth)
	nose = geo.ellipsoid(0.050, 0.034, 0.032, seg(lod, 8, 5), 3, row("hoof"), sharp=SMOOTH)
	geo.translate(nose, H + Vector((0.0, -0.188, -0.008)))
	geo.merge(bm, nose)
	for side in (-1.0, 1.0):
		nostril = geo.ellipsoid(0.012, 0.010, 0.010, 5, 3, row("coat_dark"), sharp=SMOOTH)
		geo.translate(nostril, H + Vector((side * 0.020, -0.220, -0.016)))
		geo.merge(bm, nostril)
		# Two tusks up from the underbite, and a pair of lower teeth.
		tusk = geo.tube([H + Vector((side * 0.092, -0.188, -0.118)), H + Vector((side * 0.104, -0.212, -0.050)),
				H + Vector((side * 0.124, -0.200, 0.010))], [0.024, 0.017, 0.0], seg(lod, 6, 4), row("bone"),
				sharp=SMOOTH, cap_start=row("bone"))
		geo.merge(bm, tusk)
		tooth = _cone(0.011, 0.026, "bone", 4)
		geo.merge(bm, tooth, geo.frame(H + Vector((side * 0.040, -0.200, -0.096)), (0.0, -0.1, 1.0), (0.0, -1.0, 0.0)))
		geo.merge(bm, _brow(H, side, (0.026, -0.188, 0.048), (0.080, -0.172, 0.086), (0.134, -0.122, 0.122),
				(0.026, 0.032, 0.022), "hoof", lod))
		ear = _cone(0.050, 0.140, "hood", seg(lod, 6, 4))
		geo.merge(bm, ear, geo.frame(H + Vector((side * 0.170, 0.000, 0.010)), (side * 1.0, 0.30, 0.35),
				(0.0, -1.0, 0.0)))
	geo.merge(bm, _ring(H + Vector((-0.270, 0.050, -0.010)), (0.0, 1.0, 0.0), 0.034, 0.009, lod))
	# The great bone horn out of the right of the skull, a broken stub on the left.
	horn = geo.tube([H + Vector((0.110, -0.010, 0.110)), H + Vector((0.180, 0.000, 0.230)),
			H + Vector((0.210, 0.040, 0.360)), H + Vector((0.180, 0.080, 0.450))], [0.062, 0.046, 0.026, 0.0],
			seg(lod, 8, 5), row("bone"), sharp=SMOOTH)
	geo.merge(bm, horn)
	stub = geo.tube([H + Vector((-0.110, 0.000, 0.120)), H + Vector((-0.160, 0.020, 0.190))], [0.042, 0.036],
			seg(lod, 7, 5), row("bone"), sharp=SMOOTH, cap_end=row("bone"))
	geo.merge(bm, stub)
	# A stitched scar across the crown, front left to back right.
	if lod == 0:
		scar = []
		for i in range(6):
			t = i / 5.0
			a = math.radians(-60.0 + 120.0 * t)
			scar.append(H + Vector((-0.110 + 0.150 * t, math.sin(a) * 0.150, 0.110 + math.cos(a) * 0.060)))
		geo.merge(bm, geo.tube(scar, [0.008] * 6, 4, row("string"), sharp=SMOOTH))
		for i in range(5):
			p = scar[i].lerp(scar[i + 1], 0.5)
			d = (scar[i + 1] - scar[i]).normalized()
			across = d.cross(Vector((0.0, 0.0, 1.0))).normalized() * 0.030
			geo.merge(bm, geo.tube([p - across, p + Vector((0.0, 0.0, 0.010)), p + across], [0.008, 0.009, 0.008], 4,
					row("string"), sharp=SMOOTH))
	geo.merge(bm, animals._eyes(lod, skull, H, 0.078, 0.018, rx=0.030, ry=0.036))
	return bm


def _orc_arm(lod, joints, radii, fist_r, swatch):
	"""An arm through (shoulder, elbow, wrist, fist) in `swatch`, a big fist."""
	bm = geo.new_bm()
	geo.merge(bm, geo.tube(joints[:3], radii, seg(lod, 10, 7), row(swatch), sharp=SMOOTH))
	elbow = geo.ellipsoid(radii[1] * 1.12, radii[1] * 1.12, radii[1] * 1.12, seg(lod, 8, 6), 4, row(swatch),
			sharp=SMOOTH)
	geo.translate(elbow, joints[1])
	geo.merge(bm, elbow)
	fist = geo.ellipsoid(fist_r, fist_r * 1.05, fist_r * 0.92, seg(lod, 10, 7), seg(lod, 5, 4), row(swatch),
			sharp=SMOOTH)
	geo.translate(fist, joints[3])
	geo.merge(bm, fist)
	return bm


## The raised cleaver: the blade rises up (a little back) from the fist, its edge
## turned forward and in (a diagonal chop across the body), so its flat
## face turns to the front and the game camera rather than showing its edge.
ORC_CLEAVER_UP = Vector((0.10, 0.20, 0.97)).normalized()
_EDGE = Vector((-0.45, -1.0, 0.0))
ORC_CLEAVER_EDGE = (_EDGE - ORC_CLEAVER_UP * _EDGE.dot(ORC_CLEAVER_UP)).normalized()


def _orc_cleaver(lod, fist, d=ORC_CLEAVER_UP, e=ORC_CLEAVER_EDGE):
	"""A crude butcher's cleaver as big as a door, raised ready to chop by its
	wooden handle: a pitted iron slab with a hole by the spine, a chipped
	bright edge facing the chop (`e`), rust stains. `d` runs from the fist
	along the handle to the blade's end."""
	bm = geo.new_bm()
	d = Vector(d).normalized()
	e = Vector(e).normalized()
	handle = geo.tube([fist - d * 0.120, fist + d * 0.180], [0.036, 0.036], seg(lod, 8, 5), row("wood"), sharp=SMOOTH,
			cap_start=row("wood"))
	geo.merge(bm, handle)
	cap = geo.ellipsoid(0.044, 0.044, 0.044, seg(lod, 7, 5), 4, row("steel"), sharp=SMOOTH)
	geo.translate(cap, fist - d * 0.125)
	geo.merge(bm, cap)
	# The slab, in the plate's XZ plane along local -X (= d), facing front.
	m = geo.orient(fist - e * 0.020, d.cross(e), -e)
	body = [(-0.150, 0.060), (-0.600, 0.080), (-0.640, -0.300), (-0.150, -0.280)]
	geo.merge(bm, geo.plate(body, 0.030, row("steel"), sharp=40), m)
	edge = [(-0.150, -0.270), (-0.640, -0.290), (-0.640, -0.360), (-0.560, -0.390), (-0.520, -0.345),
			(-0.470, -0.400), (-0.330, -0.395), (-0.290, -0.350), (-0.240, -0.385), (-0.150, -0.340)]
	geo.merge(bm, geo.plate(edge, 0.018, row("blade"), sharp=40), m)
	for y, n in ((-0.017, -1.0), (0.017, 1.0)):
		geo.merge(bm, geo.disc(0.040, 0.040, seg(lod, 10, 6), row("coat_dark"), dome=-0.002, depth=0.002),
				m @ geo.frame((-0.540, y, 0.000), (0.0, n, 0.0), (0.0, 0.0, 1.0)))
	if lod == 0:
		for x, z, rx, rz in ((-0.300, -0.080, 0.070, 0.050), (-0.420, -0.200, 0.050, 0.034),
				(-0.230, 0.010, 0.040, 0.030)):
			geo.merge(bm, geo.disc(rx, rz, 8, row("warpaint"), dome=0.001, depth=0.002, simple=True),
					m @ geo.frame((x, -0.017, z), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
	# Iron rivets binding the handle to the slab.
	for x in (-0.180, -0.240):
		rivet = geo.ellipsoid(0.016, 0.016, 0.016, 6, 3, row("steel"), sharp=SMOOTH)
		geo.transform(rivet, m @ Matrix.Translation((x, -0.018, 0.020)))
		geo.merge(bm, rivet)
	return bm


def _orc_team(lod, g):
	"""The team's loincloth on a dark belt (a long front flap, a back flap)
	and a tattered team war banner on a crooked pole strapped to the back,
	standing over the left shoulder, a horned skull on top."""
	bm = geo.new_bm()
	belt = geo.lathe([(0.285, -0.035), (0.300, 0.0), (0.285, 0.035)], seg(lod, 16, 10), row("leather_dark"), sharp=40)
	geo.translate(belt, (0.0, -0.010, g + 0.480))
	geo.merge(bm, belt)
	buckle = geo.box(0.080, 0.030, 0.070, row("steel"), bevel=0.006)
	geo.translate(buckle, (0.0, -0.300, g + 0.480))
	geo.merge(bm, buckle)
	for y, d, w, h in ((-0.300, -1.0, 0.140, 0.340), (0.270, 1.0, 0.150, 0.280)):
		flap = geo.plate([(-w, 0.0), (w, 0.0), (w * 0.85, -h), (w * 0.35, -h * 0.80), (0.0, -h * 1.05),
				(-w * 0.40, -h * 0.82), (-w * 0.85, -h)], 0.020, row("team_cloth"), row("team_cloth_dark"), sharp=40,
				bend=-0.6 * d)
		geo.rotate(flap, d * 10.0, 'X')
		geo.translate(flap, (0.0, y, g + 0.470))
		geo.merge(bm, flap)
	base = Vector((-0.120, 0.250, g + 0.500))
	top = Vector((-0.260, 0.330, g + 1.660))
	pole = [base, base.lerp(top, 0.5) + Vector((0.025, 0.0, 0.0)), top]
	geo.merge(bm, geo.tube(pole, [0.026, 0.024, 0.020], seg(lod, 7, 5), row("wood"), sharp=SMOOTH))
	skull = geo.ellipsoid(0.050, 0.046, 0.050, seg(lod, 8, 5), 4, row("bone"), sharp=SMOOTH)
	geo.translate(skull, top + Vector((0.0, 0.0, 0.040)))
	geo.merge(bm, skull)
	for s in (-1.0, 1.0):
		geo.merge(bm, _cone(0.020, 0.080, "bone", 4), geo.frame(top + Vector((s * 0.040, 0.0, 0.070)), (s, 0.0, 0.6),
				(0.0, 1.0, 0.0)))
	cross = geo.tube([top + Vector((-0.190, 0.0, -0.060)), top + Vector((0.170, 0.0, -0.040))], [0.016, 0.016],
			seg(lod, 6, 4), row("wood"), sharp=SMOOTH)
	geo.merge(bm, cross)
	flag = geo.plate([(-0.180, 0.0), (0.160, 0.020), (0.150, -0.300), (0.090, -0.250), (0.040, -0.420),
			(-0.020, -0.300), (-0.090, -0.400), (-0.130, -0.280), (-0.180, -0.360)], 0.014, row("team_cloth"),
			row("team_cloth_dark"), sharp=40, bend=0.15)
	geo.rotate(flag, -12.0, 'Z')
	geo.translate(flag, top + Vector((0.0, -0.016, -0.060)))
	geo.merge(bm, flag)
	# The strap holding the pole to the back.
	strap = [Vector((-0.300, -0.160, g + 1.000)), Vector((-0.240, 0.180, g + 0.980)), Vector((0.050, 0.290, g + 0.800)),
			Vector((0.280, 0.120, g + 0.640))]
	geo.merge(bm, _curl(strap, [0.030, 0.034, 0.034, 0.030], lod, "leather_dark", flatten=0.35, up=(0.0, 1.0, 0.2)))
	return bm


def orc_mutant(b, lod):
	g = b.base_height
	bm = geo.new_bm()
	# A hunched olive barrel of a body, leaning forward, on short thick legs
	# (the right one thicker).
	torso = geo.tube([Vector((0.0, 0.040, g + 0.380)), Vector((0.0, 0.0, g + 0.600)), Vector((-0.020, -0.060, g + 0.830)),
			Vector((-0.030, -0.100, g + 0.990)), Vector((-0.040, -0.130, g + 1.070))], [0.240, 0.300, 0.320, 0.270, 0.140],
			seg(lod, 14, 9), row("hood"), sharp=SMOOTH, cap_start=row("hood"))
	geo.merge(bm, torso)
	belly = geo.ellipsoid(0.250, 0.140, 0.220, seg(lod, 11, 7), seg(lod, 5, 4), row("hood"), sharp=SMOOTH)
	geo.translate(belly, (0.0, -0.200, g + 0.650))
	geo.merge(bm, belly)
	for side in (-1.0, 1.0):
		k = 1.12 if side > 0 else 1.0
		hip = Vector((side * 0.170, 0.030, g + 0.430))
		knee = Vector((side * 0.220, -0.060, g + 0.250))
		ankle = Vector((side * 0.220, 0.000, g + 0.080))
		geo.merge(bm, geo.tube([hip, knee, ankle], [0.145 * k, 0.122 * k, 0.098 * k], seg(lod, 10, 7), row("hood"),
				sharp=SMOOTH))
		foot = geo.ellipsoid(0.115 * k, 0.165, 0.062, seg(lod, 10, 7), seg(lod, 4, 3), row("hood"), sharp=SMOOTH,
				squash_bottom=0.3)
		geo.translate(foot, (ankle.x, ankle.y - 0.060, g + 0.045))
		geo.merge(bm, foot)
		if lod == 0:
			for t in (-1.0, 0.0, 1.0):
				nail = geo.ellipsoid(0.024, 0.020, 0.016, 6, 3, row("hoof"), sharp=SMOOTH)
				geo.translate(nail, (ankle.x + t * 0.052, ankle.y - 0.215, g + 0.040))
				geo.merge(bm, nail)
	# An iron shackle on the left ankle.
	shackle = geo.lathe([(0.100, -0.030), (0.112, 0.0), (0.100, 0.030)], seg(lod, 12, 8), row("steel"), sharp=40)
	geo.translate(shackle, (-0.220, -0.005, g + 0.130))
	geo.merge(bm, shackle)
	# The mutation: a huge swollen shoulder of raw mauve flesh on the right,
	# stitched on, bone spikes bursting out of it, bile pustules.
	mc = Vector((0.360, -0.050, g + 1.020))
	mound = geo.ellipsoid(0.270, 0.250, 0.250, seg(lod, 12, 8), seg(lod, 6, 4), row("ochre"), sharp=SMOOTH)
	geo.translate(mound, mc)
	_bumps(bm, mound, [(Vector((0.360, -0.600, g + 1.000)), Vector((0.0, 1.0, 0.0)), 0.036),
			(Vector((0.900, -0.100, g + 1.000)), Vector((-1.0, 0.0, 0.0)), 0.030),
			(Vector((0.460, -0.600, g + 1.120)), Vector((0.0, 1.0, 0.0)), 0.026),
			(Vector((0.260, -0.600, g + 0.900)), Vector((0.0, 1.0, 0.0)), 0.022)], lod)
	geo.merge(bm, mound)
	_stitches(bm, Vector((0.160, -0.050, g + 1.020)), (1.0, 0.0, 0.15), 0.180, lod, a0=-30.0, a1=210.0,
			up=(0.0, -1.0, 0.0))
	for v, h in (((0.3, -0.2, 1.0), 0.200), ((0.8, 0.1, 0.7), 0.160), ((0.1, 0.4, 0.9), 0.140)):
		v = Vector(v).normalized()
		spike = _cone(0.050, h, "bone", seg(lod, 6, 4))
		geo.merge(bm, spike, geo.frame(mc + Vector((v.x * 0.24, v.y * 0.22, v.z * 0.22)), v, (0.0, 1.0, 0.0)))
	# Raised: the elbow out and down, the fist up by the shoulder.
	arm_r = [Vector((0.470, -0.080, g + 0.960)), Vector((0.760, -0.060, g + 0.820)), Vector((0.800, -0.180, g + 1.140)),
			Vector((0.800, -0.210, g + 1.230))]
	arm = _orc_arm(lod, arm_r, [0.200, 0.165, 0.150], 0.180, "ochre")
	# A swollen forearm.
	fc = arm_r[1].lerp(arm_r[2], 0.45)
	fore = geo.ellipsoid(0.180, 0.180, 0.150, seg(lod, 10, 7), seg(lod, 5, 4), row("ochre"), sharp=SMOOTH)
	geo.translate(fore, fc)
	geo.merge(arm, fore)
	_bumps(bm, arm, [(fc + Vector((0.6, 0.0, -0.05)), Vector((-1.0, 0.0, 0.0)), 0.034),
			(fc + Vector((0.0, -0.6, -0.05)), Vector((0.0, 1.0, 0.0)), 0.030),
			(fc + Vector((0.6, 0.0, 0.10)), Vector((-1.0, 0.0, -0.2)), 0.026),
			(fc + Vector((-0.06, -0.6, 0.06)), Vector((0.0, 1.0, 0.0)), 0.024)], lod)
	geo.merge(bm, arm)
	for v, h in (((1.0, 0.2, 0.3), 0.130), ((0.8, 0.5, -0.1), 0.110)):
		v = Vector(v).normalized()
		spike = _cone(0.040, h, "bone", seg(lod, 5, 4))
		geo.merge(bm, spike, geo.frame(fc + v * 0.160, v, (0.0, 0.0, 1.0)))
	# An iron cuff on the big wrist.
	cuff = geo.lathe([(0.150, -0.040), (0.164, 0.0), (0.150, 0.040)], seg(lod, 12, 8), row("steel"), sharp=40)
	geo.merge(bm, cuff, geo.frame(arm_r[2] + Vector((0.0, 0.040, 0.030)), (arm_r[2] - arm_r[1]).normalized(),
			(0.0, -1.0, 0.0)))
	geo.merge(bm, _orc_cleaver(lod, arm_r[3]))
	# The ordinary left arm: an iron pauldron with spikes, an iron manacle on
	# the wrist with a broken chain swinging from it.
	arm_l = [Vector((-0.300, -0.090, g + 0.960)), Vector((-0.420, -0.190, g + 0.720)), Vector((-0.360, -0.340, g + 0.620)),
			Vector((-0.330, -0.390, g + 0.600))]
	geo.merge(bm, _orc_arm(lod, arm_l, [0.120, 0.100, 0.090], 0.105, "hood"))
	pc = Vector((-0.300, -0.080, g + 1.040))
	pauldron = geo.ellipsoid(0.175, 0.170, 0.100, seg(lod, 10, 7), seg(lod, 5, 3), row("steel"), sharp=SMOOTH,
			squash_bottom=0.3)
	geo.merge(bm, pauldron, geo.frame(pc, (-0.55, 0.0, 1.0), (0.0, -1.0, 0.0)))
	for v in ((-0.3, -0.3, 1.0), (-0.9, 0.0, 0.6), (-0.4, 0.5, 0.9)):
		v = Vector(v).normalized()
		spike = _cone(0.034, 0.110, "steel", seg(lod, 5, 4))
		geo.merge(bm, spike, geo.frame(pc + v * 0.120, v, (0.0, 1.0, 0.0)))
	manacle = geo.lathe([(0.088, -0.034), (0.100, 0.0), (0.088, 0.034)], seg(lod, 12, 8), row("steel"), sharp=40)
	geo.merge(bm, manacle, geo.frame(arm_l[2], (arm_l[2] - arm_l[1]).normalized(), (0.0, 0.0, 1.0)))
	_chain(bm, arm_l[2] + Vector((-0.020, 0.0, -0.080)), arm_l[2] + Vector((-0.060, 0.030, -0.330)), 0.0, lod,
			links=seg(lod, 5, 3))
	# A chain slung across the chest from the pauldron to the right hip,
	# laid on the chest and belly (a straight line ran inside the belly and
	# its last links poked out of the stomach by the belt).
	body = geo.new_bm()
	geo.merge(body, torso)
	geo.merge(body, belly)
	_chain(bm, (-0.200, -0.300, g + 0.980), (0.220, -0.330, g + 0.560), 0.040, lod, tree=geo.bvh(body))
	geo.merge(bm, _orc_team(lod, g))
	geo.merge(bm, _orc_head(lod, g))
	return _grow(bm, g, ORC_MUTANT_SCALE)


# --- dark lord ---------------------------------------------------------------

DARK_LORD_SCALE = 2.35
DARK_LORD_HEAD = Vector((0.0, -0.040, 1.250))


def _dark_lord_helm(lod, g):
	"""A great horned helm: a black-violet dome, a dark T-visor with two
	glowing violet eyes under gold brows in an angry V, cheek guards, a gold
	spiked crown round the brow, two great black horns curving out and up
	with gold tips, a crest spike."""
	H = DARK_LORD_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	dome = geo.ellipsoid(0.200, 0.195, 0.205, seg(lod, 13, 9), seg(lod, 7, 5), row("plate_dark"), sharp=SMOOTH)
	geo.translate(dome, H)
	geo.merge(bm, dome)
	for side in (-1.0, 1.0):
		cheek = geo.ellipsoid(0.090, 0.110, 0.120, seg(lod, 9, 6), 4, row("plate_dark"), sharp=SMOOTH)
		geo.translate(cheek, H + Vector((side * 0.110, -0.080, -0.110)))
		geo.merge(bm, cheek)
	chin = geo.ellipsoid(0.110, 0.090, 0.080, seg(lod, 9, 6), 4, row("plate_dark"), sharp=SMOOTH)
	geo.translate(chin, H + Vector((0.0, -0.130, -0.150)))
	geo.merge(bm, chin)
	# The visor: a dark eye slit and a dark mouth slot under the nose bar.
	slit = geo.box(0.230, 0.060, 0.050, row("coat_dark"), bevel=0.012)
	geo.translate(slit, H + Vector((0.0, -0.170, 0.000)))
	geo.merge(bm, slit)
	slot = geo.box(0.040, 0.060, 0.120, row("coat_dark"), bevel=0.010)
	geo.translate(slot, H + Vector((0.0, -0.172, -0.080)))
	geo.merge(bm, slot)
	for side in (-1.0, 1.0):
		eye = geo.ellipsoid(0.034, 0.016, 0.020, seg(lod, 8, 5), 3, row("gem"), sharp=SMOOTH)
		geo.merge(bm, eye, geo.frame(H + Vector((side * 0.060, -0.198, 0.000)), (0.0, -1.0, 0.0),
				(side * -0.35, 0.0, 1.0)))
		geo.merge(bm, _brow(H, side, (0.020, -0.200, 0.026), (0.070, -0.192, 0.052), (0.124, -0.160, 0.086),
				(0.020, 0.026, 0.018), "brass", lod))
		# The great horns: out from the temples, then sweeping up.
		horn = geo.tube([H + Vector((side * 0.150, 0.000, 0.080)), H + Vector((side * 0.270, 0.000, 0.120)),
				H + Vector((side * 0.330, 0.020, 0.250)), H + Vector((side * 0.320, 0.040, 0.390))],
				[0.060, 0.046, 0.030, 0.012], seg(lod, 8, 5), row("coat_dark"), sharp=SMOOTH)
		geo.merge(bm, horn)
		tip = _cone(0.014, 0.060, "brass", seg(lod, 5, 4))
		geo.merge(bm, tip, geo.frame(H + Vector((side * 0.320, 0.040, 0.385)), (side * -0.1, 0.1, 1.0), (0.0, 1.0, 0.0)))
		band = geo.lathe([(0.052, -0.014), (0.060, 0.0), (0.052, 0.014)], seg(lod, 8, 6), row("brass"), sharp=40)
		geo.merge(bm, band, geo.frame(H + Vector((side * 0.230, 0.0, 0.106)), (side * 1.0, 0.0, 0.25), (0.0, 0.0, 1.0)))
	# The gold crown: a band round the brow, spikes on its front half.
	crown = geo.lathe([(0.196, -0.030), (0.208, -0.012), (0.208, 0.012), (0.196, 0.030)], seg(lod, 16, 10),
			row("brass"), sharp=40)
	geo.translate(crown, H + Vector((0.0, 0.000, 0.090)))
	geo.merge(bm, crown)
	count = seg(lod, 5, 3)
	for k in range(count):
		a = math.radians(-60.0 + 120.0 * k / (count - 1))
		h = 0.120 if k == count // 2 else 0.085
		spike = _cone(0.026, h, "brass", seg(lod, 5, 4))
		at = H + Vector((math.sin(a) * 0.190, -math.cos(a) * 0.190, 0.110))
		geo.merge(bm, spike, geo.frame(at, (math.sin(a) * 0.25, -math.cos(a) * 0.25, 1.0), (0.0, 1.0, 0.0)))
	gem = geo.ellipsoid(0.026, 0.016, 0.030, seg(lod, 7, 5), 3, row("gem"), sharp=SMOOTH)
	geo.translate(gem, H + Vector((0.0, -0.206, 0.090)))
	geo.merge(bm, gem)
	crest = _cone(0.040, 0.130, "plate_dark", seg(lod, 6, 4))
	geo.merge(bm, crest, geo.frame(H + Vector((0.0, 0.050, 0.180)), (0.0, 0.35, 1.0), (0.0, 1.0, 0.0)))
	return bm


def _dark_lord_sword(lod, fist, tip):
	"""A huge runed greatsword held point-down: a blackened blade with bright
	steel edges and a glowing violet rune channel, a gold crossguard with
	down-swept spikes and a violet gem, a dark grip and a gold pommel."""
	bm = geo.new_bm()
	d = (tip - fist).normalized()
	guard_at = fist + d * 0.110
	length = (tip - guard_at).length
	f = (Vector((0.0, -1.0, 0.0)) - d * d.dot(Vector((0.0, -1.0, 0.0)))).normalized()
	m = geo.orient(guard_at, f, -d)
	w = 0.095
	edge = [(-w, 0.0), (w, 0.0), (w * 0.92, -length * 0.82), (0.0, -length), (-w * 0.92, -length * 0.82)]
	geo.merge(bm, geo.plate(edge, 0.020, row("blade"), sharp=40), m)
	core = [(-w * 0.72, -0.010), (w * 0.72, -0.010), (w * 0.66, -length * 0.80), (0.0, -length * 0.93),
			(-w * 0.66, -length * 0.80)]
	geo.merge(bm, geo.plate(core, 0.030, row("plate_dark"), sharp=40), m)
	rune = [(-0.026, -0.050), (0.026, -0.050), (0.026, -length * 0.74), (0.0, -length * 0.80), (-0.026, -length * 0.74)]
	geo.merge(bm, geo.plate(rune, 0.038, row("gem"), sharp=40), m)
	if lod == 0:
		for k in range(5):
			z = -0.100 - k * (length * 0.62) / 4.0
			mark = geo.box(0.030 if k % 2 else 0.044, 0.042, 0.010, row("plate_dark"))
			geo.transform(mark, m @ Matrix.Translation((0.0, 0.0, z)))
			geo.merge(bm, mark)
	# The crossguard and its down-swept spikes.
	guard = geo.tube([Vector((-0.170, 0.0, 0.0)), Vector((0.0, 0.0, 0.010)), Vector((0.170, 0.0, 0.0))],
			[0.024, 0.032, 0.024], seg(lod, 8, 5), row("brass"), sharp=SMOOTH, cap_start=row("brass"),
			cap_end=row("brass"))
	geo.transform(guard, m)
	geo.merge(bm, guard)
	for s in (-1.0, 1.0):
		spike = _cone(0.024, 0.090, "brass", seg(lod, 5, 4))
		geo.merge(bm, spike, m @ geo.frame((s * 0.165, 0.0, 0.0), (s * 0.5, 0.0, -1.0), (0.0, 1.0, 0.0)))
	gem = geo.ellipsoid(0.034, 0.030, 0.034, seg(lod, 8, 5), 4, row("gem"), sharp=SMOOTH)
	geo.transform(gem, m @ Matrix.Translation((0.0, -0.020, 0.0)))
	geo.merge(bm, gem)
	grip = geo.tube([guard_at, fist - d * 0.140], [0.026, 0.026], seg(lod, 7, 5), row("leather_dark"), sharp=SMOOTH)
	geo.merge(bm, grip)
	pommel = geo.ellipsoid(0.044, 0.044, 0.050, seg(lod, 8, 5), 4, row("brass"), sharp=SMOOTH)
	geo.translate(pommel, fist - d * 0.170)
	geo.merge(bm, pommel)
	return bm


def _dark_lord_pauldron(lod, side, g):
	"""A huge layered pauldron: two black-violet plates edged in gold, three
	black spikes raking up and out."""
	bm = geo.new_bm()
	at = Vector((side * 0.330, -0.010, g + 1.050))
	for k, (dz, r) in enumerate(((0.0, 1.0), (-0.090, 0.88))):
		p = at + Vector((side * 0.030 * k, 0.0, dz))
		plate = geo.ellipsoid(0.200 * r, 0.205 * r, 0.110, seg(lod, 11, 7), seg(lod, 5, 3), row("plate_dark"),
				sharp=SMOOTH, squash_bottom=0.25)
		m = geo.frame(p, (side * 0.70, 0.0, 0.72), (0.0, -1.0, 0.0))
		geo.merge(bm, plate, m)
		rim = geo.lathe([(0.186 * r, -0.014), (0.204 * r, 0.0), (0.186 * r, 0.014)], seg(lod, 12, 8), row("brass"),
				sharp=40)
		geo.merge(bm, rim, m @ Matrix.Translation((0.0, 0.0, -0.020)))
	for v, h in (((0.3, -0.4, 1.0), 0.180), ((0.9, 0.0, 0.8), 0.200), ((0.3, 0.5, 1.0), 0.150)):
		v = Vector((side * v[0], v[1], v[2])).normalized()
		spike = _cone(0.040, h, "coat_dark", seg(lod, 6, 4))
		geo.merge(bm, spike, geo.frame(at + v * 0.110, v, (0.0, 1.0, 0.0)))
	return bm


def _dark_lord_team(lod, g):
	"""The team's huge cape from the shoulders to the ground, flaring and
	wrapping forward at the edges (its lining a darker team shade), a team
	mantle rolled over the shoulders behind the helm, the team's tabard
	hanging from the belt front and back."""
	bm = geo.new_bm()
	outline = [(-0.300, 0.0), (0.300, 0.0), (0.470, -0.700), (0.500, -1.010), (0.360, -0.960), (0.230, -1.040),
			(0.080, -0.970), (-0.080, -1.040), (-0.230, -0.970), (-0.360, -1.040), (-0.500, -1.000), (-0.470, -0.700)]
	cape = geo.plate(outline, 0.026, row("team_cloth_dark"), row("team_cloth"), sharp=40, bend=-0.55)
	geo.rotate(cape, -9.0, 'X')
	geo.translate(cape, (0.0, 0.200, g + 1.080))
	geo.merge(bm, cape)
	mantle = _catmull([Vector((-0.300, -0.060, g + 1.090)), Vector((-0.200, 0.140, g + 1.100)),
			Vector((0.0, 0.190, g + 1.100)), Vector((0.200, 0.140, g + 1.100)), Vector((0.300, -0.060, g + 1.090))], 3)
	geo.merge(bm, geo.tube(mantle, [0.070] * len(mantle), seg(lod, 9, 6), row("team_cloth"), sharp=SMOOTH,
			cap_start=row("team_cloth"), cap_end=row("team_cloth")))
	for y, d, h in ((-0.250, -1.0, 0.470), (0.215, 1.0, 0.400)):
		tab = geo.plate([(-0.120, 0.0), (0.120, 0.0), (0.110, -h), (0.0, -h - 0.060), (-0.110, -h)], 0.020,
				row("team_cloth"), row("team_cloth_dark"), sharp=40, bend=-0.5 * d)
		geo.rotate(tab, d * 6.0, 'X')
		geo.translate(tab, (0.0, y, g + 0.600))
		geo.merge(bm, tab)
	# A gold sigil on the front tabard: a violet gem in a gold ring.
	at = Vector((0.0, -0.268, g + 0.400))
	ring = geo.lathe([(0.040, -0.008), (0.052, 0.0), (0.040, 0.008)], seg(lod, 10, 7), row("brass"), sharp=40)
	geo.merge(bm, ring, geo.frame(at, (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
	geo.merge(bm, geo.disc(0.036, 0.036, seg(lod, 8, 6), row("gem"), dome=0.008, depth=0.004),
			geo.frame(at, (0.0, -1.0, 0.0), (0.0, 0.0, 1.0)))
	return bm


def dark_lord(b, lod):
	g = b.base_height
	bm = geo.new_bm()
	# Armoured legs: greaves, knee cops with a gold spike, pointed sabatons.
	for side in (-1.0, 1.0):
		hip = Vector((side * 0.150, 0.020, g + 0.520))
		knee = Vector((side * 0.175, -0.030, g + 0.290))
		ankle = Vector((side * 0.180, 0.010, g + 0.100))
		geo.merge(bm, geo.tube([hip, knee, ankle], [0.115, 0.098, 0.090], seg(lod, 10, 7), row("plate_dark"),
				sharp=SMOOTH))
		cop = geo.ellipsoid(0.082, 0.060, 0.074, seg(lod, 9, 6), 4, row("plate_dark"), sharp=SMOOTH)
		geo.translate(cop, knee + Vector((0.0, -0.070, 0.0)))
		geo.merge(bm, cop)
		kspike = _cone(0.020, 0.060, "brass", seg(lod, 5, 4))
		geo.merge(bm, kspike, geo.frame(knee + Vector((0.0, -0.125, 0.0)), (0.0, -1.0, 0.2), (0.0, 0.0, 1.0)))
		cuff = geo.lathe([(0.098, -0.016), (0.110, 0.0), (0.098, 0.016)], seg(lod, 10, 7), row("brass"), sharp=40)
		geo.translate(cuff, ankle + Vector((0.0, 0.0, 0.030)))
		geo.merge(bm, cuff)
		boot = geo.ellipsoid(0.100, 0.165, 0.065, seg(lod, 10, 7), seg(lod, 4, 3), row("plate_dark"), sharp=SMOOTH,
				squash_bottom=0.3)
		geo.translate(boot, (ankle.x, ankle.y - 0.060, g + 0.050))
		geo.merge(bm, boot)
		toe = _cone(0.040, 0.080, "plate_dark", seg(lod, 6, 4))
		geo.merge(bm, toe, geo.frame(Vector((ankle.x, ankle.y - 0.200, g + 0.045)), (0.0, -1.0, 0.1), (0.0, 0.0, 1.0)))
	# The fauld: a flared skirt of plates, gold-edged.
	skirt = geo.lathe([(0.230, 0.0), (0.250, -0.090), (0.290, -0.200)], seg(lod, 16, 10), row("plate_dark"), sharp=40)
	geo.translate(skirt, (0.0, 0.0, g + 0.640))
	geo.merge(bm, skirt)
	hem = geo.lathe([(0.284, -0.012), (0.298, 0.0), (0.284, 0.012)], seg(lod, 16, 10), row("brass"), sharp=40)
	geo.translate(hem, (0.0, 0.0, g + 0.440))
	geo.merge(bm, hem)
	# A massive armoured chest.
	torso = geo.tube([Vector((0.0, 0.020, g + 0.580)), Vector((0.0, 0.0, g + 0.780)), Vector((0.0, -0.020, g + 0.980)),
			Vector((0.0, -0.020, g + 1.080))], [0.230, 0.290, 0.310, 0.190], seg(lod, 14, 9), row("plate_dark"),
			sharp=SMOOTH, cap_start=row("plate_dark"))
	geo.merge(bm, torso)
	breast = geo.ellipsoid(0.260, 0.150, 0.220, seg(lod, 12, 8), seg(lod, 6, 4), row("plate_dark"), sharp=SMOOTH)
	geo.translate(breast, (0.0, -0.130, g + 0.880))
	geo.merge(bm, breast)
	belt = geo.lathe([(0.238, -0.032), (0.252, 0.0), (0.238, 0.032)], seg(lod, 16, 10), row("brass"), sharp=40)
	geo.translate(belt, (0.0, 0.0, g + 0.630))
	geo.merge(bm, belt)
	# The violet rune heart in a gold setting at the middle of the chest.
	at = Vector((0.0, -0.336, g + 0.900))
	setting = geo.lathe([(0.058, -0.012), (0.072, 0.0), (0.058, 0.012)], seg(lod, 12, 8), row("brass"), sharp=40)
	geo.merge(bm, setting, geo.frame(at, (0.0, -1.0, 0.25), (0.0, 0.0, 1.0)))
	geo.merge(bm, geo.disc(0.054, 0.060, seg(lod, 10, 7), row("gem"), dome=0.016, depth=0.006),
			geo.frame(at, (0.0, -1.0, 0.25), (0.0, 0.0, 1.0)))
	for side in (-1.0, 1.0):
		ridge = geo.tube([at + Vector((side * 0.070, 0.0, 0.050)), at + Vector((side * 0.180, 0.050, 0.150))],
				[0.016, 0.012], seg(lod, 6, 4), row("brass"), sharp=SMOOTH)
		geo.merge(bm, ridge)
		geo.merge(bm, _dark_lord_pauldron(lod, side, g))
	# Arms in plate: the right holds the greatsword point-down, the left is
	# raised with violet sorcery burning in its open hand.
	arm_r = [Vector((0.360, -0.020, g + 0.960)), Vector((0.430, -0.080, g + 0.720)), Vector((0.400, -0.220, g + 0.600)),
			Vector((0.400, -0.260, g + 0.580))]
	arm_l = [Vector((-0.360, -0.020, g + 0.960)), Vector((-0.450, -0.110, g + 0.760)), Vector((-0.430, -0.280, g + 0.800)),
			Vector((-0.420, -0.330, g + 0.820))]
	for joints in (arm_r, arm_l):
		geo.merge(bm, geo.tube(joints[:3], [0.100, 0.088, 0.082], seg(lod, 9, 6), row("plate_dark"), sharp=SMOOTH))
		elbow = geo.ellipsoid(0.090, 0.090, 0.090, seg(lod, 8, 6), 4, row("plate_dark"), sharp=SMOOTH)
		geo.translate(elbow, joints[1])
		geo.merge(bm, elbow)
		d = (joints[2] - joints[1]).normalized()
		gaunt = geo.lathe([(0.088, -0.050), (0.110, 0.020), (0.100, 0.040)], seg(lod, 10, 7), row("plate_dark"),
				sharp=40)
		geo.merge(bm, gaunt, geo.frame(joints[2] - d * 0.030, d, (0.0, -1.0, 0.0)))
		trim = geo.lathe([(0.102, -0.010), (0.116, 0.0), (0.102, 0.010)], seg(lod, 10, 7), row("brass"), sharp=40)
		geo.merge(bm, trim, geo.frame(joints[2] + d * 0.008, d, (0.0, -1.0, 0.0)))
		fist = geo.ellipsoid(0.085, 0.090, 0.080, seg(lod, 9, 6), 4, row("plate_dark"), sharp=SMOOTH)
		geo.translate(fist, joints[3])
		geo.merge(bm, fist)
	geo.merge(bm, _dark_lord_sword(lod, arm_r[3], Vector((0.700, -0.800, g + 0.050))))
	for k, (dx, dy, h) in enumerate(((0.0, 0.0, 0.110), (0.030, 0.020, 0.075), (-0.030, -0.010, 0.070))):
		if lod == 1 and k:
			continue
		flame = _wisp(h * 0.55, "gem")
		geo.merge(bm, flame, geo.frame(arm_l[3] + Vector((dx, dy, 0.060)), (dx * 3.0, 0.1, 1.0), (0.0, -1.0, 0.0)))
	geo.merge(bm, _dark_lord_team(lod, g))
	geo.merge(bm, _dark_lord_helm(lod, g))
	return _grow(bm, g, DARK_LORD_SCALE)



# --- phoenix -----------------------------------------------------------------

PHOENIX_SCALE = 2.35
PHOENIX_HEAD = Vector((0.0, -0.170, 1.300))
## The raised wings: root on the right shoulder, span up and out, the
## leading edge turned in and up (the feathers fan out and down from it),
## size. The left wing is the right one mirrored.
PHOENIX_WING = (Vector((0.170, 0.080, 1.000)), (0.60, 0.22, 0.78), (-0.78, 0.30, 0.55), 0.80)


def _tongue(h, w, swatch, back=None, bend=0.0):
	"""A flame tongue standing along local +Z in the XZ plane: a broad base,
	a lick out to one side, a pointed tip leaning the other way."""
	outline = [(-w, 0.0), (w, 0.0), (w * 0.78, h * 0.40), (w * 0.96, h * 0.56), (w * 0.36, h * 0.80), (0.0, h),
			(-w * 0.46, h * 0.62), (-w * 0.86, h * 0.42)]
	return geo.plate(outline, 0.016, row(swatch), row(back or swatch), sharp=40, bend=bend)


def _flame_row(bm, count, x0, x1, z0, z1, a0, a1, l0, l1, width, swatch, depth, back="robe_dark", bend=0.0):
	"""A row of flame feathers along a wing's arm (+X), each turned from `a0`
	to `a1` degrees (90 hangs straight off the leading edge, 0 along the
	arm), overlapping like shingles."""
	for i in range(count):
		t = i / max(count - 1, 1)
		f = _tongue(l0 + (l1 - l0) * t, width * 0.5, swatch, back, bend)
		geo.rotate(f, 90.0 + a0 + (a1 - a0) * t, 'Y')
		geo.translate(f, (x0 + (x1 - x0) * t, depth - 0.002 * i, z0 + (z1 - z0) * t))
		geo.merge(bm, f)


def _phoenix_wing(lod, side):
	"""A huge raised flame wing: an amber arm, long orange flame primaries
	fanned up from the wrist, orange secondaries, amber coverts over them
	and white-hot lesser coverts at the root (the fire hottest at its
	heart), deep ember undersides. Built for the right and mirrored."""
	bm = geo.new_bm()
	arm = geo.tube([(0.0, 0.0, 0.0), (0.240, 0.0, 0.070), (0.480, 0.0, 0.080), (0.700, 0.0, 0.030)],
			[0.062, 0.052, 0.038, 0.014], seg(lod, 8, 5), row("robe_trim"), sharp=SMOOTH, flatten=0.7,
			up=(0.0, 1.0, 0.0))
	geo.merge(bm, arm)
	_flame_row(bm, seg(lod, 6, 4), 0.400, 0.690, 0.060, 0.040, 80.0, 18.0, 0.440, 0.560, 0.170, "robe", 0.012,
			bend=0.6)
	_flame_row(bm, seg(lod, 6, 4), 0.040, 0.380, 0.020, 0.070, 102.0, 86.0, 0.380, 0.430, 0.170, "robe", 0.006,
			bend=0.6)
	_flame_row(bm, seg(lod, 7, 5), 0.020, 0.620, 0.030, 0.080, 96.0, 44.0, 0.250, 0.220, 0.140, "robe_trim",
			-0.014)
	if lod == 0:
		_flame_row(bm, 6, 0.0, 0.480, 0.050, 0.090, 94.0, 60.0, 0.140, 0.120, 0.110, "ermine", -0.028)
	root, span, lead, size = PHOENIX_WING
	geo.transform(bm, _wing_matrix(1.0, root, span, lead) @ Matrix.Scale(size, 4))
	if side < 0.0:
		geo.scale(bm, -1.0, 1.0, 1.0)
		bmesh.ops.reverse_faces(bm, faces=bm.faces)
	return bm


def _phoenix_head(lod, g):
	"""A big round flame-orange head: a hooked bronze beak open in a
	screech, the shared eyes under heavy dark brows in an angry V, amber
	flame tufts swept back off the cheeks, a tall crest of flame tongues
	(amber, white-hot, orange) blazing up and back off the crown."""
	H = PHOENIX_HEAD + Vector((0.0, 0.0, g))
	bm = geo.new_bm()
	skull = geo.ellipsoid(0.175, 0.165, 0.160, seg(lod, 14, 9), seg(lod, 7, 5), row("robe"), sharp=SMOOTH)
	geo.translate(skull, H)
	geo.merge(bm, skull)
	face = geo.ellipsoid(0.120, 0.080, 0.100, seg(lod, 10, 7), 5, row("robe_trim"), sharp=SMOOTH)
	geo.translate(face, H + Vector((0.0, -0.095, -0.030)))
	geo.merge(bm, face)
	upper = geo.tube([H + Vector((0.0, -0.140, 0.010)), H + Vector((0.0, -0.225, -0.002)),
			H + Vector((0.0, -0.268, -0.046)), H + Vector((0.0, -0.262, -0.096))], [0.062, 0.046, 0.026, 0.0],
			seg(lod, 10, 7), row("fletch"), sharp=SMOOTH, flatten=1.2)
	geo.merge(bm, upper)
	lower = geo.tube([H + Vector((0.0, -0.130, -0.064)), H + Vector((0.0, -0.195, -0.094)),
			H + Vector((0.0, -0.222, -0.110))], [0.044, 0.028, 0.0], seg(lod, 8, 6), row("fletch"), sharp=SMOOTH)
	geo.merge(bm, lower)
	mouth = geo.ellipsoid(0.036, 0.060, 0.022, seg(lod, 8, 6), 3, row("mouth"), sharp=SMOOTH)
	geo.translate(mouth, H + Vector((0.0, -0.170, -0.058)))
	geo.merge(bm, mouth)
	geo.merge(bm, animals._eyes(lod, skull, H, 0.076, 0.018, rx=0.034, ry=0.042))
	for side in (-1.0, 1.0):
		geo.merge(bm, _brow(H, side, (0.024, -0.166, 0.052), (0.072, -0.146, 0.080), (0.112, -0.096, 0.104),
				(0.022, 0.028, 0.018), "coat_dark", lod))
		tuft = geo.tube([H + Vector((side * 0.130, -0.020, -0.050)), H + Vector((side * 0.190, 0.080, -0.010)),
				H + Vector((side * 0.240, 0.180, 0.050))], [0.060, 0.040, 0.0], seg(lod, 7, 5), row("robe_trim"),
				sharp=SMOOTH, flatten=0.45)
		geo.merge(bm, tuft)
	# The crest: flame tongues fanned up and back over the crown, facing
	# the front so they read from the camera.
	crest = ((0.0, 0.260, "robe_trim"), (-0.060, 0.200, "robe"), (0.060, 0.200, "robe"),
			(-0.110, 0.140, "robe_trim"), (0.110, 0.140, "robe_trim"))
	for dx, h, sw in crest[:seg(lod, 5, 3)]:
		fl = _tongue(h, 0.050, sw, "robe_dark")
		lean = Vector((dx * 4.0, 0.55 + abs(dx) * 1.5, 1.0))
		geo.merge(bm, fl, geo.frame(H + Vector((dx, 0.020 + abs(dx) * 0.3, 0.110 - abs(dx) * 0.25)), lean,
				(0.0, 1.0, 0.0)))
	if lod == 0:
		core = _tongue(0.160, 0.030, "ermine")
		geo.merge(bm, core, geo.frame(H + Vector((0.0, 0.010, 0.120)), (0.0, 0.50, 1.0), (0.0, 1.0, 0.0)))
	return bm


def _phoenix_legs(lod, g):
	"""Long charcoal legs bent back at the ankle under fiery feathered
	thighs, three ivory-taloned toes forward and one back; the team's
	jesses round each shin with two ribbons hanging off them."""
	bm = geo.new_bm()
	for side in (-1.0, 1.0):
		thigh = geo.ellipsoid(0.105, 0.125, 0.135, seg(lod, 10, 7), 5, row("robe"), sharp=SMOOTH)
		geo.translate(thigh, (side * 0.140, 0.050, g + 0.520))
		geo.merge(bm, thigh)
		hip = Vector((side * 0.150, 0.060, g + 0.450))
		knob = Vector((side * 0.160, 0.120, g + 0.270))
		foot = Vector((side * 0.170, 0.000, g + 0.040))
		geo.merge(bm, geo.tube([hip, knob, foot], [0.058, 0.046, 0.040], seg(lod, 8, 6), row("coat"), sharp=SMOOTH))
		joint = geo.ellipsoid(0.052, 0.052, 0.052, seg(lod, 8, 5), 4, row("coat"), sharp=SMOOTH)
		geo.translate(joint, knob)
		geo.merge(bm, joint)
		for k in (-1.0, 0.0, 1.0, None):
			if k is None:
				d = Vector((0.0, 1.0, -0.1)).normalized()
				length = 0.070
			else:
				d = Vector((math.sin(math.radians(30.0 * k)), -math.cos(math.radians(30.0 * k)), -0.10)).normalized()
				length = 0.140
			end = foot + d * length
			toe = geo.tube([foot, end], [0.032, 0.022], seg(lod, 6, 4), row("coat"), sharp=SMOOTH,
					cap_end=row("coat"))
			geo.merge(bm, toe)
			claw = _cone(0.020, 0.060, "bone", seg(lod, 5, 4))
			geo.merge(bm, claw, geo.frame(end - d * 0.008, (d.x, d.y, -0.7), (0.0, 0.0, 1.0)))
		# The team's jesses: a cloth band round the shin, two ribbons off it.
		axis = (foot - knob).normalized()
		at = knob.lerp(foot, 0.32)
		geo.merge(bm, _band(0.058, 0.026, lod, segments=(10, 7)), geo.frame(at, axis, (0.0, -1.0, 0.0)))
		if lod == 0:
			for dx in (-0.020, 0.020):
				ribbon = geo.tube([at + Vector((side * 0.030 + dx, 0.050, 0.0)),
						at + Vector((side * 0.050 + dx, 0.110, -0.060)), at + Vector((side * 0.060 + dx, 0.150, -0.140))],
						[0.020, 0.018, 0.012], 5, row("team_cloth"), sharp=SMOOTH, flatten=0.35, up=(1.0, 0.0, 0.0))
				geo.merge(bm, ribbon)
	return bm


def _phoenix_tail(lod, g):
	"""A long trailing flame tail: a broad orange streamer low along the
	ground curling up at its end, two amber streamers fanning out either
	side and a white-hot core along the top."""
	bm = geo.new_bm()
	streams = (
		((0.000, 0.000), [(0.260, 0.660), (0.500, 0.500), (0.800, 0.340), (1.050, 0.280), (1.220, 0.340),
				(1.320, 0.460)], [0.140, 0.170, 0.160, 0.130, 0.090, 0.0], "robe", 0.40),
		((0.060, 0.260), [(0.240, 0.640), (0.460, 0.480), (0.740, 0.300), (0.960, 0.240), (1.100, 0.300)],
				[0.100, 0.120, 0.105, 0.070, 0.0], "robe_trim", 0.38),
		((-0.060, -0.260), [(0.240, 0.640), (0.460, 0.480), (0.740, 0.300), (0.960, 0.240), (1.100, 0.300)],
				[0.100, 0.120, 0.105, 0.070, 0.0], "robe_trim", 0.38),
		((0.000, 0.000), [(0.250, 0.720), (0.480, 0.580), (0.720, 0.430), (0.900, 0.390)],
				[0.070, 0.085, 0.065, 0.0], "ermine", 0.42),
	)
	for (x0, x1), path, radii, sw, flat in streams:
		n = len(path)
		pts = [Vector((x0 + (x1 - x0) * (i / (n - 1)) ** 1.3, y, g + z)) for i, (y, z) in enumerate(path)]
		geo.merge(bm, geo.tube(pts, radii, seg(lod, 9, 6), row(sw), sharp=SMOOTH, flatten=flat))
	if lod == 0:
		for y, z, h, sw in ((0.700, 0.420, 0.070, "ermine"), (1.000, 0.350, 0.060, "robe_trim"),
				(1.300, 0.500, 0.075, "robe_trim"), (0.880, 0.330, 0.050, "robe_trim")):
			geo.merge(bm, _wisp(h * 0.55, sw), geo.frame(Vector((0.0, y, g + z)), (0.0, 0.35, 1.0), (0.0, 1.0, 0.0)))
	return bm


def _phoenix_team(lod, g):
	"""The team's collar round the base of the neck with an iron boss, and a
	swallow-tailed team pennant on an iron bar hanging from it down the
	amber breast."""
	bm = geo.new_bm()
	at = Vector((0.0, -0.110, g + 1.010))
	geo.merge(bm, _band(0.165, 0.040, lod), geo.frame(at, (0.0, -0.30, 1.0), (0.0, 0.0, 1.0)))
	pennant = geo.plate([(-0.115, 0.0), (0.115, 0.0), (0.115, -0.300), (0.0, -0.220), (-0.115, -0.300)], 0.020,
			row("team_cloth"), row("team_cloth_dark"), sharp=40, bend=0.9)
	geo.rotate(pennant, 8.0, 'X')
	geo.translate(pennant, (0.0, -0.292, g + 0.985))
	geo.merge(bm, pennant)
	bar = geo.tube([Vector((-0.125, -0.282, g + 0.985)), Vector((0.125, -0.282, g + 0.985))], [0.016, 0.016],
			seg(lod, 6, 4), row("steel"), sharp=40, cap_start=row("steel"), cap_end=row("steel"))
	geo.merge(bm, bar)
	boss = geo.lathe([(0.042, 0.0), (0.036, 0.016), (0.0, 0.024)], seg(lod, 10, 7), row("steel"), sharp=40,
			phase=0.0)
	geo.merge(bm, boss, geo.frame(Vector((0.0, -0.300, g + 1.010)), (0.0, -1.0, 0.2), (0.0, 0.0, 1.0)))
	return bm


def phoenix(b, lod):
	g = b.base_height
	bm = geo.new_bm()
	body = geo.ellipsoid(0.250, 0.300, 0.270, seg(lod, 14, 9), seg(lod, 7, 5), row("robe"), sharp=SMOOTH)
	geo.rotate(body, -35.0, 'X')
	geo.translate(body, (0.0, 0.040, g + 0.780))
	geo.merge(bm, body)
	breast = geo.ellipsoid(0.190, 0.120, 0.240, seg(lod, 12, 8), seg(lod, 6, 4), row("robe_trim"), sharp=SMOOTH)
	geo.translate(breast, (0.0, -0.150, g + 0.820))
	geo.merge(bm, breast)
	neck = geo.tube([Vector((0.0, -0.090, g + 0.930)), Vector((0.0, -0.140, g + 1.080)),
			Vector((0.0, -0.165, g + 1.190))], [0.150, 0.130, 0.120], seg(lod, 12, 8), row("robe"), sharp=SMOOTH)
	geo.merge(bm, neck)
	# Flame plumes off the back between the wings, and embers.
	for dx, h, sw in ((0.0, 0.200, "robe_trim"), (-0.080, 0.150, "robe"), (0.080, 0.150, "robe")):
		fl = _tongue(h, 0.055, sw, "robe_dark")
		geo.merge(bm, fl, geo.frame(Vector((dx, 0.200, g + 0.900)), (dx * 3.0, 0.9, 1.0), (0.0, 1.0, 0.0)))
	if lod == 0:
		for x, y, z, h in ((0.120, 0.120, 1.020, 0.055), (-0.120, 0.120, 1.020, 0.055), (0.0, 0.050, 1.060, 0.045)):
			geo.merge(bm, _wisp(h, "ermine"), geo.frame(Vector((x, y, g + z)), (x * 2.0, 0.3, 1.0), (0.0, 1.0, 0.0)))
	geo.merge(bm, _phoenix_legs(lod, g))
	geo.merge(bm, _phoenix_tail(lod, g))
	for side in (-1.0, 1.0):
		geo.merge(bm, _phoenix_wing(lod, side))
	geo.merge(bm, _phoenix_team(lod, g))
	geo.merge(bm, _phoenix_head(lod, g))
	return _grow(bm, g, PHOENIX_SCALE)
