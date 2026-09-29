// A soft dark patch on the road under the bike, so it sits on the road
// rather than floating over it.
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

uniform float darkness = 0.65;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = darkness * (1.0 - smoothstep(0.2, 1.0, length(p)));
}
