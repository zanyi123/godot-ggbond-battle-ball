class_name UiPalette
extends RefCounted

## U0-1 · UI 色板单一来源（美术UI线乙线窗口 · 2026-10-27）
## 数据文件：res://data/ui/ui_palette.json（定版/换色只改 JSON，本脚本零改动）
## 纪律：UI 脚本内禁止散落色值——一律 UiPalette.col("semantic.primary") 取色
## 状态：draft_awaiting_1027_2（元素六色为旧值迁移，待拍板项 1027-2 定版替换）
## 铁律：本类只读不写、零游戏逻辑（UI 层零判定红线）；缺键回退不炸

const PALETTE_PATH := "res://data/ui/ui_palette.json"

static var _data: Dictionary = {}
static var _loaded: bool = false


## 惰性加载（首取时读盘一次；热改 JSON 后可调 reload() 重读）
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PALETTE_PATH):
		push_warning("[UiPalette] 色板缺失：%s（全部回退 fallback）" % PALETTE_PATH)
		return
	var f := FileAccess.open(PALETTE_PATH, FileAccess.READ)
	if f == null:
		push_warning("[UiPalette] 色板打开失败：%s" % PALETTE_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_data = parsed
	else:
		push_warning("[UiPalette] 色板 JSON 解析失败（回退 fallback）")


## 热重载（编辑器里改 JSON 后调用，免重启）
static func reload() -> void:
	_loaded = false
	_data = {}
	_ensure_loaded()


## 点路径取值：get_value("element.金刚.display")
static func get_value(dotted: String, fallback: Variant = null) -> Variant:
	_ensure_loaded()
	var cur: Variant = _data
	for part in dotted.split("."):
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
		else:
			return fallback
	return cur


## 点路径取色（仅收 #RRGGBB / #RRGGBBAA，非法或缺键回退 fallback）
static func col(dotted: String, fallback: Color = Color.WHITE) -> Color:
	var v: Variant = get_value(dotted)
	if v is String and v.begins_with("#"):
		return Color.html(v)
	push_warning("[UiPalette] 非法或缺省色值：%s" % dotted)
	return fallback


## 六元素取色（key=数据层旧词：金刚/梦幻/草木/大地/冰雪/雷火，与 elements.json 对齐）
static func element_color(element_key: String) -> Color:
	return col("element.%s.color" % element_key)


## 六元素显示名（数据层旧词→v5 定稿新词：金刚→神力 等，v5 §7.4）
static func element_display(element_key: String) -> String:
	return str(get_value("element.%s.display" % element_key, element_key))


## 稀有度五色：common/good/rare/epic/legendary
static func rarity_color(rarity_key: String) -> Color:
	return col("rarity.%s" % rarity_key)


## 状态图标整条目：{"char": "疗", "color": Color}（status_icon_bar 迁移用）
static func status_entry(status_key: String) -> Dictionary:
	var v: Variant = get_value("status.%s" % status_key)
	if v is Dictionary:
		return {
			"char": str(v.get("char", "?")),
			"color": col("status.%s.color" % status_key),
		}
	return {}


## 耐久色阶（值域 0~1：>=0.5 ok / >=0.2 mid / <0.2 low，阈值对齐装备濒损规则）
static func durability_color(ratio: float) -> Color:
	if ratio < 0.2:
		return col("durability.low")
	if ratio < 0.5:
		return col("durability.mid")
	return col("durability.ok")
