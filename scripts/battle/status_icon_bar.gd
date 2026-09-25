extends Control
class_name StatusIconBar
## 13-A 通用状态图标条（技能规划/19 基础UI批次）：24px 色块图标 + 右上秒数 + 右下层数 + 充能 N/M
## 铁律：UI 零判定逻辑——只读消费 player.get_status_lights_view()/mark_changed/toggle_changed 信号，禁止写任何游戏状态
## 刷新：事件驱动（信号回调重绘；秒数递减来自 player 侧整秒节流广播），不轮询

## 临时配色表（待 ElementColorBank 统一——13 工单 §二）
const STATUS_ICONS: Dictionary = {
	"heal_block": {"char": "疗", "color": Color(0.65, 0.3, 0.85)},
	"energy_block": {"char": "能", "color": Color(0.45, 0.55, 0.65)},
	"reflect": {"char": "反", "color": Color(1.0, 0.45, 0.2)},
	"element_immune": {"char": "免", "color": Color(0.95, 0.95, 0.95)},
	"element_weak": {"char": "弱", "color": Color(0.55, 0.15, 0.15)},
	"energy_share": {"char": "摊", "color": Color(0.2, 0.8, 0.8)},
	"charge_stock": {"char": "储", "color": Color(0.3, 0.7, 0.9)},
	"stealthed": {"char": "隐", "color": Color(0.5, 0.5, 0.55)},
	"invincible": {"char": "无", "color": Color(1.0, 0.9, 0.3)},
	"stunned": {"char": "晕", "color": Color(0.9, 0.3, 0.3)},
	"rooted": {"char": "锢", "color": Color(0.6, 0.4, 0.2)},
	"silenced": {"char": "默", "color": Color(0.7, 0.3, 0.6)},
	"disarmed": {"char": "缴", "color": Color(0.8, 0.5, 0.3)},
	"mark": {"char": "印", "color": Color(0.3, 0.85, 0.4)},
	"shield": {"char": "盾", "color": Color(1.0, 0.84, 0.0)},
	"toggle": {"char": "T", "color": Color(0.9, 0.75, 0.25)},
	"heal": {"char": "+", "color": Color(0.2, 0.9, 0.5)},
}

const ICON_SIZE: float = 24.0
const ICON_GAP: float = 3.0
const MAX_VISIBLE: int = 8   # 上限 8 个，超出折叠 "+N"

var _entries: Dictionary = {}   # key → {char, color, remaining, stacks, charges, charges_max}
var _bound_player: Node = null


func _ready() -> void:
	custom_minimum_size = Vector2(MAX_VISIBLE * (ICON_SIZE + ICON_GAP), ICON_SIZE + 4.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_queue_redraw()


## 绑定球员（连接数据源信号；重复绑定先解绑旧的）
func bind_player(p: Node) -> void:
	if _bound_player != null and is_instance_valid(_bound_player):
		if _bound_player.status_lights_changed.is_connected(_on_lights_changed):
			_bound_player.status_lights_changed.disconnect(_on_lights_changed)
		if _bound_player.mark_changed.is_connected(_on_mark_changed):
			_bound_player.mark_changed.disconnect(_on_mark_changed)
		if _bound_player.toggle_changed.is_connected(_on_toggle_changed):
			_bound_player.toggle_changed.disconnect(_on_toggle_changed)
	_bound_player = p
	if _bound_player == null:
		return
	_bound_player.status_lights_changed.connect(_on_lights_changed)
	_bound_player.mark_changed.connect(_on_mark_changed)
	_bound_player.toggle_changed.connect(_on_toggle_changed)
	_on_lights_changed()  # 初次全量同步


## 测试/外部注入接口（数据 upsert；生产由信号回调驱动）
func set_entry(key: String, char_text: String, color: Color, remaining: int = 0, stacks: int = 0, charges: int = -1, charges_max: int = -1) -> void:
	_entries[key] = {
		"char": char_text, "color": color,
		"remaining": maxi(remaining, 0), "stacks": maxi(stacks, 0),
		"charges": charges, "charges_max": charges_max,
	}
	_queue_redraw()


func remove_entry(key: String) -> void:
	if _entries.erase(key):
		_queue_redraw()


func get_entry_keys() -> Array:
	return _entries.keys()


## 测试口：当前可见图标数（含折叠逻辑）
func get_visible_count() -> int:
	var total: int = _entries.size()
	if total > MAX_VISIBLE:
		return MAX_VISIBLE - 1
	return total


## 灯视图全量同步（status_lights_changed 回调；条目键=灯名）
func _on_lights_changed() -> void:
	if _bound_player == null or not is_instance_valid(_bound_player):
		return
	var view: Dictionary = _bound_player.get_status_lights_view()
	# 先清掉已熄灭的灯条目（mark/shield/toggle 键单独管理，不在灯视图里）
	for key in _entries.keys():
		if _entries[key].get("src", "") == "light" and not view.has(key):
			_entries.erase(key)
	for status in view:
		var light: Dictionary = view[status]
		var icon: Dictionary = STATUS_ICONS.get(status, {"char": status.substr(0, 1), "color": Color(0.6, 0.6, 0.6)})
		var charges: int = int(light.get("charges", -1))
		var charges_max: int = int(light.get("charges_max", -1))
		set_entry_raw(status, "light", str(icon["char"]), icon["color"],
			int(ceil(float(light.get("remaining", 0.0)))), 0, charges, charges_max)
	_queue_redraw()


func set_entry_raw(key: String, src: String, char_text: String, color: Color, remaining: int, stacks: int, charges: int = -1, charges_max: int = -1) -> void:
	_entries[key] = {
		"src": src, "char": char_text, "color": color,
		"remaining": maxi(remaining, 0), "stacks": maxi(stacks, 0),
		"charges": charges, "charges_max": charges_max,
	}
	_queue_redraw()


## 印记层数（mark_changed 回调；count=0 摘除）
func _on_mark_changed(mark_id: String, count: int) -> void:
	var icon: Dictionary = STATUS_ICONS.get("mark")
	if count <= 0:
		remove_entry("mark_" + mark_id)
	else:
		set_entry_raw("mark_" + mark_id, "mark", str(icon["char"]), icon["color"], 0, count)
	_queue_redraw()


## toggle 激活态（toggle_changed 回调；关=摘除）
func _on_toggle_changed(skill_id: String, open: bool) -> void:
	var icon: Dictionary = STATUS_ICONS.get("toggle")
	if open:
		set_entry_raw("toggle_" + skill_id, "toggle", str(icon["char"]), icon["color"], 0, 0)
	else:
		remove_entry("toggle_" + skill_id)
	_queue_redraw()


func _queue_redraw() -> void:
	queue_redraw()


func _draw() -> void:
	var keys: Array = _entries.keys()
	var visible_count: int = mini(keys.size(), MAX_VISIBLE - 1 if keys.size() > MAX_VISIBLE else MAX_VISIBLE)
	var x: float = 0.0
	for i in range(visible_count):
		var e: Dictionary = _entries[keys[i]]
		_draw_one(x, e)
		x += ICON_SIZE + ICON_GAP
	# 折叠 "+N"
	if keys.size() > MAX_VISIBLE:
		draw_rect(Rect2(x, 0, ICON_SIZE + 6.0, ICON_SIZE), Color(0.25, 0.25, 0.3, 0.9))
		draw_string(ThemeDB.fallback_font, Vector2(x + 2.0, ICON_SIZE - 6.0),
			"+%d" % (keys.size() - MAX_VISIBLE + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)


func _draw_one(x: float, e: Dictionary) -> void:
	var rect := Rect2(x, 0, ICON_SIZE, ICON_SIZE)
	draw_rect(rect, e["color"])
	draw_rect(rect, Color(0, 0, 0, 0.6), false, 1.0)
	# 中央单字符
	draw_string(ThemeDB.fallback_font, Vector2(x + 4.0, ICON_SIZE - 5.0),
		str(e["char"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.05, 0.05, 0.05))
	# 右上秒数角标
	var remaining: int = int(e.get("remaining", 0))
	if remaining > 0:
		draw_string(ThemeDB.fallback_font, Vector2(x + ICON_SIZE - 12.0, 10.0),
			str(remaining), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	# 右下层数角标
	var stacks: int = int(e.get("stacks", 0))
	if stacks > 0:
		draw_string(ThemeDB.fallback_font, Vector2(x + ICON_SIZE - 12.0, ICON_SIZE - 2.0),
			str(stacks), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	# 充能点 N/M（13-D：小圆点排，M 上限）
	var charges: int = int(e.get("charges", -1))
	var charges_max: int = int(e.get("charges_max", -1))
	if charges >= 0 and charges_max > 0:
		for i in range(charges_max):
			var cx: float = x + 3.0 + i * 5.0
			var filled: bool = i < charges
			draw_circle(Vector2(cx, 3.0), 1.8, Color.WHITE if filled else Color(0, 0, 0, 0.45))
