// Tron-suit look: a dark body whose edges glow, strongest where the surface
// turns away from the camera. A soft light from above and in front gives the
// middle of each shape some roundness too, so overlapping limbs read as
// solid shapes rather than flat cut-outs. No scene lights needed.
shader_type spatial;
render_mode unshaded;

uniform vec3 base : source_color = vec3(0.02, 0.03, 0.06);
uniform vec3 rim : source_color = vec3(1.0, 0.6, 0.0);
uniform float power = 2.2;
uniform float strength = 1.7;
uniform float shading = 0.35;

void fragment() {
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// A light fixed relative to the camera: up, a little right, towards it.
	float lit = clamp(dot(NORMAL, normalize(vec3(0.35, 0.8, 0.5))), 0.0, 1.0);
	vec3 body = base + rim * 0.22 * shading * lit * lit + base * lit * 2.0 * shading;
	ALBEDO = body + rim * pow(edge, power) * strength;
}
