shader_type spatial;
// Wind through the Thornwood's growth. Vertex colour carries the palette (and the MultiMesh
// instance tint); the bottom fifth of a tree barely moves, the top two fifths sway the most.
// One broad wave rolls through the forest in world space, each instance adds its own phase
// (INSTANCE_CUSTOM.r), and gusts swell it. Weather drives the two global parameters.
render_mode diffuse_toon, specular_toon, cull_disabled;

global uniform vec2 forest_wind_xz;
global uniform float forest_gust;
uniform float bend_height_m = 6.0;
uniform float amplitude_m = 0.14;
uniform float roughness_value = 0.9;

void vertex() {
	float h = clamp(VERTEX.y / max(bend_height_m, 0.001), 0.0, 1.0);
	float weight = smoothstep(0.18, 1.0, h);
	vec2 world_xz = MODEL_MATRIX[3].xz;
	float broad = sin(TIME * 1.7 - dot(world_xz, vec2(0.11, -0.09)));
	float local_wave = sin(TIME * 3.1 + INSTANCE_CUSTOM.r * 6.283185);
	float sway = (0.52 + 0.24 * broad + 0.09 * local_wave) * (1.0 + 0.5 * clamp(forest_gust, 0.0, 1.0));
	vec3 world_shift = vec3(forest_wind_xz.x, 0.0, forest_wind_xz.y) * weight * amplitude_m * sway;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * world_shift;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_value;
}
