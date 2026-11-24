// Water and glowglass: same lighting as terrain, blended, visible from both sides.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2DArray tiles : source_color, filter_nearest_mipmap, repeat_enable;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.78);
uniform vec3 night_color : source_color = vec3(0.24, 0.30, 0.50);
uniform vec3 lamp_color : source_color = vec3(1.0, 0.78, 0.54);
uniform vec3 ambient : source_color = vec3(0.06, 0.09, 0.12);

void fragment() {
	vec4 t = texture(tiles, vec3(UV, UV2.x));
	vec3 sky = mix(night_color, sun_color, daylight) * COLOR.a;
	float b = UV2.y;
	vec3 lamp = lamp_color * (b * b * 0.85 + b * 0.2);
	ALBEDO = t.rgb * COLOR.rgb * (max(sky, lamp) + ambient);
	ALPHA = t.a;
}
