extends "res://scripts/battle/status_icon_bar.gd"
class_name EnemyStatusMarker
## 23号工单：敌方作用对象头顶状态标记（19 基础UI的敌方侧补全）
## 复用 StatusIconBar 全套信号消费/图标绘制；差异三点：
## ①红色敌我边框 ②只显示减益/控制白名单（ENEMY_KEYS，显示范围裁定 §六-B）
## ③空态自动隐藏（无状态不显示空条；挂宿主球员头顶随其显隐）
## 铁律：UI 零判定——只读 status_lights_changed/mark_changed，禁止写任何游戏状态
## 数据边界（备案）：属性削弱类 14 标签走 buff_manager 堆栈无既有信号，本批不覆盖（加信号归判定层另批）

## 敌方相关键白名单（灯系统实际键位；mark=印记走 mark_changed 单独管理）
const ENEMY_KEYS: Array[String] = [
	"stunned", "rooted", "silenced", "disarmed",
	"vulnerable", "heal_block", "energy_block", "element_weak",
]

## 父类 STATUS_ICONS 缺字补映射（键首字 fallback 不达意的补单字）
const EXTRA_ICONS: Dictionary = {
	"vulnerable": {"char": "易", "color": Color(0.85, 0.25, 0.55)},
}

## 红色敌我区分（边框+左端色条）
const FRAME_COLOR := Color(0.95, 0.2, 0.2, 0.95)

## 头顶挂载偏移（相对宿主球员原点；条宽 8 格，水平居中）
const HEAD_OFFSET := Vector2(-108.0, -80.0)

## 显隐分流开关（23号 §六-B + 2026-09-29 主人令"正式版和测试平台都要"）：
## "all"（默认）=全员头顶标记（正式版+测试平台两场景都显示）
## "own_side"=仅玩家方头顶（§六-B 玩家对局备选，一键可切）
## "off"=全关
static var show_mode: String = "all"


## 分流判定（接入层统一走这里；controlled=当前人类控制球员，无人类传 null）
static func should_mark(player: Node, controlled: Node) -> bool:
	if player == null:
		return false
	match show_mode:
		"off":
			return false
		"own_side":
			if controlled == null:
				return true  # 无人类降级全员（AI 完全体观测）
			return player.get("team") != null and str(player.get("team")) == str(controlled.get("team"))
		_:
			return true


func _ready() -> void:
	super._ready()
	visible = false  # 空态启动（首条状态信号点亮）


## 绑定敌方球员（语义包装；宿主挂载由接入层做 add_child 到 player）
func bind_enemy(p: Node) -> void:
	bind_player(p)


## 白名单过滤：父类全量同步后删掉非敌方键（src=light 的普通灯；mark/toggle 单独管理）
func _on_lights_changed() -> void:
	super._on_lights_changed()
	var dirty := false
	for key in _entries.keys():
		if _entries[key].get("src", "") == "light" and not ENEMY_KEYS.has(key):
			_entries.erase(key)
			dirty = true
	# 白名单键的图标补映射（父类表外键如 vulnerable 的字符/颜色修正）
	for key in _entries.keys():
		if _entries[key].get("src", "") == "light" and EXTRA_ICONS.has(key):
			var icon: Dictionary = EXTRA_ICONS[key]
			_entries[key]["char"] = icon["char"]
			_entries[key]["color"] = icon["color"]
			dirty = true
	if dirty:
		_queue_redraw()


## 敌方不显示 toggle（激活开关属己方操作反馈，19 批 A 队条职责）
func _on_toggle_changed(_skill_id: String, _open: bool) -> void:
	pass


## 键图标：父类表 → 补映射 → 键首字兜底
func _icon_for(key: String) -> Dictionary:
	if EXTRA_ICONS.has(key):
		return EXTRA_ICONS[key]
	return STATUS_ICONS.get(key, {"char": key.substr(0, 1), "color": Color(0.6, 0.6, 0.6)})


func _process(delta: float) -> void:
	super._process(delta)
	# 空态自动隐藏（有状态才显示，避免常驻空条）
	var has := not _entries.is_empty()
	if visible != has:
		visible = has


func _draw() -> void:
	super._draw()
	if _entries.is_empty():
		return
	# 红色敌我边框 + 左端色条（一眼区分敌我；图例字符与 A 队条同源零学习成本）
	var total_w := custom_minimum_size.x
	draw_rect(Rect2(-2.0, -2.0, total_w + 4.0, ICON_SIZE + 4.0), FRAME_COLOR, false, 2.0)
	draw_rect(Rect2(-4.0, -2.0, 3.0, ICON_SIZE + 4.0), FRAME_COLOR)
