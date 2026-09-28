shader_type canvas_item;
// Camcorder tape look: tracking wobble, a rolling band, chroma bleed,
// grain, scanlines. `glitch` rises when something is close.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float glitch = 0.0;
uniform float dark = 0.0;
uniform float static_amt = 0.0;
uniform float white = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	float line = floor(uv.y * 270.0);
	float wob = (hash(vec2(line, floor(t * 24.0))) - 0.5) * 0.003 * (0.3 + glitch * 5.0);
	float band_y = fract(t * 0.09);
	float band = exp(-pow((uv.y - band_y) * 30.0, 2.0));
	uv.x += wob + band * 0.005 * (1.0 + glitch * 4.0);
	float blk = hash(vec2(floor(uv.y * 24.0), floor(t * 13.0)));
	if (blk < glitch * 0.3) {
		uv.x += (hash(vec2(blk, floor(t * 13.0))) - 0.5) * 0.12 * glitch;
	}
	float ca = 0.0016 + glitch * 0.007;
	vec3 c;
	c.r = texture(screen_tex, uv + vec2(ca, 0.0)).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - vec2(ca, 0.0)).b;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, 0.72);
	c *= vec3(0.96, 1.03, 0.92);
	c = (c - 0.5) * 1.08 + 0.5 + 0.015;
	c *= 0.92 + 0.08 * sin(SCREEN_UV.y * 360.0 * 3.14159);
	float n = hash(SCREEN_UV * vec2(640.0, 360.0) + fract(t * 7.3) * 100.0);
	c += (n - 0.5) * (0.07 + glitch * 0.3);
	c += band * 0.04;
	c = mix(c, vec3(n * 0.9), clamp(static_amt, 0.0, 1.0));
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - dot(d, d) * (1.2 + dark * 3.0);
	c = mix(c, vec3(1.0, 0.97, 0.85), white);
	COLOR = vec4(c, 1.0);
}
