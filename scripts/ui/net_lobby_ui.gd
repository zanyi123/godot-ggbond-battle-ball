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

var _identity: Label
var _account_panel: PanelContainer = null
var _listener: NetTransport.DiscoveryListener = null
var _list_refresh_t: float = 0.0
var _joined: bool = false
var _bound: NetSession = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# ★ 2026-10-30 U0-6 排版规范落地：根节点统一挂 Theme（字号/色值/框件全继承）
	theme = UiTheme.shared()
	_build_ui()
	_start_discovery()
	NetManager.session_changed.connect(_on_session_changed)
	AccountManager.account_changed.connect(_refresh_identity)
	_refresh_identity()
	_bind_session()

func _exit_tree() -> void:
	if _listener != null:
		_listener.stop()
		_listener = null

# ══════════ UI 构建（手排坐标，对齐 main_menu 风格） ══════════

func _build_ui() -> void:
	# 背景（2026-10-30 挂载：光疤动态背景 → 联机大厅 / 匹配界面）
	# 原为 ColorRect(0.08,0.09,0.16,0.98) 近乎纯色；现改为
	#   ① 光疤动态背景 bg_net_scar.tscn（L1底图+L2星云+L3星点+L4光核+L5光晕，14秒循环）
	#   ② 其上盖一层压暗 scrim，保证联机面板文字可读（原 alpha .98 就是为了压暗）
	var bg_scene_path := "res://scenes/ui/bg_net_scar.tscn"
	if ResourceLoader.exists(bg_scene_path):
		var dyn: Control = (load(bg_scene_path) as PackedScene).instantiate()
		dyn.name = "BGDynamic"
		dyn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dyn)
	var bg := ColorRect.new()
	bg.name = "BGScrim"
	# ★ 2026-10-30 修：原 .62 太薄 → 底下（主菜单蓝白星背景）透上来，联机大厅看起来是蓝白星不是光疤。
	#   改 .93：既压得住下层，又能看见光疤/星点/光核的动态（本层底图已 modulate 0.62 压过一道）。
	bg.color = Color(0.04, 0.05, 0.10, 0.93)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# ── 标题（U0-6 §三 T1 页题档：走 Theme，去硬编码字号/色值）
	var title := Label.new()
	title.text = "联机对战"
	title.theme_type_variation = "LblTitle"
	title.position = Vector2(220, 22)
	title.size = Vector2(400, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UiLayout.add_readability_outline(title)
	add_child(title)

	var sub := Label.new()
	sub.text = "工单01 · M1 局域网"
	sub.theme_type_variation = "LblCaption"
	sub.position = Vector2(222, 62)
	sub.size = Vector2(400, 20)
	add_child(sub)

	# 返回（次级按钮，U0-6 §四 次按钮=银线描边）
	var btn_close := UiLayout.make_ghost_button("返 回", 110)
	btn_close.position = Vector2(40, 26)
	btn_close.pressed.connect(_on_close)
	add_child(btn_close)

	# ── 快捷键提示行（U0-6 §四 第4条：常驻底栏）
	var hint_bar := UiLayout.make_key_hint_bar("Esc 返回 · Enter 确认 · 回车发送聊天")
	hint_bar.offset_top = -32
	hint_bar.offset_bottom = 0
	add_child(hint_bar)

	_status = Label.new()
	_status.text = "未连接——建房或选择局域网房间"
	_status.theme_type_variation = "LblCaption"
	_status.position = Vector2(40, 824)
	_status.size = Vector2(1200, 24)
	UiLayout.add_readability_outline(_status)
	add_child(_status)

	# ── 左面板：找房/建房 ──
	var left_head := _label("— 找房 / 建房 —", Vector2(40, 80), Vector2(420, 26), 17, Color(0.55, 0.85, 1.0))
	add_child(left_head)
	add_child(_label("昵称：", Vector2(40, 114), Vector2(420, 24), 15))
	_name_edit = LineEdit.new()
	_name_edit.text = AccountManager.get_nickname()   # 工单03：昵称默认取账号身份（游客/注册用户）
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
	# 建房=本屏主操作 → BtnPrimary（U0-6 §四：一屏最多一个主按钮）
	var btn_create := UiLayout.make_primary_button("建 房", 420)
	btn_create.text = "建 房（同局域网可见）"
	btn_create.position = Vector2(40, 252)
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
	var btn_join := UiLayout.make_ghost_button("直连", 110)
	btn_join.text = "直连加入"
	btn_join.position = Vector2(350, 692)
	btn_join.pressed.connect(_on_join_ip)
	add_child(btn_join)

	# ── 身份行（工单03：账号身份+登录/注册入口）──
	_identity = _label("", Vector2(516, 62), Vector2(880, 22), 14, Color(0.7, 0.9, 0.7))
	add_child(_identity)
	var btn_account := UiLayout.make_ghost_button("账 号", 200)
	btn_account.text = "账号（登录/注册）"
	btn_account.position = Vector2(1180, 55)
	btn_account.pressed.connect(_on_open_account)
	add_child(btn_account)
	_account_panel = PanelContainer.new()
	_account_panel.position = Vector2(900, 100)
	_account_panel.size = Vector2(500, 300)
	_account_panel.visible = false
	add_child(_account_panel)

	# ── 右面板：房间 ──
	var right_head := _label("— 房间 —", Vector2(500, 80), Vector2(900, 26), 17, Color(0.55, 0.85, 1.0))
	add_child(right_head)
	_slots_box = VBoxContainer.new()
	_slots_box.position = Vector2(516, 114)
	_slots_box.size = Vector2(560, 230)
	add_child(_slots_box)
	_btn_ready = UiLayout.make_primary_button("准 备", 160)
	_btn_ready.text = "准 备"
	_btn_ready.position = Vector2(516, 356)
	_btn_ready.pressed.connect(_on_ready)
	add_child(_btn_ready)
	var btn_leave := UiLayout.make_danger_button("离 开", 160)
	btn_leave.text = "离开房间"
	btn_leave.position = Vector2(696, 356)
	btn_leave.pressed.connect(_on_leave)
	add_child(btn_leave)
	_chat_log = RichTextLabel.new()
	_chat_log.position = Vector2(516, 414)
	_chat_log.size = Vector2(560, 400)
	_chat_log.scroll_following = true
	_chat_log.bbcode_enabled = false
	# ── 聊天区（2026-10-30 第4批：挂接 C6 聊天件 2 件）
	#   net_chat_panel.png   → 房间聊天栏皮肤（560×400，对齐本区尺寸）
	#   net_chat_inputbar.png→ 输入条皮肤
	#   素材由外来需求窗口 tools/gen_net_chat_v1.py 生成，甲线交付（见 美术规划/联机01交付_聊天语音件v1.md）
	var chat_panel_tex := _load_tex("res://assets/ui/popup/net_chat_panel.png")
	var chat_bg := PanelContainer.new()
	chat_bg.name = "ChatPanelSkin"
	chat_bg.position = Vector2(508, 406)
	chat_bg.size = Vector2(576, 416)
	chat_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if chat_panel_tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = chat_panel_tex
		chat_bg.add_theme_stylebox_override("panel", sb)
	else:
		# 缺素材回退：透明（保持旧观感，不崩）
		var fb := StyleBoxFlat.new()
		fb.bg_color = Color(0.06, 0.07, 0.13, 0.55)
		chat_bg.add_theme_stylebox_override("panel", fb)
	add_child(chat_bg)

	_chat_log = RichTextLabel.new()
	_chat_log.position = Vector2(524, 422)
	_chat_log.size = Vector2(544, 372)
	_chat_log.scroll_following = true
	_chat_log.bbcode_enabled = false
	# 聊天栏皮肤在背后，日志本体透明
	_chat_log.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	add_child(_chat_log)

	_chat_edit = LineEdit.new()
	_chat_edit.placeholder_text = "聊天：回车发送（大厅=全员；选角/对局=仅同队；1v1 对局禁用）"
	_chat_edit.position = Vector2(516, 822)
	_chat_edit.size = Vector2(560, 34)
	# 输入条皮肤
	var inputbar_tex := _load_tex("res://assets/ui/popup/net_chat_inputbar.png")
	if inputbar_tex != null:
		var ib := StyleBoxTexture.new()
		ib.texture = inputbar_tex
		_chat_edit.add_theme_stylebox_override("normal", ib)
	_chat_edit.text_submitted.connect(_on_chat_submit)
	add_child(_chat_edit)


## 安全取纹理（缺文件返回 null，不崩）
func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	push_warning("[NetLobby] 皮肤缺失（回退默认）：%s" % path)
	return null

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

## 工单03：身份行刷新（游客/登录态各配色）
func _refresh_identity() -> void:
	if _identity == null:
		return
	if AccountManager.is_guest():
		_identity.text = "身份：游客（%s）——游客身份本地保存，注册后可跨设备" % AccountManager.get_nickname()
	else:
		_identity.text = "身份：%s（已登录）" % AccountManager.get_nickname()

## 工单03：账号小面板（登录/注册/登出三动作；PocketBase 未配置时给接入提示）
func _on_open_account() -> void:
	if _account_panel == null:
		return
	for c in _account_panel.get_children():
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.position = Vector2(12, 10)
	vb.size = Vector2(476, 280)
	vb.add_theme_constant_override("separation", 8)
	_account_panel.add_child(vb)
	var title := Label.new()
	title.text = "账号（当前：%s）" % ("游客 "+AccountManager.get_nickname() if AccountManager.is_guest() else AccountManager.get_nickname())
	vb.add_child(title)
	if AccountManager.PB_BASE_URL == "":
		var hint := Label.new()
		hint.text = "未配置账号服务器：当前为游客模式。
接入步骤见 整体工作补漏/03_账号体系最小闭环_工单.md §五"
		hint.add_theme_font_size_override("font_size", 13)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(hint)
	var em := LineEdit.new()
	em.placeholder_text = "邮箱"
	vb.add_child(em)
	var pw := LineEdit.new()
	pw.placeholder_text = "密码"
	pw.secret = true
	vb.add_child(pw)
	var nk := LineEdit.new()
	nk.placeholder_text = "昵称（注册用）"
	vb.add_child(nk)
	var msg := Label.new()
	msg.add_theme_font_size_override("font_size", 13)
	vb.add_child(msg)
	var row := HBoxContainer.new()
	vb.add_child(row)
	var b_reg := Button.new()
	b_reg.text = "注册"
	b_reg.pressed.connect(func():
		msg.text = "注册中…"
		AccountManager.register(em.text.strip_edges(), pw.text, nk.text.strip_edges(), func(ok, m):
			msg.text = str(m)
			if ok:
				_refresh_identity()))
	row.add_child(b_reg)
	var b_login := Button.new()
	b_login.text = "登录"
	b_login.pressed.connect(func():
		msg.text = "登录中…"
		AccountManager.login(em.text.strip_edges(), pw.text, func(ok, m):
			msg.text = str(m)
			if ok:
				_refresh_identity()))
	row.add_child(b_login)
	var b_logout := Button.new()
	b_logout.text = "登出"
	b_logout.pressed.connect(func():
		AccountManager.logout()
		_refresh_identity()
		msg.text = "已登出（游客模式）")
	row.add_child(b_logout)
	var b_close := Button.new()
	b_close.text = "关闭"
	b_close.pressed.connect(func(): _account_panel.visible = false)
	vb.add_child(b_close)
	_account_panel.visible = true

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

func _on_match_started(config: Dictionary) -> void:
	# S5-2：开赛即进战场（配置由 battle_manager._ready 从 session._match_config 自认领；
	# host=真人操控+备战面板；guest=副本模式快照渲染）
	if not config.is_empty():
		get_tree().change_scene_to_file("res://scenes/battle/battle_arena.tscn")

func _on_match_result(result: Dictionary) -> void:
	var score: Dictionary = result.get("score", {})
	_set_status("结算：A 队 %s : %s B 队——稍后自动回大厅" % [str(score.get("A", 0)), str(score.get("B", 0))])
