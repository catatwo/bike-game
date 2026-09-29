// A synthwave sun on the horizon: a disc fading from top to bottom colour,
// sliced by gaps that thicken towards the bottom. No fog: always visible.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, blend_add;

uniform vec3 top : source_color = vec3(1.0, 0.82, 0.25);
uniform vec3 bottom : source_color = vec3(1.0, 0.17, 0.84);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float y = p.y;  // -1 at the top, 1 at the bottom
	float gap = clamp((y + 0.1) * 0.45, 0.0, 0.5);
	float cut = step(gap, fract(y * 7.0 + 0.3));
	float disc = 1.0 - smoothstep(0.97, 1.0, r);
	vec3 c = mix(top, bottom, clamp(y * 0.5 + 0.5, 0.0, 1.0));
	ALBEDO = c * 1.3 * disc * cut;
}
