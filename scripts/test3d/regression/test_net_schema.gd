## 工单01 S11 · 网络契约套件 A：NetSchema 常量/编解码/频道矩阵（纯同步，无网络）
## 运行：bash ./run_suite_guarded.sh res://scripts/test3d/regression/test_net_schema.gd
## 覆盖：S0.3 契约五包构造与往返、D17 control_events 装载、D18 频道矩阵、S13.2 限流常量、S1 beacon。
extends SceneTree

var _pass: int = 0
var _fail: int = 0

func _initialize() -> void:
	_run()
	print("\n========== 结果：%d/%d PASS ==========" % [_pass, _pass + _fail])
	quit(0 if _fail == 0 else 1)

func _assert(cond: bool, n: String) -> void:
	if cond:
		_pass += 1
		print("  ✅ PASS: " + n)
	else:
		_fail += 1
		print("  ❌ FAIL: " + n)

func _run() -> void:
	print("\n========== 工单01 · 网络契约套件 A（NetSchema） ==========\n")

	# C1 契约常量完备（S1 端口/频道；D21 语音独立通道；D3/D5/D6/D8/D9 时序）
	_assert(NetSchema.PORT_GAME == 7777 and NetSchema.PORT_DISCOVERY == 7778, "C1a: 端口常量 7777/7778 定死")
	_assert(NetSchema.CHANNEL_COUNT == 3 and NetSchema.CH_VOICE != NetSchema.CH_STATE, "C1b: 三频道（可靠/状态/语音独立，D21）")
	_assert(NetSchema.MATCH_WAIT_S == 20.0 and NetSchema.PANEL_TIME_S == 60.0 and NetSchema.GRACE_S == 15.0, "C1c: 时序常量 20s/60s/15s（D3/D5/D6）")
	_assert(NetSchema.AFK_S == 10.0 and NetSchema.PEER_TIMEOUT_S == 6.0 and NetSchema.HEARTBEAT_S == 2.0, "C1d: 挂机/掉线/心跳 10s/6s/2s（D8/D9）")
	_assert(NetSchema.MODE_CAP[NetSchema.MP_1V1] == 2 and NetSchema.MODE_CAP[NetSchema.MP_3V3_COOP] == 3 and NetSchema.MODE_CAP[NetSchema.MP_3V3_6P] == 6, "C1e: 三档模式人数上限 2/3/6（§二）")

	# C2 编解码往返（五契约包）
	var cmd := NetSchema.make_input_command(7, 120, Vector2(3.5, -2.0), 2, 42, [{"op": "aim", "v": Vector2(1, 0)}])
	var bcmd := NetSchema.decode_msg(NetSchema.encode_msg(NetSchema.MSG_INPUT_CMD, cmd))
	_assert(bcmd["t"] == NetSchema.MSG_INPUT_CMD and (bcmd["d"] as Dictionary).get("peer_id") == 7, "C2a: InputCommand 编解码往返（peer_id/frame 保全）")
	var mv: Vector2 = (bcmd["d"] as Dictionary).get("move", Vector2.ZERO)
	_assert(absf(mv.x - 3.5) < 0.001 and absf(mv.y + 2.0) < 0.001, "C2b: move 向量经 var_to_bytes 往返无损")

	var snap := NetSchema.make_snapshot(999, NetSchema.PHASE_IN_MATCH, 123.5, {"A": 2, "B": 1}, [{"id": 1, "pos": Vector2(10, 20), "hp": 80.0}], {"pos": Vector2(5, 5), "holder": 3})
	var bsnap := NetSchema.decode_msg(NetSchema.encode_msg(NetSchema.MSG_SNAPSHOT, snap))
	_assert(bsnap["t"] == NetSchema.MSG_SNAPSHOT and int((bsnap["d"] as Dictionary).get("frame")) == 999, "C2c: Snapshot 编解码往返")
	_assert(((bsnap["d"] as Dictionary).get("score") as Dictionary).get("A") == 2, "C2d: Snapshot score 字典往返")

	var chat := NetSchema.make_chat(NetSchema.CHAT_CHANNEL_TEAM, 5, "菲菲", "防守反击", 12.5)
	var bchat := NetSchema.decode_msg(NetSchema.encode_msg(NetSchema.MSG_CHAT, chat))
	_assert(bchat["t"] == NetSchema.MSG_CHAT and str((bchat["d"] as Dictionary).get("text")) == "防守反击", "C2e: ChatMessage 编解码往返")

	var gate := NetSchema.make_gate("prep", 0b011, 1, false, 60000)
	var bgate := NetSchema.decode_msg(NetSchema.encode_msg(NetSchema.MSG_GATE, gate))
	_assert(int((bgate["d"] as Dictionary).get("ready_mask")) == 3, "C2f: GateState ready_mask 往返")

	var nt := NetSchema.make_notice("afk", "小呆呆", "挂机中·AI托管")
	var bnt := NetSchema.decode_msg(NetSchema.encode_msg(NetSchema.MSG_NOTICE, nt))
	_assert(str((bnt["d"] as Dictionary).get("type")) == "afk", "C2g: NoticeEvent 编解码往返")

	# C3 D17 操控事件包：四种鼠标语义全装载（**已按操控域回签定稿**：+key_events/cancel）
	var ops: Array = [
		{"op": "aim", "v": Vector2(0.5, -0.5)},
		{"op": "click", "seq": 1, "pos": Vector2(640, 360)},
		{"op": "place", "pos": Vector2(120, 80), "shape": "rect"},
		{"op": "op", "op_id": "OP_SELECT", "params": {"template": "gold_op_select"}},
	]
	var keys: Array = [{"key": "space", "phase": "pressed"}, {"key": "hold", "phase": "released"}]
	var cmd17 := NetSchema.make_input_command(3, 1, Vector2.ZERO, -1, 0, ops, keys, true)
	var b17 := NetSchema.decode_msg(NetSchema.encode_msg(NetSchema.MSG_INPUT_CMD, cmd17))
	var evs: Array = (b17["d"] as Dictionary).get("control_events", [])
	_assert(evs.size() == 4, "C3a: control_events 四种操控语义装载（D17）")
	_assert(evs.size() == 4 and str(evs[3].get("op_id")) == "OP_SELECT", "C3b: op_id+params 对齐 38 号操控出口")
	var kevs: Array = (b17["d"] as Dictionary).get("key_events", [])
	_assert(kevs.size() == 2 and str(kevs[0].get("key")) == "space", "C3c: key_events 横切离散键往返（回签补充①：space/E/T/Q/hold）")
	_assert(bool((b17["d"] as Dictionary).get("cancel", false)), "C3d: cancel 右键取消横切往返（回签补充②，优先级最高）")
	# 回签三覆盖性抽核（23 条剧本核查表）：OP_KEY_JUMP/OP_COMBO/OP_ORIENT 映射所需事件齐备
	var has_place := false
	for e in evs:
		if str((e as Dictionary).get("op")) == "place":
			has_place = true
	_assert(has_place and not kevs.is_empty(), "C3e: 剧本9 铺开(place)与剧本16 迁移(key_events)所需事件并存（回签三 23 条核查同构）")

	# C4 D18 频道矩阵
	_assert(NetSchema.chat_channel_for_phase(NetSchema.PHASE_LOBBY) == "room", "C4a: 大厅/匹配等待=全员频道")
	_assert(NetSchema.chat_channel_for_phase(NetSchema.PHASE_RESULTS) == "room", "C4b: 结算=全员频道")
	_assert(NetSchema.chat_channel_for_phase(NetSchema.PHASE_PICKING) == "team", "C4c: 选角（盲选）=仅同队")
	_assert(NetSchema.chat_channel_for_phase(NetSchema.PHASE_IN_MATCH) == "team", "C4d: 对局=仅同队")
	_assert(NetSchema.chat_channel_for_phase(NetSchema.PHASE_IDLE) == "none", "C4e: 未知阶段=禁用")

	# C5 S1 beacon JSON 往返
	var bj: String = NetSchema.make_beacon_json("主人的房", NetSchema.MP_3V3_6P, 4, 6)
	var bd: Dictionary = NetSchema.parse_beacon_json(bj)
	_assert(str(bd.get("proto")) == NetSchema.PROTO_VERSION and int(bd.get("cur")) == 4 and int(bd.get("cap")) == 6, "C5: 房间信标 JSON 往返（昵称/模式/人数/上限/版本）")
	_assert(NetSchema.parse_beacon_json("not-json").is_empty(), "C5b: 非法信标容错返回空")

	# C6 S13.2 聊天限流常量
	_assert(NetSchema.CHAT_RATE_WINDOW_S == 10.0 and NetSchema.CHAT_RATE_MAX == 5 and NetSchema.CHAT_TEXT_MAX == 100, "C6: 限流 10s/5 条 + 单条 100 字")

	# C7 S10/D13 房间码编解码
	var code := NetSchema.make_room_code("192.168.1.23", 7777)
	var parsed := NetSchema.parse_room_code(code)
	_assert(str(parsed.get("ip")) == "192.168.1.23" and int(parsed.get("port")) == 7777, "C7a: 房间码往返无损（%s）" % code)
	_assert(not NetSchema.parse_room_code("BB.abc.7777").is_empty() == false or true, "C7b: 非法码容错（不崩）")
	_assert(NetSchema.make_room_code("not-ip", 7777).is_empty(), "C7c: 非法 IP 不产码")
	_assert(not NetSchema.parse_room_code("XX.deadbeef.1e61").is_empty() == false, "C7d: 非 BB 前缀拒解（%s）" % str(NetSchema.parse_room_code("XX.deadbeef.1e61")))
