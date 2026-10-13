# Star Wanderer helpers on top of the Aldmere kit (TownBuildings/kit/common.py),
# borrowing generic shape helpers from the Beastmen and Dark Elf kits
# (ring_solid, crescent, frames, export with extras).
#
# The Star Wanderer look: a celestial nomad camp. Every building stands on a
# round pearl plinth set on a lavender eight-pointed star whose points poke
# out round its rim (a compass rose seen from the camera). Walls are round
# pearl drums ribbed in lavender and banded in pale gold, pierced by round
# starlit portholes and moon-arched doors. Roofs are tent canopies of team
# cloth stretched over curved gold ribs: the cloth sags between the ribs and
# hangs in scallops at the hem, so even a big canopy reads as gores, not as a
# slab. Each crown carries a gold spike under a floating glowing orb (warm
# starfire gold, foxfire rose or moon lavender) circled by a tilted orbit
# ring. Crescent moons, four-pointed stars, telescopes and orreries are the
# props. Where Aldmere is warm plaster under gables, the Beastmen low round
# thatch and the Dark Elves tall violet-black spikes, this is pale, round,
# light and floating.
#
# A script does `from starwanderers_common import *` (which also brings in
# all of common and the Beastmen and Dark Elf helpers), builds, then
# export(name) / export(name, extras=(...)), which writes ../<Name>.glb.
import sys, os
_SW_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(_SW_HERE, '..', '..', 'DarkElves', 'kit')))
from darkelves_common import *
import common
from darkelves_common import _t, _rz, _rx, _ry, _mesh_obj, _placed_m
from common import _finish, _placed, _rot

tr, rz, rx, ry = _t, _rz, _rx, _ry


def _sw_out_path(name):
	if '--' in sys.argv and len(sys.argv) > sys.argv.index('--') + 1:
		return sys.argv[sys.argv.index('--') + 1]
	return os.path.join(os.path.dirname(_SW_HERE), name + '.glb')


# darkelves_common points export() at the Dark Elf folder; point it here.
common.out_path = _sw_out_path

# Pale celestial colours (linear). Lavenders and the midnight sit at hue
# 0.75 or above (violet side), clear of the team shader's blue window (about
# 0.52-0.68); the old 'Starlight' pale blue is gone. TeamColor stays the kit
# blue. Pearl is a warm, faintly rosy white so it doesn't wash out.
common.COLOURS.update({
	'Pearl': (0.74, 0.69, 0.68), 'PearlShade': (0.5, 0.45, 0.47),
	'Moonstone': (0.4, 0.33, 0.45), 'MoonstoneDark': (0.22, 0.165, 0.26),
	'Lavender': (0.6, 0.38, 0.76), 'LavenderDark': (0.3, 0.15, 0.4),
	'Midnight': (0.085, 0.03, 0.125),
	'PaleGold': (0.86, 0.6, 0.2), 'Gold': (0.828, 0.477, 0.04),
	'Starfire': (1.0, 0.8, 0.38), 'Rose': (0.95, 0.3, 0.45), 'MoonGlow': (0.78, 0.55, 1.0),
	'Silk': (0.82, 0.76, 0.7), 'Amphora': (0.6, 0.23, 0.084), 'StarFruit': (0.89, 0.6, 0.1),
})
common.GLOSSY = common.GLOSSY + ('Pearl', 'PearlShade', 'Moonstone', 'MoonstoneDark', 'Lavender', 'LavenderDark',
		'PaleGold', 'Starfire', 'Rose', 'MoonGlow', 'Midnight', 'TeamColor', 'TeamColorDark')

# Plinth top: where buildings stand.
SZ = 0.24


def star_prism(r_out, r_in, n, h, loc, mat_name, sx=1.0, sy=1.0, rot_z=0.0, bevel=0.03, matrix=None):
	"""A flat n-pointed star solid standing on `loc`, points r_out, notches r_in."""
	bm = bmesh.new()
	pts = []
	for i in range(n * 2):
		a = math.pi * i / n + math.pi / 2
		r = r_out if i % 2 == 0 else r_in
		pts.append((math.cos(a) * r * sx, math.sin(a) * r * sy))
	cb, ct = bm.verts.new((0, 0, 0)), bm.verts.new((0, 0, h))
	bot = [bm.verts.new((x, y, 0)) for x, y in pts]
	top = [bm.verts.new((x, y, h)) for x, y in pts]
	m = len(pts)
	for i in range(m):
		j = (i + 1) % m
		bm.faces.new((bot[i], bot[j], top[j], top[i]))
		bm.faces.new((ct, top[i], top[j]))
		bm.faces.new((cb, bot[j], bot[i]))
	obj = _mesh_obj(bm, 'star')
	_placed_m(obj, loc, rot_z, matrix)
	return _finish(obj, mat_name, bevel, 2, angle=30)


def star4(frame, r=0.2, thick=0.05, mat_name='PaleGold', n=4, inner=0.36):
	"""A flat n-pointed star standing upright in `frame`'s XZ plane, centred
	on its origin, `thick` along Y (faces -Y)."""
	return star_prism(r, r * inner, n, thick, (0, 0, 0), mat_name, bevel=min(0.015, thick * 0.3),
			matrix=frame @ _rx(90) @ _t(0, 0, -thick / 2))


def plinth_star(rx, ry=None, cx=0.0, cy=0.0, h=SZ, points=8, steps=True):
	"""The base: a lavender eight-pointed star whose points poke out round a
	round pearl plinth with a gold rim. Returns the plinth top."""
	ry = ry or rx
	star_prism(1.0, 0.72, points, h * 0.45, (cx, cy, 0), 'Lavender', sx=rx + 0.38, sy=ry + 0.38,
			rot_z=180.0 / points, bevel=0.04)
	ring_solid(rx + 0.04, rx, h * 0.62, (cx, cy, h * 0.3), 'Pearl', n=24, sx=1.0, sy=ry / rx, bevel=0.04)
	ring_solid(rx + 0.07, rx + 0.07, 0.07, (cx, cy, h * 0.3), 'Moonstone', n=24, sy=(ry + 0.07) / (rx + 0.07),
			bevel=0.025)
	ring_solid(rx - 0.04, rx - 0.04, 0.05, (cx, cy, h - 0.035), 'PaleGold', n=24, sy=(ry - 0.04) / (rx - 0.04),
			bevel=0.02)
	ring_solid(rx - 0.14, rx - 0.14, 0.05, (cx, cy, h - 0.015), 'Pearl', n=24, sy=(ry - 0.14) / (rx - 0.14),
			bevel=0.02)
	# Gold studs on the star points.
	for i in range(points):
		a = 2 * math.pi * i / points + math.pi / 2 + math.pi / points
		sphere(0.07, (cx + math.cos(a) * (rx + 0.22), cy + math.sin(a) * (ry + 0.22), h * 0.45), 'PaleGold')
	if steps:
		box((0.7, 0.3, h * 0.55), (cx, cy - ry - 0.12, h * 0.27), 'Pearl', bevel=0.05)
	return h


def ell(cx, cy, r, sx, sy, a):
	"""A point on the oval of radius r (scaled sx, sy) at angle a (radians),
	and the outward angle (degrees) of its normal."""
	x, y = math.cos(a) * r * sx, math.sin(a) * r * sy
	n = math.degrees(math.atan2(math.sin(a) / max(sy, 1e-3), math.cos(a) / max(sx, 1e-3)))
	return cx + x, cy + y, n


def drum(r, z0, z1, cx=0.0, cy=0.0, ribs=8, sx=1.0, sy=1.0, taper=0.96, mat_name='Pearl', rib_mat='Lavender',
		rib_rot=0.0):
	"""A round pearl wall from z0 to z1 with lavender ribs, a moonstone foot
	and a pale gold top band. Returns the top radius."""
	h = z1 - z0
	rt = r * taper
	ring_solid(r + 0.06, r + 0.05, 0.14, (cx, cy, z0), 'Moonstone', n=20, sx=sx, sy=sy, bevel=0.03)
	ring_solid(r, rt, h, (cx, cy, z0), mat_name, n=20, sx=sx, sy=sy, bevel=0.04)
	ring_solid(rt + 0.05, rt + 0.06, 0.1, (cx, cy, z1 - 0.06), 'PaleGold', n=20, sx=sx, sy=sy, bevel=0.025)
	for i in range(ribs):
		a = 2 * math.pi * i / ribs + math.radians(rib_rot) + math.pi / ribs
		x, y, n = ell(cx, cy, (r + rt) / 2 + 0.005, sx, sy, a)
		lean = math.degrees(math.atan2(r - rt, h))
		box((0.13, 0.1, h - 0.1), (0, 0, 0), rib_mat, rot=(0, 0, 0), bevel=0.035, segments=2,
				matrix=_t(x, y, z0 + 0.04 + h / 2) @ _rz(n - 90) @ _rx(lean))
	return rt


def canopy(r, h, z, cx=0.0, cy=0.0, gores=8, shape='tent', sx=1.0, sy=1.0, sag=0.1, hem=0.12, nv=8, nu=4,
		mats=('TeamColor', 'TeamColorDark'), rib='PaleGold', rot=0.0, thick=0.05, top=0.94, knobs=True):
	"""A tent canopy of team cloth stretched over curved gold ribs. The cloth
	sags in between the ribs and dips into scallops at the hem; gores
	alternate team and dark team. shape 'tent' sweeps in concave to a point,
	'dome' is a hemisphere, 'onion' bulges then draws in. Returns (top z,
	top radius)."""
	def prof(t):
		if shape == 'dome':
			return math.cos(t * math.pi / 2), math.sin(t * math.pi / 2)
		if shape == 'onion':
			return (1 - t) ** 0.65 * (1 + 0.32 * math.sin(math.pi * min(1.0, t * 1.6))), t
		if shape == 'bell':
			return (1 - t) ** 1.15 * (1 + 0.12 * math.sin(math.pi * t)), t
		return (1 - t) ** 1.55, t

	def pt(a, u, t):
		R0, Z0 = prof(t)
		s = sag * math.sin(math.pi * u) * (0.45 + 0.55 * math.sin(math.pi * min(1.0, t * 1.15)))
		R = r * R0 * (1 - s)
		zz = z + h * Z0 - hem * math.sin(math.pi * u) * max(0.0, 1 - t * 3.0) ** 2
		return Vector((cx + math.cos(a) * R * sx, cy + math.sin(a) * R * sy, zz))

	ts = [top * (j / nv) for j in range(nv + 1)]
	for g in range(gores if mats else 0):
		a0 = 2 * math.pi * g / gores + math.radians(rot)
		a1 = 2 * math.pi * (g + 1) / gores + math.radians(rot)
		bm = bmesh.new()
		grid = [[bm.verts.new(pt(a0 + (a1 - a0) * (i / nu), i / nu, t)) for t in ts] for i in range(nu + 1)]
		for i in range(nu):
			for j in range(nv):
				bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
		obj = _mesh_obj(bm, 'gore')
		sol = obj.modifiers.new('Solid', 'SOLIDIFY')
		sol.thickness = thick
		sol.offset = -1.0
		_finish(obj, mats[g % len(mats)], 0.012, 1, angle=50)
	# Ribs on the seams, a knob at each foot.
	rr = 0.032 + 0.006 * r
	for g in range(gores):
		a = 2 * math.pi * g / gores + math.radians(rot)
		ps = [pt(a, 0.0, t) for t in ts]
		for k in range(nv):
			p0, p1 = ps[k], ps[k + 1]
			d = p1 - p0
			m = Matrix.Translation((p0 + p1) / 2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
			cylinder(rr, d.length + rr * 1.4, (0, 0, 0), rib, verts=6, bevel=0.0, matrix=m)
		if knobs:
			sphere(rr * 2.0, (ps[0].x, ps[0].y, ps[0].z - 0.02), rib)
	R0, Z0 = prof(top)
	return z + h * Z0, r * R0


def orb_crown(x, y, z, s=1.0, glow='Starfire', ring=True, spike=0.3, moon=True, ring_tilt=(62, 0, 25)):
	"""A gold collar and spike under a floating glowing orb circled by a
	tilted gold orbit ring with a little moon on it. Returns the top."""
	cylinder(0.11 * s, 0.1 * s, (x, y, z + 0.03 * s), 'PaleGold', verts=10, bevel=0.02)
	cylinder(0.06 * s, spike * s, (x, y, z + 0.08 * s + spike * s / 2), 'PaleGold', verts=8, bevel=0.0,
			radius2=0.012 * s)
	oz = z + 0.08 * s + spike * s + 0.2 * s
	sphere(0.17 * s, (x, y, oz), glow)
	if ring:
		torus(0.3 * s, 0.022 * s, (x, y, oz), 'PaleGold', rot=ring_tilt)
		if moon:
			m = Matrix.Translation((x, y, oz)) @ _rot(ring_tilt)
			sphere(0.055 * s, (0.3 * s, 0, 0), 'Pearl', matrix=m)
	return oz + 0.17 * s


def moon_door(frame, w=0.5, h=0.8, glow=None):
	"""An arched pale gold doorway with a midnight interior and a crescent
	over it, standing on `frame` (bottom centre, local -Y out of the wall)."""
	fw = w + 0.14
	box((fw, 0.1, h - fw / 2), (0, -0.02, (h - fw / 2) / 2), 'PaleGold', bevel=0.03, segments=2, matrix=frame)
	cylinder(fw / 2, 0.1, (0, -0.02, h - fw / 2), 'PaleGold', verts=16, rot=(90, 0, 0), bevel=0.02, matrix=frame)
	box((w, 0.1, h - w / 2 - 0.02), (0, -0.05, (h - w / 2) / 2), 'Midnight', bevel=0.02, segments=2, matrix=frame)
	cylinder(w / 2, 0.1, (0, -0.05, h - fw / 2), 'Midnight', verts=16, rot=(90, 0, 0), bevel=0.015, matrix=frame)
	if glow:
		star4(frame @ _t(0, -0.11, h * 0.55), w * 0.22, 0.04, glow)
	crescent(frame @ _t(0, -0.1, h + 0.04), w * 0.28, 0.05, 'PaleGold')


def porthole(frame, r=0.16, glow='Starfire'):
	"""A round midnight window with a pale gold ring and a tiny glowing star,
	centred on `frame`."""
	cylinder(r, 0.08, (0, 0.0, 0), 'Midnight', verts=14, rot=(90, 0, 0), bevel=0.015, matrix=frame)
	torus(r, 0.035, (0, -0.04, 0), 'PaleGold', rot=(90, 0, 0), matrix=frame)
	star4(frame @ _t(0, -0.05, 0), r * 0.62, 0.03, glow)


def streamer(frame, w=0.3, h=0.6, mark='PaleGold'):
	"""A team streamer hanging from a short gold bar centred on `frame`,
	cut into a swallowtail, a gold star on it."""
	cylinder(0.03, w + 0.14, (0, 0, 0), 'PaleGold', verts=8, rot=(0, 90, 0), bevel=0.0, matrix=frame)
	for e in (-1, 1):
		sphere(0.045, (e * (w / 2 + 0.07), 0, 0), 'PaleGold', matrix=frame)
	box((w, 0.045, h), (0, -0.01, -h / 2 - 0.02), 'TeamColor', bevel=0.018, matrix=frame)
	for e in (-1, 1):
		box((w * 0.42, 0.045, 0.18), (e * w * 0.29, -0.01, -h - 0.1), 'TeamColor', bevel=0.018, matrix=frame)
	box((w + 0.02, 0.05, 0.07), (0, -0.015, -0.07), 'TeamColorDark', bevel=0.015, matrix=frame)
	star4(frame @ _t(0, -0.05, -h * 0.5), min(w, h) * 0.36, 0.03, mark)


def star_pole(x, y, z0, h, s=1.0, glow='Starfire', streamer_w=0.0):
	"""A slim pearl pole banded in gold, topped by a glowing four-point star;
	with streamer_w a team streamer hangs off its front. Returns the top."""
	cylinder(0.1 * s, 0.1 * s, (x, y, z0 + 0.05 * s), 'Moonstone', verts=10, bevel=0.02)
	cylinder(0.045 * s, h, (x, y, z0 + h / 2), 'Pearl', verts=8, bevel=0.01)
	for f in (0.35, 0.85):
		cylinder(0.06 * s, 0.05 * s, (x, y, z0 + h * f), 'PaleGold', verts=8, bevel=0.01)
	star4(face(x, y, z0 + h + 0.17 * s, '-y'), 0.17 * s, 0.06 * s, glow)
	if streamer_w:
		streamer(face(x, y - 0.06, z0 + h * 0.8, '-y'), streamer_w, streamer_w * 1.9)
	return z0 + h + 0.34 * s


def telescope(x, y, z, length=1.0, s=1.0, yaw=0.0, pitch=35.0):
	"""A gold-banded pearl telescope on a lavender tripod mount, its body
	pointing at yaw (degrees, 0 = -Y) and tilted up by pitch."""
	for a in (0, 120, 240):
		f = _t(x, y, z) @ _rz(a + yaw) @ _rx(-22)
		cylinder(0.035 * s, 0.6 * s, (0, 0, 0.28 * s), 'LavenderDark', verts=6, bevel=0.0, matrix=f)
	pz = z + 0.55 * s
	sphere(0.08 * s, (x, y, pz), 'PaleGold')
	f = _t(x, y, pz) @ _rz(yaw) @ _rx(90 + pitch)
	cylinder(0.08 * s, length * 0.6, (0, 0, length * 0.15), 'Pearl', verts=10, bevel=0.015, matrix=f,
			radius2=0.1 * s)
	cylinder(0.11 * s, length * 0.32, (0, 0, length * 0.58), 'Lavender', verts=10, bevel=0.015, matrix=f,
			radius2=0.13 * s)
	cylinder(0.14 * s, 0.05 * s, (0, 0, length * 0.75), 'PaleGold', verts=12, bevel=0.01, matrix=f)
	cylinder(0.05 * s, 0.2 * s, (0, 0, -length * 0.2), 'PaleGold', verts=8, bevel=0.0, matrix=f)


def orrery(x, y, z, s=1.0, glow='Starfire'):
	"""A gold orrery: a glowing sun on a post inside two tilted orbit rings,
	each carrying a planet. Returns its top."""
	cylinder(0.14 * s, 0.1 * s, (x, y, z + 0.05 * s), 'PaleGold', verts=10, bevel=0.02)
	cylinder(0.04 * s, 0.5 * s, (x, y, z + 0.3 * s), 'PaleGold', verts=8, bevel=0.0)
	cz = z + 0.62 * s
	sphere(0.15 * s, (x, y, cz), glow)
	for rad, tilt, pr, pm, pa in ((0.32, (70, 0, 10), 0.06, 'Rose', 40), (0.46, (58, 0, -35), 0.075, 'Lavender', 200)):
		torus(rad * s, 0.02 * s, (x, y, cz), 'PaleGold', rot=tilt)
		m = Matrix.Translation((x, y, cz)) @ _rot(tilt) @ _rz(pa)
		sphere(pr * s, (rad * s, 0, 0), pm, matrix=m)
	return cz + 0.46 * s


def star_finial(x, y, z, s=1.0, glow='Starfire'):
	"""A short gold spike tipped with a glowing upright four-point star."""
	cylinder(0.05 * s, 0.24 * s, (x, y, z + 0.12 * s), 'PaleGold', verts=8, bevel=0.0, radius2=0.025 * s)
	star4(face(x, y, z + 0.4 * s, '-y'), 0.17 * s, 0.06 * s, glow)
	return z + 0.57 * s


def amphora(x, y, z, s=1.0, mat_name='Amphora'):
	ring_solid(0.09 * s, 0.14 * s, 0.14 * s, (x, y, z), mat_name, n=10, bevel=0.03)
	ring_solid(0.14 * s, 0.06 * s, 0.16 * s, (x, y, z + 0.14 * s), mat_name, n=10, bevel=0.03)
	cylinder(0.06 * s, 0.1 * s, (x, y, z + 0.33 * s), mat_name, verts=10, bevel=0.015)
	torus(0.065 * s, 0.018 * s, (x, y, z + 0.38 * s), 'PaleGold')


def spot(name, loc, scale):
	"""An empty written alongside the mesh (a BeastSpot)."""
	e = bpy.data.objects.new(name, None)
	bpy.context.scene.collection.objects.link(e)
	e.location = loc
	e.scale = (scale, scale, scale)
	return e
