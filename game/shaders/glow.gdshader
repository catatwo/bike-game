// Plain glowing colour: the bike, the rider, gates. brightness above 1
// feeds the glow effect.
shader_type spatial;
render_mode unshaded;

uniform vec3 color : source_color = vec3(0.0, 0.9, 1.0);
uniform float brightness = 1.6;

void fragment() {
	ALBEDO = color * brightness;
}
