shader_type canvas_item;
// Swap de palette (SPEC §10.4) : la texture est indexée (rouge = index),
// la couleur vient de palettes.png (32 index × 4 costumes).
// flash : flash blanc d'impact ; silhouette : insert du super (noir + contour or).

uniform sampler2D palette : filter_nearest;
uniform int costume = 0;
uniform float flash = 0.0;
uniform float silhouette = 0.0;
uniform float tint_red = 0.0;

void fragment() {
	float idx = floor(texture(TEXTURE, UV).r * 255.0 + 0.5);
	if (idx < 0.5) {
		discard;
	}
	vec4 c = texture(palette, vec2((idx + 0.5) / 32.0, (float(costume) + 0.5) / 4.0));
	c.rgb = mix(c.rgb, vec3(1.0), flash);
	c.rgb = mix(c.rgb, vec3(0.9, 0.2, 0.2), tint_red * 0.5);
	if (silhouette > 0.5) {
		c.rgb = (idx < 1.5) ? vec3(0.96, 0.78, 0.24) : vec3(0.09, 0.06, 0.10);
	}
	COLOR = c;
}
