shader_type canvas_item;

// ═══════════════════════════════════════════════════════════════
// 蓝白星 · 晨昏线（昼夜分界）微移 shader（v2 新增，2026-10-30）
//
// ★ 主人要求：「星球轮廓的光暗边缘」要有设计。
//
// 原理：不改底图结构，只在其上叠加一条 **极缓慢左右移动的明暗带**，
//       模拟星体自转导致晨昏线位移。
//
// 实测几何（原图 2276×1280，行星区 y>0.35）：
//   最亮处  x ≈ 0.41（光照中心）
//   晨昏线  x ≈ 0.75~0.90（右侧暗面过渡带）
//   左边缘  随 y 变化（球面轮廓）
//
// 因为这是**全屏叠加层**，必须遵守：脉动只调 alpha，绝不乘整体 brightness。
//
// 14 秒闭环：phase = mod(TIME,14)/14，整数圈。
// ═══════════════════════════════════════════════════════════════

group_uniforms terminator;

uniform float line_x      : hint_range(0.2, 1.2, 0.001) = 0.82;   // 晨昏线基准位置（实测）
uniform float line_width  : hint_range(0.05, 0.60, 0.001) = 0.26; // 过渡带宽度
uniform float shift_amp   : hint_range(0.0, 0.20, 0.001) = 0.045;// 位移幅度（极缓）
uniform float dark_amount : hint_range(0.0, 1.0, 0.01) = 0.30;   // 暗面压暗强度
uniform float light_amount: hint_range(0.0, 1.0, 0.01) = 0.12;   // 亮面提亮强度
uniform float planet_top  : hint_range(0.0, 1.0, 0.001) = 0.30;  // 行星区起始 y（上方是太空，不处理）
uniform float loop_turns  : hint_range(1.0, 2.0, 1.0) = 1.0;     // 14 秒走几圈

const float LOOP = 14.0;

void fragment() {
	vec2 uv = UV;
	float phase = mod(TIME, LOOP) / LOOP;

	// ── 晨昏线位置：极缓慢左右摆动（14 秒整圈）
	//    用 sin 让它在 line_x ± shift_amp 之间往返，首尾闭合
	float swing = sin(6.2831 * phase * loop_turns);
	float lx = line_x + swing * shift_amp;

	// ── 只在行星区生效（太空区 alpha=0）
	float in_planet = smoothstep(planet_top - 0.05, planet_top + 0.10, uv.y);

	// ── 晨昏过渡：以 lx 为中心的平滑过渡
	//    x < lx  → 亮面（提亮）
	//    x > lx  → 暗面（压暗）
	float t = smoothstep(lx - line_width * 0.5, lx + line_width * 0.5, uv.x);

	// 亮面提亮 / 暗面压暗
	float light = (1.0 - t) * light_amount;
	float dark  = t * dark_amount;

	// ── 输出：白（提亮）与黑（压暗）两层，用 alpha 控制强度
	//    用单 pass 表达：正的 light 用白色，dark 用黑色
	float net = light - dark;
	vec3 col = net >= 0.0 ? vec3(1.0) : vec3(0.0);
	float a = abs(net) * in_planet * 0.85;

	COLOR = vec4(col, a);
}
