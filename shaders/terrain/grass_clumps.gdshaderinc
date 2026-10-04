// The painted look of the grass, shared by the terrain and the Binbun blades
// so the two always agree. Mostly it is broad, smooth blends of colour --
// warm sunlit yellow-green melting into deeper, cooler greens over tens of
// metres -- with a few faint clump shapes on top (a lit, serrated crown and a
// soft foot). Contrast is kept low on purpose: from a distance a painted
// meadow is calm colour, and the strong values belong to the shadows.
const float CLUMP_FREQ = 0.33;

vec2 clump_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// -1..1 down the front-most clump covering this point (its crown to its
// foot), or 2 where no clump grows. Most cells are left empty, so clumps sit
// as separate tufts on smooth grass rather than tiling.
float clump_height(vec2 xz) {
	vec2 p = xz * CLUMP_FREQ;
	// A gentle warp, so the cells the clumps are scattered over never show as
	// straight rows or columns.
	p += 0.45 * vec2(sin(p.y * 0.9 + 1.7 * sin(p.x * 0.31)), sin(p.x * 0.8 + 1.3 * sin(p.y * 0.27)));
	vec2 cell = floor(p);
	float best_front = -1e9;
	float shade = 2.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 h = clump_hash(c);
			if (fract(h.x * 7.13 + h.y * 3.71) < 0.55) {
				continue;
			}
			vec2 centre = c + 0.1 + h * 0.8;
			vec2 d = p - centre;
			d.y *= 1.6;
			float angle = atan(d.x, -d.y);
			// Serrated only along the top: the bottom of a bush is a smooth curve.
			float teeth = abs(sin(angle * 6.5 + h.x * 6.2831)) * smoothstep(0.2, -0.6, d.y);
			float radius = (0.5 + 0.35 * h.y) * (0.84 + 0.16 * teeth);
			if (length(d) < radius && centre.y > best_front) {
				best_front = centre.y;
				shade = clamp(d.y / radius, -1.0, 1.0);
			}
		}
	}
	return shade;
}

// Broad, smooth colour blending, as a painter washes in a meadow: warm sunlit
// yellow-green and a deeper, cooler green, melting into each other over tens
// of metres. Never thresholded -- hard edges here read as camouflage.
vec3 grass_patches(vec3 grass, vec2 xz, sampler2D noise) {
	vec2 warp = vec2(texture(noise, xz * 0.017).r, texture(noise, xz * 0.017 + vec2(0.5, 0.17)).r) - 0.5;
	float m = texture(noise, xz * 0.008 + warp * 0.08).r;
	float t = smoothstep(0.25, 0.75, m);
	vec3 deep = grass * vec3(0.82, 0.9, 0.97);
	vec3 sunlit = grass * vec3(1.14, 1.08, 0.93);
	return mix(deep, sunlit, t);
}

vec3 grass_clumps(vec3 grass, vec2 xz, sampler2D noise) {
	grass = grass_patches(grass, xz, noise);
	float h = clump_height(xz);
	// Far away a pixel spans several clumps: settle to their average.
	float fade = 1.0 - smoothstep(0.3, 0.8, length(fwidth(xz * CLUMP_FREQ)));
	// Faint flat shapes: a lit crown along the serrated top, the body left as
	// the grass around it, a gentle shade at the foot.
	vec3 painted = grass;
	if (h < 1.5) {
		painted = mix(grass * vec3(1.06, 1.05, 0.96), grass, smoothstep(-0.62, -0.5, h));
		painted = mix(painted, grass * vec3(0.9, 0.93, 0.97), smoothstep(0.55, 0.95, h));
	}
	return mix(grass, painted, fade);
}
