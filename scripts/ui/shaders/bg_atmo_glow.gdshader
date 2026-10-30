shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════
// 大气环辉光层 shader（蓝白星背景 L4 层）
//
// 原理：沿「行星地平线弧线」做辉光脉动 —— 蓝白星的主角不是光疤，是这道大气光。
//
// 弧线模型（实测数据驱动）：
//   原图 2276×1280，沿 x 逐列统计冰蓝大气环的 y 中心：
//     x=5%  → y=0.894      x=55% → y=0.527      x=95% → y=0.288
//   拟合为二次曲线：y = A + B*x + C*x²
//
// ★ 14 秒无缝循环：脉动用 mod(TIME,14)/14 驱动，整数倍频率（2 圈）→ 闭合
// ═══════════════════════════════════════════════════════════════

group_uniforms atmo;

// 弧线二次拟合系数（由脚本传入，默认值来自实测拟合）
uniform float arc_a = 1.0294;   // 常数项（实测拟合，平均误差0.022）
uniform float arc_b = -0.9384;  // 一次项
uniform float arc_c = 0.1410;   // 二次项

// 光带厚度（沿法线的衰减半径，UV 单位）
uniform float band_width  : hint_range(0.005, 0.150, 0.001) = 0.042;
// 内侧（行星面）额外光晕宽度
uniform float inner_glow  : hint_range(0.0, 0.30, 0.001) = 0.085;

// 颜色（冰蓝主色 + 白色高光）
uniform vec3 color_atmo   : source_color = vec3(0.55, 0.85, 1.00);
uniform vec3 color_hot    : source_color = vec3(0.92, 0.98, 1.00);

// 脉动强度（14 秒 2 圈闭合）
uniform float pulse_amount : hint_range(0.0, 0.8, 0.01) = 0.26;
uniform float pulse_turns  : hint_range(1.0, 4.0, 1.0) = 2.0;

// 整体亮度
uniform float brightness   : hint_range(0.0, 2.0, 0.01) = 0.75;

const float LOOP = 14.0;

void fragment() {
	vec2 uv = UV;

	// ── 弧线：y_arc(x)（归一化 UV）
	float y_arc = arc_a + arc_b * uv.x + arc_c * uv.x * uv.x;

	// 到弧线的有符号距离（>0 在弧线上方=太空，<0 在下方=行星面）
	float d = uv.y - y_arc;

	// ── 光带：以弧线为中心的柔和高斯
	float band = exp(-pow(d / band_width, 2.0));

	// ── 内侧光晕（行星边缘内的弥散光）
	float inner = exp(-pow(max(-d, 0.0) / inner_glow, 2.0)) * 0.45;

	// ── 上方外溢（稀薄大气往太空溢出）
	float outer = exp(-pow(max(d, 0.0) / (band_width * 2.2), 2.0)) * 0.30;

	float glow = band + inner + outer;

	// ── 14 秒闭环脉动（整数倍频率）
	// ★ 2026-10-30 修：原式 alpha = glow * brightness * pulse，
	//   pulse ∈ 0.74~1.26 把 **整屏明暗** 拉动 ±26%（实机实测 t=3.5 时全屏均值从 116 掉到 96.7，暗17%），
	//   观感是"整个画面在闪"而不是"大气环在呼吸"。
	//   正解：脉动只调制本层自身 alpha 的相对变化，绝不让 brightness 参与脉动。
	float phase = mod(TIME, LOOP) / LOOP;
	float pulse01 = 0.5 + 0.5 * sin(6.2831 * phase * pulse_turns);   // 0~1

	// ── 颜色：中心偏白，边缘偏冰蓝
	vec3 col = mix(color_atmo, color_hot, clamp(band * 1.35, 0.0, 1.0));
	col *= brightness;

	// ── 最终 alpha：只在自身的 ±(35%×pulse_amount) 内起伏
	float a_base = clamp(glow * brightness, 0.0, 1.0);
	float a = a_base * (1.0 - 0.35 * pulse_amount * (1.0 - pulse01));

	COLOR = vec4(col, a);
}
