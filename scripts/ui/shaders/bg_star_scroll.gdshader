shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════
// 分层星点滚动 shader（崩铁式背景 L3 层）
//
// 原理：一张单星贴图 + 网格哈希随机分布 + 每格独立闪烁相位
//      —— 关键在「同一 shader 多实例、不同 scroll_speed」→ 视差 → 纵深
//      —— 每格星星的相位由 cell 坐标哈希得出，天然各不同步
//
// 用法：同一张星贴图，建 3 个 TextureRect 叠着，speed 分别 1.0 / 2.6 / 5.2
//      再各配不同 scale（远景小、近景大）→ 真 3D 视差
// ═══════════════════════════════════════════════════════════════

group_uniforms stars;
uniform float scroll_speed   : hint_range(-20.0, 20.0, 0.01) = 1.0;   // 像素/秒（关键：多层不同值）
uniform float cell_size      : hint_range(8.0, 256.0, 0.5) = 48.0;    // 每格像素
uniform float density        : hint_range(0.0, 1.0, 0.005) = 0.22;    // 点亮概率
uniform float star_scale     : hint_range(0.05, 1.0, 0.01) = 0.35;    // 星点在格内的占比
uniform float twinkle_speed  : hint_range(0.0, 3.0, 0.01) = 0.35;     // 闪烁速度（慢！）
uniform float twinkle_amount : hint_range(0.0, 1.0, 0.01) = 0.45;     // 闪烁幅度
uniform vec3  star_color     : source_color = vec3(1.0, 0.97, 0.90);
uniform float brightness     : hint_range(0.0, 3.0, 0.01) = 1.0;
// ★ 2026-10-30：控件实际像素尺寸（由脚本按 size 传入）。
//   原实现写死 vec2(1440,900)，换分辨率/换布局（如只铺上 52%）星星就会拉伸变形。
uniform vec2  layer_size     = vec2(1440.0, 900.0);

// 精确 14 秒循环：闪烁用 mod(TIME, 14.0) 驱动
const float LOOP = 14.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	// ═══ 14 秒无缝循环（2026-10-30 主人令）═══
	// ★ 关键修正：原实现 offset 直接加在 px 上，但 cell 用 floor(px/cell_size)，
	//   px 无限增大 → cell 无限增大 → 星星沿一个方向流走并消失，14 秒也对不上。
	//   正解：在 **格子空间** 对位移做 mod，让位移量 = 整数格，14 秒回到原位。
	//
	// 数学：
	//   phase ∈ [0,1)（14 秒一圈）
	//   turns = 14 秒内滚过的整数格数（scroll_speed 换算而来，必须取整）
	//   cell_offset = -turns * phase     （单位：格）
	//   phase=0 → offset=0；phase→1 → offset→-turns，恰好整格 → 与起点同相位 ✓
	float phase = mod(TIME, LOOP) / LOOP;
	float turns = max(1.0, round(scroll_speed / max(cell_size, 1.0) * LOOP));
	vec2 cell_offset = vec2(0.0, -turns * phase);

	// 屏幕像素坐标：用 UV × 层实际尺寸（不用 SCREEN_UV，Control 上行为不稳）
	vec2 px = UV * layer_size;
	vec2 cell = floor(px / cell_size) + cell_offset;
	vec2 local = fract(px / cell_size) - 0.5;

	// 每格随机：是否存在、位置微偏、大小、闪烁相位
	float h1 = hash21(cell);
	float h2 = hash21(cell + vec2(17.3, 91.7));
	float h3 = hash21(cell + vec2(53.1, 7.9));
	float h4 = hash21(cell + vec2(23.7, 61.3));

	if (h1 > density) {
		COLOR = vec4(0.0);
	} else {
		// 星点在格内随机微偏（避免网格感 —— 这是"自然"的关键之一）
		vec2 star_pos = (vec2(h2, h3) - 0.5) * 0.62;
		float d = length(local - star_pos);

		// 星点半径：随 h4 变化（大小不一才自然）
		float r = star_scale * (0.45 + h4 * 0.85) * 0.5;
		float core = smoothstep(r, 0.0, d);

		// 外发光（柔和衰减 —— 不是硬边点）
		float glow = smoothstep(r * 3.2, 0.0, d) * 0.22;

		// 闪烁：每格独立相位；用 phase 驱动整数倍频率（4.0），14 秒恰 4 圈 → 闭环
		float twphase = h4 * 6.2831;
		float tw = 1.0 - twinkle_amount * (0.5 + 0.5 * sin(6.2831 * phase * 4.0 + twphase));

		float a = (core + glow) * tw * brightness;
		COLOR = vec4(star_color * a, a);
	}
}
