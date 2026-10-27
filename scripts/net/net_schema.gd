## 工单01 S0.3 接口契约 · 常量与包编解码（低温区，实现照此执行）
## 端口/频道/时序常量 + MSG 包类型 + InputCommand/Snapshot/ChatMessage/GateState/NoticeEvent 编解码。
## 对应裁定：D3/D5/D6/D8/D9/D17(control_events)/D18(频道矩阵)/D21(语音通道)。
## 运行：无（纯静态契约，被 net_transport/net_session/测试引用）
class_name NetSchema
extends RefCounted

# ── 端口与频道（S1 定死）──────────────────────────────
const PORT_GAME := 7777          # ENet 对局连接
const PORT_DISCOVERY := 7778     # UDP 房间信标广播
const CH_RELIABLE := 0           # 可靠通道：握手/房间状态/聊天/门禁
const CH_STATE := 1              # 不可靠通道：快照下行 / 指令上行
const CH_VOICE := 2              # 不可靠独立通道：语音（D21，与快照互不挤占）
const CHANNEL_COUNT := 3

# ── 协议版本（握手不一致拒绝，S1）──────────────────────
const PROTO_VERSION := "bb-net.v1"

# ── 模式（§二 三档）──────────────────────────────────
const MP_1V1 := "MP_1V1"
const MP_3V3_COOP := "MP_3V3_COOP"
const MP_3V3_6P := "MP_3V3_6P"
## 模式 → 会话人数上限（含房主）
const MODE_CAP := {
	MP_1V1: 2,
	MP_3V3_COOP: 3,
	MP_3V3_6P: 6,
}

# ── 时序常量（单位：秒；会话层可注入覆盖用于测试加速）──
const MATCH_WAIT_S := 20.0       # D3 匹配等待门
const PANEL_TIME_S := 60.0       # D5 备战/中场面板倒计时
const GRACE_S := 15.0            # D6 宽限→判负（D7）
const LOAD_TIMEOUT_S := 60.0     # D15 加载超时→全场取消
const HEARTBEAT_S := 2.0         # 心跳间隔
const PEER_TIMEOUT_S := 6.0      # D9 掉线判定
const AFK_S := 10.0              # D8 挂机判定（对局内）
const PICK_TIME_S := 60.0        # S3 选角锁定倒计时
const BEACON_INTERVAL_S := 1.0   # S1 房间信标广播间隔
const BEACON_STALE_S := 3.0      # S1 大厅条目失效窗（未刷新即移除）

# ── 聊天（S13.2 / D18 / D22）─────────────────────────
const CHAT_CHANNEL_ROOM := "room"   # 全员频道
const CHAT_CHANNEL_TEAM := "team"   # 同队频道
const CHAT_TEXT_MAX := 100          # 单条字数上限
const CHAT_RATE_WINDOW_S := 10.0    # 限流窗口（D 10s 内）
const CHAT_RATE_MAX := 5            # 窗口内条数上限，超限静默丢弃+本地提示

# ── 包类型（ch0 可靠为主；INPUT_CMD/SNAPSHOT 走 ch1 不可靠）──
const MSG_HELLO := 1          # C→H 入房请求 {ver, name}
const MSG_WELCOME := 2        # H→C 接纳 {your_peer_id, room}
const MSG_REJECT := 3         # H→C 拒绝 {reason}
const MSG_READY := 4          # C→H 就绪切换 {ready}
const MSG_ROOM_STATE := 5     # H→C 房间全量状态 {room}
const MSG_CHAT := 6           # 双向 聊天（S13.2 频道矩阵+host 星型转发 D22）
const MSG_START_MATCH := 7    # H→C 匹配门通过/选角加载完成 → 开赛
const MSG_CANCEL := 8         # H→C 等待阶段取消（D15）{reason}
const MSG_INPUT_CMD := 9      # C→H 指令上行（ch1）
const MSG_SNAPSHOT := 10      # H→C 快照下行（ch1）
const MSG_GATE := 11          # H→C 门禁状态（备战/中场，S7）
const MSG_NOTICE := 12        # H→C 系统播报（D11：挂机/判负/队长/房主转移）
const MSG_PING := 13          # 双向 心跳保活（ch0 reliable）
const MSG_RESULT := 14        # H→C 结算 {score, stats}
const MSG_MATCH_CONFIG := 15  # H→C 开赛配置（模式/阵容/槽位→peer 映射，S5）
const MSG_CONFIRM := 16       # C→H 队长确认面板（D2；1v1 由 ready 兼任 D4）
const MSG_PICK := 17          # C→H 选角锁定 {char_id, spirit_id}（S3；host 按 D16 队内仲裁）
const MSG_PICK_REJECT := 18   # H→C 选角被拒 {reason}（队内撞车等）

# ── 等待门面板（S7）─────────────────────────────────
const PANEL_PREP := "prep"     # 备战面板（开赛前）
const PANEL_HALF := "half"     # 中场面板
const PANEL_RESULT := "result" # 结算面板（30s 自动，无判负）

# ── 房间阶段（S1 状态机）─────────────────────────────
const PHASE_IDLE := "IDLE"
const PHASE_LOBBY := "LOBBY"           # 房间/匹配等待（含 D3 20s 门）
const PHASE_PICKING := "PICKING"       # 选角（盲选）
const PHASE_LOADING := "LOADING"       # 加载/VS 卡
const PHASE_IN_MATCH := "IN_MATCH"     # 对局（含备战/中场面板）
const PHASE_RESULTS := "RESULTS"       # 结算

## D18 频道矩阵：阶段 → 聊天可用频道（"none"=禁用）
## 大厅/匹配等待/结算=room；选角(盲选)/对局=team；1v1 对局无队友对象由会话层特判禁用。
static func chat_channel_for_phase(phase: String) -> String:
	match phase:
		PHASE_LOBBY, PHASE_RESULTS:
			return CHAT_CHANNEL_ROOM
		PHASE_PICKING, PHASE_IN_MATCH:
			return CHAT_CHANNEL_TEAM
		_:
			return "none"

# ── 编解码：Dictionary ↔ PackedByteArray（var_to_bytes 紧凑二进制）──
static func encode_msg(type: int, d: Dictionary) -> PackedByteArray:
	return var_to_bytes({"t": type, "d": d})

static func decode_msg(bytes: PackedByteArray) -> Dictionary:
	var v: Variant = bytes_to_var(bytes)
	if v is Dictionary:
		var m: Dictionary = v
		if m.has("t") and m.has("d") and m["t"] is int and m["d"] is Dictionary:
			return {"t": int(m["t"]), "d": m["d"]}
	return {"t": 0, "d": {}}

# ── 工单 S0.3 契约包构造器 ─────────────────────────────

## 指令包（含 D17 操控事件包）：guest→host 上行
## control_events: Array[Dictionary]，每项对齐 38 号操控出口语义：
##   {op:"aim", v:Vector2} / {op:"click", seq:int, pos:Vector2}
##   {op:"place", pos:Vector2, shape:String} / {op:"op", op_id:String, params:Dictionary}
static func make_input_command(peer_id: int, frame: int, move: Vector2, skill_slot: int, target_id: int, control_events: Array = []) -> Dictionary:
	return {
		"peer_id": peer_id,
		"frame": frame,
		"move": move,
		"skill_slot": skill_slot,
		"target_id": target_id,
		"control_events": control_events,
	}

## 快照包（host 权威，≥20Hz 下行）：players/ball 状态 + events
static func make_snapshot(frame: int, phase: String, match_time: float, score: Dictionary, players: Array, ball: Dictionary, events: Array = []) -> Dictionary:
	return {
		"frame": frame,
		"phase": phase,
		"match_time": match_time,
		"score": score,
		"players": players,
		"ball": ball,
		"events": events,
	}

## 聊天包（S13.2）：channel∈room|team；text ≤100 字；host 按频道矩阵分发
static func make_chat(channel: String, from_peer: int, from_name: String, text: String, ts: float) -> Dictionary:
	return {
		"channel": channel,
		"from_peer": from_peer,
		"from_name": from_name,
		"text": text,
		"ts": ts,
	}

## 门禁包（S7）：panel∈prep|half|result；ready_mask 按槽位序位
static func make_gate(panel: String, ready_mask: int, captain_id: int, captain_confirmed: bool, deadline_ms: int) -> Dictionary:
	return {
		"panel": panel,
		"ready_mask": ready_mask,
		"captain_id": captain_id,
		"captain_confirmed": captain_confirmed,
		"deadline_ms": deadline_ms,
	}

## 播报事件（D11）：type∈afk|reconnect|captain|forfeit|weak_net|host_transfer|cancel
static func make_notice(type: String, who: String, text: String) -> Dictionary:
	return {"type": type, "who": who, "text": text}

## 房间信标（S1 UDP 广播包体，明文 JSON 便于跨端调试）
static func make_beacon_json(room_name: String, mode: String, cur: int, cap: int) -> String:
	return JSON.stringify({
		"proto": PROTO_VERSION,
		"name": room_name,
		"mode": mode,
		"cur": cur,
		"cap": cap,
	})

static func parse_beacon_json(text: String) -> Dictionary:
	var v: Variant = JSON.parse_string(text)
	return v if v is Dictionary else {}

# ── S10/D13 房间码：公网 IP:端口 短码封装（`BB.<8位hex IP>.<hex端口>`）──
static func make_room_code(ip: String, port: int) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var hex_ip := ""
	for p in parts:
		hex_ip += "%02x" % clampi(int(p), 0, 255)
	return "BB.%s.%x" % [hex_ip, port]

static func parse_room_code(code: String) -> Dictionary:
	var t := code.strip_edges().split(".")
	if t.size() != 3 or t[0] != "BB" or t[1].length() != 8:
		return {}
	var ip := "%d.%d.%d.%d" % [
		t[1].substr(0, 2).hex_to_int(), t[1].substr(2, 2).hex_to_int(),
		t[1].substr(4, 2).hex_to_int(), t[1].substr(6, 2).hex_to_int(),
	]
	return {"ip": ip, "port": t[2].hex_to_int()}
