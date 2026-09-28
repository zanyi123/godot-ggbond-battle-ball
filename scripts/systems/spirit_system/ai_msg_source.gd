extends Node
class_name AIMsgSource
## 23-4 UI 信号→AI 个体消息源（技能规划/23 补充，主人裁 2026-09-28）
## 将基础 UI 数据链信号（状态灯/印记/开关）规范化为 AI 个体可订阅的消息流——
## AI 个体间"谁被挂了什么状态"的通讯内容源（数据底座，19 批信号复用零改造）。
## 纪律：纯观察转发，零判定零写操作；enabled=false 时零行为（不订阅不广播）。

signal ai_msg(player_id: int, kind: String, data: Dictionary)

const KIND_STATUS := "status_changed"   # 状态灯集合变化（含剩余秒数快照）
const KIND_MARK := "mark_changed"       # 印记层数变化
const KIND_TOGGLE := "toggle_changed"   # 开关型技能开/关
const RECENT_MAX: int = 64              # 消息环形日志上限

var enabled: bool = false               # 开关（默认关；显式 start_tracking 前需置 true）
var tracked: Array = []
var recent: Array[Dictionary] = []      # 最近消息（最新在后；查询口）


## 开始跟踪一组球员（订阅其基础 UI 数据链信号）
func start_tracking(players: Array) -> void:
	if not enabled:
		return
	stop_tracking()
	for p in players:
		if p == null or not is_instance_valid(p):
			continue
		var cb_s: Callable = _on_status.bind(p)
		var cb_m: Callable = _on_mark.bind(p)
		var cb_t: Callable = _on_toggle.bind(p)
		if p.has_signal("status_lights_changed") and not p.status_lights_changed.is_connected(cb_s):
			p.status_lights_changed.connect(cb_s)
		if p.has_signal("mark_changed") and not p.mark_changed.is_connected(cb_m):
			p.mark_changed.connect(cb_m)
		if p.has_signal("toggle_changed") and not p.toggle_changed.is_connected(cb_t):
			p.toggle_changed.connect(cb_t)
		tracked.append(p)


## 停止跟踪（解绑全部订阅）
func stop_tracking() -> void:
	for p in tracked:
		if p == null or not is_instance_valid(p):
			continue
		var cb_s: Callable = _on_status.bind(p)
		var cb_m: Callable = _on_mark.bind(p)
		var cb_t: Callable = _on_toggle.bind(p)
		if p.status_lights_changed.is_connected(cb_s):
			p.status_lights_changed.disconnect(cb_s)
		if p.mark_changed.is_connected(cb_m):
			p.mark_changed.disconnect(cb_m)
		if p.toggle_changed.is_connected(cb_t):
			p.toggle_changed.disconnect(cb_t)
	tracked.clear()


## 查询：某类消息的最近记录（kind 空=全部）
func get_msgs(kind: String = "") -> Array[Dictionary]:
	if kind == "":
		return recent.duplicate()
	var out: Array[Dictionary] = []
	for m in recent:
		if str(m.get("kind", "")) == kind:
			out.append(m)
	return out


func _on_status(p) -> void:
	if not _is_tracked(p):
		return
	var view: Dictionary = p.get_status_lights_view() if p.has_method("get_status_lights_view") else {}
	_push(int(p.get_instance_id()), KIND_STATUS, {"lights": view})


func _on_mark(mark_id: String, count: int, p) -> void:
	_push(int(p.get_instance_id()), KIND_MARK, {"mark_id": mark_id, "count": count})


func _on_toggle(skill_id: String, open: bool, p) -> void:
	_push(int(p.get_instance_id()), KIND_TOGGLE, {"skill_id": skill_id, "open": open})


func _is_tracked(p) -> bool:
	return p != null and is_instance_valid(p) and tracked.has(p)


func _push(player_id: int, kind: String, data: Dictionary) -> void:
	var msg := {"player_id": player_id, "kind": kind, "data": data}
	recent.append(msg)
	if recent.size() > RECENT_MAX:
		recent.pop_front()
	ai_msg.emit(player_id, kind, data)
