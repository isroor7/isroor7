// Characters, creatures, drops and held items: nearest-filtered skins with a simple warm key light
// and turquoise fill, scaled by the light at the entity's position (set per material).
// Skin alpha: < 0.5 cut out, 0.5-0.95 glowing pixel, otherwise lit.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D skin : source_color, filter_nearest;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform float sky_light : hint_range(0.0, 1.0) = 1.0;
uniform float block_light : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_dir = vec3(0.45, 0.8, 0.4);
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.78);
uniform vec3 night_color : source_color = vec3(0.24, 0.30, 0.50);
uniform vec3 shadow_tint : source_color = vec3(0.42, 0.62, 0.68);
uniform vec3 lamp_color : source_color = vec3(1.0, 0.78, 0.54);
uniform vec4 flash : source_color = vec4(1.0, 0.35, 0.45, 0.0);

void fragment() {
	vec4 t = texture(skin, UV);
	if (t.a < 0.5) discard;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float k = clamp(dot(n, normalize(sun_dir)) * 0.5 + 0.5, 0.0, 1.0);
	vec3 tint = mix(shadow_tint, vec3(1.0), k * 0.75 + 0.25);
	vec3 sky = mix(night_color, sun_color, daylight) * sky_light;
	vec3 lamp = lamp_color * (block_light * block_light * 0.85 + block_light * 0.2);
	vec3 lit = t.rgb * tint * (max(sky, lamp) + vec3(0.08, 0.11, 0.14));
	// Skin pixels with alpha between 0.5 and 0.95 glow: drawn at full brightness in any light.
	vec3 color = t.a < 0.95 ? t.rgb : lit;
	ALBEDO = mix(color, flash.rgb, flash.a);
}
