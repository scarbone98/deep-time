shader_type spatial;
// The ground, textured procedurally in world space so it never stretches
// or repeats visibly: soil grain, big patches, pebbles and litter, dark mud
// near the water, rock on steep slopes. Colours per era (eras.gd "ground").

uniform vec3 soil = vec3(0.12, 0.1, 0.06);
uniform vec3 patch_col = vec3(0.1, 0.14, 0.06);
uniform vec3 litter = vec3(0.18, 0.13, 0.07);
uniform vec3 wet = vec3(0.04, 0.04, 0.03);
uniform vec3 rock = vec3(0.2, 0.2, 0.18);
uniform float wet_line = 0.3;

varying vec3 wpos;
varying vec3 wnorm;

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1.0, 0.0)), f.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	return n(p) * 0.5 + n(p * 2.03) * 0.25 + n(p * 4.01) * 0.125 + n(p * 8.1) * 0.0625;
}
// scattered round blobs: pebbles, leaves
float spots(vec2 p, float density, float size) {
	vec2 c = floor(p);
	vec2 f = fract(p);
	float r = h(c);
	if (r > density) return 0.0;
	vec2 o = vec2(h(c + 3.1), h(c + 7.7)) * 0.6 + 0.2;
	return smoothstep(size, size * 0.6, length(f - o));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = wpos.xz;
	float big = fbm(p * 0.035);
	float mid = fbm(p * 0.22);
	float grain = n(p * 3.1) * 0.5 + n(p * 7.3) * 0.3 + n(p * 17.0) * 0.2;
	vec3 c = mix(soil, patch_col, smoothstep(0.42, 0.62, big + (mid - 0.5) * 0.35));
	c *= 0.78 + 0.44 * grain;
	// litter and pebbles
	float lit = spots(p * 1.6, 0.35, 0.28) + spots(p * 3.3 + 11.0, 0.4, 0.22);
	c = mix(c, litter * (0.8 + 0.4 * h(floor(p * 1.6))), clamp(lit, 0.0, 1.0) * 0.8);
	float peb = spots(p * 2.4 + 5.0, 0.12, 0.2);
	c = mix(c, rock * 0.9, peb * 0.6);
	// steep ground is rock
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	float rk = smoothstep(0.28, 0.5, slope + (mid - 0.5) * 0.2);
	vec3 rc = rock * (0.75 + 0.5 * n(vec2(p.x + p.y, wpos.y * 6.0)));
	c = mix(c, rc, rk);
	// wet, dark mud towards the water line
	float w = smoothstep(wet_line, wet_line - 0.6, wpos.y + (grain - 0.5) * 0.15);
	c = mix(c, wet, w);
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.35, w);
	SPECULAR = mix(0.3, 0.6, w);
}
