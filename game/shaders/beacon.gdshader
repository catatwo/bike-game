// A landmark's light: a soft glowing dot, pulsing, seen from anywhere (no fog).
shader_type spatial;
render_mode unshaded, fog_disabled, blend_add, depth_draw_never, cull_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.2, 0.8);

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float glow = pow(max(1.0 - d, 0.0), 2.0) * (1.4 + 0.6 * sin(TIME * 2.5));
	ALBEDO = color * glow * 2.0;
}
