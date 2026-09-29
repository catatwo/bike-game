// The ghost of your best ride: the same glow, see-through.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

uniform vec3 color : source_color = vec3(0.8, 0.9, 1.0);
uniform float brightness = 0.5;

void fragment() {
	ALBEDO = color * brightness;
}
