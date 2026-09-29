// The mountain ring on the horizon: dark, with a glowing ridge (vertex colour
// carries how close to the ridge each vertex is). No fog.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

uniform vec3 fill : source_color = vec3(0.02, 0.02, 0.06);
uniform vec3 ridge : source_color = vec3(1.0, 0.2, 0.8);

void fragment() {
	float k = COLOR.r;
	float k8 = k * k * k * k;
	k8 *= k8;
	ALBEDO = mix(fill, ridge * 1.5, k8 * k8);
}
