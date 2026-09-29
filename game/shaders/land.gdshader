// The island's land: flat tiles raised by its baked heights (Island), with a
// neon grid and contour lines every few metres of height so hills read as
// hills.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 base_color : source_color = vec3(0.01, 0.02, 0.05);
uniform vec3 line_color : source_color = vec3(0.0, 0.7, 0.9);
uniform vec3 contour_color : source_color = vec3(1.0, 0.2, 0.8);
uniform float cell = 10.0;
uniform float contour_step = 6.0;
uniform float brightness = 1.0;
uniform sampler2D heights : filter_linear, repeat_disable;
uniform vec2 heights_origin;  // world x, z of the first height
uniform vec2 heights_size;  // how many heights across and down
uniform float heights_cell = 8.0;  // m between them
uniform float outside = 40.0;  // beyond them: flat land

varying vec3 world_pos;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 t = (w.xz - heights_origin) / heights_cell;
	float h = outside;
	if (t.x >= 0.0 && t.y >= 0.0 && t.x <= heights_size.x - 1.0 && t.y <= heights_size.y - 1.0) {
		h = textureLod(heights, (t + 0.5) / heights_size, 0.0).r;
	}
	VERTEX.y = h;
	world_pos = vec3(w.x, h, w.z);
}

// 1 on a grid line, 0 between, anti-aliased; fades out where lines crowd
// together in the distance instead of shimmering.
float grid(vec2 coord) {
	vec2 fw = max(fwidth(coord), vec2(1e-4));
	vec2 d = abs(fract(coord - 0.5) - 0.5) / fw;
	float on = 1.0 - min(min(d.x, d.y), 1.0);
	return on * (1.0 - smoothstep(0.15, 0.5, max(fw.x, fw.y)));
}

float line(float coord) {
	float fw = max(fwidth(coord), 1e-4);
	float d = abs(fract(coord - 0.5) - 0.5) / fw;
	return (1.0 - min(d, 1.0)) * (1.0 - smoothstep(0.2, 0.6, fw));
}

void fragment() {
	float g = grid(world_pos.xz / cell);
	float c = line(world_pos.y / contour_step);
	ALBEDO = base_color + (line_color * g * 0.9 + contour_color * c * 0.7) * brightness;
}
