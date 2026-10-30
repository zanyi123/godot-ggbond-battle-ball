shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════
// 蓝白星 · 行星表面云层流动 shader（v2 新增，2026-10-30）
//
// ★ 主人批评：「没有针对图片特征」——本片就是针对行星表面做的。
//
// 原理：不改动底图像素，而是在「云层区域」上叠加缓慢流动的明暗调制，
//       让云看起来在飘。
//
// 关键：**云层遮罩由脚本传入**（从原图实测：V>0.62 且 S<0.30 的白云）
//       —— 只在有云的地方动，海洋/陆地不动。
//
// 14 秒闭环：用 phase = mod(TIME,14)/14，整圈噪声位移。
// ═══════════════════════════════════════════════════════════════

group_uniforms cloud;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
// 云层遮罩（单通道，从原图提取）
uniform sampler2D cloud_mask : filter_linear_mipmap;

uniform float flow_turns  : hint_range(1.0, 8.0, 1.0) = 3.0;   // 14 秒走几圈
uniform float flow_dir_x  : hint_range(-1.0, 1.0, 0.01) = 0.55;
uniform float flow_dir_y  : hint_range(-1.0, 1.0, 0.01) = -0.20;
uniform float warp_amount : hint_range(0.0, 0.08, 0.001) = 0.018;
uniform float light_delta : hint_range(0.0, 0.60, 0.01) = 0.22;   // 明暗调制幅度
uniform float speed_scale : hint_range(0.0, 2.0, 0.01) = 1.0;     // 总速度倍率

const float LOOP = 14.0;

void fragment() {
	vec2 uv = UV;
	float phase = mod(TIME, LOOP) / LOOP;

	// ── 云层遮罩（只在这片区域生效，乘上速度倍率控制整体强度）
	float mask = texture(cloud_mask, uv).r;
	mask = smoothstep(0.25, 0.85, mask);
	if (mask < 0.005) {
		COLOR = vec4(0.0);
	} else {
		// ── 整圈流动（14 秒走 flow_turns 圈）
		vec2 dir = vec2(flow_dir_x, flow_dir_y);
		vec2 flow = dir * flow_turns * phase;

		// ── 域扭曲：让云层不是匀速平移，而是「卷动」
		vec2 warp = vec2(texture(noise_tex, uv * 1.7 + flow * 0.6).r,
		                 texture(noise_tex, uv * 1.7 + flow * 0.6 + vec2(0.41, 0.73)).r) - 0.5;
		float n = texture(noise_tex, uv + flow + warp * warp_amount).r;

		// ── 明暗调制：n 高的地方云更亮（被光照透），低的地方略暗（云厚）
		float mod_amount = (n - 0.5) * 2.0;   // -1~1
		float delta = 1.0 + mod_amount * light_delta;

		// ── 输出：只输出「明暗增量」，alpha = mask × 强度
		//    白色代表提亮（乘法用），配合 canvas_item 的 modulate 实现
		float strength = mask * speed_scale;
		vec3 col = vec3(1.0) * clamp(delta, 0.0, 2.0);

		// 用 alpha 表达「是否调制」：alpha 越高，越把画面往 col 靠
		// 实现方式：延迟到 GDScript 用 blend 处理不可行，这里直接用
		// 「半透明白/黑」覆盖：亮 delta>1 时叠白，暗时叠黑
		float a = abs(mod_amount) * light_delta * strength;
		vec3 overlay = mod_amount > 0.0 ? vec3(1.0) : vec3(0.0);

		COLOR = vec4(overlay, a * 0.55);
	}
}
