shader_type spatial;
// Vertex-coloured masonry whose door region burns away in blocky ash cells.
// The door region is an arch prism in model space: |x| < half_width, y below the arch curve,
// and z inside one of two slabs. The same shader cuts the ruins' entrance with open_amount 1.

uniform float open_amount : hint_range(0.0, 1.0) = 0.0;
uniform float half_width = 2.6;
uniform float spring_height = 3.1;
uniform float arch_rise = 2.5;
uniform vec2 front_slab = vec2(-13.8, -11.97);
uniform vec2 back_slab = vec2(0.0, 0.0);
uniform float roughness_value = 0.93;
uniform vec3 ember : source_color = vec3(1.0, 0.45, 0.12);
uniform float cell_size = 0.09;
// Geometry below this height (thresholds, paving) never burns.
uniform float floor_height = 0.04;

varying vec3 model_position;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	model_position = VERTEX;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_value;
	vec3 p = model_position;
	float across = abs(p.x) / half_width;
	float ceiling = spring_height + arch_rise * sqrt(max(0.0, 1.0 - across * across));
	bool in_slab = (p.z > front_slab.x && p.z < front_slab.y) || (p.z > back_slab.x && p.z < back_slab.y);
	if (open_amount > 0.0 && across < 1.0 && p.y > floor_height && p.y < ceiling && in_slab) {
		float cell = hash(floor(p / cell_size));
		// The seal burns outward from its emblem, with cell noise breaking the front.
		float spread = length((p.xy - vec2(0.0, spring_height + 0.6)) / vec2(half_width, ceiling));
		float threshold = cell * 0.45 + spread * 0.55;
		float front = open_amount * 1.25;
		if (threshold < front) {
			discard;
		}
		float glow = 1.0 - smoothstep(0.0, 0.09, threshold - front);
		ALBEDO = mix(ALBEDO, vec3(0.05, 0.03, 0.03), glow);
		EMISSION = ember * glow * 3.0;
	}
}
