// The road: dark, with glowing edges, a dashed centre line and faint marks
// across it every 5 m, which is what makes speed visible. UV.x runs across
// (0 left, 1 right), UV.y is metres along the road.
//
// Each edge is drawn like a neon tube: a band in the area's colour at full
// saturation, with a thin bright core in the colour itself. Drawn bright
// enough to glow, a pale colour (the mountain's lilac, the valley's ice) on
// its own would come out white.
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

// The same hue, as strong as it goes: its brightest channel 1, its weakest 0.
vec3 saturated(vec3 c) {
	float hi = max(c.r, max(c.g, c.b));
	float lo = min(c.r, min(c.g, c.b));
	return (c - lo) / max(hi - lo, 1e-4);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float wu = max(fwidth(u), 1e-4);
	float d = min(u, 1.0 - u);  // across, from the nearer side
	float band = 1.0 - smoothstep(0.03, 0.03 + wu * 1.5, d);
	float core = 1.0 - smoothstep(0.004, 0.004 + wu * 1.5, abs(d - 0.015));
	float centre = 1.0 - smoothstep(0.008, 0.008 + wu * 1.5, abs(u - 0.5));
	float dashes = centre * step(0.5, fract(v / 8.0));
	float fv = max(fwidth(v / 5.0), 1e-4);
	float across = (1.0 - min(abs(fract(v / 5.0 - 0.5) - 0.5) / fv, 1.0))
		* (1.0 - smoothstep(0.2, 0.6, fv));
	vec3 tube = saturated(edge);
	ALBEDO = surface + tube * (band * (1.0 - core) + across * 0.25)
		+ edge * core * glow + dash * dashes;
}
