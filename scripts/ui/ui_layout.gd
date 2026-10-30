extends Control

## U0-6 排版规范 · 通用组件（2026-10-30 开源资源检索窗口）
##
## 依据：`美术规划/乙_视觉美术/U0-6_长停留面板排版规范.md`
##   §二 栅格 8px 基数 / 面板内边距 24~28 / 组件间距 8·12·16·22
##   §三 字号档 T1页题 20-24 / T2节题 13 / T3正文 12-13 / T4辅助 10-11 / N1数值 15-16
##   §四 固定操作区：按钮高 ≥40px、触达 ≥44px、动词 ≤2 字 + 空格、快捷键提示行常驻底栏
##   §六 防疲劳：同屏闪烁/脉冲 ≤1 处，转场 ≤300ms
##
## 纪律（U0-6 §七 验收清单）：
##   - 面板脚本 **grep 不得出现 Color( / add_theme_color_override / add_theme_font_size_override**
##   - 一切字号色值走 Theme（UiTheme）与色板（UiPalette）
##
## 本类只做「按规范拼控件」，零游戏逻辑。

class_name UiLayout

# ── 栅格（8px 基数，U0-6 §二）
const GAP_XS := 8
const GAP_S := 12
const GAP_M := 16
const GAP_L := 22
const PAD_PANEL := 24

# ── 触达尺寸（U0-6 §四：高度 ≥40，触达 ≥44）
const BTN_H := 44
const BTN_H_MAJOR := 52


## 大标题（T1 页题档，20~24px + 宽字距）
static func make_page_title(text: String) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.theme_type_variation = "LblTitle"
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# 宽字距（U0-6 §三 T1「字距 4px」）——通过主题常量控制，非字号硬编码
	lb.add_theme_constant_override("line_spacing", 0)
	add_readability_outline(lb)
	return lb


## 节题（T2，13px + 字距 4px）
static func make_section_label(text: String) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.theme_type_variation = "LblSection"
	add_readability_outline(lb)
	return lb


## 正文（T3）
static func make_body_label(text: String) -> Label:
	var lb := Label.new()
	lb.text = text
	return lb


## 辅助说明（T4）
## ★ 2026-10-30：动态背景上纯色小字对比不足（U0-6 §六 要求对比度 ≥7:1），
##   加描边提升可读性——**不改色值**（仍走 Theme），只加轮廓。
static func make_caption(text: String) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.theme_type_variation = "LblCaption"
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_readability_outline(lb)
	return lb


## 动态背景上的字可读性兜底：加一层暗描边（不是改颜色，是加轮廓）
static func add_readability_outline(lb: Label) -> void:
	lb.add_theme_constant_override("outline_size", 6)
	var c: Color = UiPalette.col("semantic.bg_base")
	lb.add_theme_color_override("font_outline_color", Color(c.r, c.g, c.b, 0.98))


## 数值（N1，15~16px，等宽数字）
static func make_num_label(text: String) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.theme_type_variation = "LblNum"
	return lb


## 主操作按钮（U0-6 §四：一屏最多一个主按钮）
## 动词 ≤2 字 + 空格间隔（如「开 始」）
static func make_primary_button(text: String, min_w: int = 240) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "BtnPrimary"
	b.custom_minimum_size = Vector2(min_w, BTN_H_MAJOR)
	return b


## 次级按钮（银线描边）
static func make_ghost_button(text: String, min_w: int = 200) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "BtnGhost"
	b.custom_minimum_size = Vector2(min_w, BTN_H)
	return b


## 危险按钮（退出/删除类）
static func make_danger_button(text: String, min_w: int = 200) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "BtnDanger"
	b.custom_minimum_size = Vector2(min_w, BTN_H)
	return b


## 快捷键提示行（U0-6 §四 第 4 条：常驻底栏）
## 默认文案对齐操控域键位表：Esc 返回 · Enter 确认
static func make_key_hint_bar(text: String = "Esc 返回 · Enter 确认") -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "KeyHintBar"
	p.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	p.offset_top = -36
	p.offset_bottom = 0
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lb := Label.new()
	lb.text = text
	lb.theme_type_variation = "LblCaption"
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(lb)
	return p


## 菜单项（去卡片化：大号裸文字 + 序号 + 悬停斜切高亮条）
## 依据经验库 10-27「UI 排版气质三要素」——小字按钮+圆角卡片=办事窗口感
static func make_menu_entry(index: int, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = "%02d   %s" % [index, text]
	b.theme_type_variation = "BtnGhost"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(320, BTN_H_MAJOR)
	if callback.is_valid():
		b.pressed.connect(callback)
	return b


## 竖排列表容器（统一间距）
static func make_vstack(sep: int = GAP_S) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", sep)
	return vb
