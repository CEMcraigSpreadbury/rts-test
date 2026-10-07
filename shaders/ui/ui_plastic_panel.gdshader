shader_type canvas_item;
render_mode unshaded;

// The whole body of a UI panel, drawn behind it by UiPlasticBody: a soft drop
// shadow, the darker moulded lip under the bottom edge, the frosted (blurred)
// battlefield showing through, the translucent tinted plastic over that, and a
// highlight along the top edge. Mirrors the CSS of the toy-plastic mockup:
//   background: linear-gradient(hi 0%, base 30%, lo 100%) at `opacity`
//   backdrop-filter: blur(10px) saturate(1.15)
//   box-shadow: inset 0 1px 0 white .3, inset 0 -2px 0 black .1,
//               0 lip 0 lip-colour, 0 12px 22px -8px shadow

uniform vec2 panel_pos = vec2(0.0);
uniform vec2 panel_size = vec2(100.0);
uniform float radius = 16.0;
uniform vec4 base_color : source_color = vec4(0.184, 0.204, 0.224, 1.0);
uniform float opacity = 0.8;
uniform float hi_mix = 0.09;
uniform float lo_mix = 0.05;
uniform float lip = 3.0;
uniform float lip_darken = 0.4;
uniform vec4 shadow_color : source_color = vec4(0.04, 0.08, 0.0, 0.55);
uniform float shadow_y = 12.0;
uniform float shadow_blur = 22.0;
uniform float shadow_spread = -8.0;
uniform float rim_alpha = 0.3;
uniform float base_shade = 0.1;
uniform float blur_lod = 3.0;
uniform float blur_saturation = 1.15;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float sd_round_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// `dst` is premultiplied.
vec4 over(vec4 dst, vec3 rgb, float a) {
	return vec4(rgb * a + dst.rgb * (1.0 - a), a + dst.a * (1.0 - a));
}

vec3 frosted(vec2 uv, vec2 px) {
	vec2 step_px = px * exp2(blur_lod);
	vec3 c = textureLod(screen_tex, uv, blur_lod).rgb * 0.2;
	c += textureLod(screen_tex, uv + vec2(step_px.x, 0.0), blur_lod).rgb * 0.1;
	c += textureLod(screen_tex, uv - vec2(step_px.x, 0.0), blur_lod).rgb * 0.1;
	c += textureLod(screen_tex, uv + vec2(0.0, step_px.y), blur_lod).rgb * 0.1;
	c += textureLod(screen_tex, uv - vec2(0.0, step_px.y), blur_lod).rgb * 0.1;
	c += textureLod(screen_tex, uv + step_px * 0.7, blur_lod).rgb * 0.1;
	c += textureLod(screen_tex, uv - step_px * 0.7, blur_lod).rgb * 0.1;
	c += textureLod(screen_tex, uv + vec2(step_px.x, -step_px.y) * 0.7, blur_lod).rgb * 0.1;
	c += textureLod(screen_tex, uv + vec2(-step_px.x, step_px.y) * 0.7, blur_lod).rgb * 0.1;
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(luma), c, blur_saturation);
}

void fragment() {
	vec2 hs = panel_size * 0.5;
	vec2 p = local - panel_pos - hs;
	float r = min(radius, min(hs.x, hs.y));

	float d_body = sd_round_box(p, hs, r);
	float d_lip = sd_round_box(p - vec2(0.0, lip), hs, r);
	float d_shadow = sd_round_box(p - vec2(0.0, shadow_y),
			max(hs + vec2(shadow_spread), vec2(1.0)), max(r + shadow_spread, 0.0));

	float body = clamp(0.5 - d_body, 0.0, 1.0);
	float lip_cov = clamp(0.5 - d_lip, 0.0, 1.0);
	// A CSS box-shadow never paints under its own box; keep that, or the
	// shadow darkens the frosted plastic from behind.
	float sigma = max(shadow_blur * 0.5, 0.001);
	float shadow = shadow_color.a * (1.0 - smoothstep(-sigma, sigma, d_shadow)) * (1.0 - body);

	vec4 acc = vec4(shadow_color.rgb * shadow, shadow);
	vec3 lip_rgb = mix(base_color.rgb, vec3(0.0), lip_darken);
	acc = over(acc, lip_rgb, lip_cov * opacity * (1.0 - body));

	float t = clamp((p.y + hs.y) / panel_size.y, 0.0, 1.0);
	vec3 hi = mix(base_color.rgb, vec3(1.0), hi_mix);
	vec3 lo = mix(base_color.rgb, vec3(0.0), lo_mix);
	vec3 tint = t < 0.3 ? mix(hi, base_color.rgb, t / 0.3) : mix(base_color.rgb, lo, (t - 0.3) / 0.7);
	vec3 glass = mix(frosted(SCREEN_UV, SCREEN_PIXEL_SIZE), tint, opacity);
	float rim_top = clamp(0.5 + sd_round_box(p - vec2(0.0, 1.0), hs, r), 0.0, 1.0);
	float rim_bottom = clamp(0.5 + sd_round_box(p + vec2(0.0, 2.0), hs, r), 0.0, 1.0);
	glass = mix(glass, vec3(1.0), rim_alpha * rim_top);
	glass = mix(glass, vec3(0.0), base_shade * rim_bottom);
	acc = over(acc, glass, body);

	COLOR = acc.a > 0.0001 ? vec4(acc.rgb / acc.a, acc.a) : vec4(0.0);
}
