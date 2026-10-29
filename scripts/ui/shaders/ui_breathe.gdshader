shader_type canvas_item;

// U0-5 · 呼吸脉冲（挂任意 CanvasItem；参数由 UiMotion.breathe() 注入）
// 用途：光疤/徽记/待机强调——同屏闪烁 ≤1 处（U0-6 防疲劳三则）

uniform float breathe_period : hint_range(0.5, 12.0) = 4.0;
uniform float breathe_min : hint_range(0.0, 1.0) = 0.72;

void fragment() {
	float w = 0.5 + 0.5 * sin(TIME * 6.2831853 / max(breathe_period, 0.01));
	COLOR.a *= mix(breathe_min, 1.0, w);
}
