extends Node
class_name UiIcon

## UiIcon · UI 图标取图单例（2026-10-30 开源资源检索窗口）
##
## 依据：`美术规划/06_面向用户2D美术资源盘点与挂载就绪度.md` §八 问题3
##   「20 支图标零引用；无 UiIcon 单例 → 路径会散落各面板；建议与 UiPalette 同构」
##
## 职责：**只做「名字 → Texture2D」的解析与缓存，零游戏逻辑**。
## 纪律（对齐 UiPalette）：
##   - 面板侧一律 `UiIcon.get_tex("el_jingang")`，禁止各面板硬写 res:// 路径
##   - 资源缺失时返回 null 并 push_warning（调用方决定回退），**不崩**
##
## 命名口径（T6：`类别_名称`，与 assets/icons/ui/ 实际文件名一致）：
##   货币 cur_*    3 支：cur_yuanshi(源石) / cur_sujing(溯晶) / cur_yuanjing(源晶)
##   元素 el_*     6 支：el_jingang(神力) / el_menghuan(泯灭) / el_caomu(巨木)
##                      el_dadi(艮土) / el_bingxue(玄冰) / el_leihuo(雷火)
##   操作 op_*     6 支：op_back / op_close / op_confirm / op_lock / op_plus / op_settings
##   系统 sys_*    5 支：sys_base / sys_codex / sys_net / sys_roster / sys_trade
##
## ⚠ 现状说明：现有图标为 **SVG 矢量**（Godot 可导入但**不支持运行时动态改色**）。
##   若将来需要「图标随元素色变化」，走 06 档 1030-4 方案：导出 PNG 多档 + SVG 留源。

const DIR := "res://assets/icons/ui/"
const EXT := ".svg"

## 元素旧词 → 图标名（v5 §7.4：金刚→神力 等；数据 key 不变，图标名保留旧 key）
const ELEMENT_ICON := {
	"金刚": "el_jingang",
	"梦幻": "el_menghuan",
	"草木": "el_caomu",
	"大地": "el_dadi",
	"冰雪": "el_bingxue",
	"雷火": "el_leihuo",
}

## 货币 key → 图标名
const CURRENCY_ICON := {
	"yuanshi": "cur_yuanshi",
	"sujing": "cur_sujing",
	"yuanjing": "cur_yuanjing",
}

static var _cache: Dictionary = {}
static var _warned: Dictionary = {}


## 取图标纹理。name 传不带扩展名的 T6 名（如 "el_jingang"）。
## 缺资源返回 null（不崩），并只警告一次。
static func get_tex(icon_name: String) -> Texture2D:
	if icon_name == "":
		return null
	if _cache.has(icon_name):
		return _cache[icon_name]
	var path := DIR + icon_name + EXT
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		_cache[icon_name] = tex
		return tex
	_cache[icon_name] = null
	if not _warned.has(icon_name):
		_warned[icon_name] = true
		push_warning("[UiIcon] 图标缺失：%s" % path)
	return null


## 按元素旧 key 取图标（"金刚"/"梦幻"/…）
static func element_tex(element_key: String) -> Texture2D:
	var n: String = ELEMENT_ICON.get(element_key, "")
	return get_tex(n) if n != "" else null


## 按货币 key 取图标
static func currency_tex(currency_key: String) -> Texture2D:
	var n: String = CURRENCY_ICON.get(currency_key, "")
	return get_tex(n) if n != "" else null


## 便捷：造一个只显示图标的 TextureRect（尺寸给定，等比缩放）
static func make_icon_rect(icon_name: String, px: int = 24) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = get_tex(icon_name)
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## 便捷：造「图标 + 文字」横排（HUD/列表常用）
static func make_icon_label(icon_name: String, text: String, px: int = 20) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.add_child(make_icon_rect(icon_name, px))
	var lb := Label.new()
	lb.text = text
	hb.add_child(lb)
	return hb


## 列出全部可用图标名（供开发者面板/自检用）
static func list_available() -> Array:
	var out: Array = []
	for k in ELEMENT_ICON.values():
		out.append(k)
	for k in CURRENCY_ICON.values():
		out.append(k)
	for n in ["op_back", "op_close", "op_confirm", "op_lock", "op_plus", "op_settings"]:
		out.append(n)
	for n in ["sys_base", "sys_codex", "sys_net", "sys_roster", "sys_trade"]:
		out.append(n)
	return out


## 自检：返回 {total, found, missing[]}
static func self_check() -> Dictionary:
	var all := list_available()
	var missing: Array = []
	for n in all:
		if get_tex(n) == null:
			missing.append(n)
	return {"total": all.size(), "found": all.size() - missing.size(), "missing": missing}
