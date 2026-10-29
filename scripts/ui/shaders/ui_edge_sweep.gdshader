shader_type canvas_item;

// U0-5 · 底缘流光扫描（主按钮待机/关键强调；参数由 UiMotion.edge_sweep() 注入）
// 结构反馈纪律：待机辉光一律走底缘扫描线，禁全件发光

uniform vec4 sweep_color : source_color = vec4(1.0, 0.92, 0.65, 0.5);
uniform float sweep_period : hint_range(0.5, 12.0) = 3.2;
uniform float sweep_width : hint_range(0.02, 0.5) = 0.18;

void fragment() {
	vec4 col = COLOR;
	float p = fract(TIME / max(sweep_period, 0.01));
	float band = 1.0 - smoothstep(0.0, sweep_width, abs(UV.x - p));
	col.rgb = mix(col.rgb, sweep_color.rgb, band * sweep_color.a);
	COLOR = col;
}
