// Night sky: the fog colour at the horizon fading up to near-black, with a
// scatter of faint stars.
shader_type sky;

uniform vec3 top : source_color = vec3(0.0, 0.0, 0.02);
uniform vec3 horizon : source_color = vec3(0.05, 0.02, 0.12);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	float y = EYEDIR.y;
	vec3 c = mix(horizon, top, smoothstep(-0.02, 0.5, y));
	vec3 cell = floor(EYEDIR * 520.0);
	float star = step(0.9975, hash(cell)) * smoothstep(0.04, 0.3, y);
	c += vec3(star) * (0.25 + 0.6 * hash(cell + 11.0));
	COLOR = c;
}
