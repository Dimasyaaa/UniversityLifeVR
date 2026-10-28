shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 light_color : source_color = vec4(1.0, 0.85, 0.62, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.13;

void fragment() {
	// Мягкая проекция двух створок, скрытая под мебелью глубиной сцены.
	vec2 edge = smoothstep(vec2(0.0), vec2(0.10, 0.10), UV)
		* (1.0 - smoothstep(vec2(0.90, 0.90), vec2(1.0), UV));
	float mullion = smoothstep(0.018, 0.045, abs(UV.x - 0.5));
	ALBEDO = light_color.rgb;
	ALPHA = edge.x * edge.y * mullion * strength;
}
