shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════
// 左侧压暗带（U0-6 §六 文字对比度兜底）
//
// 2026-10-30 开源资源检索窗口
// 用途：动态背景上放菜单文字时，在左侧铺一条「左实右渐隐」的压暗带，
//       让 Theme 的 text_dim 小字也能读清 —— **不改文字色，只压背景**。
//
// 设计要点（首版教训）：
//   用两个 ColorRect 拼硬边带 + 过渡带 → 出现三道竖条硬边（anchor 不同步）。
//   正解 = **单个 ColorRect + 本 shader 做水平渐变**，天然无硬边、无第二层。
// ═══════════════════════════════════════════════════════════════

uniform vec3  tint       : source_color = vec3(0.05, 0.05, 0.09);
uniform float max_alpha  : hint_range(0.0, 1.0, 0.01) = 0.58;
// solid_ratio 左侧纯色直到该 UV 处，之后线性渐隐到 0
uniform float solid_ratio : hint_range(0.0, 1.0, 0.01) = 0.70;
// 渐隐曲线指数（>1 更快收敛，视觉更干净）
uniform float falloff_pow : hint_range(0.5, 4.0, 0.05) = 1.6;

void fragment() {
	float x = UV.x;
	// 0..1：从左侧 1 渐变到右侧 0
	float k;
	if (x <= solid_ratio) {
		k = 1.0;
	} else {
		float t = (x - solid_ratio) / max(1.0 - solid_ratio, 1e-4);
		k = pow(clamp(1.0 - t, 0.0, 1.0), falloff_pow);
	}
	COLOR = vec4(tint, k * max_alpha);
}
