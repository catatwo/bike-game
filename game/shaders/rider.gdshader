// The rider (Loft meshes), in the bike's neon style: a dark suit whose
// outline glows in the rider's colour, with glowing lines along it. Vertex
// COLOR picks them: g lines down both sides of a part (UV.x 0 and 0.5), r
// lines along its other two sides (UV.x 0.25 and 0.75: the spine, the top of
// the helmet), b the whole part glowing (visor, cuffs), a a fill of the
// rider's colour. No scene lights: a light fixed to the camera gives the
// shapes their form, with a soft sheen of the rider's colour where it falls.
shader_type spatial;
render_mode unshaded;

uniform vec3 kit : source_color = vec3(1.0, 0.23, 0.83);  // the rider's colour
uniform vec3 suit : source_color = vec3(0.045, 0.05, 0.07);
uniform vec3 glow : source_color = vec3(1.0, 0.6, 0.92);  // lines and bands
uniform float rim_power = 2.3;
uniform float rim_strength = 0.75;
uniform float sheen_strength = 0.2;
uniform float line_strength = 1.0;
uniform float line_width = 0.02;  // half, as a share of a quarter of the way round

// 1 on the lines at whole numbers of u, 0 between, anti-aliased.
float lines(float u, float fw) {
	return 1.0 - smoothstep(line_width, line_width + fw * 1.5, abs(fract(u + 0.5) - 0.5));
}

void fragment() {
	vec3 light = normalize(vec3(-0.4, 0.75, 0.55));
	float lit = clamp(dot(NORMAL, light) * 0.6 + 0.4, 0.0, 1.0);
	float sheen = pow(clamp(dot(reflect(-light, NORMAL), VIEW), 0.0, 1.0), 8.0);
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float u = UV.x * 2.0;
	float fu = max(fwidth(u), 1e-4);
	float line = max(lines(u, fu) * COLOR.g, lines(u + 0.5, fu) * COLOR.r);
	vec3 base = mix(suit, kit * 0.3, COLOR.a);
	ALBEDO = base * (0.3 + 1.4 * lit * lit) + kit * (sheen * sheen_strength + edge * rim_strength)
		+ glow * max(line, COLOR.b) * line_strength;
}
