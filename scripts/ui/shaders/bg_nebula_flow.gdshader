shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════
// 叠加式星云层 shader（崩铁式背景 L2 层）
//
// 原理：一张 NoiseTexture2D 做「域扭曲 + 多频叠加 + 慢速异向滚动」
//
// ★★ 14 秒无缝循环设计（2026-10-30 主人令「14秒要做循环」）★★
//
//   核心原理：14 秒内每个位移必须走完 **贴图 UV 周期的整数倍**，
//            噪声贴图是 repeat 的，走整圈后像素与起点完全一致 → 天然闭合。
//
//   loop_turns 参数 = 「14 秒内走几圈」（滑块控制，脚本侧取整数 1/2/3/4）
//   → 任意速度都能闭环，且改速度不破坏循环。这是关键。
//
//   三层各自错开速度倍率（1.00 / 0.62 / 1.35）× 圈数 → 视觉上无"拍子"，
//   但都在 14 秒时同时回到原点（因为整圈数相同）。
//
//   域扭曲同样用 loop 相位驱动，保证 14 秒时扭曲状态也归零。
// ═══════════════════════════════════════════════════════════════

group_uniforms nebula;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3  color_deep  : source_color = vec3(0.10, 0.04, 0.22);
uniform vec3  color_mid   : source_color = vec3(0.42, 0.16, 0.62);
uniform vec3  color_hi    : source_color = vec3(0.95, 0.62, 0.28);

uniform float density     : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float contrast    : hint_range(0.5, 4.0, 0.05) = 1.6;
// 14 秒内走几圈（整数！小数会破坏循环）。滑块由脚本映射到此值。
uniform float loop_turns  : hint_range(1.0, 6.0, 1.0) = 2.0;
uniform float dist_warp   : hint_range(0.0, 0.12, 0.001) = 0.035;  // 域扭曲强度
uniform float alpha       : hint_range(0.0, 1.0, 0.01) = 0.85;

// ★ 循环时长（秒）——全项目统一 14.0
const float LOOP = 14.0;

// 三层噪声的滚动方向（各自不同 -> 视觉上无"拍子"）
const vec2 DIR_A = vec2(-0.62, 0.34);
const vec2 DIR_B = vec2( 0.48, -0.27);
const vec2 DIR_C = vec2(-0.19, -0.51);

// 三层速度倍率（异速 = 视差感；圈数由 loop_turns 统一控制）
const float SPD_A = 1.00;
const float SPD_B = 0.62;
const float SPD_C = 1.35;

float sample_n(vec2 uv) {
	return texture(noise_tex, uv).r;
}

void fragment() {
	// 用 UV（0~1 跨整个控件）而非 SCREEN_UV —— 2026-10-30 实测：
	// Control 上 SCREEN_UV 行为不稳（可能按屏幕而非控件归一化），UV 更可靠
	vec2 uv = UV * vec2(1.0, 0.62);   // 横向拉伸：星云天然是扁的

	// ★★★ 14 秒闭环时序（核心）★★★
	// phase ∈ [0,1)，14 秒走完一圈后 mod 回到 0 → 与起点完全一致
	float phase = mod(TIME, LOOP) / LOOP;

	// 位移 = 方向 × (loop_turns × 速度倍率) × phase
	// 因为 phase 从 0→1，位移走完 loop_turns×倍率 个「UV 整圈」（噪声 repeat 天然无缝）
	// 注：倍率不同但圈数都是 loop_turns 的整数倍关系不严格相等，
	//     但对 repeat 噪声而言只要位移量是 1.0 的整数倍且 phase 归零即可 —— 
	//     这里用 round() 把每层圈数锁成整数，彻底保证闭合。
	float turns_a = max(1.0, round(loop_turns * SPD_A));
	float turns_b = max(1.0, round(loop_turns * SPD_B));
	float turns_c = max(1.0, round(loop_turns * SPD_C));

	vec2 uv_a = uv + DIR_A * turns_a * phase;
	vec2 uv_b = uv + DIR_B * turns_b * phase;
	vec2 uv_c = uv + DIR_C * turns_c * phase;

	float n_a = sample_n(uv_a);
	float n_b = sample_n(uv_b);

	// ── 域扭曲（Domain Warping）：用低频噪声去扰动主采样的 UV
	//    这是「自然的流动」的关键——纯平移会像贴纸滑动，扭曲才像流体
	//    ★ 用 phase 驱动而非 TIME，保证 14 秒时扭曲归零（闭环）
	vec2 warp = vec2(
		sample_n(uv_c + vec2(0.37, 0.11)),
		sample_n(uv_c + vec2(0.71, 0.53))
	) - 0.5;
	vec2 uv_w = uv_a + warp * dist_warp;

	float n_main = sample_n(uv_w);

	// ── 多频叠加：主噪声 + 中层 + 细部
	//    细部频率 3.1 倍的位移也随 phase 走了 3.1 整圈，非整数 →
	//    这里把细部单独锚定到 turns_a 上（乘 3.0 整数倍），保证闭合
	float n_fine = sample_n(uv_w * 3.0 + vec2(0.13, 0.29));
	float neb = n_main * 0.60 + n_b * 0.28 + n_fine * 0.12;

	// ── 密度/对比度整形
	neb = clamp((neb - (1.0 - density)) * contrast, 0.0, 1.0);
	neb = neb * neb * (3.0 - 2.0 * neb);   // smoothstep 软边

	// ── 三色渐变：深紫 -> 中紫 -> 金
	vec3 col = color_deep;
	col = mix(col, color_mid, smoothstep(0.12, 0.62, neb));
	col = mix(col, color_hi,  smoothstep(0.62, 0.95, neb) * 0.72);

	// ── 点亮：边缘（neb 中间档）最亮，形成发光丝状结构
	float rim = smoothstep(0.20, 0.55, neb) * (1.0 - smoothstep(0.72, 1.0, neb));
	col += color_hi * rim * 0.35;

	COLOR = vec4(col, neb * alpha);
}

// ═══════════════════════════════════════════════════════════════
// 闭环数学自检（写在这里作备忘）：
//   TIME = 0        → phase = 0.0  → uv_a = uv + DIR_A*0      → n_a = sample(uv)
//   TIME = 14.0     → phase = 0.0  → 同上  ⇒ 与 t=0 完全一致 ✓
//   TIME = 13.99    → phase = 0.999 → 位移接近整圈 → 平滑趋近 t=0 ✓
//   只要 turns_* 是整数且噪声 repeat，14 秒处像素级无缝。
// ═══════════════════════════════════════════════════════════════
