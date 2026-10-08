// Bath suds: each instance of the MultiMesh is one small foam bubble, packed into a pile round the
// duck and into floating clumps (see scripts/suds.gd). White on top, a cool shade beneath, a faint
// rainbow sheen at the rims like the bubbles, and a slow bob and quiver so the suds look alive.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec4 foam_color : source_color = vec4(0.98, 0.99, 1.0, 1.0);
uniform vec4 shade_color : source_color = vec4(0.70, 0.80, 0.90, 1.0);
// The rainbow at the rims, from 0 (plain white) up.
uniform float sheen : hint_range(0.0, 1.0) = 0.35;
// How far each bubble swells and shrinks, as a share of its size.
uniform float quiver : hint_range(0.0, 0.3) = 0.06;
// How far the suds rise and fall with the water, in metres.
uniform float bob : hint_range(0.0, 0.02) = 0.003;

// Each bubble's own phase, from where it sits: the Compatibility renderer has no INSTANCE_ID.
varying float v_phase;

vec3 hsv2rgb(float h, float s, float v) {
	return ((clamp(abs(fract(h + vec3(0.0, 2.0, 1.0) / 3.0) * 6.0 - 3.0) - 1.0, 0.0, 1.0) - 1.0) * s + 1.0) * v;
}

void vertex() {
	vec3 centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	float phase = fract(sin(dot(centre.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2832;
	v_phase = phase;
	VERTEX *= 1.0 + sin(TIME * 2.3 + phase) * quiver;
	// The whole of a clump rises and falls together, the way the water carries it.
	VERTEX.y += sin(TIME * 1.4 + centre.x * 3.0 + centre.z * 2.0) * bob / max(size, 0.0001);
}

void fragment() {
	vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float up = clamp(world_normal.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 colour = mix(shade_color.rgb, foam_color.rgb, smoothstep(0.15, 0.85, up));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	colour += hsv2rgb(rim * 1.5 + TIME * 0.05 + v_phase * 0.11, 0.6, 1.0) * rim * sheen;
	ALBEDO = colour;
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
}
