// The road: dark, with glowing edges, a dashed centre line and faint marks
// across it every 5 m, which is what makes speed visible. UV.x runs across
// (0 left, 1 right), UV.y is metres along the road.
shader_type spatial;
render_mode unshaded;

uniform vec3 surface : source_color = vec3(0.02, 0.03, 0.06);
uniform vec3 edge : source_color = vec3(0.0, 0.9, 1.0);
uniform vec3 dash : source_color = vec3(0.7, 0.75, 0.8);
uniform float glow = 2.2;

// Drawn a little nearer the camera than it is (0.3%): far away, the depth
// buffer can't tell a road from the land 9 cm under it, and it would flicker.
void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz *= 0.997;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float wu = max(fwidth(u), 1e-4);
	float e = 1.0 - smoothstep(0.03, 0.03 + wu * 1.5, min(u, 1.0 - u));
	float centre = 1.0 - smoothstep(0.008, 0.008 + wu * 1.5, abs(u - 0.5));
	float dashes = centre * step(0.5, fract(v / 8.0));
	float fv = max(fwidth(v / 5.0), 1e-4);
	float across = (1.0 - min(abs(fract(v / 5.0 - 0.5) - 0.5) / fv, 1.0))
		* (1.0 - smoothstep(0.2, 0.6, fv));
	ALBEDO = surface + edge * (e * glow + across * 0.25) + dash * dashes;
}
