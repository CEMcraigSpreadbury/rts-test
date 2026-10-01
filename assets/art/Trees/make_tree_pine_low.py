"""Builds tree_pine_low.glb / tree_pine_low_2.glb: flat-shaded low-poly pines
(spire + 3 drooping tiers + hex trunk) with a tiny colour atlas, double-sided
like the AmiPolyGon pines so TreeWind / the lit pipeline treat them the same.
The second is a smaller, differently-seeded variant (stands in for tree_pine_2).

    python make_tree_pine_low.py
"""
import io
import json
import math
import random
import struct
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
# (file, seed, uniform scale)
VARIANTS = [("tree_pine_low.glb", 7, 1.0), ("tree_pine_low_2.glb", 21, 0.8)]

# Atlas: left half foliage (rows = tip -> inner gradient, 4 hue columns),
# right half trunk (3 shades). UVs only ever land on cell centres.
ATLAS = 32
FOLIAGE = [  # tip, mid, inner — per hue column
	[(98, 136, 22), (66, 104, 14), (36, 64, 6)],
	[(90, 130, 20), (60, 98, 12), (32, 60, 6)],
	[(106, 140, 26), (72, 108, 16), (40, 68, 8)],
	[(84, 124, 18), (56, 92, 10), (30, 56, 4)],
]
TRUNK = [(166, 102, 34), (138, 82, 26), (100, 58, 18)]


def lerp(a, b, t):
	return a + (b - a) * t


def build_atlas():
	img = Image.new("RGB", (ATLAS, ATLAS))
	px = img.load()
	half = ATLAS // 2
	col_w = half // len(FOLIAGE)
	for col, (tip, mid, inner) in enumerate(FOLIAGE):
		for y in range(ATLAS):
			t = y / (ATLAS - 1)
			if t < 0.5:
				c = [lerp(tip[i], mid[i], t / 0.5) for i in range(3)]
			else:
				c = [lerp(mid[i], inner[i], (t - 0.5) / 0.5) for i in range(3)]
			for x in range(col * col_w, (col + 1) * col_w):
				px[x, y] = tuple(int(round(v)) for v in c)
	band = ATLAS // len(TRUNK)
	for y in range(ATLAS):
		shade = TRUNK[min(y // band, len(TRUNK) - 1)]
		for x in range(half, ATLAS):
			px[x, y] = shade
	buf = io.BytesIO()
	img.save(buf, "PNG")
	return buf.getvalue()


def foliage_uv(col, shade):
	# shade 0 = tip (light) .. 1 = inner (dark); keep off the atlas edges.
	u = (col + 0.5) / len(FOLIAGE) * 0.5
	v = lerp(0.06, 0.94, shade)
	return (u, v)


def trunk_uv(shade_index):
	band = 1.0 / len(TRUNK)
	return (0.75, (shade_index + 0.5) * band)


class Mesh:
	def __init__(self):
		self.pos, self.nrm, self.uv = [], [], []

	def tri(self, a, b, c, uva, uvb, uvc):
		ux, uy, uz = (b[i] - a[i] for i in range(3))
		vx, vy, vz = (c[i] - a[i] for i in range(3))
		n = (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
		ln = math.sqrt(sum(x * x for x in n)) or 1.0
		n = tuple(x / ln for x in n)
		for p, t in ((a, uva), (b, uvb), (c, uvc)):
			self.pos.append(p)
			self.nrm.append(n)
			self.uv.append(t)

	@property
	def tri_count(self):
		return len(self.pos) // 3


def build(seed):
	rng = random.Random(seed)
	mesh = Mesh()

	def jitter(p, amount):
		return (p[0] + rng.uniform(-amount, amount), p[1] + rng.uniform(-amount, amount) * 0.6, p[2] + rng.uniform(-amount, amount))

	# Trunk: 6-sided, flared base (ring per (radius, y, shade)), top buried
	# in the bottom tier.
	sides = 6
	ring_specs = [(0.6, -0.05, 2), (0.46, 0.75, 1), (0.36, 2.3, 0)]
	rot = rng.uniform(0, math.tau)
	rings = [[] for _ in ring_specs]
	for i in range(sides):
		a = rot + i / sides * math.tau
		rj = rng.uniform(0.92, 1.08)
		for ring, (r, y, _) in zip(rings, ring_specs):
			ring.append((math.cos(a) * r * rj, y, math.sin(a) * r * rj))
	for lo, hi, (_, _, s_lo), (_, _, s_hi) in zip(rings, rings[1:], ring_specs, ring_specs[1:]):
		for i in range(sides):
			j = (i + 1) % sides
			s0, s1 = trunk_uv(min(s_hi + rng.randrange(2), 2)), trunk_uv(s_lo)
			mesh.tri(lo[i], hi[i], hi[j], s1, s0, s0)
			mesh.tri(lo[i], hi[j], lo[j], s1, s0, s1)

	# Foliage tiers, top to bottom: (points, rim radius, rim tip y, apex y).
	# Each is a tall cone whose apex hides in the tier above, so the visible
	# band is the sloped flank plus a short drooping lip at the rim.
	tiers = [
		(6, 0.68, 4.55, 6.2),
		(8, 1.04, 3.62, 5.18),
		(9, 1.3, 2.76, 4.66),
		(10, 1.48, 1.62, 4.12),
	]
	for t_index, (n, rad, rim_y, apex_y) in enumerate(tiers):
		rot = rng.uniform(0, math.tau)
		drop = apex_y - rim_y
		apex = (rng.uniform(-0.03, 0.03), apex_y, rng.uniform(-0.03, 0.03))
		mid, rim = [], []
		for k in range(2 * n):
			a = rot + k / (2 * n) * math.tau + rng.uniform(-0.06, 0.06)
			tip = k % 2 == 0
			r_scale = rng.uniform(0.92, 1.08)
			if tip:
				r_rim, y_rim = rad * r_scale, rim_y + rng.uniform(-0.08, 0.04)
				r_mid, y_mid = rad * 0.8 * r_scale, apex_y - drop * 0.74
			else:
				r_rim, y_rim = rad * 0.84 * r_scale, rim_y + drop * 0.1
				r_mid, y_mid = rad * 0.63 * r_scale, apex_y - drop * 0.68
			c, s = math.cos(a), math.sin(a)
			rim.append((jitter((c * r_rim, y_rim, s * r_rim), 0.03), tip))
			mid.append((jitter((c * r_mid, y_mid, s * r_mid), 0.03), tip))
		# The spire's top fan is all visible, lower tiers' apex sits hidden in the tier above.
		apex_shade = 0.55 if t_index == 0 else 1.0
		for k in range(2 * n):
			j = (k + 1) % (2 * n)
			col = rng.randrange(len(FOLIAGE))
			(m0, m0tip), (m1, m1tip) = mid[k], mid[j]
			(r0, r0tip), (r1, r1tip) = rim[k], rim[j]
			sm = lambda tip: 0.4 if tip else 0.6
			sr = lambda tip: 0.0 if tip else 0.3
			mesh.tri(apex, m1, m0, foliage_uv(col, apex_shade), foliage_uv(col, sm(m1tip)), foliage_uv(col, sm(m0tip)))
			col = rng.randrange(len(FOLIAGE))
			mesh.tri(m0, m1, r1, foliage_uv(col, sm(m0tip)), foliage_uv(col, sm(m1tip)), foliage_uv(col, sr(r1tip)))
			mesh.tri(m0, r1, r0, foliage_uv(col, sm(m0tip)), foliage_uv(col, sr(r1tip)), foliage_uv(col, sr(r0tip)))
	return mesh


def write_glb(mesh, atlas_png, path):
	def pack(fmt, rows):
		return b"".join(struct.pack(fmt, *r) for r in rows)

	pos = pack("<3f", mesh.pos)
	nrm = pack("<3f", mesh.nrm)
	uv = pack("<2f", mesh.uv)
	views, blob = [], b""
	for data, target in ((pos, 34962), (nrm, 34962), (uv, 34962), (atlas_png, None)):
		while len(blob) % 4:
			blob += b"\0"
		view = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
		if target:
			view["target"] = target
		views.append(view)
		blob += data
	while len(blob) % 4:
		blob += b"\0"
	count = len(mesh.pos)
	mins = [min(p[i] for p in mesh.pos) for i in range(3)]
	maxs = [max(p[i] for p in mesh.pos) for i in range(3)]
	gltf = {
		"asset": {"version": "2.0", "generator": "make_tree_pine_low.py"},
		"scene": 0,
		"scenes": [{"nodes": [0]}],
		"nodes": [{"name": "tree_pine_low", "mesh": 0}],
		"meshes": [{"name": "tree_pine_low", "primitives": [{
			"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
			"material": 0,
		}]}],
		"accessors": [
			{"bufferView": 0, "componentType": 5126, "count": count, "type": "VEC3", "min": mins, "max": maxs},
			{"bufferView": 1, "componentType": 5126, "count": count, "type": "VEC3"},
			{"bufferView": 2, "componentType": 5126, "count": count, "type": "VEC2"},
		],
		"bufferViews": views,
		"buffers": [{"byteLength": len(blob)}],
		"materials": [{
			"name": "tree_pine_low",
			"doubleSided": True,
			"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 1.0},
		}],
		"samplers": [{"magFilter": 9729, "minFilter": 9987}],
		"textures": [{"source": 0, "sampler": 0}],
		"images": [{"bufferView": 3, "mimeType": "image/png", "name": "Atlas"}],
	}
	js = json.dumps(gltf, separators=(",", ":")).encode()
	while len(js) % 4:
		js += b" "
	total = 12 + 8 + len(js) + 8 + len(blob)
	out = struct.pack("<III", 0x46546C67, 2, total)
	out += struct.pack("<II", len(js), 0x4E4F534A) + js
	out += struct.pack("<II", len(blob), 0x004E4942) + blob
	path.write_bytes(out)


if __name__ == "__main__":
	atlas = build_atlas()
	for name, seed, scale in VARIANTS:
		mesh = build(seed)
		mesh.pos = [tuple(v * scale for v in p) for p in mesh.pos]
		write_glb(mesh, atlas, HERE / name)
		print(f"{name}: {mesh.tri_count} tris, {len(mesh.pos)} verts")
