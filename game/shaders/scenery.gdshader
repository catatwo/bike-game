// Scenery (crystals, pyramids, blocks, trees): dark at the base, glowing at
// the top, in each instance's own colour. Meshes are 1 unit tall, centred.
shader_type spatial;
render_mode unshaded;

uniform float glow = 1.8;

varying float height;

void vertex() {
	height = clamp(VERTEX.y + 0.5, 0.0, 1.0);
}

void fragment() {
	ALBEDO = COLOR.rgb * mix(0.08, glow, height * height);
}
