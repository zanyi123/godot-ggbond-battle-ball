## 工单01 S0.3 NetManager（autoload）· 联机总开关 + 本端会话生命周期
## 纪律（R2 回退底线）：active=false 时一切联机路径不得触碰单机行为；
## 单机旧代码只允许通过 `NetManager.active` 判定走联机分支。
## UI/游戏层经本类拿 session（信号直连 NetSession），不在各处自建连接。
extends Node

## 会话引用变更（建房/入房/离开后发一次；UI 重绑信号用）
signal session_changed

var active: bool = false
var session: NetSession = null

func create_room(room_mode: String, player_name: String, port: int = NetSchema.PORT_GAME) -> bool:
	_end_session()
	var s := NetSession.new(true, player_name)
	if not s.create_room(room_mode, port):
		return false
	session = s
	active = true
	session_changed.emit()
	return true

func join_room(host_ip: String, player_name: String, port: int = NetSchema.PORT_GAME) -> bool:
	_end_session()
	var s := NetSession.new(false, player_name)
	if not s.join_room(host_ip, port, player_name):
		return false
	session = s
	active = true
	session_changed.emit()
	return true

func leave() -> void:
	_end_session()

func _end_session() -> void:
	if session != null:
		session.leave()
		session = null
	active = false
	session_changed.emit()

func _process(delta: float) -> void:
	if session != null:
		session.update(delta)

# ── 便捷转发（UI 层用，勿在多处直捅 session 内部） ──
func local_peer_id() -> int:
	return session.local_peer_id() if session != null else 0

func local_slot() -> Dictionary:
	return session.local_slot() if session != null else {}

func room_dict() -> Dictionary:
	return session._room_dict() if session != null else {}
