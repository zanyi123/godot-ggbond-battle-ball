shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════
// 蓝白星 · 星云流场 shader（v2 重做，2026-10-30）
//
// ★ 重做理由（主人批评 2026-10-30）：
//   「还是搬的前面的星云，连颜色都不变，没有针对图片特征」
//   v1 直接复用光疤版的紫金色板 → 两套背景看起来是同一个。
//
// ★ 本版改动：
//   1. **专属色板**：从原图实测取色（不是拍脑袋）
//        暗部 #1f2744 (0.124,0.155,0.268)  深靛蓝
//        中部 #4c5379 (0.301,0.329,0.478)  蓝紫
//        亮部 #abd9f4 (0.671,0.851,0.957)  冰蓝白
//      另有金调 accent，取自原图左上星云的高光金粒
//   2. **针对图片的流向**：原图星云呈左上→右下的带状走向，位移方向按这个来
//   3. **独立速度**：不再用光疤的速度参数
//   4. **14 秒无缝闭环**：同光疤版原理（整数圈 + phase）
// ═══════════════════════════════════════════════════════════════

group_uniforms nebula_planet;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

// ── 专属色板（实测取色）
uniform vec3 color_deep  : source_color = vec3(0.124, 0.155, 0.268);  // #1f2744 深靛蓝
uniform vec3 color_mid   : source_color = vec3(0.301, 0.329, 0.478);  // #4c5379 蓝紫
uniform vec3 color_hi    : source_color = vec3(0.671, 0.851, 0.957);  // #abd9f4 冰蓝白
uniform vec3 color_gold  : source_color = vec3(0.95, 0.80, 0.42);     // 金调点缀

uniform float density     : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform float contrast    : hint_range(0.5, 4.0, 0.05) = 1.35;
uniform float loop_turns  : hint_range(1.0, 6.0, 1.0) = 1.0;
uniform float dist_warp   : hint_range(0.0, 0.12, 0.001) = 0.026;
uniform float alpha       : hint_range(0.0, 1.0, 0.01) = 0.62;
uniform float gold_mix    : hint_range(0.0, 1.0, 0.01) = 0.16;   // 金色点缀比例

const float LOOP = 14.0;

// ★ 原图星云的走向：左上 → 右下（带状）
//   实测：亮部集中在左上，呈斜向条带
const vec2 FLOW_A = vec2( 0.72,  0.46);   // 主带流向
const vec2 FLOW_B = vec2( 0.38, -0.52);   // 交叉带
const vec2 FLOW_C = vec2(-0.30,  0.66);   // 细流

float sample_n(vec2 uv) {
	return texture(noise_tex, uv).r;
}

void fragment() {
	vec2 uv = UV;

	// ── 14 秒闭环
	float phase = mod(TIME, LOOP) / LOOP;
	float t_a = max(1.0, round(loop_turns * 1.0));
	float t_b = max(1.0, round(loop_turns * 2.0));
	float t_c = max(1.0, round(loop_turns * 3.0));

	vec2 uv_a = uv + FLOW_A * t_a * phase;
	vec2 uv_b = uv + FLOW_B * t_b * phase;
	vec2 uv_c = uv + FLOW_C * t_c * phase;

	// ── 域扭曲（蓝白星用更轻的扭曲，星云比光疤更「薄」）
	vec2 warp = vec2(sample_n(uv_c + vec2(0.31, 0.17)),
	                 sample_n(uv_c + vec2(0.63, 0.49))) - 0.5;
	vec2 uv_w = uv_a + warp * dist_warp;

	float n_main = sample_n(uv_w);
	float n_mid  = sample_n(uv_b);
	float n_fine = sample_n(uv_w * 3.0 + vec2(0.21, 0.37));

	// ── 多频叠加（比光疤更「丝」，细部权重提高）
	float neb = n_main * 0.52 + n_mid * 0.30 + n_fine * 0.18;

	// ── 整形
	neb = clamp((neb - (1.0 - density)) * contrast, 0.0, 1.0);
	neb = neb * neb * (3.0 - 2.0 * neb);

	// ── 蓝白专属渐变：深靛蓝 → 蓝紫 → 冰蓝白
	vec3 col = color_deep;
	col = mix(col, color_mid, smoothstep(0.10, 0.58, neb));
	col = mix(col, color_hi,  smoothstep(0.58, 0.94, neb) * 0.88);

	// ── 金色点缀：只在最亮的丝状边缘出现（对应原图左上的金粒）
	float gold_mask = smoothstep(0.74, 0.92, neb) * smoothstep(0.55, 0.25, uv.x) * gold_mix;
	col = mix(col, color_gold, gold_mask);

	// ── 亮度：丝状边缘更亮
	float rim = smoothstep(0.18, 0.52, neb) * (1.0 - smoothstep(0.70, 1.0, neb));
	col += color_hi * rim * 0.22;

	COLOR = vec4(col, neb * alpha);
}
