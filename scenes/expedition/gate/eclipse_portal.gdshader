shader_type spatial;
// The eclipse ring's portal. It opens the way the court's seal burned away: blocky cells give
// way behind an ember front, here spreading from the centre to the rim, and reveal a slow
// violet vortex flecked with stars. A thin ember rim stays alight once open.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float open_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 ember : source_color = vec3(1.0, 0.45, 0.12);
uniform vec3 deep : source_color = vec3(0.03, 0.015, 0.08);
uniform vec3 bright : source_color = vec3(0.52, 0.36, 1.0);
uniform float cell_size = 0.032;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	if (r > 1.0) {
		discard;
	}
	float cell = hash(floor(UV / cell_size));
	float threshold = cell * 0.4 + r * 0.6;
	float front = open_amount * 1.3;
	if (threshold > front) {
		discard;
	}
	float edge = 1.0 - smoothstep(0.0, 0.1, front - threshold);
	// Vortex: angle bent by radius and time, broken by noise.
	float angle = atan(c.y, c.x);
	float spin = angle * 2.0 + r * 7.0 - TIME * 0.9;
	float bands = 0.5 + 0.5 * sin(spin + value_noise(vec2(spin, r * 4.0)) * 3.0);
	float core = pow(1.0 - r, 2.2);
	vec3 color = mix(deep, bright, clamp(bands * 0.35 * (1.0 - r) + core * 0.9, 0.0, 1.0));
	// Stars drifting inward.
	vec2 drift = vec2(angle * 3.0, r * 6.0 + TIME * 0.35);
	float star = step(0.985, hash(floor(drift * 9.0)));
	color += vec3(0.8, 0.85, 1.0) * star * (1.0 - r);
	float rim = smoothstep(0.86, 1.0, r) * open_amount;
	color = mix(color, ember * 1.6, max(edge, rim * 0.8));
	ALBEDO = color;
}
