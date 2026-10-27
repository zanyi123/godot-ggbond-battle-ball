## 工单01 S2 · 联机大厅 UI（代码构建，实例化叠加在主菜单上）
## 布局：左=建房/局域网房间列表/手动IP直连；右=房间槽位+准备+聊天栏（S13.2 文本聊天 v1）。
## 入口：main_menu「联机对战」按钮；关闭=返回主菜单（恢复交互节点）。
## M1 范围：会话全流程可操作；match_started 后战斗内权威同步=S5 下一批（当前仅状态提示）。
class_name NetLobbyUI
extends Control

const MODE_KEYS: Array = [NetSchema.MP_1V1, NetSchema.MP_3V3_COOP, NetSchema.MP_3V3_6P]
const MODE_LABELS := {
	NetSchema.MP_1V1: "1v1 双人",
	NetSchema.MP_3V3_COOP: "3v3 人机（合作打AI）",
	NetSchema.MP_3V3_6P: "3v3 六人",
}

var _name_edit: LineEdit
var _mode_opt: OptionButton
var _room_list: ItemList
var _ip_edit: LineEdit
var _status: Label

var _slots_box: VBoxContainer
var _btn_ready: Button
var _chat_log: RichTextLabel
var _chat_edit: LineEdit

var _listener: NetTransport.DiscoveryListener = null
var _list_refresh_t: float = 0.0
var _joined: bool = false
var _bound: NetSession = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_start_discovery()
	NetManager.session_changed.connect(_on_session_changed)
	_bind_session()

func _exit_tree() -> void:
	if _listener != null:
		_listener.stop()
		_listener = null

# ══════════ UI 构建（手排坐标，对齐 main_menu 风格） ══════════

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.16, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "联机对战（工单01 · M1：局域网）"
	title.position = Vector2(470, 20)
	title.size = Vector2(500, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	add_child(title)

	var btn_close := Button.new()
	btn_close.text = "返回主菜单"
	btn_close.position = Vector2(40, 20)
	btn_close.size = Vector2(140, 40)
	btn_close.pressed.connect(_on_close)
	add_child(btn_close)

	_status = Label.new()
	_status.text = "未连接——建房或选择局域网房间"
	_status.position = Vector2(40, 858)
	_status.size = Vector2(1200, 30)
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	add_child(_status)

	# ── 左面板：找房/建房 ──
	var left_head := _label("— 找房 / 建房 —", Vector2(40, 80), Vector2(420, 26), 17, Color(0.55, 0.85, 1.0))
	add_child(left_head)
	add_child(_label("昵称：", Vector2(40, 114), Vector2(420, 24), 15))
	_name_edit = LineEdit.new()
	_name_edit.text = "玩家%d" % (randi() % 1000)
	_name_edit.position = Vector2(40, 140)
	_name_edit.size = Vector2(420, 34)
	add_child(_name_edit)
	add_child(_label("模式：", Vector2(40, 182), Vector2(420, 24), 15))
	_mode_opt = OptionButton.new()
	for k in MODE_KEYS:
		_mode_opt.add_item("%s（%d 人）" % [MODE_LABELS[k], NetSchema.MODE_CAP[k]])
	_mode_opt.selected = 0
	_mode_opt.position = Vector2(40, 208)
	_mode_opt.size = Vector2(420, 34)
	add_child(_mode_opt)
	var btn_create := Button.new()
	btn_create.text = "建房（同局域网可见）"
	btn_create.position = Vector2(40, 252)
	btn_create.size = Vector2(420, 44)
	btn_create.pressed.connect(_on_create)
	add_child(btn_create)
	add_child(_label("局域网房间（自动发现，点击加入）：", Vector2(40, 308), Vector2(420, 24), 15))
	_room_list = ItemList.new()
	_room_list.position = Vector2(40, 334)
	_room_list.size = Vector2(420, 320)
	_room_list.item_selected.connect(_on_room_pick)
	add_child(_room_list)
	add_child(_label("手动输入 IP 直连（防路由器隔离）：", Vector2(40, 666), Vector2(420, 24), 15))
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "例如 192.168.1.23"
	_ip_edit.position = Vector2(40, 692)
	_ip_edit.size = Vector2(300, 34)
	add_child(_ip_edit)
	var btn_join := Button.new()
	btn_join.text = "直连加入"
	btn_join.position = Vector2(350, 692)
	btn_join.size = Vector2(110, 34)
	btn_join.pressed.connect(_on_join_ip)
	add_child(btn_join)

	# ── 右面板：房间 ──
	var right_head := _label("— 房间 —", Vector2(500, 80), Vector2(900, 26), 17, Color(0.55, 0.85, 1.0))
	add_child(right_head)
	_slots_box = VBoxContainer.new()
	_slots_box.position = Vector2(516, 114)
	_slots_box.size = Vector2(560, 230)
	add_child(_slots_box)
	_btn_ready = Button.new()
	_btn_ready.text = "准备"
	_btn_ready.position = Vector2(516, 356)
	_btn_ready.size = Vector2(160, 44)
	_btn_ready.pressed.connect(_on_ready)
	add_child(_btn_ready)
	var btn_leave := Button.new()
	btn_leave.text = "离开房间"
	btn_leave.position = Vector2(696, 356)
	btn_leave.size = Vector2(160, 44)
	btn_leave.pressed.connect(_on_leave)
	add_child(btn_leave)
	_chat_log = RichTextLabel.new()
	_chat_log.position = Vector2(516, 414)
	_chat_log.size = Vector2(560, 400)
	_chat_log.scroll_following = true
	_chat_log.bbcode_enabled = false
	add_child(_chat_log)
	_chat_edit = LineEdit.new()
	_chat_edit.placeholder_text = "聊天：回车发送（大厅=全员；选角/对局=仅同队；1v1 对局禁用）"
	_chat_edit.position = Vector2(516, 822)
	_chat_edit.size = Vector2(560, 34)
	_chat_edit.text_submitted.connect(_on_chat_submit)
	add_child(_chat_edit)

func _label(t: String, pos: Vector2, sz: Vector2, fs: int, col: Color = Color(0.85, 0.85, 0.9)) -> Label:
	var l := Label.new()
	l.text = t
	l.position = pos
	l.size = sz
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l

# ══════════ 发现 ══════════

func _start_discovery() -> void:
	_listener = NetTransport.DiscoveryListener.new()
	if not _listener.start(NetSchema.PORT_DISCOVERY):
		_set_status("发现端口 %d 被占用（可用手动 IP 直连）" % NetSchema.PORT_DISCOVERY)

func _process(delta: float) -> void:
	if _listener != null:
		_listener.poll(delta)
	_list_refresh_t += delta
	if _list_refresh_t >= 0.5:
		_list_refresh_t = 0.0
		_refresh_room_list()

func _refresh_room_list() -> void:
	if _room_list == null or _listener == null:
		return
	_room_list.clear()
	for e in _listener.entries():
		var info: Dictionary = e
		_room_list.add_item("[%s] %s（%d/%d）@ %s" % [
			MODE_LABELS.get(str(info.get("mode", "")), str(info.get("mode", "?"))),
			str(info.get("name", "?")),
			int(info.get("cur", 0)),
			int(info.get("cap", 0)),
			str(info.get("ip", "?")),
		])

func _on_room_pick(idx: int) -> void:
	var entries: Array = _listener.entries() if _listener != null else []
	if idx >= 0 and idx < entries.size():
		_join_ip(str(entries[idx].get("ip", "")))

# ══════════ 动作 ══════════

func _on_create() -> void:
	if _joined:
		return
	var pname := _name_edit.text.strip_edges()
	if pname.is_empty():
		_set_status("请先填昵称")
		return
	if NetManager.create_room(MODE_KEYS[_mode_opt.selected], pname):
		_joined = true
		_set_status("建房成功，等待局域网玩家加入…（游戏端口 %d，信标 %d）" % [NetSchema.PORT_GAME, NetSchema.PORT_DISCOVERY])
	else:
		_set_status("建房失败：端口 %d 可能被占用" % NetSchema.PORT_GAME)

func _on_join_ip() -> void:
	_join_ip(_ip_edit.text.strip_edges())

func _join_ip(ip: String) -> void:
	if _joined or ip.is_empty():
		return
	var pname := _name_edit.text.strip_edges()
	if pname.is_empty():
		_set_status("请先填昵称")
		return
	if NetManager.join_room(ip, pname):
		_joined = true
		_set_status("连接 %s 中…" % ip)
	else:
		_set_status("连接发起失败：%s" % ip)

func _on_ready() -> void:
	if NetManager.session != null:
		NetManager.session.set_local_ready(not _is_local_ready())

func _on_leave() -> void:
	NetManager.leave()
	_on_left("已离开房间")

func _on_left(reason: String) -> void:
	_joined = false
	_bound = null
	_set_status(reason)
	if _chat_log != null:
		_chat_log.clear()
	_refresh_slots({})

func _on_close() -> void:
	NetManager.leave()
	var parent := get_parent()
	if parent != null and parent.has_method("_show_menu_interactive_nodes"):
		parent.call("_show_menu_interactive_nodes")
	queue_free()

func _on_chat_submit(text: String) -> void:
	if NetManager.session == null:
		return
	NetManager.session.send_chat(text)
	_chat_edit.clear()

# ══════════ 会话绑定 ══════════

func _on_session_changed() -> void:
	_bind_session()

func _bind_session() -> void:
	var s := NetManager.session
	if s == null or s == _bound:
		return
	_bound = s
	s.room_updated.connect(_on_room_updated)
	s.state_changed.connect(_on_state_changed)
	s.chat_display.connect(_on_chat_display)
	s.chat_blocked.connect(_on_chat_blocked)
	s.cancelled.connect(_on_cancelled)
	s.host_lost.connect(_on_host_lost)
	s.match_started.connect(_on_match_started)
	s.match_result.connect(_on_match_result)
	if not s._room_dict().is_empty():
		_refresh_slots(s._room_dict())
	_set_status("已进入房间")

func _is_local_ready() -> bool:
	var s := NetManager.local_slot()
	return bool(s.get("ready", false)) if not s.is_empty() else false

func _set_status(t: String) -> void:
	if _status != null:
		_status.text = t

func _refresh_slots(room: Dictionary) -> void:
	if _slots_box == null:
		return
	for c in _slots_box.get_children():
		c.queue_free()
	var slots: Array = room.get("slots", [])
	for s in slots:
		var d: Dictionary = s
		var line := Label.new()
		line.text = "%s%s%s  %s" % [
			"[队长] " if bool(d.get("captain")) else "",
			str(d.get("name")),
			"（我）" if int(d.get("peer_id")) == NetManager.local_peer_id() else "",
			"✔ 已准备" if bool(d.get("ready")) else "… 未准备",
		]
		line.add_theme_font_size_override("font_size", 17)
		_slots_box.add_child(line)
	if _btn_ready != null:
		_btn_ready.text = "取消准备" if _is_local_ready() else "准备"

# ── session 信号回调 ──

func _on_room_updated(room: Dictionary) -> void:
	_refresh_slots(room)
	var cap := int(room.get("cap", 0))
	var cur := int(room.get("cur", 0))
	_set_status("房间 %d/%d · %s · %s" % [cur, cap, str(room.get("phase", "")), MODE_LABELS.get(str(room.get("mode", "")), "")])

func _on_state_changed(phase: String) -> void:
	match phase:
		NetSchema.PHASE_LOADING:
			_show_vs_cards()   # S4：盲选到此为止，本页首次亮阵（v1 文字卡；美术占位版=美术域移交单）
			_set_status("加载中…")
		NetSchema.PHASE_IN_MATCH:
			_set_status("已开赛（M1：会话层直通；战斗内权威同步=S5 下一批接入）")
		NetSchema.PHASE_RESULTS:
			_set_status("比赛结束·结算中…")
		NetSchema.PHASE_LOBBY:
			_set_status("回到房间大厅")

## S4 VS 亮阵（v1 文字卡）：左己方·右敌方，含 S3 picks（char/spirit）
func _show_vs_cards() -> void:
	if _chat_log == null:
		return
	var s := NetManager.session
	if s == null or s._match_config.is_empty():
		return
	var cfg := s._match_config
	var left := _roster_line(cfg.get("roster_a", []))
	var right := _roster_line(cfg.get("roster_b", []))
	_chat_log.clear()
	_chat_log.add_text("══════ VS ══════\n")
	_chat_log.add_text("己方（左）：\n" + left + "\n")
	_chat_log.add_text("敌方（右）：\n" + right + "\n")
	_chat_log.add_text("════════════════\n")

func _roster_line(roster: Array) -> String:
	var out := ""
	for e in roster:
		var d: Dictionary = e
		out += "· %s  球员[%s] 元灵[%s]\n" % [str(d.get("name", "?")), str(d.get("char_id", "—")), str(d.get("spirit_id", "—"))]
	return out if not out.is_empty() else "（AI 补位）\n"

func _on_chat_display(chat: Dictionary, mine: bool) -> void:
	var tag := "【队】" if str(chat.get("channel")) == NetSchema.CHAT_CHANNEL_TEAM else ""
	_chat_log.add_text("%s%s%s: %s\n" % [tag, "（我）" if mine else "", str(chat.get("from_name")), str(chat.get("text"))])

func _on_chat_blocked(reason: String) -> void:
	_set_status("聊天不可用：%s" % reason)

func _on_cancelled(reason: String) -> void:
	_set_status("匹配取消：%s（已回大厅，可重新准备）" % reason)

func _on_host_lost() -> void:
	_on_left("与房主失去连接——已回大厅（等待阶段取消制 D15）")

func _on_match_started(_config: Dictionary) -> void:
	_set_status("已开赛（M1：会话层直通；战斗内权威同步=S5 下一批接入）")

func _on_match_result(result: Dictionary) -> void:
	var score: Dictionary = result.get("score", {})
	_set_status("结算：A 队 %s : %s B 队——稍后自动回大厅" % [str(score.get("A", 0)), str(score.get("B", 0))])
