shader_type canvas_item;
// Low-resolution retro presentation: the 3D frame is resampled on a coarse pixel grid,
// posterized through an ordered 4x4 Bayer dither, then given animated grain and a vignette.
// Fog gradients therefore break into dithered bands, as on hardware with few colour levels.
// A comic-noir grade sits on top: ink lines where neighbouring cells change brightness sharply,
// shadows crushed toward violet-black, highlights warmed toward pale yellow.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float virtual_lines : hint_range(120.0, 720.0, 1.0) = 216.0;
uniform float color_levels : hint_range(2.0, 64.0, 1.0) = 14.0;
uniform float dither_strength : hint_range(0.0, 1.5) = 1.0;
uniform float grain : hint_range(0.0, 0.2) = 0.045;
uniform float grain_fps : hint_range(1.0, 60.0) = 14.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.12;
uniform float contrast : hint_range(0.5, 1.6) = 1.12;
uniform vec3 shadow_tint : source_color = vec3(0.13, 0.08, 0.20);
uniform float shadow_lift : hint_range(0.0, 0.3) = 0.06;
uniform float vignette : hint_range(0.0, 1.0) = 0.42;
uniform float ink_strength : hint_range(0.0, 1.0) = 0.85;
uniform float ink_threshold : hint_range(0.02, 0.6) = 0.13;
uniform vec3 ink_color : source_color = vec3(0.035, 0.02, 0.06);
uniform float black_point : hint_range(0.0, 0.3) = 0.045;
uniform vec3 shadow_color : source_color = vec3(0.03, 0.03, 0.09);
uniform vec3 highlight_tint : source_color = vec3(1.0, 0.9, 0.72);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0, 0.55, 0.3);

float bayer4(vec2 cell) {
	ivec2 p = ivec2(mod(cell, 4.0));
	int i = p.x + p.y * 4;
	// 4x4 Bayer matrix, row-major.
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
			3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	float scale = max(1.0, floor(screen_size.y / virtual_lines + 0.5));
	vec2 cell = floor(FRAGCOORD.xy / scale);
	vec2 uv = (cell + 0.5) * scale * SCREEN_PIXEL_SIZE;
	vec3 c = texture(screen_tex, uv).rgb;
	vec2 step_uv = scale * SCREEN_PIXEL_SIZE;
	vec3 weights = vec3(0.299, 0.587, 0.114);
	float l0 = dot(c, weights);
	float lx1 = dot(texture(screen_tex, uv + vec2(step_uv.x, 0.0)).rgb, weights);
	float lx0 = dot(texture(screen_tex, uv - vec2(step_uv.x, 0.0)).rgb, weights);
	float ly1 = dot(texture(screen_tex, uv + vec2(0.0, step_uv.y)).rgb, weights);
	float ly0 = dot(texture(screen_tex, uv - vec2(0.0, step_uv.y)).rgb, weights);
	float edge = abs(lx1 - lx0) + abs(ly1 - ly0);
	// Ink falls on the darker side of an edge only, so lines stay one cell thick.
	float darker = step(l0, (lx1 + lx0 + ly1 + ly0) * 0.25);
	float ink = smoothstep(ink_threshold, ink_threshold + 0.1, edge) * darker * ink_strength;

	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c += shadow_tint * shadow_lift * (1.0 - smoothstep(0.0, 0.45, luma));
	// Noir grade: crush the darks into violet-black, warm the lights.
	c = mix(shadow_color, c, smoothstep(black_point, black_point + 0.28, luma));
	c = mix(c, c * highlight_tint * 1.08, smoothstep(0.6, 1.0, luma) * 0.5);
	c = mix(c, ink_color, ink);

	float frame = floor(TIME * grain_fps);
	c += (hash(cell + frame * 17.0) - 0.5) * grain;

	vec2 centered = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * smoothstep(0.32, 0.95, length(centered * vec2(1.25, 1.0)));
	c = mix(c, flash_color, flash);

	float threshold = (bayer4(cell) - 0.5) * dither_strength;
	c = floor(clamp(c, 0.0, 1.0) * (color_levels - 1.0) + 0.5 + threshold) / (color_levels - 1.0);
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
