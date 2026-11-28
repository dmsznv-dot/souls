shader_type spatial;
// Dark still water for the crossing: opaque, two drifting noise layers bend its normals so
// lantern light breaks into moving glints. Cheap: no reflection, no transparency.
render_mode diffuse_toon, specular_toon;

uniform vec3 deep_color : source_color = vec3(0.05, 0.08, 0.12);
uniform vec3 shallow_color : source_color = vec3(0.12, 0.16, 0.2);
uniform float ripple_scale = 0.35;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz * ripple_scale;
	float a = noise(p + vec2(TIME * 0.12, TIME * 0.05));
	float b = noise(p * 1.9 - vec2(TIME * 0.07, -TIME * 0.11));
	float h = a * 0.6 + b * 0.4;
	float dx = noise(p + vec2(0.05, 0.0) + vec2(TIME * 0.12, TIME * 0.05)) - a;
	float dz = noise(p + vec2(0.0, 0.05) + vec2(TIME * 0.12, TIME * 0.05)) - a;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(dx * 6.0, 0.0, dz * 6.0, 0.0)).xyz);
	ALBEDO = mix(deep_color, shallow_color, h);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
}
